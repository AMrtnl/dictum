import SwiftUI

struct HistoryView: View {
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

    private let history = HistoryStore.shared
    @State private var query = ""

    private var entries: [HistoryEntry] {
        guard !query.isEmpty else { return history.entries }
        return history.entries.filter {
            $0.text.localizedCaseInsensitiveContains(query) || ($0.original?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        Group {
            if history.entries.isEmpty {
                ContentUnavailableView {
                    Label("No dictations yet", systemImage: "waveform")
                } description: {
                    Text("Tap \(DictationController.keys(for: .pushToTalk).joined()) anywhere and speak. Your dictations show up here.")
                }
            } else if entries.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List {
                    ForEach(Self.days(entries), id: \.title) { day in
                        Section(day.title) {
                            ForEach(day.entries) { entry in
                                HistoryRow(entry: entry)
                                    .listRowSeparator(.visible)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search")
        .frame(minWidth: 460, minHeight: 360)
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    @State private var hovering = false
    @State private var showingOriginal = false
    @State private var retrying = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if entry.status != .failed, entry.appBundleID != nil || entry.app != nil {
                    Image(nsImage: AppIcons.icon(for: entry.appBundleID, name: entry.app)).resizable()
                } else {
                    Image(systemName: entry.status == .failed ? "exclamationmark.triangle" : "waveform")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 20, height: 20)
            .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                if entry.status == .failed {
                    Label("Transcription failed", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.orange)
                } else {
                    Text(showingOriginal ? (entry.original ?? entry.text) : entry.text)
                        .font(.system(size: 13))
                        .lineLimit(showingOriginal ? nil : 3)
                        .textSelection(.enabled)
                }
                Text(meta)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            actions
                .opacity(hovering || entry.status == .failed ? 1 : 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            if entry.status == .done {
                Button("Copy") { TextInserter.copy(entry.text) }
                if entry.original != nil { Button("Copy Original") { TextInserter.copy(entry.original!) } }
            }
            Button("Delete", role: .destructive) { HistoryStore.shared.delete(entry) }
        }
    }

    private var meta: String {
        let time = entry.date.formatted(date: .omitted, time: .shortened)
        let seconds = Int(entry.duration.rounded())
        let duration = String(format: "%d:%02d", seconds / 60, seconds % 60)
        let mode = DictationMode(rawValue: entry.mode)?.title ?? entry.mode
        var parts = [time, duration, mode, entry.language.uppercased()]
        if let app = entry.app { parts.insert(app, at: 1) }
        if entry.original != nil { parts.append(showingOriginal ? "original" : "rewritten") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 4) {
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
                }
            } else {
                if entry.original != nil {
                    iconButton(showingOriginal ? "wand.and.stars" : "arrow.uturn.backward",
                               help: showingOriginal ? "Show rewrite" : "Show original") { showingOriginal.toggle() }
                }
                iconButton("doc.on.doc", help: "Copy") {
                    TextInserter.copy(showingOriginal ? (entry.original ?? entry.text) : entry.text)
                }
            }
            iconButton("trash", help: "Delete") { HistoryStore.shared.delete(entry) }
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 22, height: 22) }
            .buttonStyle(.borderless)
            .help(help)
    }
}
