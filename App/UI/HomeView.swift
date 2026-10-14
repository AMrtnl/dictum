import SwiftUI

/// Home: what you've said lately, where it went, and what's left to set up.
struct HomeView: View {
    private let history = HistoryStore.shared
    private let permissions = Permissions.shared
    private let vocabulary = VocabularyStore.shared
    @AppStorage("homePeriod") private var period: UsageStats.Period = .week

    private static let latestChange = (version: "1.4", title: "Faster after you stop talking",
                                       detail: "The speech model stays in memory and long dictations are transcribed while you speak.")
    private static let periods: [UsageStats.Period] = [.today, .week, .month, .allTime]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                if permissions.accessibility != .granted { PasteNotice() }
                VStack(alignment: .leading, spacing: 22) {
                    summary
                    rhythm
                }
                if !periodEntries.isEmpty { breakdown }
                if !latest.isEmpty { latestDictations }
                if steps.contains(where: { !$0.done }) { getStarted }
                whatsNew
            }
            .padding(.horizontal, 34)
            .padding(.top, 26)
            .padding(.bottom, 30)
            .frame(maxWidth: 800, alignment: .leading)
        }
    }

    private var periodEntries: [HistoryEntry] { UsageStats.done(history.entries, in: period) }

    // MARK: Summary

    private var summary: some View {
        let stats = UsageStats(history.entries, period: period)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text(heading).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Picker("Period", selection: $period) {
                    ForEach(Self.periods) { Text($0.shortTitle).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            headline(stats)
                .font(.system(size: 24, weight: .regular))
                .fixedSize(horizontal: false, vertical: true)
            if let detail = detail(stats) {
                detail
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var heading: String {
        switch period {
        case .today: "Today"
        case .week: "This week"
        case .month: "This month"
        case .allTime: "Since you started"
        }
    }

    private func headline(_ stats: UsageStats) -> Text {
        if history.entries.isEmpty { return Text("Your words will show up here.") }
        guard stats.dictations > 0 else {
            return Text(period == .today ? "Nothing dictated yet today." : "Nothing dictated in this period.")
        }
        let words = Text(Self.count(stats.words, "word")).fontWeight(.semibold)
        let dictations = Text(Self.count(stats.dictations, "dictation")).fontWeight(.semibold)
        return Text("You dictated \(words) in \(dictations).")
    }

    private func detail(_ stats: UsageStats) -> Text? {
        if history.entries.isEmpty || stats.dictations == 0 {
            let keys = DictationController.keys(for: .pushToTalk).joined()
            return Text("Tap \(Text(keys).fontWeight(.semibold)) in any app, say something, and tap it again.")
        }
        var parts: [Text] = []
        let minutes = Int(stats.minutesSaved.rounded())
        if minutes >= 1 {
            parts.append(Text("That's about \(Text(stats.savedDescription).foregroundStyle(.primary)) less typing."))
        }
        if stats.wordsPerMinute > 0 {
            let times = Double(stats.wordsPerMinute) / UsageStats.typingWPM
            let pace = times >= 1.3 ? ", \(times.formatted(.number.precision(.fractionLength(1)))) times typing speed" : ""
            parts.append(Text("You speak \(Text("\(stats.wordsPerMinute) words a minute").foregroundStyle(.primary))\(pace)."))
        }
        guard var text = parts.first else { return nil }
        for part in parts.dropFirst() { text = Text("\(text) \(part)") }
        return text
    }

    private static func count(_ value: Int, _ noun: String) -> String {
        "\(value.formatted()) \(noun)\(value == 1 ? "" : "s")"
    }

    // MARK: Rhythm

    private var rhythm: some View {
        let days = UsageStats.days(history.entries)
        return VStack(alignment: .leading, spacing: 8) {
            RhythmChart(days: days, period: period)
            if let busiest = days.max(by: { $0.words < $1.words }), busiest.words > 0 {
                Text("Busiest day: \(busiest.date.formatted(.dateTime.weekday(.wide).day().month(.wide))), \(busiest.words.formatted()) words")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Breakdown

    private var breakdown: some View {
        let apps = UsageStats.topApps(history.entries, in: period, limit: 6)
        let languages = UsageStats.languages(history.entries, in: period)
        let mostWords = Double(max(apps.first?.words ?? 0, 1))
        return HStack(alignment: .top, spacing: 14) {
            DashCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        CardTitle("Where your words go")
                        Spacer()
                        Text("Words").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 4) {
                        if apps.isEmpty { emptyRow("The apps you dictate into show up here.") }
                        ForEach(apps, id: \.name) { app in
                            BarRow(label: app.name, value: Self.compact(app.words),
                                   fraction: Double(app.words) / mostWords) {
                                Image(nsImage: AppIcons.icon(for: app.bundleID, name: app.name)).resizable()
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 14) {
                DashCard {
                    VStack(alignment: .leading, spacing: 12) {
                        CardTitle("When you dictate")
                        HourStrip(counts: UsageStats.hours(history.entries, in: period))
                    }
                }
                if !languages.isEmpty {
                    DashCard {
                        VStack(alignment: .leading, spacing: 12) {
                            CardTitle("Languages")
                            LanguageSplit(languages: languages)
                        }
                    }
                }
            }
            .frame(width: 290)
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(.secondary).padding(8)
    }

    static func compact(_ value: Int) -> String {
        value >= 10_000 ? value.formatted(.number.notation(.compactName)) : value.formatted()
    }

    // MARK: Latest

    private var latest: [HistoryEntry] {
        Array(history.entries.lazy.filter { $0.status == .done && !$0.text.isEmpty }.prefix(3))
    }

    private var latestDictations: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle("Latest")
                Spacer()
                Button("Show All") { MainNavigation.shared.page = .history }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
            }
            VStack(spacing: 0) {
                ForEach(Array(latest.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { Divider().padding(.leading, 34) }
                    LatestRow(entry: entry)
                }
            }
        }
    }

    // MARK: Get started

    private struct Step: Identifiable {
        let symbol: String
        let title: String
        let detail: String
        var keys: [String] = []
        let done: Bool
        var action: (() -> Void)?
        var id: String { title }
    }

    private var steps: [Step] {
        [
            Step(symbol: "lock.open", title: "Allow the microphone and pasting",
                 detail: "Dictum needs both to hear you and to type for you.",
                 done: permissions.allGranted) { WindowManager.shared.show(.onboarding) },
            Step(symbol: "waveform", title: "Dictate your first sentence",
                 detail: "Tap the shortcut in any app, speak, then tap it again. Or hold it while you talk.",
                 keys: DictationController.keys(for: .pushToTalk), done: !history.entries.isEmpty),
            Step(symbol: "sparkle", title: "Try Rewrite",
                 detail: "Removes filler words and false starts, and keeps only your corrections.",
                 keys: DictationController.keys(for: .pushToTalkRewrite),
                 done: history.entries.contains { $0.mode == DictationMode.rewrite.rawValue }) {
                MainNavigation.shared.page = .modes
            },
            Step(symbol: "character.book.closed", title: "Teach Dictum a word",
                 detail: "Names and terms it should always spell your way.",
                 done: !vocabulary.terms.isEmpty) { MainNavigation.shared.page = .vocabulary },
            Step(symbol: "macwindow", title: "Choose your recording window",
                 detail: "A small pill or a large window, and how your voice is drawn.",
                 done: UserDefaults.standard.bool(forKey: "visitedConfiguration")) {
                MainNavigation.shared.page = .configuration
            },
        ]
    }

    private var getStarted: some View {
        let steps = steps
        let done = steps.filter(\.done).count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                SectionTitle("Get started")
                HStack(spacing: 3) {
                    ForEach(steps.indices, id: \.self) { index in
                        Capsule().fill(index < done ? Color.accentColor : Color.secondary.opacity(0.2))
                            .frame(width: 14, height: 4)
                    }
                }
                .accessibilityHidden(true)
                Text("\(done) of \(steps.count)").font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
            }
            VStack(spacing: 2) {
                ForEach(steps) { step in StepRow(step: step) }
            }
        }
    }

    private struct StepRow: View {
        let step: Step

        var body: some View {
            Button { step.action?() } label: {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: step.done ? "checkmark.circle.fill" : step.symbol)
                        .font(.system(size: 15))
                        .foregroundStyle(step.done ? Color.accentColor : Color.secondary)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(step.done ? .secondary : .primary)
                        if !step.done {
                            Text(step.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if !step.done, !step.keys.isEmpty { KeycapsView(keys: step.keys) }
                    if !step.done, step.action != nil {
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, step.done ? 5 : 8)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(HoverRowStyle())
            .disabled(step.done || step.action == nil)
        }
    }

    // MARK: What's new

    private var whatsNew: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("New in \(Self.latestChange.version)")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.latestChange.title).font(.system(size: 13, weight: .semibold))
                Text(Self.latestChange.detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Link("All Changes", destination: URL(string: "https://github.com/AMrtnl/dictum/releases")!)
                .font(.system(size: 12))
        }
        .padding(.top, 14)
        .overlay(alignment: .top) { Divider() }
    }
}

/// One recent dictation: where it went, what was said, a copy button on hover.
private struct LatestRow: View {
    let entry: HistoryEntry
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: AppIcons.icon(for: entry.appBundleID, name: entry.app))
                .resizable()
                .frame(width: 22, height: 22)
                .opacity(entry.app == nil ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.text)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .textSelection(.enabled)
                Text(meta).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                TextInserter.copy(entry.text)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.4))
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .opacity(hovering || copied ? 1 : 0)
            .help("Copy")
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var meta: String {
        let time = Calendar.current.isDateInToday(entry.date)
            ? entry.date.formatted(date: .omitted, time: .shortened)
            : entry.date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        let seconds = Int(entry.duration.rounded())
        return [time, entry.app, seconds > 0 ? String(format: "%d:%02d", seconds / 60, seconds % 60) : nil]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

/// Shown while Accessibility isn't granted: one line, the fix, and help for a stuck permission.
private struct PasteNotice: View {
    private let permissions = Permissions.shared
    @State private var showingHelp = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 1) {
                Text("Auto-paste is off").font(.system(size: 13, weight: .semibold))
                Text("Dictum copies your text instead of typing it, until you allow Accessibility.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Not Working?") { showingHelp = true }
                .buttonStyle(.link)
                .font(.system(size: 12))
                .popover(isPresented: $showingHelp, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Already allowed, but still not pasting?").font(.system(size: 13, weight: .semibold))
                        Text("macOS can keep an outdated entry after an update. Reset it, then switch Dictum on again in Privacy & Security → Accessibility.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Reset Permission") {
                            showingHelp = false
                            permissions.resetAccessibility()
                        }
                    }
                    .padding(14)
                    .frame(width: 290)
                }
            Button("Allow Pasting") { permissions.requestAccessibility() }
                .glassButton(prominent: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassSurface(cornerRadius: 16, tint: Color.orange.opacity(0.18))
    }
}

/// A row that highlights under the pointer.
struct HoverRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverRow(configuration: configuration)
    }

    private struct HoverRow: View {
        let configuration: ButtonStyle.Configuration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(!isEnabled ? 0 : configuration.isPressed ? 0.16 : hovering ? 0.08 : 0)))
                .onHover { hovering = $0 }
        }
    }
}
