import Foundation

enum UILanguage: String, Codable, CaseIterable {
    case system, chinese, english

    var label: String {
        switch self {
        case .system:  return L("跟随系统", "Follow System")
        case .chinese: return "简体中文"
        case .english: return "English"
        }
    }
}

enum L10n {
    /// Resolved once at launch and whenever the user changes the setting, so every
    /// `L(_:_:)` call in the UI is a cheap branch rather than a locale lookup.
    static var isChinese = true

    static func apply(_ setting: UILanguage) {
        switch setting {
        case .chinese: isChinese = true
        case .english: isChinese = false
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            isChinese = preferred.hasPrefix("zh")
        }
    }
}

/// Two languages don't justify a string-key indirection layer — keeping both variants
/// at the call site is easier to read and impossible to leave untranslated.
func L(_ zh: String, _ en: String) -> String {
    L10n.isChinese ? zh : en
}
