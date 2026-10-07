import AVFoundation
import Foundation
import Observation

/// One recording kept for fine-tuning: the audio plus its verbatim transcript.
struct TrainingSample: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    /// Relative to the dataset folder, e.g. "audio/<id>.wav".
    var fileName: String
    /// What was said, word for word (the transcript after Vocabulary, before Rewrite).
    var transcription: String
    var rewrite: String?
    var language: String
    var duration: TimeInterval
    /// Set once the user has checked or corrected the transcript.
    var verified = false
}

/// Recordings saved for training, as a Hugging Face "audiofolder" dataset:
/// `audio/*.wav` (16 kHz mono) plus `metadata.jsonl`, ready for fine-tuning tools.
@Observable
final class TrainingDataStore {
    static let shared = TrainingDataStore()
    static let folder = Paths.support.appending(path: "Training data", directoryHint: .isDirectory)
    private static let index = folder.appending(path: "samples.json")
    private static let metadata = folder.appending(path: "metadata.jsonl")

    private(set) var samples: [TrainingSample] = []

    private init() {
        if let data = try? Data(contentsOf: Self.index),
           let decoded = try? JSONDecoder().decode([TrainingSample].self, from: data) {
            samples = decoded
        }
    }

    var totalDuration: TimeInterval { samples.reduce(0) { $0 + $1.duration } }
    var verifiedCount: Int { samples.filter(\.verified).count }

    func url(for sample: TrainingSample) -> URL { Self.folder.appending(path: sample.fileName) }

    /// Copies the take into the dataset. Call before the take file is deleted.
    func add(take: URL, transcription: String, rewrite: String?, language: String, duration: TimeInterval) {
        let id = UUID()
        let fileName = "audio/\(id.uuidString).wav"
        let destination = Self.folder.appending(path: fileName)
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: take, to: destination)
        } catch {
            return
        }
        samples.insert(TrainingSample(id: id, fileName: fileName, transcription: transcription, rewrite: rewrite,
                                      language: language, duration: duration), at: 0)
        save()
    }

    func correct(_ sample: TrainingSample, transcription: String) {
        guard let index = samples.firstIndex(where: { $0.id == sample.id }) else { return }
        samples[index].transcription = transcription.trimmingCharacters(in: .whitespacesAndNewlines)
        samples[index].verified = true
        save()
    }

    func delete(_ sample: TrainingSample) {
        try? FileManager.default.removeItem(at: url(for: sample))
        samples.removeAll { $0.id == sample.id }
        save()
    }

    func deleteAll() {
        try? FileManager.default.removeItem(at: Self.folder)
        samples.removeAll()
    }

    var bytesOnDisk: Int64 {
        samples.reduce(0) { total, sample in
            let attributes = try? FileManager.default.attributesOfItem(atPath: url(for: sample).path)
            return total + ((attributes?[.size] as? NSNumber)?.int64Value ?? 0)
        }
    }

    /// Zips the dataset folder (audio + metadata.jsonl) to `destination`.
    func export(to destination: URL) throws {
        save()
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", Self.folder.path, destination.path]
        try ditto.run()
        ditto.waitUntilExit()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(samples) {
            try? data.write(to: Self.index, options: .atomic)
        }
        // metadata.jsonl, oldest first, in the audiofolder convention.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let lines = samples.reversed().compactMap { sample -> String? in
            let row = MetadataRow(file_name: sample.fileName, transcription: sample.transcription,
                                  language: sample.language, duration: (sample.duration * 100).rounded() / 100,
                                  verified: sample.verified)
            return (try? encoder.encode(row)).flatMap { String(data: $0, encoding: .utf8) }
        }
        try? (lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n"))
            .write(to: Self.metadata, atomically: true, encoding: .utf8)
    }

    private struct MetadataRow: Encodable {
        let file_name: String
        let transcription: String
        let language: String
        let duration: Double
        let verified: Bool
    }
}

/// Plays one sample at a time.
@Observable
final class SamplePlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = SamplePlayer()
    private(set) var playing: UUID?
    @ObservationIgnored private var player: AVAudioPlayer?

    func toggle(_ sample: TrainingSample) {
        if playing == sample.id {
            stop()
            return
        }
        stop()
        guard let player = try? AVAudioPlayer(contentsOf: TrainingDataStore.shared.url(for: sample)) else { return }
        player.delegate = self
        player.play()
        self.player = player
        playing = sample.id
    }

    func stop() {
        player?.stop()
        player = nil
        playing = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}
