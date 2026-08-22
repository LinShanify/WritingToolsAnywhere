import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var prefs = Prefs.load()
    private var hotKeys: HotKeyManager!
    private var panel: PanelController!
    private var bubble: BubbleController!
    private var watcher: SelectionWatcher!
    private var settings: SettingsWindow!
    private var statusItem: NSStatusItem!
    private var busy = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        L10n.apply(prefs.uiLanguage)
        Log.isEnabled = prefs.debugLogging
        Log.reset()
        Log.write("launch: trusted=\(TextBridge.isTrusted) llm=\(LLM.isAvailable)")

        panel = PanelController(prefs: prefs)
        panel.installEscapeMonitor()

        bubble = BubbleController()
        bubble.onQuickAction = { [weak self] action, selection in
            self?.runQuickAction(action, on: selection)
        }
        bubble.onOpenWritingTools = { [weak self] selection in
            self?.openPanel(with: selection)
        }

        watcher = SelectionWatcher(
            onShow: { [weak self] selection in self?.bubble.show(selection) },
            onHide: { [weak self] in
                guard let self, self.bubble.isVisible, !self.bubble.mouseIsOver else { return }
                self.bubble.hide()
            }
        )
        watcher.isEnabled = prefs.bubbleEnabled

        settings = SettingsWindow(prefs: prefs) { [weak self] updated in
            self?.applyPrefs(updated)
        }

        hotKeys = HotKeyManager { [weak self] in self?.trigger() }
        _ = hotKeys.register(prefs.hotkey)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = MenuBarIcon.image()
        rebuildMenu()

        if TextBridge.isTrusted {
            watcher.start()
        } else {
            promptForAccessibility()
        }
        checkAppleIntelligence()
    }

    // MARK: - Menu

    private func rebuildMenu() {
        let menu = NSMenu()

        let run = NSMenuItem(title: L("改写选中文字", "Rewrite Selected Text"),
                             action: #selector(trigger), keyEquivalent: "")
        run.target = self
        menu.addItem(run)

        // Only surfaced when there's something the user can actually act on.
        if !LLM.isAvailable {
            menu.addItem(.separator())
            let warn = NSMenuItem(title: "⚠️ " + LLM.unavailableReason,
                                  action: LLM.isFixableInSettings ? #selector(openAISettings) : nil,
                                  keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
        }

        menu.addItem(.separator())
        let prefsItem = NSMenuItem(title: L("设置…", "Settings…"),
                                   action: #selector(openSettings), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("退出", "Quit"),
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    // MARK: - Settings plumbing

    private func applyPrefs(_ updated: Prefs) {
        let languageChanged = updated.uiLanguage != prefs.uiLanguage
        let hotkeyChanged = updated.hotkey.display != prefs.hotkey.display
        prefs = updated

        L10n.apply(prefs.uiLanguage)
        Log.isEnabled = prefs.debugLogging
        panel.updatePrefs(prefs)
        watcher.isEnabled = prefs.bubbleEnabled
        if !prefs.bubbleEnabled { bubble.hide() }

        if hotkeyChanged, !hotKeys.register(prefs.hotkey) {
            warn(L("快捷键无法注册", "Couldn't register that shortcut"),
                 L("\(prefs.hotkey.display) 已被其他应用占用，换一个组合试试。",
                   "\(prefs.hotkey.display) is already taken by another app. Try another combination."))
        }
        if languageChanged { rebuildMenu() }
    }

    @objc private func openSettings() {
        settings.update(prefs)
        settings.show()
    }

    @objc private func openAISettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!)
    }

    // MARK: - Actions

    private func capture(from selection: Selection) -> TextBridge.Capture {
        TextBridge.Capture(text: selection.text, app: selection.app, element: selection.element)
    }

    private func runQuickAction(_ action: QuickAction, on selection: Selection) {
        let cap = capture(from: selection)
        let prefs = self.prefs
        Task {
            do {
                let result = try await LLM.run(action, on: selection.text)
                await MainActor.run {
                    self.bubble.hide()
                    self.watcher.reset()
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    TextBridge.writeBack(result, to: cap, prefs: prefs)
                }
            } catch {
                await MainActor.run {
                    self.bubble.showError(L("失败：", "Failed: ") + error.localizedDescription)
                }
            }
        }
    }

    private func openPanel(with selection: Selection) {
        watcher.reset()
        panel.present(capture(from: selection))
    }

    @objc private func trigger() {
        guard !busy else { return }
        guard TextBridge.isTrusted else {
            promptForAccessibility()
            return
        }
        busy = true
        bubble.hide()
        DispatchQueue.global(qos: .userInitiated).async { [prefs] in
            let capture = TextBridge.captureSelection(prefs: prefs)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.busy = false
                guard let capture else {
                    self.warn(L("没有取到选中的文字", "No text selected"),
                              L("请先在目标应用里选中一段文字，再按快捷键。",
                                "Select some text in the other app first, then press the shortcut."))
                    return
                }
                self.panel.present(capture)
            }
        }
    }

    // MARK: - Onboarding

    private func checkAppleIntelligence() {
        guard !LLM.isAvailable, LLM.isFixableInSettings else { return }
        let alert = NSAlert()
        alert.messageText = L("需要开启 Apple Intelligence", "Apple Intelligence is required")
        alert.informativeText = LLM.unavailableReason + "\n\n" + L(
            "一键改写用的是 Apple Intelligence 的端上模型。开启之后重新打开本应用即可。",
            "The one-click rewrites run on Apple Intelligence's on-device model. "
            + "Turn it on, then reopen this app.")
        alert.addButton(withTitle: L("去开启…", "Open Settings…"))
        alert.addButton(withTitle: L("稍后", "Later"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { openAISettings() }
        NSApp.hide(nil)
    }

    @objc private func promptForAccessibility() {
        if TextBridge.requestTrust() {
            watcher.start()
            return
        }
        let alert = NSAlert()
        alert.messageText = L("需要「辅助功能」权限", "Accessibility permission needed")
        alert.informativeText = L(
            "本应用需要辅助功能权限，才能检测你在其他应用里选中的文字、显示悬浮球，并把结果写回去。\n\n"
            + "系统设置 → 隐私与安全性 → 辅助功能 → 打开 WritingToolsAnywhere，然后重新启动本应用。",
            "This app needs Accessibility permission to detect the text you select in other "
            + "apps, show the bubble, and write results back.\n\n"
            + "System Settings → Privacy & Security → Accessibility → enable "
            + "WritingToolsAnywhere, then relaunch the app.")
        alert.addButton(withTitle: L("打开系统设置", "Open Settings"))
        alert.addButton(withTitle: L("稍后", "Later"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        NSApp.hide(nil)
    }

    private func warn(_ title: String, _ body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        NSApp.hide(nil)
    }
}
