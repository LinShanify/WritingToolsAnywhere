import AppKit
import Carbon.HIToolbox

/// Virtual key codes for the characters we let users bind.
enum KeyCodes {
    static let map: [String: UInt32] = [
        "A": 0x00, "S": 0x01, "D": 0x02, "F": 0x03, "H": 0x04, "G": 0x05, "Z": 0x06,
        "X": 0x07, "C": 0x08, "V": 0x09, "B": 0x0B, "Q": 0x0C, "W": 0x0D, "E": 0x0E,
        "R": 0x0F, "Y": 0x10, "T": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15,
        "6": 0x16, "5": 0x17, "=": 0x18, "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C,
        "0": 0x1D, "]": 0x1E, "O": 0x1F, "U": 0x20, "[": 0x21, "I": 0x22, "P": 0x23,
        "L": 0x25, "J": 0x26, "'": 0x27, "K": 0x28, ";": 0x29, "\\": 0x2A, ",": 0x2B,
        "/": 0x2C, "N": 0x2D, "M": 0x2E, ".": 0x2F, "`": 0x32,
        "SPACE": 0x31, "RETURN": 0x24, "TAB": 0x30, "ESCAPE": 0x35,
    ]

    static func code(for key: String) -> UInt32? { map[key.uppercased()] }
}

/// Registers a system-wide hotkey through Carbon, which — unlike a CGEventTap —
/// works without Accessibility permission and never sees unrelated keystrokes.
final class HotKeyManager {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let onFire: () -> Void

    init(onFire: @escaping () -> Void) {
        self.onFire = onFire
    }

    func register(_ spec: HotKeySpec) -> Bool {
        unregister()
        guard let code = KeyCodes.code(for: spec.key) else { return false }

        var mods: UInt32 = 0
        if spec.command { mods |= UInt32(cmdKey) }
        if spec.option { mods |= UInt32(optionKey) }
        if spec.shift { mods |= UInt32(shiftKey) }
        if spec.control { mods |= UInt32(controlKey) }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, ctx -> OSStatus in
            guard let ctx else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if hkID.signature == OSType(0x5754_4B59) { // 'WTKY'
                Unmanaged<HotKeyManager>.fromOpaque(ctx).takeUnretainedValue().onFire()
            }
            return noErr
        }, 1, &eventType, me, &handler)

        let hkID = EventHotKeyID(signature: OSType(0x5754_4B59), id: 1)
        let status = RegisterEventHotKey(code, mods, hkID, GetApplicationEventTarget(), 0, &ref)
        return status == noErr
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    deinit { unregister() }
}
