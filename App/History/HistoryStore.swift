import Foundation
import Observation

struct HistoryEntry: Codable, Identifiable, Hashable {
    enum Status: String, Codable { case done, failed }

    var id = UUID()
    var date = Date()
    var text: String
    /// The transcript before Rewrite cleaned it, when Rewrite changed it.
    var original: String?
    var duration: TimeInterval
    var mode: String
    var language: String
    var status: Status = .done
    /// Kept only for failed entries, so they can be retried.
    var audioPath: String?
    /// The app the text was pasted into.
    var app: String?
    var appBundleID: String?
}

/// Recent dictations, stored as JSON in Application Support.
@Observable
final class HistoryStore {
    static let shared = HistoryStore()
    static let limit = 500

    private(set) var entries: [HistoryEntry] = []

    private init() {
        if let data = try? Data(contentsOf: Paths.history),
           let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = decoded
        }
    }

    var last: HistoryEntry? { entries.first { $0.status == .done } }

    func add(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.limit {
            for dropped in entries[Self.limit...] { removeAudio(of: dropped) }
            entries.removeLast(entries.count - Self.limit)
        }
        save()
    }

    func replace(_ entry: HistoryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        save()
    }

    func delete(_ entry: HistoryEntry) {
        removeAudio(of: entry)
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries.forEach(removeAudio)
        entries.removeAll()
        save()
    }

    private func removeAudio(of entry: HistoryEntry) {
        if let path = entry.audioPath { try? FileManager.default.removeItem(atPath: path) }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: Paths.history, options: .atomic)
        }
    }
}
