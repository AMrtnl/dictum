import Foundation
import NaturalLanguage

/// Identifies which of the user's languages a transcript is in, with Apple's on-device
/// NaturalLanguage recognizer. Speech models that need a language hint still write what
/// they hear in the spoken language, so detecting on the text is reliable; Dictum then
/// re-transcribes with the right hint for that language's punctuation and number style.
enum LanguageDetector {
    /// nil when the text is too short or the recognizer isn't confident.
    static func detect(_ text: String, among languages: [SpeechLanguage]) -> SpeechLanguage? {
        guard languages.count > 1, text.split(whereSeparator: \.isWhitespace).count >= 3 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = languages.flatMap(\.naturalLanguages)
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              confidence >= 0.55
        else { return nil }
        return languages.first { $0.naturalLanguages.contains(language) }
    }
}

extension SpeechLanguage {
    var naturalLanguages: [NLLanguage] {
        switch self {
        case .zh: [.simplifiedChinese, .traditionalChinese]
        default: [NLLanguage(rawValue: rawValue)]
        }
    }

    /// The user's first two system languages that the speech model supports (English if
    /// none). Many Macs list more languages than people dictate in; fewer means fewer mix-ups.
    static var systemDefaults: [SpeechLanguage] {
        let codes = Locale.preferredLanguages.compactMap { Locale(identifier: $0).language.languageCode?.identifier }
        var languages: [SpeechLanguage] = []
        for code in codes {
            if let language = SpeechLanguage(rawValue: code), !languages.contains(language) { languages.append(language) }
        }
        return languages.isEmpty ? [.en] : Array(languages.prefix(2))
    }
}
