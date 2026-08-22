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
    private var trustTimer: Timer?
    private var updateTimer: Timer?
    private var pendingUpdate: AppRelease?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        L10n.apply(prefs.uiLanguage)
        Log.isEnabled = prefs.debugLogging
        Log.reset()
        Log.write("launch: trusted=\(TextBridge.isTrusted) llm=\(LLM.isAvailable)")

        panel = PanelController(prefs: prefs)
        panel.installEscapeMonitor()

        bubble = BubbleController()
        bubble.onAction = { [weak self] action, selection in
            self?.perform(action, on: selection)
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
        if prefs.hotkeyEnabled { _ = hotKeys.register(prefs.hotkey) }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = MenuBarIcon.image()
        rebuildMenu()

        awaitAccessibility()
        checkAppleIntelligence()
        scheduleUpdateChecks()
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

        if let release = pendingUpdate {
            menu.addItem(.separator())
            let update = NSMenuItem(title: L("↓ 有新版本 \(release.version)",
                                             "↓ Version \(release.version) available"),
                                    action: #selector(openUpdatePage), keyEquivalent: "")
            update.target = self
            menu.addItem(update)
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
            || updated.hotkeyEnabled != prefs.hotkeyEnabled
        prefs = updated

        L10n.apply(prefs.uiLanguage)
        Log.isEnabled = prefs.debugLogging
        panel.updatePrefs(prefs)
        watcher.isEnabled = prefs.bubbleEnabled
        if !prefs.bubbleEnabled { bubble.hide() }

        if hotkeyChanged {
            if !prefs.hotkeyEnabled {
                hotKeys.unregister()
            } else if !hotKeys.register(prefs.hotkey) {
                warn(L("快捷键无法注册", "Couldn't register that shortcut"),
                     L("\(prefs.hotkey.display) 已被其他应用占用，换一个组合试试。",
                       "\(prefs.hotkey.display) is already taken by another app. Try another combination."))
            }
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

    private func perform(_ action: BubbleAction, on selection: Selection) {
        switch action {
        case .writingTools:
            openPanel(with: selection)
        case .proofread:
            transform(selection) { try await LLM.proofread($0) }
        case .translate:
            transform(selection) { [primary = prefs.primaryLanguage] text in
                try await Translator.run(text, primary: primary)
            }
        }
    }

    /// Runs an edit and writes the result back, with the two outcomes that aren't a
    /// result — nothing to do, and something went wrong — surfaced in the bubble
    /// instead of silently pasting.
    private func transform(_ selection: Selection,
                           _ work: @escaping (String) async throws -> String?) {
        let cap = capture(from: selection)
        let prefs = self.prefs
        Task {
            do {
                let result = try await work(selection.text)

                guard let result, result != selection.text else {
                    await MainActor.run {
                        self.bubble.showMessage(L("没有可改的地方", "Nothing to change"))
                    }
                    return
                }

                await MainActor.run {
                    self.bubble.hide()
                    self.watcher.reset()
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    TextBridge.writeBack(result, to: cap, prefs: prefs)
                }
            } catch {
                await MainActor.run {
                    self.bubble.showMessage(error.localizedDescription)
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

    /// Granting Accessibility doesn't notify the app, and the old build simply never
    /// looked again — you had to relaunch for the bubble to start working. Poll instead,
    /// so flipping the switch in System Settings takes effect straight away.
    private func awaitAccessibility() {
        trustTimer?.invalidate()
        trustTimer = nil

        guard !TextBridge.isTrusted else {
            watcher.start()
            return
        }
        promptForAccessibility()

        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self, TextBridge.isTrusted else { return }
            timer.invalidate()
            self.trustTimer = nil
            self.watcher.start()
            Log.write("accessibility granted without a relaunch")
        }
    }

    // MARK: - Updates

    private func scheduleUpdateChecks() {
        guard prefs.checkForUpdates else { return }
        // Give launch a moment to settle before touching the network.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.checkForUpdate(announce: false)
        }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            self?.checkForUpdate(announce: false)
        }
    }

    /// `announce` distinguishes the user asking from the timer firing: a manual check
    /// should say "you're up to date", an automatic one should stay quiet.
    func checkForUpdate(announce: Bool) {
        Task { @MainActor in
            do {
                let release = try await UpdateChecker.check()
                guard let release else {
                    if announce {
                        self.warn(L("已是最新版本", "You're up to date"),
                                  L("当前版本 \(UpdateChecker.currentVersion)。",
                                    "Version \(UpdateChecker.currentVersion) is the latest."))
                    }
                    return
                }
                Log.write("update available: \(release.version) (running \(UpdateChecker.currentVersion))")
                self.pendingUpdate = release
                self.rebuildMenu()
                if announce || release.version != self.prefs.skippedVersion {
                    self.offerUpdate(release)
                }
            } catch {
                if announce {
                    self.warn(L("检查更新失败", "Couldn't check for updates"),
                              error.localizedDescription)
                }
                Log.write("update check failed: \(error.localizedDescription)")
            }
        }
    }

    private func offerUpdate(_ release: AppRelease) {
        let alert = NSAlert()
        alert.messageText = L("有新版本 \(release.version)", "Version \(release.version) is available")
        alert.informativeText = L(
            "你正在使用 \(UpdateChecker.currentVersion)。前往下载页面获取新版本。",
            "You're running \(UpdateChecker.currentVersion). Open the release page to download it.")
        alert.addButton(withTitle: L("前往下载", "Open Download Page"))
        alert.addButton(withTitle: L("稍后", "Later"))
        alert.addButton(withTitle: L("跳过此版本", "Skip This Version"))
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(release.page)
        case .alertThirdButtonReturn:
            prefs.skippedVersion = release.version
            prefs.save()
        default:
            break
        }
        NSApp.hide(nil)
    }

    @objc private func openUpdatePage() {
        if let release = pendingUpdate { NSWorkspace.shared.open(release.page) }
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

    private func warn(_ title: String, _ body: String, style: NSAlert.Style = .informational) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = style
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        NSApp.hide(nil)
    }
}
