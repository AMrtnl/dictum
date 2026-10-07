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
    @ObservationIgnored private var processingTask: Task<Void, Never>?
    @ObservationIgnored private var cancelListeners: [Task<Void, Never>] = []
    @ObservationIgnored private var lastText: String?
    @ObservationIgnored private let log = Logger(subsystem: "ch.martinoli.dictum", category: "dictation")

    /// Releases shorter than this are accidental taps and get discarded silently.
    private static let minimumHold: Duration = .milliseconds(250)
    /// Takes whose loudest moment stays under this are treated as silence.
    private static let speechLevel: Float = 0.12

    private struct PanelConfig: Equatable {
        var style: RecordingWindowStyle
        var stopKeys: [String]
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
        guard state == .idle else { return }
        guard canDictate() else { return }

        activeShortcut = shortcut
        activeMode = shortcut == .pushToTalkRewrite ? .rewrite : settings.mode
        let panel = currentPanel(for: shortcut)
        do {
            // Through `self.panel`, so levels follow a Classic ↔ Mini switch mid-recording.
            try recorder.start(deviceUID: settings.microphoneUID) { [weak self] level in
                self?.panel?.content.push(level: level)
            }
        } catch {
            showToast(error.localizedDescription)
            return
        }

        log.info("recording (\(self.activeMode.rawValue, privacy: .public))")
        state = .recording
        recordingStart = .now
        listenForCancel()
        Sounds.playStart()
        hideToast()
        panel?.content.mode = .recording
        panel?.content.modeTitle = activeMode.title
        panel?.content.resetLevels()
        panel?.show()
    }

    private func released(_ shortcut: KeyboardShortcuts.Name) {
        guard state == .recording, shortcut == activeShortcut, let start = recordingStart else { return }
        recordingStart = nil
        let held = ContinuousClock.now - start
        let take = recorder.stop()

        guard held >= Self.minimumHold else {
            discard(take)
            finish()
            return
        }
        guard let take else {
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
        processingTask = Task { await process(take, mode: mode) }
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

    private func process(_ take: AudioRecorder.Take, mode: DictationMode) async {
        do {
            var text = try await engine.transcribe(take.url, language: settings.language)
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

            discard(take)
            finish()
            deliver(text)
            lastText = text
            if settings.saveHistory {
                HistoryStore.shared.add(HistoryEntry(
                    text: text, original: original, duration: take.duration,
                    mode: mode.rawValue, language: settings.language.rawValue))
            }
            if let note { showToast(note, symbol: "info.circle.fill") }
        } catch {
            guard !Task.isCancelled else { return discard(take) }
            log.error("transcription failed: \(error.localizedDescription, privacy: .public)")
            finish()
            keepForRetry(take, mode: mode, error: error)
        }
    }

    private func deliver(_ text: String) {
        if TextInserter.insert(text, keepInClipboard: settings.keepInClipboard) == .copiedOnly {
            showToast("Copied — allow Accessibility in Settings to paste automatically", symbol: "doc.on.clipboard.fill")
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
            var text = try await engine.transcribe(URL(fileURLWithPath: path), language: settings.language)
            var original: String?
            if entry.mode == DictationMode.rewrite.rawValue, engine.rewriteModel == .installed,
               let cleaned = try? await engine.rewrite(text), cleaned != text {
                original = text
                text = cleaned
            }
            var updated = entry
            updated.text = text
            updated.original = original
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
        recorder.cancel()
        processingTask?.cancel()
        finish()
    }

    private func finish() {
        state = .idle
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
        let config = PanelConfig(style: settings.recordingWindowStyle, stopKeys: Self.keys(for: shortcut))
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
            case .mini: MiniRecordingView()
            case .classic: ClassicRecordingView(stopKeys: config.stopKeys)
            case .none: nil
            }
            view?.onToggleSize = { [weak self] in self?.toggleWindowSize() }
            view?.onToggleRewrite = { [weak self] in
                guard let self else { return }
                settings.mode = settings.mode == .rewrite ? .dictation : .rewrite
            }
            view?.onOpenSettings = { WindowManager.shared.show(.settings) }
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
            _ = (settings.recordingWindowStyle, settings.alwaysShowIndicator, settings.mode)
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
        await process(AudioRecorder.Take(url: copy, duration: 0, peakLevel: 1), mode: mode)
        log.info("debug transcript: \(self.lastText ?? "<none>", privacy: .public)")
    }

    /// One press/hold/release cycle without the keyboard, for checking the window:
    /// `open Dictum.app --args -previewPill 4`
    func simulateHold(seconds: Double) {
        Task {
            pressed(.pushToTalk)
            try? await Task.sleep(for: .seconds(seconds))
            released(.pushToTalk)
        }
    }
    #endif
}
