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

/// Speech-to-text models Dictum can run (all through mlx-speech). Figures are from our
/// benchmark on real English/French speech on an M4 Pro.
enum SpeechModel: String, CaseIterable, Identifiable {
    case qwen3, cohere, nemotron

    var id: Self { self }

    var title: String {
        switch self {
        case .qwen3: "Qwen3-ASR 1.7B"
        case .cohere: "Cohere Transcribe"
        case .nemotron: "Nemotron 3.5 Streaming"
        }
    }

    var badge: String {
        switch self {
        case .qwen3: "Most accurate"
        case .cohere: "Fastest"
        case .nemotron: "Smallest"
        }
    }

    var summary: String {
        switch self {
        case .qwen3: "Detects your language phrase by phrase, so you can mix French and English, and uses your Vocabulary as hints."
        case .cohere: "Very fast and light on memory. It can't detect the language itself, so Dictum works it out from the text; it struggles when one dictation mixes languages."
        case .nemotron: "A small download that detects your language, but noticeably less accurate."
        }
    }

    var detectsLanguage: Bool { self != .cohere }
    var usesVocabulary: Bool { self == .qwen3 }

    /// Word error rate on English / French test speech, lower is better.
    var accuracy: String {
        switch self {
        case .qwen3: "3.3 % / 5.2 %"
        case .cohere: "4.8 % / 5.6 %"
        case .nemotron: "9.8 % / 12.8 %"
        }
    }

    /// Time to transcribe a 10-second dictation.
    var speed: String {
        switch self {
        case .qwen3: "0.6 s"
        case .cohere: "0.2 s"
        case .nemotron: "0.3 s"
        }
    }

    var memory: String {
        switch self {
        case .qwen3: "3 GB"
        case .cohere: "1.9 GB"
        case .nemotron: "1.6 GB"
        }
    }

    var download: String {
        switch self {
        case .qwen3: "2.5 GB"
        case .cohere: "2.4 GB"
        case .nemotron: "0.8 GB"
        }
    }
}

/// What the dictation shortcut does when pressed.
enum ShortcutBehavior: String, CaseIterable, Identifiable {
    case hybrid, toggle, hold

    var id: Self { self }

    var title: String {
        switch self {
        case .hybrid: "Tap to lock, hold to talk"
        case .toggle: "Press to start and stop"
        case .hold: "Hold to talk"
        }
    }

    var summary: String {
        switch self {
        case .hybrid: "A quick tap starts a hands-free dictation; tap again to stop and paste. Holding the shortcut records only while you hold it."
        case .toggle: "Every press starts or stops a dictation."
        case .hold: "Records while you hold the shortcut and pastes when you let go."
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
    var speechModel: SpeechModel { didSet { store(speechModel.rawValue, "speechModel") } }
    var shortcutBehavior: ShortcutBehavior { didSet { store(shortcutBehavior.rawValue, "shortcutBehavior") } }
    var language: SpeechLanguage { didSet { store(language.rawValue, "language") } }
    /// Detect which of `spokenLanguages` each dictation is in.
    var autoLanguage: Bool { didSet { store(autoLanguage, "autoLanguage") } }
    var spokenLanguages: [SpeechLanguage] {
        didSet { store(spokenLanguages.map(\.rawValue).joined(separator: ","), "spokenLanguages") }
    }
    /// The language the last dictation turned out to be; the next one starts with it.
    var lastLanguage: SpeechLanguage? { didSet { store(lastLanguage?.rawValue, "lastLanguage") } }
    var recordingWindowStyle: RecordingWindowStyle {
        didSet { store(recordingWindowStyle.rawValue, RecordingWindowStyle.defaultsKey) }
    }
    var alwaysShowIndicator: Bool { didSet { store(alwaysShowIndicator, "alwaysShowIndicator") } }
    var waveformStyle: WaveformStyle { didSet { store(waveformStyle.rawValue, "waveformStyle") } }
    /// Core Audio device UID; nil follows the system default input.
    var microphoneUID: String? { didSet { store(microphoneUID, "microphoneUID") } }
    var playSounds: Bool { didSet { store(playSounds, "playSounds") } }
    var keepInClipboard: Bool { didSet { store(keepInClipboard, "keepInClipboard") } }
    var saveHistory: Bool { didSet { store(saveHistory, "saveHistory") } }
    var saveTrainingData: Bool { didSet { store(saveTrainingData, "saveTrainingData") } }
    var hasCompletedOnboarding: Bool { didSet { store(hasCompletedOnboarding, "hasCompletedOnboarding") } }
    var speechKeepLoaded: KeepLoaded { didSet { store(speechKeepLoaded.rawValue, "speechKeepLoaded") } }
    var rewriteKeepLoaded: KeepLoaded { didSet { store(rewriteKeepLoaded.rawValue, "rewriteKeepLoaded") } }

    @ObservationIgnored private let defaults = UserDefaults.standard

    private init() {
        let d = UserDefaults.standard
        mode = d.string(forKey: "mode").flatMap(DictationMode.init) ?? .dictation
        speechModel = d.string(forKey: "speechModel").flatMap(SpeechModel.init) ?? .qwen3
        shortcutBehavior = d.string(forKey: "shortcutBehavior").flatMap(ShortcutBehavior.init) ?? .hybrid
        language = d.string(forKey: "language").flatMap(SpeechLanguage.init) ?? .en
        autoLanguage = d.object(forKey: "autoLanguage") as? Bool ?? true
        spokenLanguages = d.string(forKey: "spokenLanguages")?.split(separator: ",")
            .compactMap { SpeechLanguage(rawValue: String($0)) } ?? SpeechLanguage.systemDefaults
        lastLanguage = d.string(forKey: "lastLanguage").flatMap(SpeechLanguage.init)
        recordingWindowStyle = .current
        alwaysShowIndicator = d.object(forKey: "alwaysShowIndicator") as? Bool ?? true
        waveformStyle = d.string(forKey: "waveformStyle").flatMap(WaveformStyle.init) ?? .conveyor
        microphoneUID = d.string(forKey: "microphoneUID")
        playSounds = d.object(forKey: "playSounds") as? Bool ?? true
        keepInClipboard = d.bool(forKey: "keepInClipboard")
        saveHistory = d.object(forKey: "saveHistory") as? Bool ?? true
        saveTrainingData = d.bool(forKey: "saveTrainingData")
        hasCompletedOnboarding = d.bool(forKey: "hasCompletedOnboarding")
        speechKeepLoaded = (d.object(forKey: "speechKeepLoaded") as? Int).flatMap(KeepLoaded.init) ?? .always
        rewriteKeepLoaded = (d.object(forKey: "rewriteKeepLoaded") as? Int).flatMap(KeepLoaded.init) ?? .oneMinute
    }

    private func store(_ value: Any?, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
