import SwiftUI

struct VocabularyView: View {
    @Bindable private var vocabulary = VocabularyStore.shared
    @State private var word = ""
    @State private var heardAs = ""
    @FocusState private var wordFocused: Bool

    var body: some View {
        Form {
            Section {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    TextField("Word or name", text: $word, prompt: Text("e.g. Dictum"))
                        .focused($wordFocused)
                    TextField("Heard as", text: $heardAs, prompt: Text("optional: dik tum, dictem"))
                    Button("Add", action: add)
                        .disabled(word.trimmingCharacters(in: .whitespaces).isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
            } header: {
                Text("Add a word")
            } footer: {
                Text("Dictum writes the word exactly as you type it here. It also replaces anything listed under “Heard as”, comma-separated, in every transcript.")
            }

            Section("Your vocabulary") {
                if vocabulary.terms.isEmpty {
                    Text("No words yet. Add names, brands or jargon the speech model gets wrong.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach($vocabulary.terms) { $term in
                        HStack(spacing: 10) {
                            TextField("Word", text: $term.word)
                                .fontWeight(.semibold)
                            TextField("Heard as", text: Binding(
                                get: { term.heardAs.joined(separator: ", ") },
                                set: { term.heardAs = Self.split($0) }
                            ), prompt: Text("heard as…"))
                            .foregroundStyle(.secondary)
                            Button {
                                vocabulary.terms.removeAll { $0.id == term.id }
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove")
                        }
                        .textFieldStyle(.plain)
                        .labelsHidden()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func add() {
        let trimmed = word.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        vocabulary.terms.insert(VocabularyTerm(word: trimmed, heardAs: Self.split(heardAs)), at: 0)
        word = ""
        heardAs = ""
        wordFocused = true
    }

    private static func split(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
