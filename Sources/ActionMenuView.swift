import AppKit

/// A self-drawn button. NSButton's bezel machinery clips an `.imageAbove` layout at
/// this size, and borderless push buttons don't highlight on hover — both matter here.
final class ActionChip: NSView {
    private let symbol: NSImageView
    private let label: NSTextField
    private var tracking: NSTrackingArea?
    private var hovered = false { didSet { needsDisplay = true } }
    private var pressed = false { didSet { needsDisplay = true } }

    var onClick: (() -> Void)?
    var isDisabled = false {
        didSet {
            alphaValue = isDisabled ? 0.35 : 1
        }
    }

    init(symbolName: String, title: String, pointSize: CGFloat = 15) {
        symbol = NSImageView()
        symbol.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .regular))
        symbol.contentTintColor = .controlAccentColor
        symbol.imageScaling = .scaleNone

        label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .labelColor
        label.alignment = .center

        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous

        let stack = NSStackView(views: [symbol, label])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2),
            symbol.heightAnchor.constraint(equalToConstant: pointSize + 3),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

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

    override func mouseEntered(with event: NSEvent) { if !isDisabled { hovered = true } }
    override func mouseExited(with event: NSEvent) { hovered = false; pressed = false }
    override func mouseDown(with event: NSEvent) { if !isDisabled { pressed = true } }

    override func mouseUp(with event: NSEvent) {
        let wasPressed = pressed
        pressed = false
        guard !isDisabled, wasPressed, bounds.contains(convert(event.locationInWindow, from: nil))
        else { return }
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard hovered || pressed else { return }
        let color = pressed
            ? NSColor.controlAccentColor.withAlphaComponent(0.28)
            : NSColor.controlAccentColor.withAlphaComponent(0.15)
        color.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
    }
}

/// The expanded bubble: five one-click actions plus a way into Apple's own panel,
/// all as equal chips on one row.
final class ActionMenuView: NSView {
    static let preferredSize = NSSize(width: 396, height: 64)

    var onAction: ((QuickAction) -> Void)?
    var onWritingTools: (() -> Void)?

    init(quickActionsEnabled: Bool, disabledReason: String = "") {
        super.init(frame: NSRect(origin: .zero, size: Self.preferredSize))

        let row = NSStackView()
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.spacing = 3
        row.translatesAutoresizingMaskIntoConstraints = false

        for action in QuickAction.allCases {
            let chip = ActionChip(symbolName: action.symbol, title: action.title)
            chip.isDisabled = !quickActionsEnabled
            chip.toolTip = quickActionsEnabled
                ? L("一键\(action.title)并替换原文", "\(action.title) and replace the text")
                : disabledReason
            chip.onClick = { [weak self] in self?.onAction?(action) }
            row.addArrangedSubview(chip)
        }

        let more = ActionChip(symbolName: "sparkles", title: L("写作工具", "More"))
        more.toolTip = L("打开编辑面板并唤起 Apple 原版 Writing Tools",
                         "Open the editor and Apple's own Writing Tools")
        more.onClick = { [weak self] in self?.onWritingTools?() }
        row.addArrangedSubview(more)

        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}
