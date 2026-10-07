import SwiftUI
import UniformTypeIdentifiers

struct TrainingDataView: View {
    @Bindable private var settings = AppSettings.shared
    private let store = TrainingDataStore.shared
    @State private var confirmDelete = false
    @State private var exportError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Save recordings for training", isOn: $settings.saveTrainingData)
                Text("Keeps each dictation's audio and its word-for-word transcript on this Mac, so you can fine-tune a speech model on your own voice later. Check and correct transcripts below; corrected ones are marked verified.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 0) {
                    stat("\(store.samples.count)", "Recordings")
                    stat(Self.duration(store.totalDuration), "Audio")
                    stat("\(store.verifiedCount)", "Verified")
                    stat(ByteCountFormatter.string(fromByteCount: store.bytesOnDisk, countStyle: .file), "On disk")
                }
                HStack {
                    Button("Show in Finder") {
                        try? FileManager.default.createDirectory(at: TrainingDataStore.folder, withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([TrainingDataStore.folder])
                    }
                    Button("Export…", action: export).disabled(store.samples.isEmpty)
                    Spacer()
                    Button("Delete All…", role: .destructive) { confirmDelete = true }.disabled(store.samples.isEmpty)
                }
            } header: {
                Text("Dataset")
            } footer: {
                Text("Hugging Face “audiofolder” format: audio/*.wav (16 kHz mono) and metadata.jsonl with file_name, transcription, language. Most fine-tuning scripts for Whisper, Parakeet or Cohere Transcribe load it directly.")
            }
            if let exportError {
                Text(exportError).foregroundStyle(.red).font(.callout)
            }

            Section("Recordings") {
                if store.samples.isEmpty {
                    Text(settings.saveTrainingData ? "Your next dictations will appear here." : "Turn on “Save recordings for training” to start collecting.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.samples) { sample in
                        SampleRow(sample: sample)
                    }
                }
            }
        }
        .formStyle(.grouped)
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

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 17, weight: .semibold)).monospacedDigit()
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    .lineLimit(1...6)
                    .onSubmit(save)
                HStack(spacing: 6) {
                    Text(sample.date.formatted(date: .abbreviated, time: .shortened))
                    Text("·")
                    Text(TrainingDataView.duration(sample.duration))
                    Text("·")
                    Text(sample.language.uppercased())
                    if sample.verified {
                        Label("Verified", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    } else if text != sample.transcription {
                        Button("Save correction", action: save).buttonStyle(.link)
                    } else {
                        Button("Mark verified", action: save).buttonStyle(.link)
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
        .padding(.vertical, 2)
    }

    private func save() {
        TrainingDataStore.shared.correct(sample, transcription: text)
    }
}
