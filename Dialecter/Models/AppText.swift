import Foundation

public enum AppText {
    public static var isSimplifiedChinese: Bool {
        Locale.preferredLanguages.first?.hasPrefix("zh-Hans") == true
            || Locale.preferredLanguages.first?.hasPrefix("zh-CN") == true
    }

    public static func t(_ english: String, _ simplifiedChinese: String) -> String {
        isSimplifiedChinese ? simplifiedChinese : english
    }
}
