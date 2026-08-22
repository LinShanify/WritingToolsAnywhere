import Foundation

struct HotKeySpec {
    var key: String = "W"
    var command: Bool = true
    var option: Bool = true
    var shift: Bool = false
    var control: Bool = false

    var display: String {
        var s = ""
        if control { s += "⌃" }
        if option { s += "⌥" }
        if shift { s += "⇧" }
        if command { s += "⌘" }
        return s + key.uppercased()
    }
}

extension HotKeySpec: Codable {
    enum K: String, CodingKey { case key, command, option, shift, control }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? "W"
        command = try c.decodeIfPresent(Bool.self, forKey: .command) ?? true
        option = try c.decodeIfPresent(Bool.self, forKey: .option) ?? true
        shift = try c.decodeIfPresent(Bool.self, forKey: .shift) ?? false
        control = try c.decodeIfPresent(Bool.self, forKey: .control) ?? false
    }
}

enum OutputLanguage: String, Codable, CaseIterable {
    case auto, chinese, traditionalChinese, english, japanese, korean, french, german, spanish

    var label: String {
        switch self {
        case .auto:               return L("跟随原文", "Match the input")
        case .chinese:            return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .english:            return "English"
        case .japanese:           return "日本語"
        case .korean:             return "한국어"
        case .french:             return "Français"
        case .german:             return "Deutsch"
        case .spanish:            return "Español"
        }
    }

    /// Appended to every rewrite instruction.
    var promptClause: String {
        switch self {
        case .auto:
            return "Write in the same language as the input. If the input is Chinese, reply in Chinese."
        case .chinese:            return "Write your reply in Simplified Chinese, whatever language the input is in."
        case .traditionalChinese: return "Write your reply in Traditional Chinese, whatever language the input is in."
        case .english:            return "Write your reply in English, whatever language the input is in."
        case .japanese:           return "Write your reply in Japanese, whatever language the input is in."
        case .korean:             return "Write your reply in Korean, whatever language the input is in."
        case .french:             return "Write your reply in French, whatever language the input is in."
        case .german:             return "Write your reply in German, whatever language the input is in."
        case .spanish:            return "Write your reply in Spanish, whatever language the input is in."
        }
    }
}

enum WriteBackMode: String, Codable, CaseIterable {
    case paste, accessibility

    var label: String {
        switch self {
        case .paste:         return L("模拟粘贴（兼容性最好）", "Simulated paste (most compatible)")
        case .accessibility: return L("辅助功能直接写入", "Write via Accessibility")
        }
    }
}

struct Prefs: Codable {
    var hotkey = HotKeySpec()
    var bubbleEnabled = true
    var autoApply = false
    var uiLanguage = UILanguage.system
    var outputLanguage = OutputLanguage.auto
    var writeBackMode = WriteBackMode.paste
    var restoreClipboard = true
    var captureViaAX = true
    /// Off by default: the log records the text you select, which shouldn't hit disk
    /// unless you're actively debugging.
    var debugLogging = false

    enum K: String, CodingKey {
        case hotkey, bubbleEnabled, autoApply, uiLanguage, outputLanguage
        case writeBackMode, restoreClipboard, captureViaAX, debugLogging
    }

    init() {}

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        hotkey = try c.decodeIfPresent(HotKeySpec.self, forKey: .hotkey) ?? HotKeySpec()
        bubbleEnabled = try c.decodeIfPresent(Bool.self, forKey: .bubbleEnabled) ?? true
        autoApply = try c.decodeIfPresent(Bool.self, forKey: .autoApply) ?? false
        uiLanguage = try c.decodeIfPresent(UILanguage.self, forKey: .uiLanguage) ?? .system
        outputLanguage = try c.decodeIfPresent(OutputLanguage.self, forKey: .outputLanguage) ?? .auto
        writeBackMode = try c.decodeIfPresent(WriteBackMode.self, forKey: .writeBackMode) ?? .paste
        restoreClipboard = try c.decodeIfPresent(Bool.self, forKey: .restoreClipboard) ?? true
        captureViaAX = try c.decodeIfPresent(Bool.self, forKey: .captureViaAX) ?? true
        debugLogging = try c.decodeIfPresent(Bool.self, forKey: .debugLogging) ?? false
    }

    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WritingToolsAnywhere", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    static func load() -> Prefs {
        guard let data = try? Data(contentsOf: url),
              let p = try? JSONDecoder().decode(Prefs.self, from: data) else {
            let fresh = Prefs()
            fresh.save()
            return fresh
        }
        return p
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(self).write(to: Prefs.url)
    }
}
