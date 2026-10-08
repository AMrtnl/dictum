import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct ConfigurationPage: View {
    @Bindable private var settings = AppSettings.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Dictate", name: .pushToTalk)
                KeyboardShortcuts.Recorder("Dictate with Rewrite", name: .pushToTalkRewrite)
                KeyboardShortcuts.Recorder("Paste last transcript", name: .pasteLast)
                Picker("When I press the shortcut", selection: $settings.shortcutBehavior) {
                    ForEach(ShortcutBehavior.allCases) { Text($0.title).tag($0) }
                }
                Text(settings.shortcutBehavior.summary).font(.callout).foregroundStyle(.secondary)
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("Esc cancels a dictation. Pressing the other dictation shortcut to stop a hands-free dictation switches its mode.")
            }

            Section("Recording window") {
                RecordingStylePicker(selection: $settings.recordingWindowStyle, waveform: settings.waveformStyle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                HStack(alignment: .firstTextBaseline) {
                    Text(settings.recordingWindowStyle.summary).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Preview on Screen") { DictationController.shared.previewRecordingWindow() }
                        .disabled(settings.recordingWindowStyle == .none)
                        .help("Shows the recording window where it will appear, with made-up sound — the microphone stays off.")
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Waveform")
                    WaveformStylePicker(selection: $settings.waveformStyle)
                }
                .padding(.vertical, 4)
                Toggle("Always show", isOn: $settings.alwaysShowIndicator)
                    .disabled(settings.recordingWindowStyle == .none)
                Text("Keeps the small window on screen between dictations, asleep as a thin pill; hover it for Rewrite, Home and Expand. It does no work while idle.")
                    .font(.callout).foregroundStyle(.secondary)
                LabeledContent("Position") {
                    Button("Reset to Bottom Centre") { RecordingPanel.resetPositions() }
                }
                Text("Drag the small window to snap it to the top or bottom of the screen, centred or in a corner. The large window moves freely and resizes from its edges; its ↘↖ button returns to the small one.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("Language") {
                Toggle("Detect the language automatically", isOn: $settings.autoLanguage)
                if settings.autoLanguage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Languages you speak").font(.callout)
                        LanguageChips(selection: $settings.spokenLanguages)
                    }
                    Text("Dictum works out which of these each dictation is in, so you can switch between them freely. Fewer languages means fewer mix-ups.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Picker("Language", selection: $settings.language) {
                        ForEach(SpeechLanguage.allCases) { Text($0.title).tag($0) }
                    }
                }
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

/// Toggle chips for the languages the user speaks (at least one stays selected).
struct LanguageChips: View {
    @Binding var selection: [SpeechLanguage]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(SpeechLanguage.allCases) { language in
                let on = selection.contains(language)
                Button {
                    if on { if selection.count > 1 { selection.removeAll { $0 == language } } }
                    else { selection.append(language) }
                } label: {
                    Text(language.title)
                        .font(.system(size: 12, weight: on ? .semibold : .regular))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(on ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08)))
                        .overlay(Capsule().strokeBorder(on ? Color.accentColor : Color.secondary.opacity(0.2)))
                        .foregroundStyle(on ? Color.accentColor : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Wraps its children onto as many rows as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct SoundPage: View {
    @Bindable private var settings = AppSettings.shared
    @State private var devices = AudioDevices.inputs()

    var body: some View {
        Form {
            Section("Input") {
                Picker("Microphone", selection: $settings.microphoneUID) {
                    Text("System default (\(AudioDevices.defaultInputName() ?? "none"))").tag(String?.none)
                    ForEach(devices) { Text($0.name).tag(Optional($0.uid)) }
                }
                Text("The microphone is only open while you hold a dictation shortcut.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Feedback") {
                Toggle("Play start and stop sounds", isOn: $settings.playSounds)
            }
        }
        .formStyle(.grouped)
        .onAppear { devices = AudioDevices.inputs() }
    }
}

/// The two modes as cards, superwhisper-style: click one to make it the default.
struct ModesPage: View {
    @Bindable private var settings = AppSettings.shared
    private let engine = SpeechEngine.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("The default mode runs when you hold the dictation shortcut. The Rewrite shortcut always rewrites.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                card(.dictation, symbol: "waveform", keys: DictationController.keys(for: .pushToTalk))
                card(.rewrite, symbol: "sparkle", keys: DictationController.keys(for: .pushToTalkRewrite))
                if engine.rewriteModel != .installed {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.circle").foregroundStyle(.secondary)
                        Text("Rewrite needs the Tiny Aya model (1.9 GB on disk).").font(.system(size: 13))
                        Spacer()
                        Button("Models library…") { MainNavigation.shared.page = .models }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.07)))
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: 820, alignment: .leading)
        }
    }

    private func card(_ mode: DictationMode, symbol: String, keys: [String]) -> some View {
        let selected = settings.mode == mode
        return Button { settings.mode = mode } label: {
            HStack(spacing: 14) {
                SidebarIcon(symbol: symbol, tint: mode == .rewrite ? .blue : .orange)
                    .scaleEffect(1.4)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(mode.title).font(.system(size: 15, weight: .semibold))
                        if selected {
                            Text("Default")
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    Text(mode.summary).font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                KeycapsView(keys: keys)
            }
            .padding(16)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(selected ? 0.12 : 0.06)))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.15), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }
}

struct ModelSettings: View {
    @Bindable private var settings = AppSettings.shared
    private let engine = SpeechEngine.shared

    var body: some View {
        Form {
            Section {
                ForEach(SpeechModel.allCases) { model in
                    SpeechModelCard(model: model)
                }
                if let error = engine.speechModelError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
                Picker("Keep loaded", selection: $settings.speechKeepLoaded) {
                    ForEach([KeepLoaded.always, .oneHour, .fiveMinutes]) { Text($0.title).tag($0) }
                }
                .onChange(of: settings.speechKeepLoaded) { Task { await engine.applyKeepLoaded() } }
                Text("“Always” makes every dictation instant. Shorter times free the model's memory between bursts of dictation; the next one then takes a few seconds longer.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: {
                Text("Speech")
            } footer: {
                Text("Accuracy is word error rate on real English / French test speech (lower is better); speed is for a 10-second dictation on an M4 Pro. All models run on this Mac.")
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

/// One speech model in the Models library: what it's good at, measured numbers, and actions.
struct SpeechModelCard: View {
    let model: SpeechModel
    private let engine = SpeechEngine.shared
    private let settings = AppSettings.shared

    var body: some View {
        let state = engine.speechModels[model] ?? .missing
        let inUse = settings.speechModel == model
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(model.title).font(.system(size: 14, weight: .semibold))
                Text(model.badge)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                actions(state: state, inUse: inUse)
            }
            Text(model.summary).font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                metric("Accuracy", model.accuracy)
                metric("Speed", model.speed)
                metric("Memory", model.memory)
                metric("Download", model.download)
                if model.detectsLanguage { tag("Detects language", "globe") }
                if model.usesVocabulary { tag("Vocabulary", "book.closed") }
            }
            if case .installing(let fraction) = state {
                ProgressView(value: fraction)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func actions(state: SpeechEngine.ModelState, inUse: Bool) -> some View {
        switch state {
        case .installed where inUse:
            GrantedLabel(text: "In use")
        case .installed:
            HStack(spacing: 6) {
                Button("Remove") { Task { await engine.removeSpeechModel(model) } }
                Button("Use") { Task { await engine.use(model) } }.buttonStyle(.borderedProminent)
            }
        case .installing(let fraction):
            Text(fraction >= 0.999 ? "Preparing…" : "\(Int(fraction * 100)) %")
                .font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
        case .missing:
            Button("Download") { Task { await engine.installSpeechModel(model) } }
                .disabled(engine.isBusySettingUp && !inUse)
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 12, weight: .semibold)).monospacedDigit()
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private func tag(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
    }
}

struct HistoryPage: View {
    @Bindable private var settings = AppSettings.shared
    private let history = HistoryStore.shared
    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Toggle("Save history", isOn: $settings.saveHistory)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Text("\(history.entries.count) dictations · text only, on this Mac")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button("Clear…", role: .destructive) { confirmClear = true }
                    .disabled(history.entries.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            Divider()
            HistoryView()
        }
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

/// The app's icon, for in-app branding (it carries its own margins and shadow, so it's
/// drawn slightly larger than `size` to make the tile itself about `size` wide).
struct AppGlyph: View {
    var size: CGFloat = 64

    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size * 1.24, height: size * 1.24)
            .frame(width: size, height: size)
    }
}
