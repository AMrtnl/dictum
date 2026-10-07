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

    var savedDescription: String {
        let minutes = Int(minutesSaved.rounded())
        if minutes < 1 { return "–" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = Double(minutes) / 60
        return hours < 10 ? String(format: hours.truncatingRemainder(dividingBy: 1) < 0.1 ? "%.0f h" : "%.1f h", hours)
            : "\(Int(hours.rounded())) h"
    }
}
