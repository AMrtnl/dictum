import KeyboardShortcuts
import SwiftUI

@main
struct DictumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
        } label: {
            MenuBarIcon()
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = Permissions.shared
        DictationController.shared.start()
        Task {
            await SpeechEngine.shared.bootstrap()
            let engine = SpeechEngine.shared
            if !AppSettings.shared.hasCompletedOnboarding || engine.phase == .needsSetup {
                WindowManager.shared.show(.onboarding)
            }
        }
        #if DEBUG
        let preview = UserDefaults.standard.double(forKey: "previewPill")
        if preview > 0 { DictationController.shared.simulateHold(seconds: preview) }
        if UserDefaults.standard.bool(forKey: "runSetUp") { Task { await SpeechEngine.shared.setUp() } }
        if let path = UserDefaults.standard.string(forKey: "snapshotUI") {
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                WindowManager.shared.snapshot(to: URL(fileURLWithPath: path))
                NSApplication.shared.terminate(nil)
            }
        }
        if let path = UserDefaults.standard.string(forKey: "debugTranscribe") {
            let mode = UserDefaults.standard.string(forKey: "debugMode").flatMap(DictationMode.init) ?? .dictation
            Task {
                while !SpeechEngine.shared.isReady { try? await Task.sleep(for: .milliseconds(200)) }
                await DictationController.shared.debugTranscribe(path, mode: mode)
            }
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        SpeechEngine.shared.stop()
    }
}

/// Template symbol that reflects what Dictum is doing.
private struct MenuBarIcon: View {
    private let controller = DictationController.shared
    private let engine = SpeechEngine.shared

    var body: some View {
        Image(systemName: symbol)
    }

    private var symbol: String {
        switch controller.state {
        case .recording: return "waveform.circle.fill"
        case .processing: return "ellipsis.circle"
        case .idle: break
        }
        switch engine.phase {
        case .installingRuntime, .installingModel: return "arrow.down.circle"
        case .needsSetup, .failed: return "exclamationmark.triangle"
        default: return "waveform"
        }
    }
}

private struct MenuContent: View {
    @Bindable private var settings = AppSettings.shared
    private let engine = SpeechEngine.shared
    private let controller = DictationController.shared

    var body: some View {
        Text(status)
        if engine.phase == .needsSetup || engine.phase.isFailure {
            Button("Set Up Dictum…") { WindowManager.shared.show(.onboarding) }
        }
        Divider()

        Button("Paste Last Transcript") { if let text = controller.lastTranscript { TextInserter.insert(text, keepInClipboard: settings.keepInClipboard) } }
            .disabled(controller.lastTranscript == nil)
        Button("Copy Last Transcript") { if let text = controller.lastTranscript { TextInserter.copy(text) } }
            .disabled(controller.lastTranscript == nil)
        Divider()

        Picker("Mode", selection: $settings.mode) {
            ForEach(DictationMode.allCases) { Text($0.title).tag($0) }
        }
        Picker("Language", selection: $settings.language) {
            ForEach(SpeechLanguage.allCases) { Text($0.title).tag($0) }
        }
        Picker("Microphone", selection: $settings.microphoneUID) {
            Text("System Default").tag(String?.none)
            ForEach(AudioDevices.inputs()) { Text($0.name).tag(Optional($0.uid)) }
        }
        Picker("Recording Window", selection: $settings.recordingWindowStyle) {
            ForEach(RecordingWindowStyle.allCases) { Text($0.title).tag($0) }
        }
        Divider()

        Button("History…") { WindowManager.shared.show(.history) }
        Button("Settings…") { WindowManager.shared.show(.settings) }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Dictum") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var status: String {
        switch engine.phase {
        case .checking, .starting: return "Starting…"
        case .needsSetup: return "Speech engine not installed"
        case .installingRuntime: return "Setting up the speech engine…"
        case .installingModel(let fraction, let converting):
            return converting ? "Converting the speech model…" : "Downloading the speech model… \(Int(fraction * 100)) %"
        case .failed: return "Speech engine needs attention"
        case .ready:
            switch controller.state {
            case .recording: return "Listening…"
            case .processing: return "Transcribing…"
            case .idle:
                let keys = DictationController.keys(for: .pushToTalk).joined()
                return keys.isEmpty ? "Ready" : "Ready — hold \(keys) to dictate"
            }
        }
    }
}

extension SpeechEngine.Phase {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
