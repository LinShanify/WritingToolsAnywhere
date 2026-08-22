import AppKit

// Matches the Finder window the installer opens: icons sit at y=195 in Finder's
// coordinate space, so the arrow and caption are placed around that line.
let size = CGSize(width: 640, height: 400)
let appIconX: CGFloat = 165
let applicationsX: CGFloat = 475
let iconRowY: CGFloat = 205        // from the bottom, in Core Graphics coordinates

func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

func draw(into ctx: CGContext, scale: CGFloat) {
    ctx.saveGState()
    ctx.scaleBy(x: scale, y: scale)

    // A very light wash of the app icon's palette — enough to feel deliberate, pale
    // enough that dark icon labels stay readable on top of it.
    ctx.setFillColor(hex(0xFFFFFF))
    ctx.fill(CGRect(origin: .zero, size: size))
    if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [hex(0xFF8A5B, 0.10), hex(0xFF3D9A, 0.08),
                                   hex(0x8B5CF6, 0.09), hex(0x3B82F6, 0.11)] as CFArray,
                          locations: [0, 0.34, 0.70, 1]) {
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: size.height),
                               end: CGPoint(x: size.width, y: 0), options: [])
    }

    // Arrow, from just right of the app icon to just left of the Applications folder.
    let from = CGPoint(x: appIconX + 78, y: iconRowY)
    let to = CGPoint(x: applicationsX - 78, y: iconRowY)
    let head: CGFloat = 30

    ctx.setStrokeColor(hex(0x3B3B44, 0.55))
    ctx.setLineWidth(8)
    ctx.setLineCap(.round)
    ctx.move(to: from)
    ctx.addLine(to: CGPoint(x: to.x - head * 0.7, y: to.y))
    ctx.strokePath()

    ctx.setFillColor(hex(0x3B3B44, 0.55))
    ctx.move(to: to)
    ctx.addLine(to: CGPoint(x: to.x - head, y: to.y + head * 0.62))
    ctx.addLine(to: CGPoint(x: to.x - head, y: to.y - head * 0.62))
    ctx.closePath()
    ctx.fillPath()

    ctx.restoreGState()
}

func text(_ string: String, _ font: NSFont, _ color: NSColor, centerX: CGFloat, y: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let s = NSAttributedString(string: string, attributes: attrs)
    let w = s.size().width
    s.draw(at: NSPoint(x: centerX - w / 2, y: y))
}

func render(scale: CGFloat, to path: String) {
    let px = Int(size.width * scale)
    let py = Int(size.height * scale)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: py,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gctx
    draw(into: gctx.cgContext, scale: scale)

    gctx.cgContext.saveGState()
    gctx.cgContext.scaleBy(x: scale, y: scale)
    // Core Graphics counts up from the bottom; the icon labels sit just under the icons,
    // so the caption goes well below them rather than at iconRowY + something.
    text("Drag to install  ·  拖入即可安装",
         .systemFont(ofSize: 15, weight: .medium),
         NSColor(white: 0.32, alpha: 1), centerX: size.width / 2, y: 86)
    text("Writing Tools Anywhere",
         .systemFont(ofSize: 22, weight: .semibold),
         NSColor(white: 0.18, alpha: 1), centerX: size.width / 2, y: size.height - 66)
    gctx.cgContext.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("  \(path)  \(px)x\(py)")
}

let out = CommandLine.arguments[1]
render(scale: 1, to: "\(out)/dmg-background.png")
render(scale: 2, to: "\(out)/dmg-background@2x.png")
