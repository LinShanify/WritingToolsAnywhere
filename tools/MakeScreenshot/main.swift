import AppKit

// Renders the real ActionMenuView beside a mocked-up text field, so the README shows the
// actual interface rather than an approximation of it that can drift out of date.
let W: CGFloat = 900, H: CGFloat = 300

func draw(_ appearance: NSAppearance.Name, chinese: Bool, to path: String) {
    L10n.isChinese = chinese
    let scale: CGFloat = 2
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)

    NSGraphicsContext.saveGraphicsState()
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gctx
    let appear = NSAppearance(named: appearance)!
    appear.performAsCurrentDrawingAppearance {
        let dark = appearance == .darkAqua

        // Backdrop
        (dark ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.96, alpha: 1)).setFill()
        NSRect(x: 0, y: 0, width: W, height: H).fill()

        // A message composer, the situation this is actually used in
        let box = NSRect(x: 60, y: 55, width: W - 120, height: 190)
        (dark ? NSColor(white: 0.18, alpha: 1) : .white).setFill()
        let boxPath = NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12)
        boxPath.fill()
        (dark ? NSColor(white: 0.28, alpha: 1) : NSColor(white: 0.86, alpha: 1)).setStroke()
        boxPath.lineWidth = 1
        boxPath.stroke()

        let body = NSFont.systemFont(ofSize: 16)
        let text = chinese
            ? "这个方案我觉的还有一些问题，另外文档也写的不够详细"
            : "hi team, the migration is takeing longer then expected"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: body,
            .foregroundColor: dark ? NSColor(white: 0.92, alpha: 1) : NSColor(white: 0.12, alpha: 1),
            .backgroundColor: NSColor.selectedTextBackgroundColor,
        ]
        NSAttributedString(string: text, attributes: attrs)
            .draw(at: NSPoint(x: box.minX + 22, y: box.maxY - 52))

        let hint = NSAttributedString(string: chinese
            ? "选中文字后，小球就浮在旁边"
            : "Select text and the bubble appears beside it", attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: dark ? NSColor(white: 0.5, alpha: 1) : NSColor(white: 0.58, alpha: 1),
        ])
        hint.draw(at: NSPoint(x: box.minX + 22, y: box.minY + 18))

        // The genuine article, laid out by the same code the app runs
        let menu = ActionMenuView(proofreadEnabled: true)
        let size = ActionMenuView.preferredSize
        let host = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        host.material = .popover
        host.state = .active
        host.blendingMode = .withinWindow
        host.appearance = appear
        host.wantsLayer = true
        host.layer?.cornerRadius = 10
        host.layer?.masksToBounds = true
        menu.frame = host.bounds
        host.addSubview(menu)
        host.layoutSubtreeIfNeeded()

        let origin = NSPoint(x: box.minX + 300, y: box.maxY - 130)
        NSGraphicsContext.current?.cgContext.saveGState()
        NSGraphicsContext.current?.cgContext.setShadow(
            offset: CGSize(width: 0, height: -6), blur: 22,
            color: NSColor.black.withAlphaComponent(dark ? 0.6 : 0.22).cgColor)
        if let bubbleRep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bubbleRep)
            NSImage(size: size, flipped: false) { r in bubbleRep.draw(in: r); return true }
                .draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
        }
        NSGraphicsContext.current?.cgContext.restoreGState()
    }
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("  \(path)")
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let out = CommandLine.arguments[1]
draw(.aqua, chinese: false, to: "\(out)/bubble-light.png")
draw(.darkAqua, chinese: false, to: "\(out)/bubble-dark.png")
draw(.aqua, chinese: true, to: "\(out)/bubble-light-zh.png")
draw(.darkAqua, chinese: true, to: "\(out)/bubble-dark-zh.png")
