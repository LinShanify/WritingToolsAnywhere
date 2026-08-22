import AppKit

enum Diagnostics {
    static func report(prefs: Prefs) -> String {
        [
            "WritingToolsAnywhere",
            "macOS " + ProcessInfo.processInfo.operatingSystemVersionString,
            "",
            L("辅助功能权限：", "Accessibility: ")
                + (TextBridge.isTrusted ? "granted" : "NOT granted"),
            L("端上模型：", "On-device model: ")
                + (LLM.isAvailable ? "available" : LLM.unavailableReason),
            L("开机启动：", "Login item: ") + (LoginItem.isEnabled ? "on" : "off"),
            L("悬浮球：", "Bubble: ") + (prefs.bubbleEnabled ? "on" : "off"),
            L("快捷键：", "Shortcut: ") + (prefs.hotkeyEnabled ? prefs.hotkey.display : "off"),
            L("我的语言：", "My language: ") + prefs.primaryLanguage,
            L("替换方式：", "Write-back: ") + prefs.writeBackMode.rawValue,
            L("屏幕数：", "Screens: ") + String(NSScreen.screens.count),
        ].joined(separator: "\n")
    }
}
