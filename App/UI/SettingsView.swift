import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct GeneralSettings: View {
    @Bindable private var settings = AppSettings.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Dictate", name: .pushToTalk)
                KeyboardShortcuts.Recorder("Dictate with Rewrite", name: .pushToTalkRewrite)
                KeyboardShortcuts.Recorder("Paste last transcript", name: .pasteLast)
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("Hold a dictation shortcut while you speak and let go to paste. Esc cancels.")
            }

            Section("Dictation") {
                Picker("Default mode", selection: $settings.mode) {
                    ForEach(DictationMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(settings.mode.summary).font(.callout).foregroundStyle(.secondary)

                Picker("Language", selection: $settings.language) {
                    ForEach(SpeechLanguage.allCases) { Text($0.title).tag($0) }
                }
                Text("A hint for the speech model. Mixed French and English dictation still comes out in the language you speak.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("Pasting") {
                Toggle("Keep the transcript in the clipboard", isOn: $settings.keepInClipboard)
                Text(settings.keepInClipboard
                     ? "The transcript stays in the clipboard after pasting."
                     : "Your previous clipboard is restored right after pasting.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("System") {
                Toggle("Launch Dictum at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
    }
}

struct RecordingSettings: View {
    @Bindable private var settings = AppSettings.shared
    @State private var devices = AudioDevices.inputs()

    var body: some View {
        Form {
            Section("Recording window") {
                RecordingStylePicker(selection: $settings.recordingWindowStyle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                Toggle("Always show", isOn: $settings.alwaysShowIndicator)
                    .disabled(settings.recordingWindowStyle == .none)
                Text("Keeps a dimmed indicator on screen between dictations. It does no work while idle.")
                    .font(.callout).foregroundStyle(.secondary)
                LabeledContent("Position") {
                    Button("Reset to Bottom Centre") { RecordingPanel.resetPositions() }
                }
                Text("Drag the recording window anywhere; Dictum remembers where you leave each style. The ↘↖ button on Classic collapses it to Mini.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("Input") {
                Picker("Microphone", selection: $settings.microphoneUID) {
                    Text("System default").tag(String?.none)
                    ForEach(devices) { Text($0.name).tag(Optional($0.uid)) }
                }
                Toggle("Play start and stop sounds", isOn: $settings.playSounds)
            }
        }
        .formStyle(.grouped)
        .onAppear { devices = AudioDevices.inputs() }
    }
}

struct ModelSettings: View {
    @Bindable private var settings = AppSettings.shared
    private let engine = SpeechEngine.shared

    var body: some View {
        Form {
            Section {
                speechStatus
                Picker("Keep loaded", selection: $settings.speechKeepLoaded) {
                    ForEach([KeepLoaded.always, .oneHour, .fiveMinutes]) { Text($0.title).tag($0) }
                }
                .onChange(of: settings.speechKeepLoaded) { Task { await engine.applyKeepLoaded() } }
                Text("“Always” makes every dictation instant and uses about 1.5 GB of memory. Shorter times free it between bursts of dictation; the next one then takes a few seconds longer.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: {
                Text("Speech — Cohere Transcribe")
            } footer: {
                Text("4-bit, 14 languages, runs on this Mac. Apache 2.0.")
            }

            Section {
                rewriteStatus
                Picker("Keep loaded", selection: $settings.rewriteKeepLoaded) {
                    ForEach([KeepLoaded.thirtySeconds, .oneMinute, .fiveMinutes, .oneHour]) { Text($0.title).tag($0) }
                }
                .onChange(of: settings.rewriteKeepLoaded) { Task { await engine.applyKeepLoaded() } }
            } header: {
                Text("Rewrite — Tiny Aya Global")
            } footer: {
                Text("3.35B parameters, 4-bit. Licensed CC-BY-NC 4.0: personal, non-commercial use only.")
            }

            Section {
                LabeledContent("Location") {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Paths.models]) }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var speechStatus: some View {
        switch engine.phase {
        case .ready:
            LabeledContent("Status") { GrantedLabel(text: "Ready") }
        case .installingRuntime:
            LabeledContent("Status") { ProgressView().controlSize(.small); Text("Setting up runtime…") }
        case .installingModel(let fraction, let converting):
            VStack(alignment: .leading, spacing: 6) {
                Text(converting ? "Converting to 4-bit…" : "Downloading… \(Int(fraction * 100)) %").font(.callout)
                ProgressView(value: fraction)
            }
        case .checking, .starting:
            LabeledContent("Status") { ProgressView().controlSize(.small) }
        case .needsSetup:
            LabeledContent("Status") {
                Button("Install (2.4 GB download)") { Task { await engine.setUp() } }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text(message).font(.callout).foregroundStyle(.red)
                Button("Try Again") { Task { await engine.setUp() } }
            }
        }
    }

    @ViewBuilder
    private var rewriteStatus: some View {
        switch engine.rewriteModel {
        case .installed:
            LabeledContent("Status") {
                HStack {
                    GrantedLabel(text: "Installed")
                    Button("Remove") { Task { await engine.removeRewriteModel() } }
                }
            }
        case .installing(let fraction):
            VStack(alignment: .leading, spacing: 6) {
                Text(fraction >= 1 ? "Converting to 4-bit…" : "Downloading… \(Int(fraction * 100)) %").font(.callout)
                ProgressView(value: fraction)
            }
        case .missing:
            LabeledContent("Status") {
                Button("Download (3.6 GB, 1.9 GB on disk)") { Task { await engine.installRewriteModel() } }
                    .disabled(!engine.isReady)
            }
            if let error = engine.rewriteError {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        }
    }
}

struct HistorySettings: View {
    @Bindable private var settings = AppSettings.shared
    private let history = HistoryStore.shared
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section {
                Toggle("Save dictation history", isOn: $settings.saveHistory)
                LabeledContent("Saved dictations", value: "\(history.entries.count)")
                HStack {
                    Button("Open History…") { WindowManager.shared.show(.history) }
                    Spacer()
                    Button("Clear History…", role: .destructive) { confirmClear = true }
                        .disabled(history.entries.isEmpty)
                }
            } footer: {
                Text("Text only, stored on this Mac. Audio is kept only for failed dictations, so you can retry them.")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Clear all saved dictations?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { history.clear() }
        }
    }
}

struct AboutSettings: View {
    private let permissions = Permissions.shared
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    AppGlyph(size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dictum").font(.title2.weight(.semibold))
                        Text("Version \(version) · on-device dictation for Apple Silicon")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Permissions") {
                permissionRow("Microphone", granted: permissions.microphone == .granted) {
                    Task { await permissions.requestMicrophone() }
                }
                permissionRow("Accessibility (to paste)", granted: permissions.accessibility == .granted) {
                    permissions.requestAccessibility()
                }
            }

            Section {
                HStack {
                    Button("Show Welcome Window") { WindowManager.shared.show(.onboarding) }
                    Button("Open Logs") { NSWorkspace.shared.open(Paths.logs) }
                }
            } footer: {
                Text("Cohere Transcribe (Apache 2.0) · Tiny Aya (CC-BY-NC 4.0) · mlx-speech, mlx-lm (MIT) · KeyboardShortcuts (MIT)")
            }
        }
        .formStyle(.grouped)
    }

    private func permissionRow(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        LabeledContent(title) {
            if granted { GrantedLabel() } else { Button("Allow…", action: action) }
        }
    }
}

/// The app's mark: white waveform bars in a dark rounded square.
struct AppGlyph: View {
    var size: CGFloat = 64

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.04)], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay {
                HStack(spacing: size * 0.05) {
                    ForEach([0.3, 0.55, 0.85, 1.0, 0.7, 0.45, 0.25], id: \.self) { height in
                        Capsule().fill(.white).frame(width: size * 0.055, height: size * 0.5 * height)
                    }
                }
            }
            .shadow(color: .black.opacity(0.2), radius: size * 0.06, y: size * 0.03)
    }
}
