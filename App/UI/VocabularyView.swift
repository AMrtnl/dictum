import SwiftUI

/// Words Dictum should always spell your way: add one at the top, edit or remove them below.
struct VocabularyView: View {
    @Bindable private var vocabulary = VocabularyStore.shared
    @State private var word = ""
    @State private var heardAs = ""
    @FocusState private var wordFocused: Bool

    var body: some View {
        PageScroll {
            PageLead("Names, brands and jargon Dictum should always spell your way. Qwen3 also listens for them while you speak.")

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Word", text: $word, prompt: Text("Word or name"))
                        .focused($wordFocused)
                        .frame(width: 200)
                    TextField("Heard as", text: $heardAs, prompt: Text("Heard as (optional), e.g. ghosty, ghost tea"))
                    Button("Add", action: add)
                        .keyboardShortcut(.defaultAction)
                        .disabled(word.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .onSubmit(add)
                Text("“Heard as” lists, separated by commas, what the speech model writes instead. Dictum replaces it with your word in every transcript.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if vocabulary.terms.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle(vocabulary.terms.count == 1 ? "1 word" : "\(vocabulary.terms.count) words")
                    VStack(spacing: 0) {
                        ForEach(Array(vocabulary.terms.enumerated()), id: \.element.id) { index, term in
                            if index > 0 { Divider() }
                            TermRow(term: $vocabulary.terms[index]) {
                                vocabulary.terms.removeAll { $0.id == term.id }
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)
            Text("No words yet").font(.system(size: 14, weight: .semibold))
            Text("Try a colleague's name or an app you use every day, then dictate it to see the difference.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 10)
    }

    private func add() {
        let trimmed = word.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        vocabulary.terms.insert(VocabularyTerm(word: trimmed, heardAs: Self.split(heardAs)), at: 0)
        word = ""
        heardAs = ""
        wordFocused = true
    }

    static func split(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

/// One word: editable in place, with its alternative spellings beside it.
private struct TermRow: View {
    @Binding var term: VocabularyTerm
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            TextField("Word", text: $term.word)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 200, alignment: .leading)
            HStack(spacing: 6) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .opacity(term.heardAs.isEmpty ? 0 : 1)
                TextField("Heard as", text: Binding(
                    get: { term.heardAs.joined(separator: ", ") },
                    set: { term.heardAs = VocabularyView.split($0) }
                ), prompt: Text("Add how it's misheard"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(action: remove) {
                Image(systemName: "trash").font(.system(size: 12)).frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .opacity(hovering ? 1 : 0)
            .help("Remove")
        }
        .textFieldStyle(.plain)
        .labelsHidden()
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
