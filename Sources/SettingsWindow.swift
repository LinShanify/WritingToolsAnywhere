import AppKit

/// Retains a closure so plain AppKit controls can use closures instead of a pile of
/// @objc selectors.
private final class Handler: NSObject {
    private let block: (NSControl) -> Void
    init(_ block: @escaping (NSControl) -> Void) { self.block = block }
    @objc func fire(_ sender: NSControl) { block(sender) }
}

final class SettingsWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var prefs: Prefs
    private let onChange: (Prefs) -> Void
    private var handlers: [Handler] = []
    private var refreshers: [() -> Void] = []

    init(prefs: Prefs, onChange: @escaping (Prefs) -> Void) {
        self.prefs = prefs
        self.onChange = onChange
    }

    func update(_ p: Prefs) { prefs = p }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 400),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.delegate = self
            w.isReleasedWhenClosed = false
            window = w
        }
        rebuild()
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        refreshers.forEach { $0() }
    }

    /// Rebuilt wholesale rather than mutated: changing the interface language has to
    /// retitle every control, and this is simpler than tracking each one.
    private func rebuild() {
        handlers.removeAll()
        refreshers.removeAll()
        window?.title = L("设置", "Settings")

        let grid = NSGridView(numberOfColumns: 2, rows: 0)
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 10
        grid.columnSpacing = 14

        buildStatus(grid)
        buildGeneral(grid)
        buildLanguage(grid)
        buildAdvanced(grid)

        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
        ])
        window?.contentView = content
        window?.setContentSize(content.fittingSize)
    }

    // MARK: - Sections

    private func buildStatus(_ grid: NSGridView) {
        section(grid, L("状态", "Status"), first: true)

        let (aiText, aiButton) = statusRow(
            action: L("去开启…", "Turn On…"),
            onClick: {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!)
            })
        grid.addRow(with: [label("Apple Intelligence"), aiButton])
        refreshers.append {
            let ok = LLM.isAvailable
            aiText.stringValue = ok ? L("✅ 已开启", "✅ On") : "⚠️ " + LLM.unavailableReason
            aiText.textColor = ok ? .secondaryLabelColor : .systemOrange
            aiButton.arrangedSubviews.last?.isHidden = ok || !LLM.isFixableInSettings
        }

        let (axText, axButton) = statusRow(
            action: L("去授权…", "Open Settings…"),
            onClick: {
                TextBridge.requestTrust()
                NSWorkspace.shared.open(URL(
                    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            })
        grid.addRow(with: [label(L("辅助功能权限", "Accessibility")), axButton])
        refreshers.append {
            let ok = TextBridge.isTrusted
            axText.stringValue = ok
                ? L("✅ 已授予", "✅ Granted")
                : L("⚠️ 未授予，悬浮球无法工作", "⚠️ Not granted — the bubble can't work")
            axText.textColor = ok ? .secondaryLabelColor : .systemOrange
            axButton.arrangedSubviews.last?.isHidden = ok
        }
    }

    private func buildGeneral(_ grid: NSGridView) {
        section(grid, L("通用", "General"))

        let login = checkbox(L("登录时自动启动", "Start at login"), LoginItem.isEnabled) { [weak self] on in
            if let error = LoginItem.set(on) {
                self?.warn(L("无法设置开机启动", "Couldn't change the login item"), error)
            }
        }
        grid.addRow(with: [label(L("启动", "Launch")), login])
        refreshers.append { (login as? NSButton)?.state = LoginItem.isEnabled ? .on : .off }

        let bubble = checkbox(L("选中文字时显示悬浮球", "Show the bubble when text is selected"),
                              prefs.bubbleEnabled) { [weak self] on in
            self?.mutate { $0.bubbleEnabled = on }
        }
        grid.addRow(with: [label(L("悬浮球", "Bubble")), bubble])

        grid.addRow(with: [label(L("快捷键", "Shortcut")), hotKeyEditor()])
    }

    private func buildLanguage(_ grid: NSGridView) {
        section(grid, L("语言", "Language"))

        let ui = popup(UILanguage.allCases.map(\.label),
                       selected: UILanguage.allCases.firstIndex(of: prefs.uiLanguage) ?? 0) { [weak self] i in
            guard let self else { return }
            self.mutate { $0.uiLanguage = UILanguage.allCases[i] }
            L10n.apply(self.prefs.uiLanguage)
            self.rebuild()
            self.refreshers.forEach { $0() }
        }
        grid.addRow(with: [label(L("界面语言", "Interface")), ui])

        let codes = TranslateLanguage.all.map(\.code)
        let primary = popup(TranslateLanguage.all.map(\.label),
                            selected: codes.firstIndex(of: prefs.primaryLanguage) ?? 0) { [weak self] i in
            self?.mutate { $0.primaryLanguage = codes[i] }
            self?.refreshers.forEach { $0() }
        }
        grid.addRow(with: [label(L("我的语言", "My language")), primary])

        let explanation = NSTextField(wrappingLabelWithString: "")
        explanation.font = .systemFont(ofSize: 11)
        explanation.textColor = .tertiaryLabelColor
        explanation.preferredMaxLayoutWidth = 340
        grid.addRow(with: [spacer(), explanation])
        refreshers.append { [weak self] in
            guard let self else { return }
            let mine = TranslateLanguage.label(for: self.prefs.primaryLanguage)
            explanation.stringValue = self.prefs.primaryLanguage == Translator.counterpart
                ? L("翻译会把任何非英文的文字转成英文；英文原样保留。",
                    "Translate turns anything that isn't English into English, and leaves English alone.")
                : L("翻译会自动判断方向：\(mine) 转英文，英文转\(mine)，其他语言也转成\(mine)。",
                    "Translate picks the direction for you: \(mine) to English, English back to "
                    + "\(mine), and any other language to \(mine).")
        }

        let download = button(L("下载语言包…", "Download Languages…")) {
            NSWorkspace.shared.open(URL(
                string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!)
        }
        grid.addRow(with: [spacer(), download])
        hint(grid, L("翻译使用 Apple 内置的翻译引擎，语言包需要先在系统设置里下载。",
                     "Translation uses Apple's built-in engine; language pairs must be "
                     + "downloaded in System Settings first."))
    }

    private func buildAdvanced(_ grid: NSGridView) {
        section(grid, L("高级", "Advanced"))

        let auto = checkbox(L("写作工具结束后自动替换原文", "Replace automatically when Writing Tools finishes"),
                            prefs.autoApply) { [weak self] on in
            self?.mutate { $0.autoApply = on }
        }
        grid.addRow(with: [label(L("编辑面板", "Editor")), auto])

        let mode = popup(WriteBackMode.allCases.map(\.label),
                         selected: WriteBackMode.allCases.firstIndex(of: prefs.writeBackMode) ?? 0) { [weak self] i in
            self?.mutate { $0.writeBackMode = WriteBackMode.allCases[i] }
        }
        grid.addRow(with: [label(L("替换方式", "Replace using")), mode])

        let restore = checkbox(L("用完后恢复剪贴板原有内容", "Restore the previous clipboard afterwards"),
                               prefs.restoreClipboard) { [weak self] on in
            self?.mutate { $0.restoreClipboard = on }
        }
        grid.addRow(with: [label(L("剪贴板", "Clipboard")), restore])

        let log = checkbox(L("记录调试日志（会写入你选中的文字）",
                             "Write a debug log (records the text you select)"),
                           prefs.debugLogging) { [weak self] on in
            self?.mutate { $0.debugLogging = on }
            Log.isEnabled = on
            if !on { Log.reset() }
        }
        grid.addRow(with: [label(L("诊断", "Diagnostics")), log])

        let copy = button(L("复制诊断信息", "Copy Diagnostics")) { [weak self] in
            guard let self else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(Diagnostics.report(prefs: self.prefs), forType: .string)
        }
        grid.addRow(with: [spacer(), copy])
    }

    // MARK: - Building blocks

    private func section(_ grid: NSGridView, _ title: String, first: Bool = false) {
        let header = NSTextField(labelWithString: title)
        header.font = .systemFont(ofSize: 12, weight: .semibold)
        header.textColor = .secondaryLabelColor
        let row = grid.addRow(with: [header])
        row.mergeCells(in: NSRange(location: 0, length: 2))
        // The label column is trailing-aligned; a merged cell inherits that, which would
        // pin section headers to the right edge.
        row.cell(at: 0).xPlacement = .leading
        row.topPadding = first ? 0 : 18
    }

    private func hint(_ grid: NSGridView, _ text: String) {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: 11)
        field.textColor = .tertiaryLabelColor
        field.preferredMaxLayoutWidth = 340
        grid.addRow(with: [spacer(), field])
    }

    private func label(_ text: String) -> NSView {
        let field = NSTextField(labelWithString: text)
        field.alignment = .right
        return field
    }

    private func spacer() -> NSView { NSGridCell.emptyContentView }

    private func statusRow(action: String, onClick: @escaping () -> Void) -> (NSTextField, NSStackView) {
        let text = NSTextField(labelWithString: "")
        text.font = .systemFont(ofSize: 12)
        text.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [text, button(action, onClick)])
        stack.spacing = 10
        return (text, stack)
    }

    private func checkbox(_ title: String, _ on: Bool, _ change: @escaping (Bool) -> Void) -> NSView {
        let handler = Handler { control in change((control as! NSButton).state == .on) }
        handlers.append(handler)
        let b = NSButton(checkboxWithTitle: title, target: handler, action: #selector(Handler.fire(_:)))
        b.state = on ? .on : .off
        return b
    }

    private func button(_ title: String, _ click: @escaping () -> Void) -> NSButton {
        let handler = Handler { _ in click() }
        handlers.append(handler)
        return NSButton(title: title, target: handler, action: #selector(Handler.fire(_:)))
    }

    private func popup(_ titles: [String], selected: Int, _ change: @escaping (Int) -> Void) -> NSPopUpButton {
        let handler = Handler { control in change((control as! NSPopUpButton).indexOfSelectedItem) }
        handlers.append(handler)
        let p = NSPopUpButton()
        p.target = handler
        p.action = #selector(Handler.fire(_:))
        p.addItems(withTitles: titles)
        p.selectItem(at: selected)
        return p
    }

    /// Modifier checkboxes plus a key menu — a real key recorder would have to swallow
    /// global keystrokes, which is a lot of machinery for one setting.
    private func hotKeyEditor() -> NSView {
        var spec = prefs.hotkey
        let keys = ["A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S",
                    "T","U","V","W","X","Y","Z","0","1","2","3","4","5","6","7","8","9","SPACE"]

        func commit() { mutate { $0.hotkey = spec } }

        let ctrl = checkbox("⌃", spec.control) { on in spec.control = on; commit() }
        let opt = checkbox("⌥", spec.option) { on in spec.option = on; commit() }
        let shift = checkbox("⇧", spec.shift) { on in spec.shift = on; commit() }
        let cmd = checkbox("⌘", spec.command) { on in spec.command = on; commit() }
        let key = popup(keys, selected: keys.firstIndex(of: spec.key.uppercased()) ?? 22) { i in
            spec.key = keys[i]; commit()
        }
        key.widthAnchor.constraint(equalToConstant: 92).isActive = true

        let stack = NSStackView(views: [ctrl, opt, shift, cmd, key])
        stack.spacing = 6
        return stack
    }

    // MARK: - Plumbing

    private func mutate(_ change: (inout Prefs) -> Void) {
        change(&prefs)
        prefs.save()
        onChange(prefs)
    }

    private func warn(_ title: String, _ body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.runModal()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refreshers.forEach { $0() }
    }
}
