import Foundation

/// Totals for the Home dashboard, computed from history.
struct UsageStats {
    enum Period: String, CaseIterable, Identifiable {
        case allTime, today, week, month

        var id: Self { self }

        var title: String {
            switch self {
            case .allTime: "All time"
            case .today: "Today"
            case .week: "Last 7 days"
            case .month: "Last 30 days"
            }
        }

        var start: Date? {
            let calendar = Calendar.current
            switch self {
            case .allTime: return nil
            case .today: return calendar.startOfDay(for: .now)
            case .week: return calendar.date(byAdding: .day, value: -7, to: .now)
            case .month: return calendar.date(byAdding: .day, value: -30, to: .now)
            }
        }
    }

    /// Typing speed the time-saved figure compares against.
    static let typingWPM = 40.0

    let words: Int
    let wordsPerMinute: Int
    let appsUsed: Int
    let minutesSaved: Double
    let dictations: Int

    init(_ entries: [HistoryEntry], period: Period) {
        let start = period.start
        let done = entries.filter { $0.status == .done && (start == nil || $0.date >= start!) }
        let wordCounts = done.map { $0.text.split(whereSeparator: \.isWhitespace).count }
        words = wordCounts.reduce(0, +)
        dictations = done.count

        // Speed only from dictations with a measured duration.
        var timedWords = 0
        var spokenSeconds = 0.0
        for (entry, count) in zip(done, wordCounts) where entry.duration > 0 {
            timedWords += count
            spokenSeconds += entry.duration
        }
        wordsPerMinute = spokenSeconds > 0 ? Int((Double(timedWords) / (spokenSeconds / 60)).rounded()) : 0
        appsUsed = Set(done.compactMap(\.app)).count
        minutesSaved = max(0, Double(words) / Self.typingWPM - spokenSeconds / 60)
    }

    /// Words per day for the last `days` days, oldest first (empty days included).
    static func daily(_ entries: [HistoryEntry], days: Int = 14) -> [(day: Date, words: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var totals: [Date: Int] = [:]
        for entry in entries where entry.status == .done {
            totals[calendar.startOfDay(for: entry.date), default: 0] += entry.text.split(whereSeparator: \.isWhitespace).count
        }
        return (0..<days).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { ($0, totals[$0] ?? 0) }
        }
    }

    /// Share of dictations per language, largest first.
    static func languages(_ entries: [HistoryEntry]) -> [(code: String, share: Double)] {
        let done = entries.filter { $0.status == .done }
        guard !done.isEmpty else { return [] }
        let counts = Dictionary(grouping: done, by: \.language).mapValues(\.count)
        return counts.map { ($0.key, Double($0.value) / Double(done.count)) }.sorted { $0.share > $1.share }
    }

    /// Apps dictated into most, with their bundle IDs for icons.
    static func topApps(_ entries: [HistoryEntry], limit: Int = 4) -> [(name: String, bundleID: String?, count: Int)] {
        var counts: [String: (bundleID: String?, count: Int)] = [:]
        for entry in entries where entry.status == .done {
            guard let app = entry.app else { continue }
            let current = counts[app] ?? (entry.appBundleID, 0)
            counts[app] = (current.bundleID ?? entry.appBundleID, current.count + 1)
        }
        let ranked: [(name: String, bundleID: String?, count: Int)] = counts.map { name, value in
            (name: name, bundleID: value.bundleID, count: value.count)
        }
        return Array(ranked.sorted { $0.count > $1.count }.prefix(limit))
    }

    var savedDescription: String {
        let minutes = Int(minutesSaved.rounded())
        if minutes < 1 { return "–" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = Double(minutes) / 60
        return hours < 10 ? String(format: hours.truncatingRemainder(dividingBy: 1) < 0.1 ? "%.0f h" : "%.1f h", hours)
            : "\(Int(hours.rounded())) h"
    }
}
