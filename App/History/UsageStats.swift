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
            // Calendar days including today, so the chart's highlighted bars match the totals.
            case .week: return calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: .now))
            case .month: return calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: .now))
            }
        }

        var shortTitle: String {
            switch self {
            case .allTime: "All"
            case .today: "Today"
            case .week: "7 days"
            case .month: "30 days"
            }
        }

        func contains(_ date: Date) -> Bool { start.map { date >= $0 } ?? true }
    }

    /// One day of dictation, for the rhythm chart.
    struct Day: Identifiable {
        let date: Date
        let words: Int
        let dictations: Int
        let seconds: Double
        var id: Date { date }
    }

    /// Typing speed the time-saved figure compares against.
    static let typingWPM = 40.0

    static func words(in text: String) -> Int { text.split(whereSeparator: \.isWhitespace).count }

    /// Successful dictations in the period, newest first.
    static func done(_ entries: [HistoryEntry], in period: Period) -> [HistoryEntry] {
        entries.filter { $0.status == .done && period.contains($0.date) }
    }

    /// The last `count` days, oldest first, empty days included.
    static func days(_ entries: [HistoryEntry], count: Int = 30) -> [Day] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var totals: [Date: (words: Int, dictations: Int, seconds: Double)] = [:]
        for entry in entries where entry.status == .done {
            let day = calendar.startOfDay(for: entry.date)
            let current = totals[day] ?? (0, 0, 0)
            totals[day] = (current.words + words(in: entry.text), current.dictations + 1, current.seconds + entry.duration)
        }
        return (0..<count).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let total = totals[day] ?? (0, 0, 0)
            return Day(date: day, words: total.words, dictations: total.dictations, seconds: total.seconds)
        }
    }

    /// Dictations per hour of the day (0–23) in the period.
    static func hours(_ entries: [HistoryEntry], in period: Period) -> [Int] {
        var counts = [Int](repeating: 0, count: 24)
        for entry in done(entries, in: period) {
            counts[Calendar.current.component(.hour, from: entry.date)] += 1
        }
        return counts
    }

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
        appsUsed = Set(done.compactMap(\.app).filter { !Self.isSystemProcess($0) }).count
        minutesSaved = max(0, Double(words) / Self.typingWPM - spokenSeconds / 60)
    }

    /// Share of dictations per language in the period, largest first.
    static func languages(_ entries: [HistoryEntry], in period: Period = .allTime) -> [(code: String, share: Double)] {
        let done = done(entries, in: period)
        guard !done.isEmpty else { return [] }
        let counts = Dictionary(grouping: done, by: \.language).mapValues(\.count)
        return counts.map { ($0.key, Double($0.value) / Double(done.count)) }.sorted { $0.share > $1.share }
    }

    /// Frontmost "apps" that aren't somewhere anyone dictates into (lock screen, Dictum itself).
    static func isSystemProcess(_ app: String) -> Bool {
        ["loginwindow", "Dictum", "ScreenSaverEngine", "UserNotificationCenter", "Dock"].contains(app)
    }

    /// Apps dictated into most in the period, with their bundle IDs for icons.
    static func topApps(_ entries: [HistoryEntry], in period: Period = .allTime,
                        limit: Int = 5) -> [(name: String, bundleID: String?, count: Int, words: Int)] {
        var totals: [String: (bundleID: String?, count: Int, words: Int)] = [:]
        for entry in done(entries, in: period) {
            guard let app = entry.app, !Self.isSystemProcess(app) else { continue }
            let current = totals[app] ?? (entry.appBundleID, 0, 0)
            totals[app] = (current.bundleID ?? entry.appBundleID, current.count + 1, current.words + words(in: entry.text))
        }
        let ranked = totals.map { name, value in
            (name: name, bundleID: value.bundleID, count: value.count, words: value.words)
        }
        return Array(ranked.sorted { $0.words > $1.words }.prefix(limit))
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
