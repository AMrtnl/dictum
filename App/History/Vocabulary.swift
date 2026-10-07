import Foundation
import Observation

/// A word the user wants written a particular way, plus what the model tends to write instead.
struct VocabularyTerm: Codable, Identifiable, Hashable {
    var id = UUID()
    var word: String
    /// Spellings to replace with `word`, e.g. ["dik tum", "dictem"]. The word itself always
    /// matches case-insensitively, so "dictum" becomes "Dictum" without listing it.
    var heardAs: [String] = []
}

/// Custom vocabulary, applied to every transcript. Cohere Transcribe can't be biased toward
/// words, so this corrects the text afterwards: whole-word, case-insensitive replacements.
@Observable
final class VocabularyStore {
    static let shared = VocabularyStore()
    private static let file = Paths.support.appending(path: "vocabulary.json")

    var terms: [VocabularyTerm] = [] {
        didSet { save() }
    }

    private init() {
        if let data = try? Data(contentsOf: Self.file),
           let decoded = try? JSONDecoder().decode([VocabularyTerm].self, from: data) {
            terms = decoded
        }
    }

    func apply(to text: String) -> String {
        var result = text
        let replacements = terms.flatMap { term in
            ([term.word] + term.heardAs).map { ($0.trimmingCharacters(in: .whitespaces), term.word) }
        }
        .filter { !$0.0.isEmpty && !$0.1.isEmpty }
        .sorted { $0.0.count > $1.0.count }  // longest first, so phrases win over their words
        for (pattern, word) in replacements {
            let escaped = NSRegularExpression.escapedPattern(for: pattern)
            guard let regex = try? NSRegularExpression(
                pattern: "(?<![\\p{L}\\p{N}])\(escaped)(?![\\p{L}\\p{N}])", options: [.caseInsensitive])
            else { continue }
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result),
                withTemplate: NSRegularExpression.escapedTemplate(for: word))
        }
        return result
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(terms) {
            try? data.write(to: Self.file, options: .atomic)
        }
    }
}
