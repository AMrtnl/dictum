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
                .help(settings.shortcutBehavior.summary)
            } header: {
                VStack(alignment: .leading, spacing: 22) {
                    PageHeader("Configuration", subtitle: "Shortcuts, the recording window, languages and pasting.")
                        .foregroundStyle(.primary)
                    Text("Shortcuts")
                }
            } footer: {
                Text("Esc cancels.")
            }

            Section("Recording window") {
                RecordingStylePicker(selection: $settings.recordingWindowStyle, waveform: settings.waveformStyle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                LabeledContent(settings.recordingWindowStyle.title) {
                    Button("Preview on Screen") { DictationController.shared.previewRecordingWindow() }
                        .disabled(settings.recordingWindowStyle == .none)
                }
                .help(settings.recordingWindowStyle.summary)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Waveform")
                    WaveformStylePicker(selection: $settings.waveformStyle)
                }
                .padding(.vertical, 4)
                Toggle("Show live transcription", isOn: $settings.liveTranscript)
                    .disabled(settings.recordingWindowStyle == .none)
                    .help("Shows your words as you say them, beside the small window or along the bottom of the large one.")
                Toggle("Animate the menu bar icon", isOn: $settings.animateMenuBar)
                    .help("The menu bar icon becomes a small live waveform while you dictate.")
                Toggle("Keep the small window on screen", isOn: $settings.alwaysShowIndicator)
                    .disabled(settings.recordingWindowStyle == .none)
                    .help("Between dictations it sleeps as a thin pill; hover it for Rewrite, Home and Expand.")
                LabeledContent("Position") {
                    Button("Reset to Bottom Centre") { RecordingPanel.resetPositions() }
                }
                .help("Drag the small window to snap it to an edge or corner. The large window moves and resizes freely.")
            }

            Section("Language") {
                Toggle("Detect the language automatically", isOn: $settings.autoLanguage)
                if settings.autoLanguage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Languages you speak").font(.callout)
                        LanguageChips(selection: $settings.spokenLanguages)
                    }
                    .help("Dictum works out which of these each dictation is in. Fewer languages means fewer mix-ups.")
                } else {
                    Picker("Language", selection: $settings.language) {
                        ForEach(SpeechLanguage.allCases) { Text("\($0.flag)  \($0.title)").tag($0) }
                    }
                }
            }

            Section("Pasting") {
                Toggle("Keep the transcript in the clipboard", isOn: $settings.keepInClipboard)
                    .help("Off: your previous clipboard comes back right after pasting.")
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
                    Text("\(language.flag)  \(language.title)")
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
                if tester.isRunning {
                    Text("Say something. Nothing is recorded.").font(.callout).foregroundStyle(.secondary)
                } else if permissions.microphone != .granted {
                    Text("Allow microphone access first, in About.").font(.callout).foregroundStyle(.secondary)
                }
            } header: {
                VStack(alignment: .leading, spacing: 22) {
                    PageHeader("Sound", subtitle: "The microphone Dictum listens to, and its sounds.")
                        .foregroundStyle(.primary)
                    Text("Input")
                }
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

/// The two modes side by side. Each shows the same spoken sentence and what that mode
/// does to it: what Dictation adds in blue, what Rewrite removes struck through.
struct ModesPage: View {
    @Bindable private var settings = AppSettings.shared
    private let engine = SpeechEngine.shared

    var body: some View {
        PageScroll {
            PageHeader("Modes", subtitle: "Choose what \(DictationController.keys(for: .pushToTalk).joined()) does.")
            HStack(alignment: .top, spacing: 14) {
                ModeCard(mode: .dictation, selected: settings.mode == .dictation) { settings.mode = .dictation }
                ModeCard(mode: .rewrite, selected: settings.mode == .rewrite) { settings.mode = .rewrite }
            }
            rewriteModelNote
        }
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
            InlineNote(symbol: "arrow.down.circle", text: "Rewrite needs Tiny Aya (1.9 GB, runs on this Mac).") {
                Button("Download") { Task { await engine.installRewriteModel() } }
                    .glassButton()
                    .disabled(!engine.isReady)
            }
        }
    }
}

private struct ModeCard: View {
    let mode: DictationMode
    let selected: Bool
    let action: () -> Void

    private enum Mark { case same, added, removed }

    /// "um so the report is due on friday no actually thursday", as each mode writes it.
    private var segments: [(String, Mark)] {
        switch mode {
        case .dictation:
            [("U", .added), ("m", .same), (",", .added), (" so the report is due on ", .same), ("F", .added),
             ("riday", .same), (",", .added), (" no", .same), (",", .added), (" actually ", .same),
             ("T", .added), ("hursday", .same), (".", .added)]
        case .rewrite:
            [("um so ", .removed), ("the report is due on ", .same), ("friday no actually ", .removed), ("thursday", .same)]
        }
    }

    private var diff: Text {
        segments.reduce(Text("")) { text, segment in
            let part = switch segment.1 {
            case .same: Text(segment.0)
            case .added: Text(segment.0).foregroundStyle(Color.accentColor).fontWeight(.semibold)
            case .removed: Text(segment.0).strikethrough(color: .secondary).foregroundStyle(.tertiary)
            }
            return Text("\(text)\(part)")
        }
    }

    var body: some View {
        Button(action: action) {
            Panel(selected: selected) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: mode == .rewrite ? "sparkle" : "waveform")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill((selected ? Color.accentColor : Color.secondary).opacity(0.12)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(mode.title).font(.system(size: 15, weight: .semibold))
                            Text(mode == .rewrite ? "Clean text, without fillers or false starts." : "Exactly what you said, punctuated.")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selected { Chip("Default") }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        diff
                            .font(.system(size: 14))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                        if mode == .rewrite {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: "arrow.turn.down.right").font(.system(size: 11)).foregroundStyle(.tertiary)
                                Text("The report is due on Thursday.").font(.system(size: 14, weight: .semibold))
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.secondary.opacity(0.07)))

                    HStack(spacing: 6) {
                        legend
                        Spacer()
                        shortcut
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var legend: some View {
        if mode == .rewrite {
            Text("abc").strikethrough().foregroundStyle(.tertiary)
            Text("removed")
        } else {
            Text(".,A").fontWeight(.semibold).foregroundStyle(Color.accentColor)
            Text("added")
        }
    }

    @ViewBuilder
    private var shortcut: some View {
        if mode == .rewrite {
            KeycapsView(keys: DictationController.keys(for: .pushToTalkRewrite))
            if selected { KeycapsView(keys: DictationController.keys(for: .pushToTalk)) }
        } else if selected {
            KeycapsView(keys: DictationController.keys(for: .pushToTalk))
        } else {
            Text("Click to use")
        }
    }
}

/// The Models library: each speech model with what it's good at and measured numbers,
/// the one in use outlined; then Rewrite's model and how long models stay in memory.
struct ModelSettings: View {
    @Bindable private var settings = AppSettings.shared
    private let engine = SpeechEngine.shared

    var body: some View {
        PageScroll {
            PageHeader("Models", subtitle: "All models run on this Mac. Nothing you say leaves it.")

            VStack(alignment: .leading, spacing: 10) {
                ForEach(SpeechModel.allCases) { model in
                    SpeechModelCard(model: model)
                }
                if let error = engine.speechModelError {
                    Text(error).font(.system(size: 12)).foregroundStyle(.red)
                }
                Text("Errors: word error rate on English and French test speech, lower is better. Speed: a 10-second dictation on an M4 Pro.")
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
                    detail: "“Always” starts every dictation instantly.",
                    selection: $settings.speechKeepLoaded,
                    options: [.always, .oneHour, .fiveMinutes]
                )
                Divider()
                keepLoadedRow(
                    title: "Keep Rewrite loaded",
                    detail: "Uses about 1.9 GB while loaded.",
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
                    Text("Removes filler words and false starts, keeping only your corrections.")
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
                        .glassButton()
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
                Button("Use") { Task { await engine.use(model) } }.glassButton(prominent: true)
                Button("Remove") { Task { await engine.removeSpeechModel(model) } }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
            }
        case .installing(let fraction):
            Text(fraction >= 0.999 ? "Preparing…" : "\(Int(fraction * 100)) %")
                .font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
        case .missing:
            Button("Download") { Task { await engine.installSpeechModel(model) } }
                .glassButton()
                .disabled(engine.isBusySettingUp && !inUse)
        }
    }
}

/// The History page: the list carries its own header, filters and search.
struct HistoryPage: View {
    var body: some View { HistoryView() }
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
