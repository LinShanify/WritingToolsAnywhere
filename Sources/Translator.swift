import Foundation
import NaturalLanguage
import Translation

struct TranslateLanguage {
    let code: String
    let label: String

    static let all: [TranslateLanguage] = [
        .init(code: "zh-Hans", label: "简体中文"),
        .init(code: "zh-Hant", label: "繁體中文"),
        .init(code: "en", label: "English"),
        .init(code: "ja", label: "日本語"),
        .init(code: "ko", label: "한국어"),
        .init(code: "fr", label: "Français"),
        .init(code: "de", label: "Deutsch"),
        .init(code: "es", label: "Español"),
        .init(code: "it", label: "Italiano"),
        .init(code: "pt-BR", label: "Português"),
        .init(code: "ru", label: "Русский"),
        .init(code: "ar", label: "العربية"),
    ]

    static func label(for code: String) -> String {
        all.first { $0.code == code }?.label ?? code
    }
}

enum TranslateError: LocalizedError {
    case notInstalled(from: String, to: String)
    case unsupported(from: String, to: String)

    var errorDescription: String? {
        switch self {
        case .notInstalled(let from, let to):
            let pair = "\(TranslateLanguage.label(for: from)) → \(TranslateLanguage.label(for: to))"
            return L("\(pair) 尚未下载，请在系统设置 → 翻译语言里添加",
                     "\(pair) isn't downloaded — add it in System Settings → Translation Languages")
        case .unsupported(let from, let to):
            return L("不支持 \(TranslateLanguage.label(for: from)) → \(TranslateLanguage.label(for: to))",
                     "\(TranslateLanguage.label(for: from)) → \(TranslateLanguage.label(for: to)) isn't supported")
        }
    }
}

/// Translation goes through Apple's dedicated Translation framework rather than the
/// language model.
///
/// The on-device LLM will translate if asked, but it invents facts while doing it —
/// "明天" (tomorrow) came back as "Wednesday", and an untranslated "someone" was left
/// sitting in the middle of a Chinese sentence. The purpose-built translator makes
/// ordinary word-choice mistakes instead of confident fabrications, which is a very
/// different kind of wrong to paste into someone's message.
enum Translator {

    /// The counterpart is always English: the whole point is moving between the
    /// language you think in and the one work happens in.
    static let counterpart = "en"

    /// Which way to translate, or nil when there's nothing to do.
    ///
    /// With a primary of, say, Chinese: Chinese goes to English, English comes back to
    /// Chinese, and a third language goes to Chinese. With a primary of English there is
    /// no pair — everything becomes English, and English itself is left alone.
    static func direction(for text: String, primary: String) -> (source: String, target: String)? {
        let detected = detectLanguage(text, fallbackPair: (primary, counterpart))

        if matches(primary, counterpart) {
            return matches(detected, counterpart) ? nil : (detected, counterpart)
        }
        if matches(detected, primary) { return (detected, counterpart) }
        return (detected, primary)
    }

    /// Detection needs a few words to be worth anything. Measured on short strings,
    /// confidence separates cleanly at 0.6: real sentences score 0.85–1.00, while "ok"
    /// came back as Polish at 0.29 and "LGTM" as Turkish at 0.31. Below the line, pick
    /// whichever of the configured pair scores higher instead of trusting the winner.
    private static func detectLanguage(_ text: String, fallbackPair: (String, String)) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 8)

        if let best = hypotheses.max(by: { $0.value < $1.value }), best.value >= 0.6 {
            return best.key.rawValue
        }

        let scoreOf: (String) -> Double = { code in
            hypotheses.first { matches($0.key.rawValue, code) }?.value ?? 0
        }
        return scoreOf(fallbackPair.1) > scoreOf(fallbackPair.0) ? fallbackPair.1 : fallbackPair.0
    }

    /// "zh-Hans" and "zh-Hant" are different targets, but a bare "zh" should match either.
    private static func matches(_ a: String, _ b: String) -> Bool {
        a == b || a.split(separator: "-").first == b.split(separator: "-").first
    }

    /// Returns nil when the text is already in the only language we'd translate it to.
    static func run(_ text: String, primary: String) async throws -> String? {
        guard let (source, target) = direction(for: text, primary: primary) else { return nil }
        let from = Locale.Language(identifier: source)
        let to = Locale.Language(identifier: target)

        switch await LanguageAvailability().status(from: from, to: to) {
        case .installed:
            break
        case .supported:
            throw TranslateError.notInstalled(from: source, to: target)
        case .unsupported:
            throw TranslateError.unsupported(from: source, to: target)
        @unknown default:
            throw TranslateError.unsupported(from: source, to: target)
        }

        let session = TranslationSession(installedSource: from, target: to)
        return try await session.translate(text).targetText
    }
}
