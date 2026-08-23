import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Everything that talks to *other* applications: reading the current selection
/// and putting the rewritten text back.
enum TextBridge {

    // MARK: - Permission

    static var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func requestTrust() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: - Accessibility helpers

    /// The focused element inside a specific app, captured while that app is still frontmost
    /// so we can still reach it after our own panel takes over.
    static func focusedElement(of app: NSRunningApplication) -> AXUIElement? {
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value else { return nil }
        return (value as! AXUIElement)
    }

    private static func axString(_ el: AXUIElement, _ attr: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success,
              let s = value as? String, !s.isEmpty else { return nil }
        return s
    }

    // MARK: - Synthetic keystrokes

    /// The hotkey's own modifiers are usually still held down when we fire. Posting ⌘C while
    /// ⌥ is physically down produces ⌥⌘C, so wait for a clean slate first.
    private static func waitForModifierRelease(timeout: TimeInterval = 0.6) {
        let deadline = Date().addingTimeInterval(timeout)
        let watched: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        while Date() < deadline {
            if NSEvent.modifierFlags.intersection(watched).isEmpty { return }
            usleep(15_000)
        }
    }

    private static func postCommandKey(_ virtualKey: UInt32) {
        let src = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(virtualKey), keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(virtualKey), keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        usleep(12_000)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }

    // MARK: - Clipboard

    private struct ClipboardSnapshot {
        let items: [[String: Data]]
        static func take() -> ClipboardSnapshot {
            let pb = NSPasteboard.general
            let items = (pb.pasteboardItems ?? []).map { item -> [String: Data] in
                var dict: [String: Data] = [:]
                for type in item.types {
                    if let data = item.data(forType: type) { dict[type.rawValue] = data }
                }
                return dict
            }
            return ClipboardSnapshot(items: items)
        }

        func restore() {
            let pb = NSPasteboard.general
            pb.clearContents()
            guard !items.isEmpty else { return }
            let restored = items.map { dict -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in dict { item.setData(data, forType: .init(type)) }
                return item
            }
            pb.writeObjects(restored)
        }
    }

    // MARK: - Capture

    struct Capture {
        var text: String
        var app: NSRunningApplication?
        var element: AXUIElement?
    }

    /// Grab whatever the user has selected in the frontmost app.
    /// Must run on a background queue — it blocks while waiting on the clipboard.
    static func captureSelection(prefs: Prefs) -> Capture? {
        let app = NSWorkspace.shared.frontmostApplication
        let element = app.flatMap { focusedElement(of: $0) }

        if prefs.captureViaAX, let element, let text = axString(element, kAXSelectedTextAttribute as String) {
            return Capture(text: text, app: app, element: element)
        }

        // Fallback: ⌘C. Works in Electron apps and anything else that ignores AX.
        waitForModifierRelease()
        let pb = NSPasteboard.general
        let snapshot = ClipboardSnapshot.take()
        let beforeCount = pb.changeCount
        pb.clearContents()

        postCommandKey(KeyCodes.map["C"]!)

        var copied: String?
        let deadline = Date().addingTimeInterval(0.5)
        while Date() < deadline {
            if pb.changeCount != beforeCount + 1, let s = pb.string(forType: .string), !s.isEmpty {
                copied = s
                break
            }
            usleep(20_000)
        }

        if prefs.restoreClipboard { snapshot.restore() }
        guard let copied, !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Capture(text: copied, app: app, element: element)
    }

    // MARK: - Write back

    /// Put `text` where the selection used to be. Runs on a background queue.
    static func writeBack(_ text: String, to capture: Capture, prefs: Prefs) {
        capture.app?.activate()
        usleep(150_000)

        if prefs.writeBackMode == .accessibility, let element = capture.element,
           AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString,
                                        text as CFString) == .success {
            return
        }

        let pb = NSPasteboard.general
        let snapshot = ClipboardSnapshot.take()
        pb.clearContents()
        pb.setString(text, forType: .string)

        waitForModifierRelease(timeout: 0.3)
        postCommandKey(KeyCodes.map["V"]!)

        if prefs.restoreClipboard {
            usleep(400_000)
            snapshot.restore()
        }
    }

    static func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}

// MARK: - Passive selection reading (for the floating bubble)

extension TextBridge {
    /// Electron/Chromium apps only build an accessibility tree once a client asks for one.
    /// Flipping this attribute is what makes Teams, Slack, VS Code and Obsidian report
    /// their selection. Doing it costs the target app memory, so only do it once per app.
    private static let manuallyEnabled = NSMutableSet()

    private static func enableAccessibility(for app: NSRunningApplication, _ appEl: AXUIElement) {
        let pid = app.processIdentifier
        guard !manuallyEnabled.contains(pid) else { return }
        manuallyEnabled.add(pid)
        AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    struct AXSelection {
        var text: String
        var element: AXUIElement
        /// Screen rect of the selection in AX coordinates (top-left origin).
        /// Empty when the app doesn't report usable bounds — Electron apps return 0×0.
        var rect: CGRect
    }

    /// Read the selection without touching the clipboard. Safe to call on every mouse-up.
    static func peekSelection(of app: NSRunningApplication) -> AXSelection? {
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        // Default AX timeout is several seconds; this runs on the main thread after every
        // mouse-up, so a busy target app must never be allowed to stall the UI.
        AXUIElementSetMessagingTimeout(appEl, 0.35)
        enableAccessibility(for: app, appEl)

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return nil }
        let element = focused as! AXUIElement

        guard var text = axString(element, kAXSelectedTextAttribute as String),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        // Some apps hand back a multi-line selection with the line breaks silently
        // dropped — Claude's own app returns three bullet points as one unbroken line.
        // The field's full value usually still has them, so re-cut the selection from
        // that using the reported range, and keep it only if it really is the same text
        // with structure restored.
        if !text.contains(where: \.isNewline) {
            // Report which link of the chain gives out, so a failure here is diagnosable
            // from the log instead of by guesswork.
            let signature = text.filter { !$0.isWhitespace }
            let candidates = axString(element, kAXValueAttribute as String)
                .map { selectedSlices(of: $0, in: element) } ?? []

            if let recovered = candidates.first(where: {
                $0.contains(where: \.isNewline) && $0.filter({ !$0.isWhitespace }) == signature
            }) {
                Log.write("selection: line breaks recovered (\(text.count)ch → \(recovered.count)ch)")
                text = recovered
            } else if !candidates.isEmpty {
                Log.write("selection: flat, no candidate matched "
                          + candidates.map { "\($0.count)ch" }.joined(separator: "/"))
            }
        }

        var rect = CGRect.zero
        var rangeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
           let rangeValue {
            var boundsValue: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                    element, kAXBoundsForRangeParameterizedAttribute as CFString,
                    rangeValue, &boundsValue) == .success, let boundsValue {
                AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect)
            }
        }
        return AXSelection(text: text, element: element, rect: rect)
    }

    /// The selected substring taken from the element's whole value, which preserves line
    /// breaks that `AXSelectedText` sometimes flattens.
    ///
    /// An app that flattens the selected text also numbers it that way: Claude's composer
    /// reported a 73-unit range over a 75-character value, the two missing units being
    /// exactly its two line breaks. Cutting at the raw offsets lands two characters short.
    /// The range is therefore treated as indices into the value with line breaks removed,
    /// and mapped back. Both interpretations are returned so the caller can keep whichever
    /// actually matches the selection.
    private static func selectedSlices(of whole: String, in element: AXUIElement) -> [String] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString,
                                            &value) == .success, let value else { return [] }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range),
              range.location >= 0, range.length > 0 else { return [] }

        var results: [String] = []

        // Literal reading: offsets index the value as it is.
        let utf16 = Array(whole.utf16)
        let end = range.location + range.length
        if end <= utf16.count, let literal = String(utf16: Array(utf16[range.location..<end])) {
            results.append(literal)
        }

        // Flattened reading: offsets index the value with its line breaks removed.
        var flatIndex = 0
        var start: String.Index?
        var finish: String.Index?
        for index in whole.indices {
            if flatIndex == range.location, start == nil { start = index }
            if flatIndex == range.location + range.length { finish = index; break }
            if !whole[index].isNewline { flatIndex += 1 }
        }
        if let start {
            results.append(String(whole[start..<(finish ?? whole.endIndex)]))
        }
        return results
    }

    /// AX reports screen positions with the origin at the top-left of the main display;
    /// AppKit wants the bottom-left.
    static func flip(_ point: CGPoint) -> NSPoint {
        guard let main = NSScreen.screens.first else { return NSPoint(x: point.x, y: point.y) }
        return NSPoint(x: point.x, y: main.frame.maxY - point.y)
    }
}

private extension String {
    /// Builds a String from UTF-16 code units, returning nil on an invalid sequence
    /// rather than substituting replacement characters.
    init?(utf16 units: [UInt16]) {
        var decoder = UTF16()
        var iterator = units.makeIterator()
        var result = ""
        while true {
            switch decoder.decode(&iterator) {
            case .scalarValue(let scalar): result.unicodeScalars.append(scalar)
            case .emptyInput: self = result; return
            case .error: return nil
            }
        }
    }
}
