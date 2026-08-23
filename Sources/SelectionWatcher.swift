import AppKit
import ApplicationServices

struct Selection {
    var text: String
    var app: NSRunningApplication
    var element: AXUIElement?
    /// Where the bubble should hang, in AppKit screen coordinates (bottom-left origin).
    var anchor: NSPoint
    /// True when the app exposes no text and `text` is still unknown — it has to be
    /// fetched with a simulated copy at the moment an action is chosen.
    var needsClipboardRead = false
}

/// Watches for the user selecting text in *any* app and reports it, Grammarly-style.
///
/// Deliberately event-driven rather than polling: we only look at the selection right
/// after a mouse-up or a selection keystroke, and we never simulate ⌘C here — hijacking
/// the clipboard on every click would be unacceptable.
final class SelectionWatcher {
    private var monitors: [Any] = []
    private var pending: DispatchWorkItem?
    private var lastText = ""
    private var dragOrigin: NSPoint?

    var isEnabled = true
    private let onShow: (Selection) -> Void
    private let onHide: () -> Void

    init(onShow: @escaping (Selection) -> Void, onHide: @escaping () -> Void) {
        self.onShow = onShow
        self.onHide = onHide
    }

    func start() {
        stop()
        Log.write("watcher: start")
        add(.leftMouseUp) { [weak self] _ in self?.scheduleCheck(delay: 0.14) }
        add(.leftMouseDown) { [weak self] _ in
            self?.dragOrigin = NSEvent.mouseLocation
            self?.dismiss()
        }
        add(.rightMouseDown) { [weak self] _ in self?.dismiss() }
        add(.scrollWheel) { [weak self] _ in self?.dismiss() }
        add(.keyDown) { [weak self] event in
            guard let self else { return }
            let arrows: Set<UInt16> = [123, 124, 125, 126, 115, 116, 119, 121]
            let isSelectAll = event.modifierFlags.contains(.command) && event.keyCode == 0
            let isShiftMove = event.modifierFlags.contains(.shift) && arrows.contains(event.keyCode)
            if isSelectAll || isShiftMove {
                self.scheduleCheck(delay: 0.18)
            } else if event.keyCode == 53 { // esc
                self.dismiss()
            } else {
                self.dismiss()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.dismiss() }
    }

    private func add(_ mask: NSEvent.EventTypeMask, _ handler: @escaping (NSEvent) -> Void) {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
            monitors.append(m)
        } else {
            Log.write("watcher: FAILED to install monitor")
        }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        pending?.cancel()
    }

    /// Forget the current selection so an identical one can trigger the bubble again.
    func reset() { lastText = "" }

    private func dismiss() {
        pending?.cancel()
        lastText = ""
        onHide()
    }

    private func scheduleCheck(delay: TimeInterval) {
        pending?.cancel()
        guard isEnabled else { return }
        let work = DispatchWorkItem { [weak self] in self?.check() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func check() {
        let front = NSWorkspace.shared.frontmostApplication
        guard let app = front,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            dismiss(); return
        }

        let peek = TextBridge.peekSelection(of: app)
        Log.write("check: front=" + (app.localizedName ?? "nil")
                  + " sel=" + (peek.map { String($0.text.prefix(30)) } ?? "<none>")
                  + " rect=" + (peek.map { String(describing: $0.rect) } ?? "-"))

        guard let sel = peek else {
            offerBlindBubble(for: app)
            return
        }

        guard sel.text != lastText else {
            Log.write("check: unchanged, skip")
            return
        }
        lastText = sel.text

        let anchor = anchorPoint(for: sel.rect)
        Log.write("check: SHOW anchor=" + String(describing: anchor))
        onShow(Selection(text: sel.text, app: app, element: sel.element, anchor: anchor))
    }

    /// For an app that exposes no text at all, the drag is the only evidence a selection
    /// exists. Show the bubble on that alone and read the text with a simulated copy if,
    /// and only if, an action is actually chosen — so the clipboard is touched when the
    /// user commits, never on an ordinary click.
    private func offerBlindBubble(for app: NSRunningApplication) {
        guard let origin = dragOrigin, !TextBridge.exposesText(app) else {
            dismiss(); return
        }
        let end = NSEvent.mouseLocation
        let distance = hypot(end.x - origin.x, end.y - origin.y)
        guard distance >= 15 else { dismiss(); return }

        lastText = ""
        Log.write("check: \(app.localizedName ?? "?") exposes no text — blind bubble")
        onShow(Selection(text: "", app: app, element: nil, anchor: end, needsClipboardRead: true))
    }

    /// Prefer the real selection rectangle; Electron apps report 0×0, so fall back to
    /// wherever the pointer is — which is exactly where the user just finished dragging.
    private func anchorPoint(for rect: CGRect) -> NSPoint {
        if rect.width > 1, rect.height > 1 {
            return TextBridge.flip(CGPoint(x: rect.maxX, y: rect.maxY))
        }
        let mouse = NSEvent.mouseLocation
        return NSPoint(x: mouse.x, y: mouse.y)
    }
}
