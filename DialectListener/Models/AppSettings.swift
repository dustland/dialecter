import Foundation

public enum ListeningMode: String, CaseIterable, Identifiable {
    case standard
    case ambient
    case meeting

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .standard: AppText.t("Standard", "标准")
        case .ambient: AppText.t("Ambient", "环境声")
        case .meeting: AppText.t("Meeting", "会议记录")
        }
    }

    public var subtitle: String {
        switch self {
        case .standard: AppText.t("For nearby speech", "适合近距离讲话")
        case .ambient: AppText.t("For distant or noisy speech", "适合远距离或嘈杂环境")
        case .meeting: AppText.t("Low-key notes-style capture", "低调笔记式倾听")
        }
    }
}

public enum MicSensitivity: String, CaseIterable, Identifiable {
    case low
    case medium
    case high

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .low: AppText.t("Low", "低")
        case .medium: AppText.t("Medium", "中")
        case .high: AppText.t("High", "高")
        }
    }
}

public enum SourceLanguage: String, CaseIterable, Identifiable {
    case cantonese
    case mandarin
    case english

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cantonese: AppText.t("Cantonese", "粤语")
        case .mandarin: AppText.t("Mandarin", "普通话")
        case .english: AppText.t("English", "英语")
        }
    }

    public var localeIdentifier: String {
        switch self {
        case .cantonese: "zh-HK"
        case .mandarin: "zh-CN"
        case .english: "en-US"
        }
    }
}

public enum TranslationTarget: String, CaseIterable, Identifiable {
    case simplifiedChinese
    case traditionalChinese
    case english

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .simplifiedChinese: AppText.t("Simplified Chinese", "简体中文")
        case .traditionalChinese: AppText.t("Traditional Chinese", "繁体中文")
        case .english: AppText.t("English", "英语")
        }
    }

    public var promptName: String {
        switch self {
        case .simplifiedChinese: "Simplified Chinese"
        case .traditionalChinese: "Traditional Chinese"
        case .english: "English"
        }
    }
}

public enum ChatTargetDialect: String, CaseIterable, Identifiable {
    case cantonese

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cantonese: AppText.t("Cantonese", "粤语")
        }
    }

    public var promptName: String {
        switch self {
        case .cantonese: "Hong Kong Cantonese"
        }
    }

    public var pronunciationSystem: String {
        switch self {
        case .cantonese: "Jyutping with tone numbers"
        }
    }

    public var speechLocaleIdentifier: String {
        switch self {
        case .cantonese: "zh-HK"
        }
    }
}

@Observable
public final class AppSettings {
    private enum Key {
        static let listeningMode = "settings.listeningMode"
        static let micSensitivity = "settings.micSensitivity"
        static let sourceLanguage = "settings.sourceLanguage"
        static let translationTarget = "settings.translationTarget"
        static let chatTargetDialect = "settings.chatTargetDialect"
        static let liveTranscriptEnabled = "settings.liveTranscriptEnabled"
        static let liveTranslationEnabled = "settings.liveTranslationEnabled"
        static let keepScreenAwake = "settings.keepScreenAwake"
    }

    public var listeningMode: ListeningMode {
        didSet { defaults.set(listeningMode.rawValue, forKey: Key.listeningMode) }
    }
    public var micSensitivity: MicSensitivity {
        didSet { defaults.set(micSensitivity.rawValue, forKey: Key.micSensitivity) }
    }
    public var sourceLanguage: SourceLanguage {
        didSet { defaults.set(sourceLanguage.rawValue, forKey: Key.sourceLanguage) }
    }
    public var translationTarget: TranslationTarget {
        didSet { defaults.set(translationTarget.rawValue, forKey: Key.translationTarget) }
    }
    public var chatTargetDialect: ChatTargetDialect {
        didSet { defaults.set(chatTargetDialect.rawValue, forKey: Key.chatTargetDialect) }
    }
    public var liveTranscriptEnabled: Bool {
        didSet { defaults.set(liveTranscriptEnabled, forKey: Key.liveTranscriptEnabled) }
    }
    public var liveTranslationEnabled: Bool {
        didSet { defaults.set(liveTranslationEnabled, forKey: Key.liveTranslationEnabled) }
    }
    public var keepScreenAwake: Bool {
        didSet { defaults.set(keepScreenAwake, forKey: Key.keepScreenAwake) }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.listeningMode = ListeningMode(rawValue: defaults.string(forKey: Key.listeningMode) ?? "") ?? .meeting
        self.micSensitivity = MicSensitivity(rawValue: defaults.string(forKey: Key.micSensitivity) ?? "") ?? .high
        self.sourceLanguage = SourceLanguage(rawValue: defaults.string(forKey: Key.sourceLanguage) ?? "") ?? .cantonese
        self.translationTarget = TranslationTarget(rawValue: defaults.string(forKey: Key.translationTarget) ?? "") ?? .simplifiedChinese
        self.chatTargetDialect = ChatTargetDialect(rawValue: defaults.string(forKey: Key.chatTargetDialect) ?? "") ?? .cantonese
        self.liveTranscriptEnabled = defaults.object(forKey: Key.liveTranscriptEnabled) as? Bool ?? true
        self.liveTranslationEnabled = defaults.object(forKey: Key.liveTranslationEnabled) as? Bool ?? true
        self.keepScreenAwake = defaults.object(forKey: Key.keepScreenAwake) as? Bool ?? true
    }
}
