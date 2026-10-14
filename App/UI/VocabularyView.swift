import SwiftUI

/// Vocabulary, laid out like the replacement tables of dictation and transcription apps
/// (Heidi's "Instead of → Do this", VEED's "Find → Replace"): one field to add a word,
/// then a table of what Dictum hears and what it writes instead.
struct VocabularyView: View {
    @Bindable private var vocabulary = VocabularyStore.shared
    private let history = HistoryStore.shared
    @State private var newWord = ""
    @FocusState private var addFocused: Bool

    private var canAdd: Bool { !newWord.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        let uses = Self.uses(of: vocabulary.terms.map(\.word), in: history.entries)
        PageScroll {
            PageHeader("Vocabulary", subtitle: "Names, brands and jargon Dictum should always spell your way.")

            VStack(alignment: .leading, spacing: 16) {
                addField
                if vocabulary.terms.isEmpty {
                    Text("Add a colleague's name or an app you use every day, then dictate it.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 2)
                } else {
                    table(uses: uses)
                    Text("Qwen3 also listens for these words while you speak.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 2)
                }
            }
        }
    }

    /// One filled field with the add button inside it, like most "add a word" screens.
    private var addField: some View {
        HStack(spacing: 8) {
            TextField("New word", text: $newWord, prompt: Text("Add a word or name…"))
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($addFocused)
                .onSubmit(add)
            Button(action: add) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(canAdd ? Color.accentColor : Color.secondary.opacity(0.35)))
            }
            .buttonStyle(.plain)
            .disabled(!canAdd)
            .help("Add")
        }
        .padding(.leading, 14)
        .padding(.trailing, 7)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(addFocused ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1.5))
        .frame(maxWidth: 520)
    }

    private func table(uses: [String: Int]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Heard as").frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: 12)
                Text("Written as").frame(width: Self.wordColumn, alignment: .leading)
                Text("Used").frame(width: 44, alignment: .trailing)
                Color.clear.frame(width: 24)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(Color.primary.opacity(0.04))

            ForEach($vocabulary.terms) { $term in
                Divider()
                ReplacementRow(term: $term, uses: uses[term.word.lowercased()] ?? 0) {
                    vocabulary.terms.removeAll { $0.id == term.id }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.cardBorder))
    }

    static let wordColumn: CGFloat = 210

    private func add() {
        let trimmed = newWord.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        vocabulary.terms.insert(VocabularyTerm(word: trimmed, heardAs: []), at: 0)
        newWord = ""
        addFocused = true
    }

    static func split(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// How many times each word appears (whole word, any case) in the saved dictations.
    static func uses(of words: [String], in entries: [HistoryEntry]) -> [String: Int] {
        let texts = entries.filter { $0.status == .done }.map(\.text)
        var counts: [String: Int] = [:]
        for word in words where !word.isEmpty {
            guard let pattern = try? NSRegularExpression(pattern: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b",
                                                         options: .caseInsensitive) else { continue }
            counts[word.lowercased()] = texts.reduce(0) { total, text in
                total + pattern.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
            }
        }
        return counts
    }
}

/// One row: the misheard spellings, the word Dictum writes, how often it's used. Both
/// text cells edit in place; delete shows on hover.
private struct ReplacementRow: View {
    @Binding var term: VocabularyTerm
    let uses: Int
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            TextField("Heard as", text: Binding(
                get: { term.heardAs.joined(separator: ", ") },
                set: { term.heardAs = VocabularyView.split($0) }
            ), prompt: Text("Misheard spellings, optional"))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 12)
            TextField("Written as", text: $term.word)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: VocabularyView.wordColumn, alignment: .leading)
            Text(uses == 0 ? "–" : "\(uses)×")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
                .help(uses == 0 ? "Not in your saved dictations yet" : "Appears \(uses) times in your saved dictations")
            Button(action: remove) {
                Image(systemName: "trash").font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(hovering ? Color.red : Color.secondary)
            .opacity(hovering ? 1 : 0)
            .frame(width: 24)
            .help("Remove")
        }
        .textFieldStyle(.plain)
        .labelsHidden()
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(hovering ? Color.primary.opacity(0.03) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

#if DEBUG
/// Snapshot-only: table rows with sample words, without touching the real vocabulary.
struct VocabularyCardsSample: View {
    @State private var terms = [
        VocabularyTerm(word: "Ghostty", heardAs: ["ghosty", "ghost tea"]),
        VocabularyTerm(word: "Qwen3", heardAs: ["queen three"]),
        VocabularyTerm(word: "Martinoli", heardAs: []),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach($terms) { $term in
                Divider()
                ReplacementRow(term: $term, uses: term.word == "Ghostty" ? 14 : 0) {}
            }
        }
        .padding(30)
        .frame(width: 700)
    }
}
#endif
