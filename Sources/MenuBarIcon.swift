import AppKit

/// The status bar glyph: the app icon's idea — lines of text with a sparkle — redrawn
/// for 18pt. The full logo's proportions turn to mush at this size, so the bars are
/// fewer and chunkier and the second sparkle is dropped.
///
/// Drawn rather than shipped as a PNG so it stays crisp on any display scale, and
/// marked as a template so macOS handles light/dark and the menu-highlight state.
enum MenuBarIcon {
    static let side: CGFloat = 18

    static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            draw()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func draw() {
        NSColor.black.setFill()

        for (x, y, w) in [(0.5, 9.4, 8.0), (0.5, 5.5, 12.2), (0.5, 1.6, 9.6)] as [(CGFloat, CGFloat, CGFloat)] {
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: 2.6),
                         xRadius: 1.3, yRadius: 1.3).fill()
        }

        sparkle(center: NSPoint(x: 12.9, y: 13.1), radius: 4.7).fill()
    }

    /// Four concave points. The curves are quadratics — a cubic with both control
    /// points bunched near the centre over-pulls the edges and the result reads as a
    /// spiky starburst rather than a sparkle. A fatter waist than the app icon uses,
    /// because thin points vanish at 18pt.
    private static func sparkle(center c: NSPoint, radius r: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let w = r * 0.34
        let tips = [NSPoint(x: c.x, y: c.y + r), NSPoint(x: c.x + r, y: c.y),
                    NSPoint(x: c.x, y: c.y - r), NSPoint(x: c.x - r, y: c.y)]
        let controls = [NSPoint(x: c.x + w, y: c.y + w), NSPoint(x: c.x + w, y: c.y - w),
                        NSPoint(x: c.x - w, y: c.y - w), NSPoint(x: c.x - w, y: c.y + w)]

        path.move(to: tips[0])
        for i in 0..<4 {
            let from = tips[i], to = tips[(i + 1) % 4], q = controls[i]
            // Exact cubic equivalent of a quadratic: C1 = P0 + ⅔(Q−P0), C2 = P2 + ⅔(Q−P2).
            path.curve(to: to,
                       controlPoint1: NSPoint(x: from.x + 2.0 / 3 * (q.x - from.x),
                                              y: from.y + 2.0 / 3 * (q.y - from.y)),
                       controlPoint2: NSPoint(x: to.x + 2.0 / 3 * (q.x - to.x),
                                              y: to.y + 2.0 / 3 * (q.y - to.y)))
        }
        path.close()
        return path
    }
}
