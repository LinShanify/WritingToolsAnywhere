import AppKit
import ImageIO
import UniformTypeIdentifiers

// Renders the README artwork from the views the app itself instantiates, so the pictures
// cannot drift from the interface. Emits stills and an animation of the whole gesture.
let W: CGFloat = 900, H: CGFloat = 300
let scale: CGFloat = 2

enum Stage { case selected, ball, menu, done }

let boxRect = NSRect(x: 60, y: 55, width: W - 120, height: 190)
let textOrigin = NSPoint(x: boxRect.minX + 22, y: boxRect.maxY - 52)

func cursor(at p: NSPoint) {
    let path = NSBezierPath()
    path.move(to: p)
    path.line(to: NSPoint(x: p.x, y: p.y - 17))
    path.line(to: NSPoint(x: p.x + 4.4, y: p.y - 12.6))
    path.line(to: NSPoint(x: p.x + 7.2, y: p.y - 18.4))
    path.line(to: NSPoint(x: p.x + 10.2, y: p.y - 17))
    path.line(to: NSPoint(x: p.x + 7.4, y: p.y - 11.2))
    path.line(to: NSPoint(x: p.x + 12.6, y: p.y - 11.2))
    path.close()
    NSColor.black.withAlphaComponent(0.75).setStroke()
    NSColor.white.setFill()
    path.fill()
    path.lineWidth = 1.4
    path.stroke()
}

func render(_ stage: Stage, _ appearance: NSAppearance.Name, chinese: Bool) -> CGImage {
    L10n.isChinese = chinese
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!
    let appear = NSAppearance(named: appearance)!
    appear.performAsCurrentDrawingAppearance {
        let dark = appearance == .darkAqua
        (dark ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.96, alpha: 1)).setFill()
        NSRect(x: 0, y: 0, width: W, height: H).fill()

        (dark ? NSColor(white: 0.18, alpha: 1) : .white).setFill()
        let box = NSBezierPath(roundedRect: boxRect, xRadius: 12, yRadius: 12)
        box.fill()
        (dark ? NSColor(white: 0.28, alpha: 1) : NSColor(white: 0.86, alpha: 1)).setStroke()
        box.lineWidth = 1
        box.stroke()

        let corrected = stage == .done
        let body = chinese
            ? (corrected ? "这个方案我觉得还有一些问题，另外文档也写得不够详细"
                         : "这个方案我觉的还有一些问题，另外文档也写的不够详细")
            : (corrected ? "Hi team, the migration is taking longer than expected."
                         : "hi team, the migration is takeing longer then expected")
        var attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: dark ? NSColor(white: 0.92, alpha: 1) : NSColor(white: 0.12, alpha: 1),
        ]
        if !corrected { attrs[.backgroundColor] = NSColor.selectedTextBackgroundColor }
        NSAttributedString(string: body, attributes: attrs).draw(at: textOrigin)

        let captions: [Stage: String] = chinese
            ? [.selected: "① 选中文字", .ball: "② 小球浮在旁边",
               .menu: "③ 鼠标移上去，展开", .done: "④ 改好，原地替换"]
            : [.selected: "1 · Select text", .ball: "2 · The bubble appears",
               .menu: "3 · Hover, and it opens", .done: "4 · Replaced in place"]
        NSAttributedString(string: captions[stage] ?? "", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: dark ? NSColor(white: 0.52, alpha: 1) : NSColor(white: 0.55, alpha: 1),
        ]).draw(at: NSPoint(x: boxRect.minX + 22, y: boxRect.minY + 18))

        func place(_ view: NSView, at origin: NSPoint, radius: CGFloat) {
            let host = NSVisualEffectView(frame: NSRect(origin: .zero, size: view.frame.size))
            host.material = .popover
            host.state = .active
            host.blendingMode = .withinWindow
            host.appearance = appear
            host.wantsLayer = true
            host.layer?.cornerRadius = radius
            host.layer?.masksToBounds = true
            view.frame = host.bounds
            host.addSubview(view)
            host.layoutSubtreeIfNeeded()
            guard let r = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: r)
            NSGraphicsContext.current?.cgContext.saveGState()
            NSGraphicsContext.current?.cgContext.setShadow(
                offset: CGSize(width: 0, height: -6), blur: 20,
                color: NSColor.black.withAlphaComponent(dark ? 0.6 : 0.22).cgColor)
            NSImage(size: host.frame.size, flipped: false) { rect in r.draw(in: rect); return true }
                .draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.current?.cgContext.restoreGState()
        }

        let ballOrigin = NSPoint(x: textOrigin.x + 300, y: textOrigin.y - 48)
        switch stage {
        case .selected:
            cursor(at: NSPoint(x: textOrigin.x + 292, y: textOrigin.y + 4))
        case .ball:
            place(BubbleBallView(), at: ballOrigin, radius: BubbleBallView.preferredSize.height / 2)
            cursor(at: NSPoint(x: ballOrigin.x + 34, y: ballOrigin.y + 6))
        case .menu:
            place(ActionMenuView(proofreadEnabled: true), at: ballOrigin, radius: 10)
            cursor(at: NSPoint(x: ballOrigin.x + 38, y: ballOrigin.y + 34))
        case .done:
            break
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage!
}

func writePNG(_ image: CGImage, _ path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let d = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(d, image, nil)
    CGImageDestinationFinalize(d)
    print("  \(path)")
}

func writeGIF(_ frames: [(CGImage, Double)], _ path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let d = CGImageDestinationCreateWithURL(url, UTType.gif.identifier as CFString,
                                                  frames.count, nil) else { return }
    CGImageDestinationSetProperties(d, [kCGImagePropertyGIFDictionary: [
        kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for (image, delay) in frames {
        CGImageDestinationAddImage(d, image, [kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
    }
    CGImageDestinationFinalize(d)
    print("  \(path)")
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let out = CommandLine.arguments[1]

for (suffix, chinese) in [("", false), ("-zh", true)] {
    for (theme, name) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
        writePNG(render(.menu, theme, chinese: chinese), "\(out)/bubble-\(name)\(suffix).png")
        writeGIF([
            (render(.selected, theme, chinese: chinese), 1.4),
            (render(.ball, theme, chinese: chinese), 1.2),
            (render(.menu, theme, chinese: chinese), 2.2),
            (render(.done, theme, chinese: chinese), 2.0),
        ], "\(out)/bubble-\(name)\(suffix).gif")
    }
}
