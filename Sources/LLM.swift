import Foundation
import FoundationModels

/// The one-click actions on the bubble. Apple exposes no API to invoke a *specific*
/// Writing Tool, so these run on the same on-device model through FoundationModels.
enum QuickAction: String, CaseIterable {
    case proofread, rewrite, friendly, professional, concise

    var title: String {
        switch self {
        case .proofread:    return L("校对", "Proofread")
        case .rewrite:      return L("改写", "Rewrite")
        case .friendly:     return L("友好", "Friendly")
        case .professional: return L("专业", "Professional")
        case .concise:      return L("简洁", "Concise")
        }
    }

    var symbol: String {
        switch self {
        case .proofread:    return "checkmark.circle"
        case .rewrite:      return "arrow.triangle.2.circlepath"
        case .friendly:     return "face.smiling"
        case .professional: return "briefcase"
        case .concise:      return "text.line.first.and.arrowtriangle.forward"
        }
    }

    private var task: String {
        switch self {
        case .proofread:
            return "Correct grammar, spelling, and punctuation. Preserve the author's wording and voice as much as possible — change only what is wrong."
        case .rewrite:
            return "Rewrite the text so it reads more clearly and flows better, keeping the original meaning and roughly the original length."
        case .friendly:
            return "Rewrite the text in a warm, friendly, conversational tone."
        case .professional:
            return "Rewrite the text in a polished, professional tone suitable for workplace communication."
        case .concise:
            return "Rewrite the text to be significantly shorter. Cut filler and redundancy while keeping every substantive point."
        }
    }

    func instructions(language: OutputLanguage) -> String {
        """
        You are a writing assistant that edits text in place.

        \(task)

        Rules:
        - Reply with ONLY the edited text. No preamble, no explanation, no quotation marks around it.
        - \(language.promptClause)
        - Preserve the original formatting: line breaks, lists, indentation, and any markup.
        - If the text needs no change, return it unchanged.
        """
    }
}

enum LLM {
    static var isAvailable: Bool { SystemLanguageModel.default.availability == .available }

    static var unavailableReason: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return ""
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return L("此设备不支持 Apple Intelligence",
                         "This Mac doesn't support Apple Intelligence")
            case .appleIntelligenceNotEnabled:
                return L("Apple Intelligence 尚未开启", "Apple Intelligence is turned off")
            case .modelNotReady:
                return L("模型还在下载中，请稍后再试", "The model is still downloading")
            @unknown default:
                return L("端上模型当前不可用", "The on-device model is unavailable")
            }
        @unknown default:
            return L("端上模型当前不可用", "The on-device model is unavailable")
        }
    }

    /// True only when the reason is something the user can fix in System Settings.
    static var isFixableInSettings: Bool {
        if case .unavailable(let reason) = SystemLanguageModel.default.availability {
            return reason != .deviceNotEligible
        }
        return false
    }

    /// Warm the model up while the user is still deciding which button to press.
    static func prewarm(language: OutputLanguage) {
        guard isAvailable else { return }
        LanguageModelSession(instructions: QuickAction.proofread.instructions(language: language))
            .prewarm()
    }

    static func run(_ action: QuickAction, on text: String,
                    language: OutputLanguage) async throws -> String {
        let session = LanguageModelSession(instructions: action.instructions(language: language))
        let response = try await session.respond(to: text)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
