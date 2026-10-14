import SwiftUI
import UniformTypeIdentifiers

struct TrainingDataView: View {
    @Bindable private var settings = AppSettings.shared
    private let store = TrainingDataStore.shared
    @State private var confirmDelete = false
    @State private var exportError: String?

    var body: some View {
        PageScroll {
            PageLead("Keep each dictation's audio with its word-for-word transcript, so you can later teach a speech model your voice, accent and words. Everything stays on this Mac.") {
                Toggle("Save recordings", isOn: $settings.saveTrainingData)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help("Save recordings for training")
            }

            if !store.samples.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    summary
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button("Show in Finder") {
                            try? FileManager.default.createDirectory(at: TrainingDataStore.folder, withIntermediateDirectories: true)
                            NSWorkspace.shared.activateFileViewerSelecting([TrainingDataStore.folder])
                        }
                        Button("Export…", action: export)
                        Spacer()
                        Button("Delete All…", role: .destructive) { confirmDelete = true }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                    }
                    if let exportError {
                        Text(exportError).foregroundStyle(.red).font(.system(size: 12))
                    }
                    Text("Exports a Hugging Face “audiofolder” dataset: audio/*.wav (16 kHz mono) and metadata.jsonl. Most fine-tuning scripts for Whisper, Parakeet or Cohere Transcribe read it as is.")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Recordings")
                if store.samples.isEmpty {
                    Text(settings.saveTrainingData
                         ? "Your next dictations will appear here."
                         : "Turn on saving to start collecting. Nothing is kept until you do.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Listen, correct what the model got wrong, then mark it correct. Checked recordings make the best training data.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    LazyVStack(spacing: 0) {
                        ForEach(Array(store.samples.enumerated()), id: \.element.id) { index, sample in
                            if index > 0 { Divider().padding(.leading, 34) }
                            SampleRow(sample: sample)
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

    private var summary: Text {
        let recordings = Text("\(store.samples.count) recording\(store.samples.count == 1 ? "" : "s")").foregroundStyle(.primary)
        let audio = Text(Self.duration(store.totalDuration)).foregroundStyle(.primary)
        let checked = Text("\(store.verifiedCount) checked").foregroundStyle(.primary)
        let size = Text(ByteCountFormatter.string(fromByteCount: store.bytesOnDisk, countStyle: .file)).foregroundStyle(.primary)
        return Text("\(recordings), \(audio) of audio, \(checked) by you, \(size) on this Mac.")
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

private struct SampleRow: View {
    let sample: TrainingSample
    @State private var text: String
    private let player = SamplePlayer.shared

    init(sample: TrainingSample) {
        self.sample = sample
        _text = State(initialValue: sample.transcription)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { player.toggle(sample) } label: {
                Image(systemName: player.playing == sample.id ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.borderless)
            .help(player.playing == sample.id ? "Stop" : "Play")

            VStack(alignment: .leading, spacing: 4) {
                TextField("Transcript", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .labelsHidden()  // in a Form row the label would push the text to the right edge
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1...6)
                    .onSubmit(save)
                HStack(spacing: 6) {
                    Text(sample.date.formatted(date: .abbreviated, time: .shortened))
                    Text("·")
                    Text(TrainingDataView.duration(sample.duration))
                    Text("·")
                    Text(sample.language.uppercased())
                    if sample.verified {
                        Label("Checked", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else if text != sample.transcription {
                        Button("Save Correction", action: save).buttonStyle(.link)
                    } else {
                        Button("Mark as Correct", action: save).buttonStyle(.link)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button {
                if player.playing == sample.id { player.stop() }
                TrainingDataStore.shared.delete(sample)
            } label: {
                Image(systemName: "trash").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Delete")
        }
        .padding(.vertical, 10)
    }

    private func save() {
        TrainingDataStore.shared.correct(sample, transcription: text)
    }
}
