import SwiftUI
import UniformTypeIdentifiers

/// Training data: your recordings with their word-for-word transcripts. A summary card on
/// top (with how many you've checked), then each recording with its own waveform.
struct TrainingDataView: View {
    @Bindable private var settings = AppSettings.shared
    private let store = TrainingDataStore.shared
    @State private var confirmDelete = false
    @State private var exportError: String?

    var body: some View {
        PageScroll {
            PageLead("Recordings and their transcripts, to teach a speech model your voice. They stay on this Mac.") {
                Toggle("Save recordings", isOn: $settings.saveTrainingData)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help("Save each dictation's audio for training")
            }

            if !store.samples.isEmpty { summaryCard }

            if store.samples.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "waveform.badge.plus").font(.system(size: 24)).foregroundStyle(.tertiary)
                        .padding(.bottom, 4)
                    Text(settings.saveTrainingData ? "Nothing saved yet" : "Saving is off").font(.system(size: 14, weight: .semibold))
                    Text(settings.saveTrainingData ? "Your next dictations will appear here." : "Turn it on to start collecting. Nothing is kept until you do.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle("Recordings")
                    DashCard(padding: 0) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(store.samples.enumerated()), id: \.element.id) { index, sample in
                                if index > 0 { Divider().padding(.leading, 52) }
                                SampleRow(sample: sample)
                            }
                        }
                    }
                }
            }
        }
        .confirmationDialog("Delete all saved recordings?", isPresented: $confirmDelete) {
            Button("Delete All", role: .destructive) {
                SamplePlayer.shared.stop()
                store.deleteAll()
            }
        } message: {
            Text("The audio and transcripts are removed from this Mac.")
        }
        .onDisappear { SamplePlayer.shared.stop() }
    }

    private var summaryCard: some View {
        let total = store.samples.count
        let checked = store.verifiedCount
        return DashCard(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 0) {
                    metric("\(total)", "Recordings")
                    Divider().frame(height: 40).padding(.horizontal, 18)
                    metric(Self.duration(store.totalDuration), "Audio")
                    Divider().frame(height: 40).padding(.horizontal, 18)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(checked)").font(.system(size: 22, weight: .bold))
                            Text("of \(total) checked").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        GeometryReader { proxy in
                            Capsule().fill(Color.primary.opacity(0.08))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Color.green)
                                        .frame(width: max(checked > 0 ? 6 : 0, proxy.size.width * Double(checked) / Double(max(total, 1))))
                                }
                        }
                        .frame(width: 140, height: 5)
                    }
                    Divider().frame(height: 40).padding(.horizontal, 18)
                    metric(ByteCountFormatter.string(fromByteCount: store.bytesOnDisk, countStyle: .file), "On disk")
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    Button("Show in Finder") {
                        try? FileManager.default.createDirectory(at: TrainingDataStore.folder, withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([TrainingDataStore.folder])
                    }
                    Button("Export…", action: export)
                        .help("A Hugging Face “audiofolder” dataset: audio/*.wav and metadata.jsonl.")
                    if let exportError {
                        Text(exportError).foregroundStyle(.red).font(.system(size: 12))
                    }
                    Spacer()
                    Button("Delete All…", role: .destructive) { confirmDelete = true }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                }
                .controlSize(.small)
            }
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 22, weight: .bold))
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "Dictum training data.zip"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.export(to: url)
            exportError = nil
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            exportError = "Export failed: \(error.localizedDescription)"
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return total < 3600 ? String(format: "%d:%02d", total / 60, total % 60)
            : String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }
}

/// One recording: play it, see its shape, correct its transcript, mark it checked.
private struct SampleRow: View {
    let sample: TrainingSample
    @State private var text: String
    @State private var hovering = false
    private let player = SamplePlayer.shared

    init(sample: TrainingSample) {
        self.sample = sample
        _text = State(initialValue: sample.transcription)
    }

    var body: some View {
        let playing = player.playing == sample.id
        HStack(alignment: .top, spacing: 12) {
            Button { player.toggle(sample) } label: {
                Image(systemName: playing ? "stop.fill" : "play.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.accentColor))
            }
            .buttonStyle(.plain)
            .help(playing ? "Stop" : "Play")

            VStack(alignment: .leading, spacing: 8) {
                AudioThumbnail(url: TrainingDataStore.shared.url(for: sample), playing: playing)
                    .frame(width: 180, height: 20)
                TextField("Transcript", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .labelsHidden()
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(size: 13))
                    .lineLimit(1...6)
                    .onSubmit(save)
                HStack(spacing: 6) {
                    Text(sample.date.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                    Text("·").foregroundStyle(.tertiary)
                    Text(TrainingDataView.duration(sample.duration)).monospacedDigit()
                    Text("·").foregroundStyle(.tertiary)
                    Text(SpeechLanguage.flag(for: sample.language)).help(SpeechLanguage.name(for: sample.language))
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                if sample.verified && text == sample.transcription {
                    Label("Checked", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                } else if text != sample.transcription {
                    Button("Save Correction", action: save).controlSize(.small)
                } else {
                    Button("Mark Correct", action: save).controlSize(.small)
                }
                Button {
                    if player.playing == sample.id { player.stop() }
                    TrainingDataStore.shared.delete(sample)
                } label: {
                    Image(systemName: "trash").font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .opacity(hovering ? 1 : 0)
                .help("Delete")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private func save() {
        TrainingDataStore.shared.correct(sample, transcription: text)
    }
}

/// A recording's shape: its loudness over time as mirrored bars, read from the WAV once
/// (off the main thread) and cached.
private struct AudioThumbnail: View {
    let url: URL
    let playing: Bool
    @State private var peaks: [Float] = []

    var body: some View {
        Canvas { context, size in
            guard !peaks.isEmpty else {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: size.height / 2))
                line.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                context.stroke(line, with: .color(.secondary.opacity(0.25)), lineWidth: 1)
                return
            }
            let step = size.width / CGFloat(peaks.count)
            let width = max(1.5, step * 0.55)
            for (index, peak) in peaks.enumerated() {
                let height = max(2, CGFloat(peak) * size.height)
                let rect = CGRect(x: CGFloat(index) * step + (step - width) / 2, y: (size.height - height) / 2,
                                  width: width, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: width / 2),
                             with: .color(playing ? Color.accentColor : Color.secondary.opacity(0.55)))
            }
        }
        .task(id: url) { peaks = await AudioPeaks.load(url) }
        .accessibilityHidden(true)
    }
}

/// Peak levels of a 16 kHz mono 16-bit WAV, in a fixed number of buckets, normalised to the
/// loudest one. Computed off the main thread; kept for the session.
enum AudioPeaks {
    private static var cache: [URL: [Float]] = [:]

    static func load(_ url: URL, buckets: Int = 60) async -> [Float] {
        if let cached = cache[url] { return cached }
        let peaks = await Task.detached(priority: .utility) { compute(url, buckets: buckets) }.value
        cache[url] = peaks
        return peaks
    }

    nonisolated private static func compute(_ url: URL, buckets: Int) -> [Float] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count > 46 else { return [] }
        let samples = (data.count - 44) / 2
        let perBucket = max(1, samples / buckets)
        var peaks = [Float](repeating: 0, count: buckets)
        data.withUnsafeBytes { raw in
            for bucket in 0..<buckets {
                var loudest: Int32 = 0
                var index = bucket * perBucket
                let end = min(samples, index + perBucket)
                while index < end {
                    let offset = 44 + index * 2
                    let value = Int32(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: Int16.self)))
                    loudest = max(loudest, abs(value))
                    index += 4  // every 4th sample is plenty for a thumbnail
                }
                peaks[bucket] = Float(loudest) / 32768
            }
        }
        let top = max(peaks.max() ?? 0, 0.02)
        return peaks.map { min(1, $0 / top) }
    }
}
