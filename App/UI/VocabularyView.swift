import SwiftUI

/// Words Dictum should always spell your way: add one at the top; below, a card per word
/// with how it gets misheard and how often it shows up in your dictations.
struct VocabularyView: View {
    @Bindable private var vocabulary = VocabularyStore.shared
    private let history = HistoryStore.shared
    @State private var word = ""
    @State private var heardAs = ""
    @FocusState private var wordFocused: Bool

    var body: some View {
        let uses = Self.uses(of: vocabulary.terms.map(\.word), in: history.entries)
        PageScroll {
            PageLead("Names, brands and jargon Dictum should always spell your way.")

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.accentColor)
                    TextField("Word", text: $word, prompt: Text("New word"))
                        .font(.system(size: 15, weight: .semibold))
                        .focused($wordFocused)
                        .frame(width: 170)
                    Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 20)
                    Image(systemName: "ear")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .help("How the speech model mishears it, separated by commas")
                    TextField("Heard as", text: $heardAs, prompt: Text("misheard as… (optional)"))
                        .font(.system(size: 14))
                    Button("Add", action: add)
                        .glassButton(prominent: true)
                        .keyboardShortcut(.defaultAction)
                        .disabled(word.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .textFieldStyle(.plain)
                .labelsHidden()
                .onSubmit(add)
                .padding(.leading, 14)
                .padding(.trailing, 6)
                .padding(.vertical, 7)
                .glassSurface(cornerRadius: 24, interactive: true)

                if !word.trimmingCharacters(in: .whitespaces).isEmpty {
                    preview
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 16)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: word.isEmpty)

            if vocabulary.terms.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "character.book.closed").font(.system(size: 24)).foregroundStyle(.tertiary)
                        .padding(.bottom, 4)
                    Text("No words yet").font(.system(size: 14, weight: .semibold))
                    Text("Add a colleague's name or an app you use every day, then dictate it.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        SectionTitle(vocabulary.terms.count == 1 ? "1 word" : "\(vocabulary.terms.count) words")
                        let total = uses.values.reduce(0, +)
                        if total > 0 {
                            Text("· \(total) in your dictations").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], alignment: .leading, spacing: 12) {
                        ForEach($vocabulary.terms) { $term in
                            TermCard(term: $term, uses: uses[term.word.lowercased()] ?? 0) {
                                vocabulary.terms.removeAll { $0.id == term.id }
                            }
                        }
                    }
                }
            }
        }
    }

    /// What the new word will do, as you type it.
    private var preview: Text {
        let target = Text(word.trimmingCharacters(in: .whitespaces)).fontWeight(.semibold).foregroundStyle(.primary)
        let spellings = Self.split(heardAs)
        guard !spellings.isEmpty else { return Text("Dictum will always write \(target).") }
        let heard = spellings.map { Text($0).strikethrough() }.reduce(Text("")) { list, item in
            list == Text("") ? item : Text("\(list), \(item)")
        }
        return Text("Dictum will write \(target) when it hears \(heard).")
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

/// One word: the spelling Dictum writes, the spellings it replaces, how often it's used.
private struct TermCard: View {
    @Binding var term: VocabularyTerm
    let uses: Int
    let remove: () -> Void
    @State private var hovering = false
    @State private var editing = false

    var body: some View {
        DashCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(term.word).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                    Spacer(minLength: 6)
                    if hovering {
                        Button { editing = true } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary).help("Edit")
                        Button(action: remove) { Image(systemName: "trash") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary).help("Remove")
                    } else {
                        Text(uses == 0 ? "Not used yet" : "\(uses)×")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(uses == 0 ? Color.secondary : Color.accentColor)
                            .help(uses == 0 ? "Not in your saved dictations yet" : "Appears \(uses) times in your saved dictations")
                    }
                }
                if term.heardAs.isEmpty {
                    Text("Written exactly like this").font(.system(size: 12)).foregroundStyle(.tertiary)
                } else {
                    FlowLayout(spacing: 5) {
                        ForEach(term.heardAs, id: \.self) { spelling in
                            Text(spelling)
                                .strikethrough(color: .secondary)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.primary.opacity(0.06)))
                        }
                    }
                }
            }
            .frame(minHeight: 58, alignment: .top)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { editing = true }
        .popover(isPresented: $editing, arrowEdge: .bottom) {
            TermEditor(term: $term)
        }
    }
}

private struct TermEditor: View {
    @Binding var term: VocabularyTerm

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Word").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            TextField("Word", text: $term.word).textFieldStyle(.roundedBorder)
            Text("Heard as, separated by commas").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            TextField("Heard as", text: Binding(
                get: { term.heardAs.joined(separator: ", ") },
                set: { term.heardAs = VocabularyView.split($0) }
            ))
            .textFieldStyle(.roundedBorder)
        }
        .labelsHidden()
        .padding(14)
        .frame(width: 280)
    }
}

#if DEBUG
/// Snapshot-only: the word cards with sample words, without touching the real vocabulary.
struct VocabularyCardsSample: View {
    @State private var terms = [
        VocabularyTerm(word: "Ghostty", heardAs: ["ghosty", "ghost tea"]),
        VocabularyTerm(word: "Qwen3", heardAs: ["queen three", "quen 3"]),
        VocabularyTerm(word: "Martinoli", heardAs: []),
        VocabularyTerm(word: "Discio", heardAs: ["disco", "dizzio"]),
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], alignment: .leading, spacing: 12) {
            ForEach($terms) { $term in
                TermCard(term: $term, uses: term.word == "Ghostty" ? 14 : term.word == "Qwen3" ? 3 : 0) {}
            }
        }
        .padding(30)
    }
}
#endif
