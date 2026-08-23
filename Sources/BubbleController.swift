import AppKit

/// Buttons in a non-activating panel never see a "first" click unless they opt in.
private final class ClickThroughButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class ClickThroughView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns its own tracking area so hover works reliably in a borderless, never-key panel.
private final class HoverView: NSVisualEffectView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    private var tracking: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}

private final class BubblePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The Grammarly-style bubble: a small ✨ ball that appears beside the selection and
/// expands into one-click actions on hover.
final class BubbleController: NSObject {

    private enum Mode { case ball, menu, working }

    private let ballSize = NSSize(width: 30, height: 30)
    private let menuSize = ActionMenuView.preferredSize

    private var panel: BubblePanel!
    private var container: HoverView!
    private var ballView: NSView!
    private var menuView: NSView!
    private var workingView: NSView!
    private var workingLabel: NSTextField!
    private var spinner: NSProgressIndicator!

    private var mode: Mode = .ball
    private var anchor: NSPoint = .zero
    private var selection: Selection?
    private var hideWork: DispatchWorkItem?

    var onAction: ((BubbleAction, Selection) -> Void)?

    override init() {
        super.init()
        build()
    }

    // MARK: - Construction

    private func build() {
        panel = BubblePanel(contentRect: NSRect(origin: .zero, size: ballSize),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        container = HoverView()
        container.material = .popover
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerCurve = .continuous
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor.separatorColor.cgColor

        ballView = makeBallView()
        menuView = makeMenuView()
        workingView = makeWorkingView()

        container.onEnter = { [weak self] in self?.handleMouseEntered() }
        container.onExit = { [weak self] in self?.handleMouseExited() }

        panel.contentView = container
        setMode(.ball)
    }

    private func makeBallView() -> NSView {
        let view = BubbleBallView()
        view.onClick = { [weak self] in self?.expand() }
        return view
    }

    private func makeMenuView() -> NSView {
        let view = ActionMenuView(proofreadEnabled: LLM.isAvailable,
                                  disabledReason: LLM.unavailableReason)
        view.onAction = { [weak self] action in self?.fire(action) }
        return view
    }

    private func makeWorkingView() -> NSView {
        let view = ClickThroughView()
        spinner = NSProgressIndicator()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.style = .spinning
        spinner.controlSize = .small

        workingLabel = NSTextField(labelWithString: L("处理中…", "Working…"))
        workingLabel.translatesAutoresizingMaskIntoConstraints = false
        workingLabel.font = .systemFont(ofSize: 12)

        view.addSubview(spinner)
        view.addSubview(workingLabel)
        NSLayoutConstraint.activate([
            spinner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 16),
            spinner.heightAnchor.constraint(equalToConstant: 16),
            workingLabel.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 8),
            workingLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            workingLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
        ])
        return view
    }

    // MARK: - Show / hide

    func show(_ selection: Selection) {
        self.selection = selection
        anchor = selection.anchor
        hideWork?.cancel()
        setMode(.ball)
        position(for: ballSize)
        panel.orderFront(nil)
        Log.write("bubble: orderFront frame=" + String(describing: panel.frame)
                  + " visible=" + String(panel.isVisible))
        LLM.prewarm()
    }

    func hide() {
        hideWork?.cancel()
        panel.orderOut(nil)
        selection = nil
        setMode(.ball)
    }

    var isVisible: Bool { panel.isVisible }

    /// The global event monitors shouldn't be able to dismiss the bubble out from under
    /// a click that is landing on the bubble itself.
    var mouseIsOver: Bool {
        panel.isVisible && panel.frame.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation)
    }

    // MARK: - Layout

    /// Hang the bubble just below-right of the selection, nudged back on screen if needed.
    private func position(for size: NSSize) {
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        var origin = NSPoint(x: anchor.x + 8, y: anchor.y - size.height - 8)

        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
            if origin.y < visible.minY + 4 {
                origin.y = anchor.y + 8   // flip above the selection
            }
            origin.y = min(origin.y, visible.maxY - size.height - 4)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func setMode(_ new: Mode) {
        mode = new
        let (view, size, radius): (NSView, NSSize, CGFloat)
        switch new {
        case .ball:    (view, size, radius) = (ballView, ballSize, ballSize.height / 2)
        case .menu:    (view, size, radius) = (menuView, menuSize, 10)
        case .working: (view, size, radius) = (workingView, NSSize(width: 148, height: 34), 10)
        }

        container.subviews.forEach { $0.removeFromSuperview() }
        container.layer?.cornerRadius = radius
        container.layer?.masksToBounds = true

        // Resize the window *before* installing the content. Dropping a 366×104 view into
        // a 30×30 container and letting the autoresizing mask scale it up produces a
        // garbage frame — the proportional maths has nothing sane to work from.
        position(for: size)

        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        container.layoutSubtreeIfNeeded()
    }

    // MARK: - Interaction

    private func handleMouseEntered() {
        hideWork?.cancel()
        if mode == .ball { setMode(.menu) }
    }

    private func handleMouseExited() {
        guard mode != .working else { return }
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    @objc private func expand() {
        setMode(.menu)
    }

    private func fire(_ action: BubbleAction) {
        guard let selection else { return }
        Log.write("bubble: \(action.title) on \(selection.text.prefix(20))")
        if action == .writingTools {
            hide()
        } else {
            workingLabel.stringValue = L("\(action.title)中…", "\(action.title)…")
            setMode(.working)
            spinner.startAnimation(nil)
        }
        onAction?(action, selection)
    }

    func showMessage(_ message: String) {
        spinner.stopAnimation(nil)
        workingLabel.stringValue = message
        setMode(.working)
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }
}
