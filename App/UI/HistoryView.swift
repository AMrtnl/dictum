import SwiftUI

/// History: every dictation, newest first, grouped into one card per day. Filter by mode,
/// search the text, hover a dictation to copy or delete it, click it to read all of it.
struct HistoryView: View {
    enum Filter: Int, CaseIterable {
        case all, dictation, rewrite, failed

        var title: String {
            switch self {
            case .all: "All"
            case .dictation: "Dictation"
            case .rewrite: "Rewrite"
            case .failed: "Failed"
            }
        }
    }

    /// Entries grouped by day: Today, Yesterday, then dates.
    static func days(_ entries: [HistoryEntry]) -> [(title: String, entries: [HistoryEntry])] {
        let calendar = Calendar.current
        var order: [Date] = []
        var groups: [Date: [HistoryEntry]] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)
            if groups[day] == nil { order.append(day) }
            groups[day, default: []].append(entry)
        }
        return order.map { day in
            let title = calendar.isDateInToday(day) ? "Today"
                : calendar.isDateInYesterday(day) ? "Yesterday"
                : day.formatted(.dateTime.weekday(.wide).day().month(.wide))
            return (title, groups[day] ?? [])
        }
    }

    @Bindable private var settings = AppSettings.shared
    private let history = HistoryStore.shared
    @State private var query = ""
    @State private var filter = 0
    @State private var confirmClear = false

    private var entries: [HistoryEntry] {
        history.entries.filter { entry in
            let matchesFilter = switch Filter(rawValue: filter) ?? .all {
            case .all: true
            case .dictation: entry.status == .done && entry.mode != DictationMode.rewrite.rawValue
            case .rewrite: entry.status == .done && entry.mode == DictationMode.rewrite.rawValue
            case .failed: entry.status == .failed
            }
            guard matchesFilter else { return false }
            guard !query.isEmpty else { return true }
            return entry.text.localizedCaseInsensitiveContains(query)
                || (entry.original?.localizedCaseInsensitiveContains(query) ?? false)
                || (entry.app?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                controls
                if history.entries.isEmpty {
                    empty("No dictations yet",
                          detail: "Tap \(DictationController.keys(for: .pushToTalk).joined()) anywhere and speak. Your dictations show up here.")
                } else if entries.isEmpty {
                    empty("Nothing matches", detail: "Try another word or filter.")
                } else {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(Self.days(entries), id: \.title) { day in
                            daySection(day.title, day.entries)
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 30)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .confirmationDialog("Clear all saved dictations?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { history.clear() }
        } message: {
            Text("The text of every dictation is removed from this Mac.")
        }
    }

    // MARK: Header

    private var header: some View {
        let done = history.entries.filter { $0.status == .done }
        let words = done.reduce(0) { $0 + UsageStats.words(in: $1.text) }
        let subtitle = "\(done.count.formatted()) dictation\(done.count == 1 ? "" : "s") · \(words.formatted()) words, kept as text on this Mac"
        return PageHeader("History", subtitle: settings.saveHistory ? subtitle : "History is off. New dictations aren't kept.") {
            Toggle("Keep history", isOn: $settings.saveHistory)
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Dictations are kept as text, on this Mac only.")
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
    }

    private var controls: some View {
        HStack(spacing: 12) {
            PillPicker(options: Filter.allCases.map { (value: $0.rawValue, title: $0.title) }, selection: $filter)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 12))
                TextField("Search", text: $query)
                    .textFieldStyle(.plain)
                    .frame(width: 180)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
    }

    // MARK: Days

    private func daySection(_ title: String, _ entries: [HistoryEntry]) -> some View {
        let words = entries.filter { $0.status == .done }.reduce(0) { $0 + UsageStats.words(in: $1.text) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text("\(entries.count) · \(words.formatted()) words")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            DashCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider().padding(.leading, 50) }
                        HistoryRow(entry: entry)
                    }
                }
            }
        }
    }

    private func empty(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "waveform").font(.system(size: 24)).foregroundStyle(.tertiary).padding(.bottom, 4)
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .padding(.top, 20)
    }
}

/// One dictation: where it went, what was said, and its details; click to read it all.
private struct HistoryRow: View {
    let entry: HistoryEntry
    @State private var hovering = false
    @State private var expanded = false
    @State private var showingOriginal = false
    @State private var retrying = false
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 6) {
                if entry.status == .failed {
                    Text("Transcription failed").font(.system(size: 13, weight: .medium)).foregroundStyle(.orange)
                } else {
                    Text(showingOriginal ? (entry.original ?? entry.text) : entry.text)
                        .font(.system(size: 13))
                        .lineLimit(expanded ? nil : 3)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                meta
            }
            Spacer(minLength: 8)
            actions
                .opacity(hovering || entry.status == .failed || copied ? 1 : 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(hovering ? Color.primary.opacity(0.03) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() } }
        .onHover { hovering = $0 }
        .contextMenu {
            if entry.status == .done {
                Button("Copy") { TextInserter.copy(entry.text) }
                if let original = entry.original { Button("Copy Original") { TextInserter.copy(original) } }
            }
            Button("Delete", role: .destructive) { HistoryStore.shared.delete(entry) }
        }
    }

    @ViewBuilder
    private var icon: some View {
        Group {
            if entry.status == .failed {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            } else {
                Image(nsImage: AppIcons.icon(for: entry.appBundleID, name: entry.app)).resizable()
                    .opacity(entry.app == nil ? 0.5 : 1)
            }
        }
        .frame(width: 24, height: 24)
    }

    private var meta: some View {
        let seconds = Int(entry.duration.rounded())
        return HStack(spacing: 6) {
            Text(entry.date.formatted(date: .omitted, time: .shortened))
            if let app = entry.app { dot; Text(app) }
            if seconds > 0 { dot; Text(String(format: "%d:%02d", seconds / 60, seconds % 60)).monospacedDigit() }
            dot
            Text(SpeechLanguage.flag(for: entry.language)).font(.system(size: 11)).help(SpeechLanguage.name(for: entry.language))
            if entry.mode == DictationMode.rewrite.rawValue {
                Chip("Rewrite").scaleEffect(0.92)
            }
            if entry.original != nil {
                Button(showingOriginal ? "Show Rewrite" : "Show Original") { showingOriginal.toggle() }
                    .buttonStyle(.link)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    private var dot: some View { Text("·").foregroundStyle(.tertiary) }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 2) {
            if entry.status == .failed {
                if retrying {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Retry") {
                        retrying = true
                        Task {
                            await DictationController.shared.retry(entry)
                            retrying = false
                        }
                    }
                    .controlSize(.small)
                }
            } else {
                iconButton(copied ? "checkmark" : "doc.on.doc", help: "Copy") {
                    TextInserter.copy(showingOriginal ? (entry.original ?? entry.text) : entry.text)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.4))
                        copied = false
                    }
                }
            }
            iconButton("trash", help: "Delete") { HistoryStore.shared.delete(entry) }
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12)).frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(help)
    }
}
