import AppKit

private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// A borrowed native text view: it holds the text we stole from another app, and because
/// it is a real NSTextView, macOS gives it the full inline Writing Tools experience.
final class PanelController: NSObject, NSWindowDelegate {
    private var panel: KeyPanel!
    private var textView: NSTextView!
    private var statusLabel: NSTextField!
    private var applyButton: NSButton!

    private var capture: TextBridge.Capture?
    private var originalText = ""
    private var prefs: Prefs
    private var pollTimer: Timer?
    private var sawWritingToolsActive = false

    init(prefs: Prefs) {
        self.prefs = prefs
        super.init()
        buildPanel()
    }

    func updatePrefs(_ p: Prefs) { prefs = p }

    // MARK: - UI

    private func buildPanel() {
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 580, height: 320),
                         styleMask: [.titled, .closable, .resizable, .utilityWindow],
                         backing: .buffered, defer: false)
        panel.title = "Writing Tools"
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let content = NSView(frame: panel.contentRect(forFrameRect: panel.frame))

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        textView = NSTextView()
        textView.isEditable = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        if #available(macOS 15.0, *) {
            textView.writingToolsBehavior = .complete
        }
        scroll.documentView = textView

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor

        let toolsButton = NSButton(title: L("写作工具", "Writing Tools"), target: self, action: #selector(showWritingTools))
        toolsButton.keyEquivalent = "j"
        toolsButton.keyEquivalentModifierMask = [.command]

        let copyButton = NSButton(title: L("复制", "Copy"), target: self, action: #selector(copyResult))
        copyButton.keyEquivalent = "c"
        copyButton.keyEquivalentModifierMask = [.command, .shift]

        applyButton = NSButton(title: L("替换原文", "Replace"), target: self, action: #selector(applyResult))
        applyButton.keyEquivalent = "\r"

        let buttons = NSStackView(views: [toolsButton, copyButton, applyButton])
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.spacing = 8

        content.addSubview(scroll)
        content.addSubview(statusLabel)
        content.addSubview(buttons)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -10),

            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            statusLabel.centerYAnchor.constraint(equalTo: buttons.centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: buttons.leadingAnchor, constant: -8),

            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])

        panel.contentView = content
    }

    // MARK: - Presentation

    func present(_ capture: TextBridge.Capture) {
        self.capture = capture
        originalText = capture.text
        sawWritingToolsActive = false

        textView.string = capture.text
        let source = capture.app?.localizedName ?? "其他应用"
        statusLabel.stringValue = L("来自 \(source) · ⌘J 打开写作工具 · ⌘↩ 替换原文 · esc 取消",
                                    "From \(source) · ⌘J Writing Tools · ⌘↩ replace · esc cancel")

        centerOnActiveScreen()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: (capture.text as NSString).length))

        // Give the panel a runloop turn to become key before the popover anchors to it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.showWritingTools()
        }
        startPolling()
    }

    private func centerOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                     y: visible.midY - size.height / 2))
    }

    // MARK: - Actions

    @objc func showWritingTools() {
        if textView.selectedRange().length == 0 {
            textView.setSelectedRange(NSRange(location: 0, length: (textView.string as NSString).length))
        }
        let sel = NSSelectorFromString("showWritingTools:")
        if textView.responds(to: sel) {
            textView.perform(sel, with: nil)
        } else {
            statusLabel.stringValue = L("此系统版本不支持 Writing Tools", "Writing Tools isn't available on this system")
        }
    }

    @objc func copyResult() {
        TextBridge.copyToClipboard(textView.string)
        statusLabel.stringValue = L("已复制到剪贴板", "Copied to clipboard")
    }

    @objc func applyResult() {
        guard let capture else { return }
        let result = textView.string
        close()
        DispatchQueue.global(qos: .userInitiated).async {
            TextBridge.writeBack(result, to: capture, prefs: self.prefs)
        }
    }

    @objc func close() {
        stopPolling()
        panel.orderOut(nil)
        NSApp.hide(nil)
    }

    // MARK: - Auto apply

    /// `isWritingToolsActive` is not documented as KVO-compliant, so poll it instead.
    private func startPolling() {
        stopPolling()
        guard prefs.autoApply else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, #available(macOS 15.0, *) else { return }
            if self.textView.isWritingToolsActive {
                self.sawWritingToolsActive = true
            } else if self.sawWritingToolsActive, self.textView.string != self.originalText {
                self.applyResult()
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) { stopPolling() }

    func windowDidResignKey(_ notification: Notification) {
        // The Writing Tools popover takes key status; don't treat that as a dismissal.
    }
}

extension PanelController {
    /// esc closes the panel. NSTextView swallows `cancelOperation:`, so watch the key event directly.
    func installEscapeMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53, self.panel.isKeyWindow else { return event }
            self.close()
            return nil
        }
    }
}
