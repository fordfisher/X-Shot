import AppKit
import Carbon
import Foundation

/// A concrete global hotkey (Carbon key code + Carbon modifier mask).
public struct HotkeyBinding: Equatable, Codable, Sendable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32

    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    public var displayName: String {
        HotkeyBinding.displayName(keyCode: keyCode, carbonModifiers: carbonModifiers)
    }

    public static let shiftCommand4 = HotkeyBinding(
        keyCode: UInt32(kVK_ANSI_4),
        carbonModifiers: UInt32(shiftKey | cmdKey)
    )
    public static let controlShiftCommand4 = HotkeyBinding(
        keyCode: UInt32(kVK_ANSI_4),
        carbonModifiers: UInt32(controlKey | shiftKey | cmdKey)
    )
    public static let shiftCommand3 = HotkeyBinding(
        keyCode: UInt32(kVK_ANSI_3),
        carbonModifiers: UInt32(shiftKey | cmdKey)
    )
    public static let optionShiftCommand4 = HotkeyBinding(
        keyCode: UInt32(kVK_ANSI_4),
        carbonModifiers: UInt32(optionKey | shiftKey | cmdKey)
    )
    public static let shiftCommand5 = HotkeyBinding(
        keyCode: UInt32(kVK_ANSI_5),
        carbonModifiers: UInt32(shiftKey | cmdKey)
    )
    public static let f13 = HotkeyBinding(
        keyCode: UInt32(kVK_F13),
        carbonModifiers: 0
    )

    public static func from(event: NSEvent) -> HotkeyBinding? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Require at least one modifier, except for F-keys (F13–F19) which work alone.
        let code = UInt32(event.keyCode)
        let isFunctionKey = (code >= UInt32(kVK_F1) && code <= UInt32(kVK_F20))
        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if carbon == 0 && !isFunctionKey { return nil }
        // Ignore pure modifier presses.
        if [UInt32(kVK_Command), UInt32(kVK_Shift), UInt32(kVK_Option), UInt32(kVK_Control),
            UInt32(kVK_RightCommand), UInt32(kVK_RightShift), UInt32(kVK_RightOption), UInt32(kVK_RightControl)]
            .contains(code) {
            return nil
        }
        return HotkeyBinding(keyCode: code, carbonModifiers: carbon)
    }

    public static func displayName(keyCode: UInt32, carbonModifiers: UInt32) -> String {
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if carbonModifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyGlyph(keyCode))
        return parts.joined()
    }

    private static func keyGlyph(_ keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Escape: return "⎋"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Tab: return "⇥"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_F20: return "F20"
        default: return "Key\(keyCode)"
        }
    }
}

public enum HotkeyPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case shiftCommand4
    case controlShiftCommand4
    case shiftCommand3
    case shiftCommand5
    case optionShiftCommand4
    case f13
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .shiftCommand4: return "⇧⌘4  (default)"
        case .controlShiftCommand4: return "⌃⇧⌘4"
        case .shiftCommand3: return "⇧⌘3"
        case .shiftCommand5: return "⇧⌘5"
        case .optionShiftCommand4: return "⌥⇧⌘4"
        case .f13: return "F13 (Print Screen)"
        case .custom: return "Custom…"
        }
    }

    public var binding: HotkeyBinding? {
        switch self {
        case .shiftCommand4: return .shiftCommand4
        case .controlShiftCommand4: return .controlShiftCommand4
        case .shiftCommand3: return .shiftCommand3
        case .shiftCommand5: return .shiftCommand5
        case .optionShiftCommand4: return .optionShiftCommand4
        case .f13: return .f13
        case .custom: return nil
        }
    }
}

public struct HotkeySettings: Equatable, Codable, Sendable {
    public var preset: HotkeyPreset
    public var custom: HotkeyBinding
    public var alsoF13: Bool

    public static let `default` = HotkeySettings(
        preset: .shiftCommand4,
        custom: .shiftCommand4,
        alsoF13: true
    )

    public init(
        preset: HotkeyPreset = .shiftCommand4,
        custom: HotkeyBinding = .shiftCommand4,
        alsoF13: Bool = true
    ) {
        self.preset = preset
        self.custom = custom
        self.alsoF13 = alsoF13
    }

    public var primary: HotkeyBinding {
        preset.binding ?? custom
    }

    public var activeDisplayName: String {
        HotkeyParser.displayName(for: self)
    }
}

public enum HotkeyParser {
    public static func displayName(for settings: HotkeySettings) -> String {
        var parts = [settings.primary.displayName]
        let primaryIsF13 = settings.primary.keyCode == HotkeyBinding.f13.keyCode
            && settings.primary.carbonModifiers == 0
        if settings.alsoF13 && !primaryIsF13 {
            parts.append(HotkeyBinding.f13.displayName)
        }
        return parts.joined(separator: " · ")
    }
}

public enum HotkeyStore {
    private static let defaultsKey = "xshot.hotkeySettings"

    public static func load() -> HotkeySettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(HotkeySettings.self, from: data) else {
            return .default
        }
        return decoded
    }

    public static func save(_ settings: HotkeySettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
