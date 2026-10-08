import Foundation
import Observation
import OSLog

/// Owns the Python runtime and the inference helper process.
///
/// Setup: `uv` (or a Python ≥ 3.13) creates a private virtualenv with mlx-speech and
/// mlx-lm, then the helper downloads the chosen speech model (and, on request, Tiny Aya).
/// Runtime: the helper keeps the chosen speech model loaded; Tiny Aya is loaded on demand.
@Observable
final class SpeechEngine {
    enum Phase: Equatable {
        case checking
        case needsSetup
        case installingRuntime
        case installingModel(fraction: Double, converting: Bool)
        case starting
        case ready
        case failed(String)
    }

    enum ModelState: Equatable {
        case missing, installing(Double), installed
    }

    static let shared = SpeechEngine()

    private(set) var phase: Phase = .checking
    private(set) var speechModels: [SpeechModel: ModelState] = [:]
    private(set) var speechModelError: String?
    private(set) var rewriteModel: ModelState = .missing
    private(set) var rewriteError: String?

    var isReady: Bool { phase == .ready }
    var isBusySettingUp: Bool {
        switch phase {
        case .installingRuntime, .installingModel, .starting: true
        default: false
        }
    }

    @ObservationIgnored private var helper: Process?
    @ObservationIgnored private var helperInput: Pipe?
    @ObservationIgnored private let log = Logger(subsystem: "ch.martinoli.dictum", category: "engine")

    private static let packages = ["mlx-speech==0.5.3", "mlx-lm==0.32.0"]
    private static let runtimeMarker = Paths.runtime.appending(path: ".dictum-runtime")

    private init() {}

    // MARK: - Lifecycle

    /// Called at launch: starts the helper if the runtime is already installed.
    func bootstrap() async {
        guard runtimeIsInstalled else {
            phase = .needsSetup
            return
        }
        do {
            try await startHelper()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Installs whatever is missing (runtime, speech model) and starts the helper.
    func setUp() async {
        guard !isBusySettingUp else { return }
        do {
            if !runtimeIsInstalled {
                phase = .installingRuntime
                try await installRuntime()
            }
            try await startHelper()
            if !isReady {
                try await installModel(AppSettings.shared.speechModel.rawValue)
            }
        } catch {
            log.error("setup failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed(error.localizedDescription)
        }
    }

    func stop() {
        helper?.terminate()
        helper = nil
        helperInput = nil
    }

    // MARK: - Requests

    /// Transcribes with the chosen model. `language` nil lets models that detect the
    /// language do so; returns the text and the language code the model reports.
    func transcribe(_ take: URL, language: SpeechLanguage?, vocabulary: [String] = []) async throws
        -> (text: String, language: String?) {
        var request = HelperRequest(op: "transcribe", path: take.path, language: language?.rawValue,
                                    model: AppSettings.shared.speechModel.rawValue)
        request.vocabulary = vocabulary.isEmpty ? nil : vocabulary
        let reply = try await self.request(request, timeout: 300)
        return (reply.text ?? "", reply.language)
    }

    /// A dictation started: the helper loads what it will need — or pages it back in after
    /// a long idle — while the user is talking rather than after they stop.
    func prepare(rewrite: Bool) {
        guard isReady else { return }
        var request = HelperRequest(op: "prepare", model: AppSettings.shared.speechModel.rawValue)
        request.rewrite = rewrite && rewriteModel == .installed ? true : nil
        Task { _ = try? await self.request(request, timeout: 120) }
    }

    /// Transcribes the finished stretches of a take that is still being recorded, so that
    /// stopping a long dictation only waits for its last stretch.
    func transcribeAhead(_ take: URL, language: SpeechLanguage?, vocabulary: [String]) async {
        var request = HelperRequest(op: "partial", path: take.path, language: language?.rawValue,
                                    model: AppSettings.shared.speechModel.rawValue)
        request.vocabulary = vocabulary.isEmpty ? nil : vocabulary
        _ = try? await self.request(request, timeout: 120)
    }

    /// Downloads another speech model (shown in the Models library).
    func installSpeechModel(_ model: SpeechModel) async {
        speechModelError = nil
        do {
            try await installModel(model.rawValue)
        } catch {
            speechModels[model] = .missing
            speechModelError = error.localizedDescription
        }
    }

    func removeSpeechModel(_ model: SpeechModel) async {
        guard model != AppSettings.shared.speechModel else { return }
        if let reply = try? await request(HelperRequest(op: "remove", model: model.rawValue), timeout: 30) {
            apply(reply)
        }
    }

    /// Switches to `model` and loads it in the background, so the next dictation is instant.
    func use(_ model: SpeechModel) async {
        AppSettings.shared.speechModel = model
        if let reply = try? await request(HelperRequest(op: "select", model: model.rawValue), timeout: 120) {
            apply(reply)
        }
    }

    /// Returns the cleaned text, or the input unchanged if the rewrite drifted from it.
    func rewrite(_ text: String) async throws -> String {
        let reply = try await request(HelperRequest(op: "rewrite", text: text), timeout: 30)
        return reply.text ?? text
    }

    func installRewriteModel() async {
        rewriteError = nil
        do {
            try await installModel("rewrite")
        } catch {
            rewriteModel = .missing
            rewriteError = error.localizedDescription
            log.error("rewrite install failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Pushes the "Keep loaded for" settings to a running helper.
    func applyKeepLoaded() async {
        guard helper?.isRunning == true else { return }
        let settings = AppSettings.shared
        var request = HelperRequest(op: "configure")
        request.asrIdle = settings.speechKeepLoaded.rawValue
        request.rewriteIdle = settings.rewriteKeepLoaded.rawValue
        _ = try? await HelperClient.send(request, socketPath: Paths.socket, timeout: 10)
    }

    func removeRewriteModel() async {
        if let reply = try? await request(HelperRequest(op: "remove", model: "rewrite"), timeout: 30) {
            apply(reply)
        }
    }

    // MARK: - Helper process

    private func request(_ request: HelperRequest, timeout: TimeInterval?) async throws -> HelperMessage {
        if helper?.isRunning != true {
            try await startHelper()
        }
        return try await HelperClient.send(request, socketPath: Paths.socket, timeout: timeout)
    }

    @ObservationIgnored private var startup: Task<Void, Error>?

    /// Starts the helper once, shared by all callers. Runs in its own task, so a caller
    /// being cancelled (Esc) can't abandon it half-way, and any failure ends in `.failed`.
    private func startHelper() async throws {
        if helper?.isRunning == true, startup == nil { return }
        let task = startup ?? Task { @MainActor in
            defer { startup = nil }
            do {
                try await launchHelper()
            } catch {
                phase = .failed(error.localizedDescription)
                throw error
            }
        }
        startup = task
        try await task.value
    }

    private func launchHelper() async throws {
        if helper?.isRunning == true { return }
        guard let script = Bundle.main.url(forResource: "dictum_helper", withExtension: "py") else {
            throw HelperError.failed("dictum_helper.py is missing from the app bundle.")
        }
        phase = .starting
        try FileManager.default.createDirectory(at: Paths.models, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = Paths.python
        let settings = AppSettings.shared
        process.arguments = [
            script.path, "--socket", Paths.socket, "--models", Paths.models.path,
            "--asr-idle", String(settings.speechKeepLoaded.rawValue),
            "--rewrite-idle", String(settings.rewriteKeepLoaded.rawValue),
            "--speech-model", settings.speechModel.rawValue,
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["HF_HOME"] = Paths.huggingFaceHome.path
        environment["HF_HUB_DISABLE_TELEMETRY"] = "1"
        environment["TOKENIZERS_PARALLELISM"] = "false"
        environment["PYTHONUNBUFFERED"] = "1"
        process.environment = environment
        // The helper exits when this pipe closes, i.e. whenever Dictum quits or crashes.
        let input = Pipe()
        process.standardInput = input
        let logFile = Paths.logFile("helper.log")
        process.standardOutput = logFile
        process.standardError = logFile
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { @MainActor in self?.helperDidExit(status: status) }
        }
        try process.run()
        helper = process
        helperInput = input
        log.info("helper started, pid \(process.processIdentifier)")

        // Python + MLX import takes about a second; wait for the socket to answer.
        for _ in 0..<200 {
            if let reply = try? await HelperClient.send(
                HelperRequest(op: "status"), socketPath: Paths.socket, timeout: 2) {
                apply(reply)
                return
            }
            guard process.isRunning else { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        throw HelperError.failed("The speech engine did not start. See ~/Library/Logs/Dictum/helper.log.")
    }

    private func helperDidExit(status: Int32) {
        log.info("helper exited with status \(status)")
        helper = nil
        helperInput = nil
        if phase == .ready || phase == .starting {
            phase = .failed("The speech engine stopped. It restarts on the next dictation.")
        }
    }

    private func apply(_ status: HelperMessage) {
        for (name, state) in status.models ?? [:] {
            guard let model = SpeechModel(rawValue: name) else { continue }
            switch state {
            case "installed", "loaded": speechModels[model] = .installed
            case "missing": speechModels[model] = .missing
            default: break
            }
        }
        if status.models != nil {
            switch speechModels[AppSettings.shared.speechModel] {
            case .installed: phase = .ready
            case .missing, nil: if !isBusySettingUp || phase == .starting { phase = .needsSetup }
            case .installing: break
            }
        }
        switch status.rewrite {
        case "installed", "loaded": rewriteModel = .installed
        case "missing": rewriteModel = .missing
        default: break
        }
    }

    private func installModel(_ name: String) async throws {
        if name == "rewrite" {
            rewriteModel = .installing(0)
        } else if let model = SpeechModel(rawValue: name) {
            speechModels[model] = .installing(0)
            if model == AppSettings.shared.speechModel { phase = .installingModel(fraction: 0, converting: false) }
        }
        let reply = try await request(HelperRequest(op: "install", model: name), timeout: nil) { event in
            Task { @MainActor in self.progress(event) }
        }
        apply(reply)
    }

    private func request(
        _ request: HelperRequest, timeout: TimeInterval?,
        onEvent: @escaping @Sendable (HelperMessage) -> Void
    ) async throws -> HelperMessage {
        if helper?.isRunning != true {
            try await startHelper()
        }
        return try await HelperClient.send(request, socketPath: Paths.socket, timeout: timeout, onEvent: onEvent)
    }

    private func progress(_ event: HelperMessage) {
        let fraction = event.fraction ?? 0
        if event.model == "rewrite" {
            rewriteModel = .installing(fraction)
        } else if let model = event.model.flatMap(SpeechModel.init) {
            speechModels[model] = .installing(fraction)
            if model == AppSettings.shared.speechModel {
                phase = .installingModel(fraction: fraction, converting: event.phase == "convert")
            }
        }
    }

    // MARK: - Runtime

    var runtimeIsInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: Paths.python.path)
            && (try? String(contentsOf: Self.runtimeMarker, encoding: .utf8)) == Self.packages.joined(separator: " ")
    }

    private func installRuntime() async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        if let uv = Self.firstExecutable(Self.uvCandidates) {
            try await run(uv, ["venv", "--clear", "--python", "3.13", Paths.runtime.path])
            try await run(uv, ["pip", "install", "--python", Paths.python.path] + Self.packages)
        } else if let python = Self.firstExecutable(Self.pythonCandidates) {
            try await run(python, ["-m", "venv", "--clear", Paths.runtime.path])
            try await run(Paths.python.path, ["-m", "pip", "install", "--quiet"] + Self.packages)
        } else {
            throw HelperError.failed(
                "Dictum needs uv or Python 3.13+ to install its speech engine. Install uv with “brew install uv”, then try again.")
        }
        try Self.packages.joined(separator: " ").write(to: Self.runtimeMarker, atomically: true, encoding: .utf8)
    }

    private func run(_ executable: String, _ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
        process.environment = environment
        let logFile = Paths.logFile("setup.log")
        process.standardOutput = logFile
        process.standardError = logFile
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        guard status == 0 else {
            throw HelperError.failed(
                "Installing the speech engine failed (\(URL(fileURLWithPath: executable).lastPathComponent) exited with \(status)). See ~/Library/Logs/Dictum/setup.log.")
        }
    }

    private static let uvCandidates = [
        "/opt/homebrew/bin/uv", "/usr/local/bin/uv",
        NSString(string: "~/.local/bin/uv").expandingTildeInPath,
        NSString(string: "~/.cargo/bin/uv").expandingTildeInPath,
    ]

    private static let pythonCandidates = ["3.14", "3.13"].flatMap { version in [
        "/opt/homebrew/bin/python\(version)",
        "/usr/local/bin/python\(version)",
        "/Library/Frameworks/Python.framework/Versions/\(version)/bin/python3",
    ] }

    private static func firstExecutable(_ paths: [String]) -> String? {
        paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
