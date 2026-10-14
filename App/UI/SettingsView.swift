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
                Toggle("Show live transcription", isOn: $settings.liveTranscript)
                    .disabled(settings.recordingWindowStyle == .none)
                Text("Shows what you're saying while you dictate: in a bubble beside the small window, or along the bottom of the large one. Words still being said are dimmer — amber in Rewrite — and the text pasted shows for a moment at the end. It keeps the speech model busy while you talk.")
                    .font(.callout).foregroundStyle(.secondary)
                Toggle("Animate the menu bar icon", isOn: $settings.animateMenuBar)
                Text("While you dictate, Dictum's menu bar icon becomes a small live waveform in the style above; amber with ✦ in Rewrite, pulsing dots while transcribing.")
                    .font(.callout).foregroundStyle(.secondary)
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
        .onAppear { UserDefaults.standard.set(true, forKey: "visitedConfiguration") }  // Home's Get started
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
    @State private var tester = MicrophoneTester()
    private let permissions = Permissions.shared

    var body: some View {
        Form {
            Section {
                Picker("Microphone", selection: $settings.microphoneUID) {
                    Text("System default (\(AudioDevices.defaultInputName() ?? "none"))").tag(String?.none)
                    ForEach(devices) { Text($0.name).tag(Optional($0.uid)) }
                }
                LabeledContent("Level") {
                    HStack(spacing: 12) {
                        LevelMeter(level: tester.level, active: tester.isRunning)
                        Button(tester.isRunning ? "Stop" : "Test Microphone") {
                            if tester.isRunning { tester.stop() } else { tester.start(deviceUID: settings.microphoneUID) }
                        }
                        .disabled(permissions.microphone != .granted)
                    }
                }
                Text(tester.isRunning
                     ? "Say something: the bars should move as you speak. Nothing is recorded."
                     : permissions.microphone == .granted
                        ? "The microphone is only on while you dictate, or for the few seconds of a test."
                        : "Allow microphone access first (About → Permissions).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Input")
            }
            Section("Feedback") {
                Toggle("Play start and stop sounds", isOn: $settings.playSounds)
            }
        }
        .formStyle(.grouped)
        .onAppear { devices = AudioDevices.inputs() }
        .onDisappear { tester.stop() }
        .onChange(of: settings.microphoneUID) {
            if tester.isRunning { tester.start(deviceUID: settings.microphoneUID) }
        }
    }
}

/// Sixteen segments lit up to the input level; the top ones warn of clipping.
private struct LevelMeter: View {
    let level: Float
    let active: Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<16, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(active && Float(index) / 16 < level
                          ? (index >= 14 ? Color.orange : Color.accentColor)
                          : Color.secondary.opacity(0.18))
                    .frame(width: 5, height: 14)
            }
        }
        .animation(.linear(duration: 0.08), value: level)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Input level")
        .accessibilityValue(active ? "\(Int(level * 100)) percent" : "Off")
    }
}

/// The two modes side by side, each with what you say and what Dictum writes;
/// click one to make it what the dictation shortcut does.
struct ModesPage: View {
    @Bindable private var settings = AppSettings.shared
    private let engine = SpeechEngine.shared

    private static let said = "um so the report is due on friday no actually thursday"

    var body: some View {
        PageScroll {
            PageLead(lead)
            HStack(alignment: .top, spacing: 14) {
                ModeCard(mode: .dictation, symbol: "waveform", selected: settings.mode == .dictation,
                         said: Self.said, written: "Um, so the report is due on Friday, no, actually Thursday.") {
                    settings.mode = .dictation
                }
                ModeCard(mode: .rewrite, symbol: "sparkle", selected: settings.mode == .rewrite,
                         said: Self.said, written: "The report is due on Thursday.") {
                    settings.mode = .rewrite
                }
            }
            rewriteModelNote
        }
    }

    private var lead: Text {
        let dictate = Text(DictationController.keys(for: .pushToTalk).joined()).fontWeight(.semibold).foregroundStyle(.primary)
        let rewrite = Text(DictationController.keys(for: .pushToTalkRewrite).joined()).fontWeight(.semibold).foregroundStyle(.primary)
        return Text("\(dictate) uses the mode you pick here. \(rewrite) always rewrites, so you can choose at the moment you speak.")
    }

    @ViewBuilder
    private var rewriteModelNote: some View {
        switch engine.rewriteModel {
        case .installed:
            EmptyView()
        case .installing(let fraction):
            InlineNote(symbol: "arrow.down.circle", text: fraction >= 1 ? "Preparing Tiny Aya…" : "Downloading Tiny Aya… \(Int(fraction * 100)) %") {
                ProgressView(value: min(fraction, 1)).frame(width: 120)
            }
        case .missing:
            InlineNote(symbol: "arrow.down.circle", text: "Rewrite uses Tiny Aya, a 1.9 GB model that runs on this Mac.") {
                Button("Download") { Task { await engine.installRewriteModel() } }
                    .disabled(!engine.isReady)
            }
        }
    }
}

private struct ModeCard: View {
    let mode: DictationMode
    let symbol: String
    let selected: Bool
    let said: String
    let written: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Panel(selected: selected) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                        Text(mode.title).font(.system(size: 15, weight: .semibold))
                        Spacer()
                        if selected {
                            Chip("Default")
                        } else {
                            Text("Make Default").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    Text(mode.summary)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("You say").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                            Text("“\(said)”").font(.system(size: 13)).italic().foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dictum writes").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                            Text(written).font(.system(size: 13))
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.07)))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The Models library: each speech model with what it's good at and measured numbers,
/// the one in use outlined; then Rewrite's model and how long models stay in memory.
struct ModelSettings: View {
    @Bindable private var settings = AppSettings.shared
    private let engine = SpeechEngine.shared

    var body: some View {
        PageScroll {
            PageLead("Every model runs on this Mac, and what you say never leaves it. Pick the one that suits how you talk.")

            VStack(alignment: .leading, spacing: 10) {
                ForEach(SpeechModel.allCases) { model in
                    SpeechModelCard(model: model)
                }
                if let error = engine.speechModelError {
                    Text(error).font(.system(size: 12)).foregroundStyle(.red)
                }
                Text("Errors is the word error rate on real English and French speech; lower is better. Speed is for a 10-second dictation on an M4 Pro.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Rewrite")
                rewriteCard
            }

            VStack(alignment: .leading, spacing: 4) {
                SectionTitle("Memory")
                    .padding(.bottom, 6)
                keepLoadedRow(
                    title: "Keep the speech model loaded",
                    detail: "“Always” makes every dictation start instantly. A shorter time frees about 2.5 GB between bursts of dictation; the next one then waits a few seconds.",
                    selection: $settings.speechKeepLoaded,
                    options: [.always, .oneHour, .fiveMinutes]
                )
                Divider()
                keepLoadedRow(
                    title: "Keep Rewrite loaded",
                    detail: "Rewrite's model uses about 1.9 GB while it's loaded.",
                    selection: $settings.rewriteKeepLoaded,
                    options: [.thirtySeconds, .oneMinute, .fiveMinutes, .oneHour]
                )
            }
            .onChange(of: settings.speechKeepLoaded) { Task { await engine.applyKeepLoaded() } }
            .onChange(of: settings.rewriteKeepLoaded) { Task { await engine.applyKeepLoaded() } }

            Button("Show Models in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Paths.models]) }
                .buttonStyle(.link)
                .font(.system(size: 12))
        }
    }

    private func keepLoadedRow(title: String, detail: String, selection: Binding<KeepLoaded>,
                               options: [KeepLoaded]) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Picker(title, selection: selection) {
                ForEach(options) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        }
        .padding(.vertical, 8)
    }

    private var rewriteCard: some View {
        Panel(selected: engine.rewriteModel == .installed && settings.mode == .rewrite) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Tiny Aya Global").font(.system(size: 15, weight: .semibold))
                        Chip("Cleans up", tint: .secondary)
                    }
                    Text("Removes filler words and false starts and keeps only your corrections. If its rewrite drifts from what you said, Dictum pastes your words as spoken.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 24) {
                        Figure(value: "~0.8 s", label: "Per sentence")
                        Figure(value: "1.9 GB", label: "Memory")
                        Figure(value: "3.6 GB", label: "Download")
                    }
                    Text("Licensed CC-BY-NC 4.0: personal, non-commercial use only.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    if case .installing(let fraction) = engine.rewriteModel {
                        ProgressView(value: min(fraction, 1))
                    }
                    if let error = engine.rewriteError {
                        Text(error).font(.system(size: 12)).foregroundStyle(.red)
                    }
                }
                Spacer(minLength: 8)
                switch engine.rewriteModel {
                case .installed:
                    VStack(alignment: .trailing, spacing: 8) {
                        GrantedLabel(text: "Installed")
                        Button("Remove") { Task { await engine.removeRewriteModel() } }
                            .controlSize(.small)
                    }
                case .installing(let fraction):
                    Text(fraction >= 1 ? "Preparing…" : "\(Int(fraction * 100)) %")
                        .font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                case .missing:
                    Button("Download") { Task { await engine.installRewriteModel() } }
                        .disabled(!engine.isReady)
                }
            }
        }
    }
}

/// One speech model: what it's good at, its measured numbers, and what you can do with it.
struct SpeechModelCard: View {
    let model: SpeechModel
    private let engine = SpeechEngine.shared
    private let settings = AppSettings.shared

    var body: some View {
        let state = engine.speechModels[model] ?? .missing
        let inUse = settings.speechModel == model
        Panel(selected: inUse) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(model.title).font(.system(size: 15, weight: .semibold))
                        Chip(model.badge, tint: .secondary)
                    }
                    Text(model.summary)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .top, spacing: 24) {
                        Figure(value: model.accuracy, label: "Errors EN / FR")
                        Figure(value: model.speed, label: "Speed")
                        Figure(value: model.memory, label: "Memory")
                        Figure(value: model.download, label: "Download")
                    }
                    HStack(spacing: 14) {
                        if model.detectsLanguage { Label("Detects the language", systemImage: "globe") }
                        if model.usesVocabulary { Label("Uses your vocabulary", systemImage: "character.book.closed") }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    if case .installing(let fraction) = state {
                        ProgressView(value: min(fraction, 1))
                    }
                }
                Spacer(minLength: 8)
                actions(state: state, inUse: inUse)
            }
        }
    }

    @ViewBuilder
    private func actions(state: SpeechEngine.ModelState, inUse: Bool) -> some View {
        switch state {
        case .installed where inUse:
            Chip("In use")
        case .installed:
            VStack(alignment: .trailing, spacing: 8) {
                Button("Use") { Task { await engine.use(model) } }.buttonStyle(.borderedProminent)
                Button("Remove") { Task { await engine.removeSpeechModel(model) } }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
            }
        case .installing(let fraction):
            Text(fraction >= 0.999 ? "Preparing…" : "\(Int(fraction * 100)) %")
                .font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
        case .missing:
            Button("Download") { Task { await engine.installSpeechModel(model) } }
                .disabled(engine.isBusySettingUp && !inUse)
        }
    }
}

struct HistoryPage: View {
    @Bindable private var settings = AppSettings.shared
    private let history = HistoryStore.shared
    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text(summary)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Keep history", isOn: $settings.saveHistory)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Menu {
                    Button("Clear History…", role: .destructive) { confirmClear = true }
                        .disabled(history.entries.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More")
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            Divider()
            HistoryView()
        }
        .confirmationDialog("Clear all saved dictations?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { history.clear() }
        } message: {
            Text("The text of every dictation is removed from this Mac.")
        }
    }

    private var summary: String {
        guard settings.saveHistory else { return "History is off. New dictations aren't kept." }
        let count = history.entries.count
        return count == 0 ? "Your dictations are kept here, as text, on this Mac."
            : "\(count) dictation\(count == 1 ? "" : "s"), kept as text on this Mac."
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
                        Text("Version \(version)")
                            .font(.callout).foregroundStyle(.secondary)
                        Text("Dictation that runs entirely on this Mac.")
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
                Text("Models: Qwen3-ASR and Cohere Transcribe (Apache 2.0), Nemotron (OpenMDW 1.1), Tiny Aya (CC-BY-NC 4.0, non-commercial). Libraries: mlx-speech, mlx-lm and KeyboardShortcuts (MIT).")
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
