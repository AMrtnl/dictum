import AppKit
import KeyboardShortcuts
import Observation
import OSLog

extension KeyboardShortcuts.Name {
    /// ⌥Space is free on this Mac: superwhisper holds Right ⌘, Sotto uses fn,
    /// Wispr Flow uses fn combos (and ⌃⌘V, hence ⌃⌥V for Paste Last).
    static let pushToTalk = Self("pushToTalk", initial: .init(.space, modifiers: [.option]))
    static let pushToTalkRewrite = Self("pushToTalkRewrite", initial: .init(.space, modifiers: [.option, .shift]))
    static let pasteLast = Self("pasteLast", initial: .init(.v, modifiers: [.control, .option]))
}

/// Hold-to-talk state machine: hotkey down → record, hotkey up → transcribe
/// (→ rewrite) → paste → idle. Esc cancels; it is only grabbed during a dictation.
@Observable
final class DictationController {
    enum State { case idle, recording, processing }

    static let shared = DictationController()

    private(set) var state: State = .idle

    @ObservationIgnored private let settings = AppSettings.shared
    @ObservationIgnored private let engine = SpeechEngine.shared
    @ObservationIgnored private let recorder = AudioRecorder()
    @ObservationIgnored private var panel: RecordingPanel?
    @ObservationIgnored private var panelConfig: PanelConfig?
    @ObservationIgnored private var retiringPanels: [RecordingPanel] = []
    @ObservationIgnored private var toast: RecordingPanel?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var activeMode: DictationMode = .dictation
    @ObservationIgnored private var activeShortcut: KeyboardShortcuts.Name = .pushToTalk
    @ObservationIgnored private var recordingStart: ContinuousClock.Instant?
    /// Hands-free: recording continues after the shortcut is released, until it is pressed again.
    @ObservationIgnored private var isLocked = false
    @ObservationIgnored private var processingTask: Task<Void, Never>?
    @ObservationIgnored private var cancelListeners: [Task<Void, Never>] = []
    @ObservationIgnored private var lastText: String?
    @ObservationIgnored private var askedForAccessibility = false
    @ObservationIgnored private let log = Logger(subsystem: "ch.martinoli.dictum", category: "dictation")

    /// "Hold to talk": releases shorter than this are accidental taps and get discarded.
    private static let minimumHold: Duration = .milliseconds(250)
    /// "Tap to lock": releases shorter than this lock the dictation hands-free.
    private static let tapThreshold: Duration = .milliseconds(350)
    /// Takes whose loudest moment stays under this are treated as silence.
    private static let speechLevel: Float = 0.12

    private struct PanelConfig: Equatable {
        var style: RecordingWindowStyle
        var stopKeys: [String]
        var waveform: WaveformStyle
    }

    private init() {}

    func start() {
        KeyboardShortcuts.onKeyDown(for: .pushToTalk) { [weak self] in self?.pressed(.pushToTalk) }
        KeyboardShortcuts.onKeyUp(for: .pushToTalk) { [weak self] in self?.released(.pushToTalk) }
        KeyboardShortcuts.onKeyDown(for: .pushToTalkRewrite) { [weak self] in self?.pressed(.pushToTalkRewrite) }
        KeyboardShortcuts.onKeyUp(for: .pushToTalkRewrite) { [weak self] in self?.released(.pushToTalkRewrite) }
        KeyboardShortcuts.onKeyUp(for: .pasteLast) { [weak self] in self?.pasteLast() }
        observeIndicatorSettings()
        refreshIndicator()
    }

    var lastTranscript: String? { lastText ?? HistoryStore.shared.last?.text }

    // MARK: - Hotkey

    private func pressed(_ shortcut: KeyboardShortcuts.Name) {
        // A press while hands-free (or in toggle mode) ends the dictation. Using the other
        // dictation shortcut to stop switches mode: talk freely, then decide to rewrite.
        if state == .recording {
            guard isLocked else { return }
            if shortcut != activeShortcut {
                activeMode = shortcut == .pushToTalkRewrite ? .rewrite : settings.mode
            }
            stopRecording()
            return
        }
        guard state == .idle else { return }
        guard canDictate() else { return }

        activeShortcut = shortcut
        activeMode = shortcut == .pushToTalkRewrite ? .rewrite : settings.mode
        let panel = currentPanel(for: shortcut)
        do {
            // Through `self.panel`, so levels follow a Classic ↔ Mini switch mid-recording.
            try recorder.start(deviceUID: settings.microphoneUID) { [weak self] level in
                self?.panel?.content.push(level: level)
            } onLimit: { [weak self] in
                self?.stopRecording()
            }
        } catch {
            showToast(error.localizedDescription)
            return
        }

        log.info("recording (\(self.activeMode.rawValue, privacy: .public))")
        state = .recording
        recordingStart = .now
        setLocked(settings.shortcutBehavior == .toggle)
        listenForCancel()
        Sounds.playStart()
        hideToast()
        panel?.content.mode = .recording
        panel?.content.modeTitle = activeMode.title
        panel?.content.resetLevels()
        panel?.show()
    }

    private func released(_ shortcut: KeyboardShortcuts.Name) {
        guard state == .recording, shortcut == activeShortcut, !isLocked, let start = recordingStart else { return }
        let held = ContinuousClock.now - start
        switch settings.shortcutBehavior {
        case .hybrid where held < Self.tapThreshold:
            setLocked(true)  // a tap: keep recording hands-free
            if lockHintsShown < 3 {
                lockHintsShown += 1
                let keys = Self.keys(for: activeShortcut).joined()
                showToast("Hands-free — press \(keys) again to stop", symbol: "lock.fill")
            }
        case .hold where held < Self.minimumHold:
            recorder.cancel()  // an accidental tap
            finish()
        default:
            stopRecording()
        }
    }

    /// Ends the recording and starts transcription (or explains why there's nothing to do).
    private func stopRecording() {
        guard state == .recording else { return }
        recordingStart = nil
        setLocked(false)
        guard let take = recorder.stop() else {
            Sounds.playEmpty()
            finish()
            showToast("Nothing was recorded — check the microphone", symbol: "mic.slash.fill")
            return
        }
        guard take.peakLevel >= Self.speechLevel else {
            discard(take)
            Sounds.playEmpty()
            finish()
            showToast("No speech detected", symbol: "mic.slash.fill")
            return
        }

        Sounds.playStop()
        state = .processing
        panel?.content.processingLabel = "Transcribing…"
        panel?.content.mode = .processing
        let mode = activeMode
        let deliverText = !debugNoPaste
        processingTask = Task { await process(take, mode: mode, deliverText: deliverText) }
    }

    /// Set by the debug harness: run the real recorder and pipeline but never paste.
    @ObservationIgnored var debugNoPaste = false

    private func setLocked(_ locked: Bool) {
        isLocked = locked
        panel?.content.isLocked = locked
    }

    private var lockHintsShown: Int {
        get { UserDefaults.standard.integer(forKey: "lockHintsShown") }
        set { UserDefaults.standard.set(newValue, forKey: "lockHintsShown") }
    }

    /// Whether a dictation can start right now; explains why not otherwise.
    private func canDictate() -> Bool {
        switch engine.phase {
        case .installingModel(let fraction, _):
            showToast("Downloading the speech model… \(Int(fraction * 100)) %", symbol: "arrow.down.circle.fill")
            return false
        case .installingRuntime:
            showToast("Setting up the speech engine…", symbol: "arrow.down.circle.fill")
            return false
        case .needsSetup:
            showToast("Set up the speech engine first")
            WindowManager.shared.show(.onboarding)
            return false
        case .failed where !engine.runtimeIsInstalled:
            WindowManager.shared.show(.onboarding)
            return false
        default:
            break
        }
        if case .installing(let fraction) = engine.rewriteModel, fraction >= 0.999 {
            showToast("Finishing the Rewrite model install — try again in a moment", symbol: "arrow.down.circle.fill")
            return false
        }
        let permissions = Permissions.shared
        permissions.refresh()
        switch permissions.microphone {
        case .granted:
            return true
        case .notAsked:
            Task { await permissions.requestMicrophone() }
            return false
        case .denied:
            showToast("Microphone access is off — enable it in System Settings", symbol: "mic.slash.fill")
            permissions.open("Privacy_Microphone")
            return false
        }
    }

    // MARK: - Processing

    /// - Parameter deliverText: false only for the debug file test, which must never
    ///   paste into (or touch the clipboard of) whatever app is in front.
    private func process(_ take: AudioRecorder.Take, mode: DictationMode, deliverText: Bool = true) async {
        do {
            var (text, language) = try await transcribe(take.url)
            guard !Task.isCancelled else { return discard(take) }
            var original: String?
            if text.isEmpty {
                discard(take)
                finish()
                Sounds.playEmpty()
                showToast("No speech detected", symbol: "mic.slash.fill")
                return
            }

            var note: String?
            if mode == .rewrite {
                if engine.rewriteModel == .installed {
                    panel?.content.processingLabel = "Rewriting…"
                    if let cleaned = try? await engine.rewrite(text), cleaned != text {
                        original = text
                        text = cleaned
                    }
                    guard !Task.isCancelled else { return discard(take) }
                } else {
                    note = "Rewrite model not installed — pasted the plain transcript"
                }
            }

            text = VocabularyStore.shared.apply(to: text)
            original = original.map(VocabularyStore.shared.apply)
            let frontmost = NSWorkspace.shared.frontmostApplication
            let app = frontmost?.localizedName
            if settings.saveTrainingData {
                // The verbatim transcript is the training label; a rewrite is kept alongside.
                TrainingDataStore.shared.add(take: take.url, transcription: original ?? text,
                                             rewrite: original == nil ? nil : text,
                                             language: language, duration: take.duration)
            }
            discard(take)
            finish()
            if deliverText { deliver(text) }
            lastText = text
            if settings.saveHistory {
                HistoryStore.shared.add(HistoryEntry(
                    text: text, original: original, duration: take.duration,
                    mode: mode.rawValue, language: language, app: app,
                    appBundleID: frontmost?.bundleIdentifier))
            }
            if let note { showToast(note, symbol: "info.circle.fill") }
        } catch {
            guard !Task.isCancelled else { return discard(take) }
            log.error("transcription failed: \(error.localizedDescription, privacy: .public)")
            finish()
            keepForRetry(take, mode: mode, error: error)
        }
    }

    /// Transcribes the take and returns the text with its language code.
    ///
    /// Models that detect the language (Qwen3, Nemotron) do it themselves, phrase by phrase,
    /// so one dictation can mix languages; Vocabulary words are passed as hints. For Cohere,
    /// which needs a language, Dictum transcribes with the last language used and — if the
    /// text turns out to be another of the user's languages — again with that one (~0.25 s).
    private func transcribe(_ url: URL) async throws -> (String, String) {
        let model = settings.speechModel
        if model.detectsLanguage {
            let hint: SpeechLanguage? = settings.autoLanguage ? nil : settings.language
            let words = model.usesVocabulary ? VocabularyStore.shared.terms.map(\.word) : []
            let result = try await engine.transcribe(url, language: hint, vocabulary: words)
            return (result.text, result.language ?? hint?.rawValue ?? "en")
        }
        guard settings.autoLanguage, settings.spokenLanguages.count > 1 else {
            let language = settings.autoLanguage ? (settings.spokenLanguages.first ?? settings.language) : settings.language
            return (try await engine.transcribe(url, language: language).text, language.rawValue)
        }
        let spoken = settings.spokenLanguages
        let hint = settings.lastLanguage.flatMap { spoken.contains($0) ? $0 : nil } ?? spoken[0]
        let first = try await engine.transcribe(url, language: hint).text
        guard let detected = LanguageDetector.detect(first, among: spoken), detected != hint else {
            return (first, hint.rawValue)
        }
        log.info("language: \(hint.rawValue, privacy: .public) → \(detected.rawValue, privacy: .public)")
        settings.lastLanguage = detected
        return (try await engine.transcribe(url, language: detected).text, detected.rawValue)
    }

    private func deliver(_ text: String) {
        Task {
            switch await TextInserter.insert(text, keepInClipboard: settings.keepInClipboard) {
            case .pasted:
                break
            case .copiedOnly:
                showToast("Copied — Dictum needs Accessibility access to paste automatically", symbol: "doc.on.clipboard.fill")
                // Once per launch, bring up macOS's own prompt / the Accessibility pane.
                if !askedForAccessibility {
                    askedForAccessibility = true
                    Permissions.shared.requestAccessibility()
                }
            case .secureInput:
                showToast("Secure input is on in this app — press ⌘V to paste", symbol: "lock.fill")
            }
        }
    }

    /// Never lose a dictation: failed takes stay on disk and show up in History with Retry.
    private func keepForRetry(_ take: AudioRecorder.Take, mode: DictationMode, error: Error) {
        let kept = Paths.support.appending(path: "failed/\(take.url.lastPathComponent)")
        try? FileManager.default.createDirectory(at: kept.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.moveItem(at: take.url, to: kept)
        HistoryStore.shared.add(HistoryEntry(
            text: "", duration: take.duration, mode: mode.rawValue, language: settings.language.rawValue,
            status: .failed, audioPath: kept.path))
        showToast("Transcription failed — saved in History to retry")
    }

    /// Re-runs a failed entry; the result goes to the clipboard (focus is on the History window).
    func retry(_ entry: HistoryEntry) async {
        guard let path = entry.audioPath else { return }
        do {
            var (text, _) = try await transcribe(URL(fileURLWithPath: path))
            var original: String?
            if entry.mode == DictationMode.rewrite.rawValue, engine.rewriteModel == .installed,
               let cleaned = try? await engine.rewrite(text), cleaned != text {
                original = text
                text = cleaned
            }
            var updated = entry
            updated.text = VocabularyStore.shared.apply(to: text)
            updated.original = original.map(VocabularyStore.shared.apply)
            text = updated.text
            updated.status = .done
            updated.audioPath = nil
            try? FileManager.default.removeItem(atPath: path)
            HistoryStore.shared.replace(updated)
            TextInserter.copy(text)
            lastText = text
        } catch {
            showToast("Retry failed: \(error.localizedDescription)")
        }
    }

    private func pasteLast() {
        guard state == .idle, let text = lastTranscript else { return }
        deliver(text)
    }

    // MARK: - Cancel / finish

    private func cancel() {
        guard state != .idle else { return }
        log.info("cancelled")
        recordingStart = nil
        setLocked(false)
        recorder.cancel()
        processingTask?.cancel()
        finish()
    }

    private func finish() {
        state = .idle
        if isLocked { setLocked(false) }
        processingTask = nil
        cancelListeners.forEach { $0.cancel() }
        cancelListeners = []
        if settings.alwaysShowIndicator, settings.recordingWindowStyle != .none, let panel {
            panel.content.mode = .idle
            panel.content.resetLevels()
        } else {
            panel?.hide()
        }
    }

    private func discard(_ take: AudioRecorder.Take?) {
        if let take { try? FileManager.default.removeItem(at: take.url) }
    }

    /// Esc cancels. While the shortcut is still held, Esc arrives with its modifiers
    /// (⌥Esc for ⌥Space), and hot keys match modifiers exactly, so listen for both.
    private func listenForCancel() {
        var variants = [KeyboardShortcuts.Shortcut(.escape)]
        if let held = KeyboardShortcuts.getShortcut(for: activeShortcut)?.modifiers, !held.isEmpty {
            variants.append(KeyboardShortcuts.Shortcut(.escape, modifiers: held))
        }
        cancelListeners = variants.map { shortcut in
            Task { [weak self] in
                for await event in KeyboardShortcuts.events(for: shortcut) where event == .keyDown {
                    self?.cancel()
                }
            }
        }
    }

    // MARK: - Recording window

    private func currentPanel(for shortcut: KeyboardShortcuts.Name = .pushToTalk) -> RecordingPanel? {
        let config = PanelConfig(style: settings.recordingWindowStyle, stopKeys: Self.keys(for: shortcut),
                                 waveform: settings.waveformStyle)
        if config != panelConfig {
            if let old = panel {  // cross-fade: keep the old window alive while it fades out
                retiringPanels.append(old)
                old.hide()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.retiringPanels.removeAll { $0 === old }
                }
            }
            panelConfig = config
            let view: RecordingWindowView? = switch config.style {
            case .mini: MiniRecordingView(style: config.waveform)
            case .classic: ClassicRecordingView(stopKeys: config.stopKeys, style: config.waveform)
            case .none: nil
            }
            view?.onToggleSize = { [weak self] in self?.toggleWindowSize() }
            view?.onToggleRewrite = { [weak self] in
                guard let self else { return }
                settings.mode = settings.mode == .rewrite ? .dictation : .rewrite
            }
            view?.onOpenSettings = { WindowManager.shared.show(.home) }
            view?.rewriteOn = settings.mode == .rewrite
            panel = view.map { RecordingPanel(content: $0, positionKey: config.style.rawValue) }
        }
        return panel
    }

    /// The collapse / expand control: Classic ↔ Mini.
    private func toggleWindowSize() {
        settings.recordingWindowStyle = settings.recordingWindowStyle == .classic ? .mini : .classic
    }

    /// Rebuilds the window for a new style while a dictation is on screen, keeping its state.
    private func swapPanelLive() {
        let previous = panel?.content
        guard let panel = currentPanel(for: activeShortcut), panel.content !== previous else { return }
        panel.content.modeTitle = activeMode.title
        panel.content.processingLabel = previous?.processingLabel ?? "Transcribing…"
        panel.content.mode = state == .recording ? .recording : .processing
        panel.content.resetLevels()
        panel.show()
    }

    /// Shows or hides the resting indicator when its settings change.
    private func refreshIndicator() {
        guard state == .idle else { return swapPanelLive() }
        if settings.alwaysShowIndicator, let panel = currentPanel() {
            panel.content.mode = .idle
            panel.content.resetLevels()
            panel.show()
        } else {
            panel?.hide()
            if settings.recordingWindowStyle == .none { panel = nil; panelConfig = nil }
        }
    }

    private func observeIndicatorSettings() {
        withObservationTracking {
            _ = (settings.recordingWindowStyle, settings.alwaysShowIndicator, settings.mode, settings.waveformStyle)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.panel?.content.rewriteOn = self.settings.mode == .rewrite
                self.refreshIndicator()
                self.observeIndicatorSettings()
            }
        }
    }

    func showToast(_ message: String, symbol: String = "exclamationmark.circle.fill") {
        toastTask?.cancel()
        toast?.orderOut(nil)
        if state == .idle { panel?.orderOut(nil) }  // the toast takes the indicator's spot
        let toast = RecordingPanel(content: ToastView(message, symbol: symbol),
                                   anchor: RecordingPanel.Anchor.saved(for: RecordingWindowStyle.mini.rawValue))
        self.toast = toast
        toast.show()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            toast.hide()
            self?.refreshIndicator()
        }
    }

    private func hideToast() {
        toastTask?.cancel()
        toast?.orderOut(nil)
        toast = nil
    }

    /// Key caps for a shortcut, e.g. ["⌥", "Space"].
    static func keys(for name: KeyboardShortcuts.Name) -> [String] {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else { return [] }
        let modifiers = shortcut.modifiers.ks_symbolicRepresentation
        let key = String(shortcut.description.dropFirst(modifiers.count))
        return modifiers.map(String.init) + [key]
    }

    #if DEBUG
    /// Runs a WAV file through the real pipeline (transcribe → rewrite → paste → history):
    /// `open Dictum.app --args -debugTranscribe /path/to/take.wav -debugMode rewrite`
    func debugTranscribe(_ path: String, mode: DictationMode) async {
        let copy = Paths.takes.appending(path: "debug-\(UUID().uuidString).wav")
        try? FileManager.default.createDirectory(at: Paths.takes, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: copy)
        state = .processing
        let panel = currentPanel()
        panel?.content.mode = .processing
        panel?.show()
        await process(AudioRecorder.Take(url: copy, duration: 0, peakLevel: 1), mode: mode, deliverText: false)
        log.info("debug transcript: \(self.lastText ?? "<none>", privacy: .public)")
    }

    /// One press/hold/release cycle without the keyboard, for checking the window:
    /// `open Dictum.app --args -previewPill 4`
    func simulateHold(seconds: Double) {
        debugNoPaste = true
        Task {
            pressed(.pushToTalk)
            try? await Task.sleep(for: .seconds(seconds))
            released(.pushToTalk)
        }
    }
    #endif
}
