import AppKit
import CoreGraphics

// Everything is drawn in a 1024×1024 space and scaled down per output size, so every
// resolution is rendered from the vector art rather than resampled from one bitmap.
let canvas: CGFloat = 1024

// The icon body, inset inside the canvas the way macOS app icons are, with slightly
// more room below for the drop shadow.
let body = CGRect(x: 100, y: 112, width: 824, height: 824)

func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

/// A superellipse — the continuous-curvature "squircle" Apple uses, not a rounded rect.
func squircle(_ rect: CGRect, n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * (ct < 0 ? -1 : 1) * pow(abs(ct), 2 / n)
        let y = cy + b * (st < 0 ? -1 : 1) * pow(abs(st), 2 / n)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

/// A four-point twinkle with concave sides — control points at the centre pull the
/// edges inward, which is what separates a sparkle from a diamond.
func sparkle(center c: CGPoint, radius r: CGFloat, waist: CGFloat = 0.12) -> CGPath {
    let path = CGMutablePath()
    let w = r * waist
    path.move(to: CGPoint(x: c.x, y: c.y + r))
    path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + w, y: c.y + w))
    path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x + w, y: c.y - w))
    path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - w, y: c.y - w))
    path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x - w, y: c.y + w))
    path.closeSubpath()
    return path
}

func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: body.minX + x, y: body.minY + y, width: w, height: h),
           cornerWidth: h / 2, cornerHeight: h / 2, transform: nil)
}

func draw(into ctx: CGContext, size: CGFloat) {
    ctx.saveGState()
    ctx.scaleBy(x: size / canvas, y: size / canvas)

    let shape = squircle(body)

    // Drop shadow under the body.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 44, color: hex(0x000000, 0.30))
    ctx.addPath(shape)
    ctx.setFillColor(hex(0x000000))
    ctx.fillPath()
    ctx.restoreGState()

    // Apple-Intelligence-flavoured diagonal gradient.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let colors = [hex(0xFF8A5B), hex(0xFF3D9A), hex(0x8B5CF6), hex(0x3B82F6)] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: colors, locations: [0, 0.34, 0.70, 1]) {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: body.minX, y: body.maxY),
                               end: CGPoint(x: body.maxX, y: body.minY),
                               options: [])
    }
    // A soft highlight across the top edge gives the surface some dimension.
    if let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [hex(0xFFFFFF, 0.28), hex(0xFFFFFF, 0)] as CFArray,
                              locations: [0, 1]) {
        ctx.drawLinearGradient(sheen,
                               start: CGPoint(x: body.midX, y: body.maxY),
                               end: CGPoint(x: body.midX, y: body.midY),
                               options: [])
    }
    ctx.restoreGState()

    // Glyph: lines of text with a sparkle lifting off the end of them.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: hex(0x000000, 0.22))
    ctx.setFillColor(hex(0xFFFFFF))
    ctx.addPath(bar(132, 448, 360, 76))   // short — the sparkle sits above its right end
    ctx.addPath(bar(132, 324, 552, 76))
    ctx.addPath(bar(132, 200, 462, 76))
    ctx.fillPath()

    ctx.addPath(sparkle(center: CGPoint(x: body.minX + 636, y: body.minY + 632), radius: 134))
    ctx.fillPath()
    ctx.addPath(sparkle(center: CGPoint(x: body.minX + 772, y: body.minY + 470), radius: 52))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.restoreGState()
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gctx
    draw(into: gctx.cgContext, size: CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

for (name, size) in [("icon_16x16", 16), ("icon_16x16@2x", 32),
                     ("icon_32x32", 32), ("icon_32x32@2x", 64),
                     ("icon_128x128", 128), ("icon_128x128@2x", 256),
                     ("icon_256x256", 256), ("icon_256x256@2x", 512),
                     ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    try! render(size: size).write(to: out.appendingPathComponent("\(name).png"))
}
print("✓ rendered iconset →", out.path)
