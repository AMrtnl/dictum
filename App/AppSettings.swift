import Foundation
import Observation

enum DictationMode: String, CaseIterable, Identifiable {
    case dictation, rewrite

    var id: Self { self }

    var title: String {
        switch self {
        case .dictation: "Dictation"
        case .rewrite: "Rewrite"
        }
    }

    var summary: String {
        switch self {
        case .dictation: "Pastes exactly what you said."
        case .rewrite: "Cleans up fillers, false starts and punctuation with Tiny Aya."
        }
    }
}

/// How long a model stays in memory after its last use (RAM vs. first-use delay).
enum KeepLoaded: Int, CaseIterable, Identifiable {
    case thirtySeconds = 30, oneMinute = 60, fiveMinutes = 300, oneHour = 3600, always = 0

    var id: Self { self }

    var title: String {
        switch self {
        case .thirtySeconds: "30 seconds"
        case .oneMinute: "1 minute"
        case .fiveMinutes: "5 minutes"
        case .oneHour: "1 hour"
        case .always: "Always"
        }
    }
}

/// The 14 languages Cohere Transcribe was trained on. The setting is a hint:
/// in testing, French speech still came out in French with English selected.
enum SpeechLanguage: String, CaseIterable, Identifiable {
    case en, fr, de, es, it, pt, nl, pl, el, ar, ja, ko, zh, vi

    var id: Self { self }

    var title: String {
        Locale(identifier: "en").localizedString(forLanguageCode: rawValue)?.capitalized ?? rawValue
    }
}

/// User preferences, persisted in UserDefaults.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var mode: DictationMode { didSet { store(mode.rawValue, "mode") } }
    var language: SpeechLanguage { didSet { store(language.rawValue, "language") } }
    var recordingWindowStyle: RecordingWindowStyle {
        didSet { store(recordingWindowStyle.rawValue, RecordingWindowStyle.defaultsKey) }
    }
    var alwaysShowIndicator: Bool { didSet { store(alwaysShowIndicator, "alwaysShowIndicator") } }
    /// Core Audio device UID; nil follows the system default input.
    var microphoneUID: String? { didSet { store(microphoneUID, "microphoneUID") } }
    var playSounds: Bool { didSet { store(playSounds, "playSounds") } }
    var keepInClipboard: Bool { didSet { store(keepInClipboard, "keepInClipboard") } }
    var saveHistory: Bool { didSet { store(saveHistory, "saveHistory") } }
    var hasCompletedOnboarding: Bool { didSet { store(hasCompletedOnboarding, "hasCompletedOnboarding") } }
    var speechKeepLoaded: KeepLoaded { didSet { store(speechKeepLoaded.rawValue, "speechKeepLoaded") } }
    var rewriteKeepLoaded: KeepLoaded { didSet { store(rewriteKeepLoaded.rawValue, "rewriteKeepLoaded") } }

    @ObservationIgnored private let defaults = UserDefaults.standard

    private init() {
        let d = UserDefaults.standard
        mode = d.string(forKey: "mode").flatMap(DictationMode.init) ?? .dictation
        language = d.string(forKey: "language").flatMap(SpeechLanguage.init) ?? .en
        recordingWindowStyle = .current
        alwaysShowIndicator = d.bool(forKey: "alwaysShowIndicator")
        microphoneUID = d.string(forKey: "microphoneUID")
        playSounds = d.object(forKey: "playSounds") as? Bool ?? true
        keepInClipboard = d.bool(forKey: "keepInClipboard")
        saveHistory = d.object(forKey: "saveHistory") as? Bool ?? true
        hasCompletedOnboarding = d.bool(forKey: "hasCompletedOnboarding")
        speechKeepLoaded = (d.object(forKey: "speechKeepLoaded") as? Int).flatMap(KeepLoaded.init) ?? .always
        rewriteKeepLoaded = (d.object(forKey: "rewriteKeepLoaded") as? Int).flatMap(KeepLoaded.init) ?? .oneMinute
    }

    private func store(_ value: Any?, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
