import AppKit
import Carbon.HIToolbox

/// The shoot mode shortcut: a key code plus Carbon modifier flags, as `HotKey` takes them.
struct Shortcut: Equatable {
    static let standard = Shortcut(keyCode: kVK_ANSI_H, modifiers: controlKey | optionKey)

    /// Modifiers in the order macOS menus show them.
    private static let modifierKeys: [(carbon: Int, flag: NSEvent.ModifierFlags, symbol: String)] = [
        (controlKey, .control, "⌃"), (optionKey, .option, "⌥"), (shiftKey, .shift, "⇧"), (cmdKey, .command, "⌘"),
    ]

    /// Keys that don't type a character: how menus show them, and the character AppKit uses for them
    /// as a key equivalent.
    private static let specialKeys: [Int: (name: String, character: Int)] = {
        var keys: [Int: (name: String, character: Int)] = [
            kVK_Space: ("Space", 0x20), kVK_Return: ("↩", 0x0D), kVK_ANSI_KeypadEnter: ("⌤", 0x03), kVK_Tab: ("⇥", 0x09),
            kVK_Delete: ("⌫", 0x08), kVK_ForwardDelete: ("⌦", NSDeleteFunctionKey),
            kVK_LeftArrow: ("←", NSLeftArrowFunctionKey), kVK_RightArrow: ("→", NSRightArrowFunctionKey),
            kVK_UpArrow: ("↑", NSUpArrowFunctionKey), kVK_DownArrow: ("↓", NSDownArrowFunctionKey),
            kVK_Home: ("↖", NSHomeFunctionKey), kVK_End: ("↘", NSEndFunctionKey),
            kVK_PageUp: ("⇞", NSPageUpFunctionKey), kVK_PageDown: ("⇟", NSPageDownFunctionKey),
        ]
        let functionKeys = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
        ]
        for (index, keyCode) in functionKeys.enumerated() {
            keys[keyCode] = ("F\(index + 1)", NSF1FunctionKey + index)
        }
        return keys
    }()

    let keyCode: Int
    /// `controlKey`, `optionKey`, `shiftKey` and `cmdKey` flags.
    let modifiers: Int

    /// The shortcut picked in the Shortcut window, or ⌃⌥H.
    static var saved: Shortcut {
        get {
            guard let keyCode = UserDefaults.standard.object(forKey: "shortcutKeyCode") as? Int,
                  let modifiers = UserDefaults.standard.object(forKey: "shortcutModifiers") as? Int
            else { return .standard }
            return Shortcut(keyCode: keyCode, modifiers: modifiers)
        }
        set {
            UserDefaults.standard.set(newValue.keyCode, forKey: "shortcutKeyCode")
            UserDefaults.standard.set(newValue.modifiers, forKey: "shortcutModifiers")
        }
    }

    init(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// The combination in a key press; nil without ⌃, ⌥ or ⌘, since that would take over ordinary typing.
    init?(event: NSEvent) {
        let modifiers = Self.modifierKeys.reduce(0) { event.modifierFlags.contains($1.flag) ? $0 | $1.carbon : $0 }
        guard modifiers & (controlKey | optionKey | cmdKey) != 0 else { return nil }
        self.init(keyCode: Int(event.keyCode), modifiers: modifiers)
    }

    /// Like "⌃⌥H" or "⇧⌘Space".
    var symbols: String { Self.symbols(for: modifierFlags) + keyName }

    /// The modifiers as AppKit flags, for a menu item's key equivalent.
    var modifierFlags: NSEvent.ModifierFlags {
        Self.modifierKeys.reduce(into: []) { flags, key in
            if modifiers & key.carbon != 0 { flags.insert(key.flag) }
        }
    }

    /// The key as a menu item's key equivalent; together with `modifierFlags` the menu shows `symbols`.
    var keyEquivalent: String {
        if let special = Self.specialKeys[keyCode] { return String(utf16CodeUnits: [UniChar(special.character)], count: 1) }
        return Self.character(for: keyCode) ?? ""
    }

    /// Held modifiers as symbols, like "⌃⌥".
    static func symbols(for flags: NSEvent.ModifierFlags) -> String {
        modifierKeys.filter { flags.contains($0.flag) }.map(\.symbol).joined()
    }

    private var keyName: String {
        Self.specialKeys[keyCode]?.name ?? Self.character(for: keyCode)?.uppercased() ?? "Key \(keyCode)"
    }

    /// What the key types, without modifiers, on the current keyboard layout (or its Latin
    /// counterpart, for layouts like Russian).
    private static func character(for keyCode: Int) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layout = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(layout).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { bytes in
            UCKeyTranslate(bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                           UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeys, 4, &length, &characters)
        }
        let text = String(utf16CodeUnits: characters, count: length)
        // Keys without a printable character (or one in the function-key range) need a name instead.
        guard status == noErr, length > 0,
              text.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value != 0x7F && !(0xF700...0xF8FF).contains($0.value) })
        else { return nil }
        return text
    }
}
