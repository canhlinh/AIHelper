//
//  ShortcutStore.swift
//  AIHelper — macOS AI writing assistant
//
//  Persists the user's chosen global shortcut in UserDefaults.
//

import Cocoa
import Carbon

nonisolated struct HotkeyShortcut: Codable, Equatable, Sendable {
    var keyCode: UInt16
    var modifierFlags: UInt64 // raw CGEventFlags value

    // Default: Cmd+Shift+G (keyCode 5)
    static let `default` = HotkeyShortcut(keyCode: 5, modifierFlags: CGEventFlags([.maskCommand, .maskShift]).rawValue)

    var cgFlags: CGEventFlags { CGEventFlags(rawValue: modifierFlags) }

    /// Human-readable string like "⌘⇧G"
    var displayString: String {
        var parts = ""
        let flags = cgFlags
        if flags.contains(.maskControl)   { parts += "⌃" }
        if flags.contains(.maskAlternate) { parts += "⌥" }
        if flags.contains(.maskShift)     { parts += "⇧" }
        if flags.contains(.maskCommand)   { parts += "⌘" }
        parts += keyCodeToChar(keyCode)
        return parts
    }

    private func keyCodeToChar(_ code: UInt16) -> String {
        // Use TISCopyCurrentKeyboardInputSource to translate keycode → glyph
        let src = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let layoutData = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData)
        guard let data = layoutData else {
            return "(\(code))"
        }
        let layout = unsafeBitCast(data, to: CFData.self)
        let keyboardLayout = unsafeBitCast(CFDataGetBytePtr(layout), to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0

        UCKeyTranslate(
            keyboardLayout,
            code,
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            4,
            &length,
            &chars
        )
        if length > 0 {
            return String(chars[..<length].map { Character(Unicode.Scalar($0)!) }).uppercased()
        }
        return "(\(code))"
    }
}

nonisolated class ShortcutStore: @unchecked Sendable {
    static let shared = ShortcutStore()
    private let key = "userHotkey"

    var shortcut: HotkeyShortcut {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let s = try? JSONDecoder().decode(HotkeyShortcut.self, from: data) else {
                return .default
            }
            return s
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }
}
