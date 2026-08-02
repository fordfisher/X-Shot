import Carbon
import Foundation

public protocol HotkeyHandling: AnyObject {
    @MainActor func hotkeyTriggered(_ chord: HotkeyChord)
}

/// Registers global hotkeys via Carbon (no Accessibility permission required).
public final class HotkeyManager {
    public weak var handler: HotkeyHandling?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?
    private var settings: HotkeySettings

    private static let signature: OSType = 0x5853_4854 // 'XSHT'
    private static var sharedInstance: HotkeyManager?

    public init(settings: HotkeySettings = .default) {
        self.settings = settings
        HotkeyManager.sharedInstance = self
    }

    deinit {
        unregisterAll()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
        if HotkeyManager.sharedInstance === self {
            HotkeyManager.sharedInstance = nil
        }
    }

    public func apply(_ settings: HotkeySettings) {
        self.settings = settings
        unregisterAll()
        registerAll()
    }

    public func start() {
        installHandlerIfNeeded()
        registerAll()
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                guard let event else { return noErr }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard hotKeyID.signature == HotkeyManager.signature else { return noErr }
                let chord: HotkeyChord = hotKeyID.id == 2 ? .f13 : .controlShiftCommand4
                DispatchQueue.main.async {
                    HotkeyManager.sharedInstance?.handler?.hotkeyTriggered(chord)
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &handlerRef
        )
        if status != noErr {
            NSLog("XShot: failed to install hotkey handler: \(status)")
        }
    }

    private func registerAll() {
        // id 1 = primary ⌃⇧⌘4, id 2 = F13
        register(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(controlKey | shiftKey | cmdKey), id: 1)
        if settings.alsoF13 {
            register(keyCode: UInt32(kVK_F13), modifiers: 0, id: 2)
        }
    }

    private func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: HotkeyManager.signature, id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr {
            hotKeyRefs.append(hotKeyRef)
        } else {
            NSLog("XShot: failed to register hotkey id=\(id) status=\(status)")
        }
    }

    private func unregisterAll() {
        for ref in hotKeyRefs {
            if let ref { UnregisterEventHotKey(ref) }
        }
        hotKeyRefs.removeAll()
    }
}

/// Pure helpers for tests / settings display.
public enum HotkeyParser {
    public static func displayName(for settings: HotkeySettings) -> String {
        var parts = [settings.primary.displayName]
        if settings.alsoF13 && settings.primary != .f13 {
            parts.append(HotkeyChord.f13.displayName)
        }
        return parts.joined(separator: " · ")
    }

    public static func parseDisplay(_ string: String) -> HotkeySettings? {
        let s = string.uppercased()
        if s.contains("F13") && (s.contains("4") || s.contains("⌃") || s.contains("CTRL")) {
            return HotkeySettings(primary: .controlShiftCommand4, alsoF13: true)
        }
        if s.contains("F13") {
            return HotkeySettings(primary: .f13, alsoF13: true)
        }
        if s.contains("4") {
            return HotkeySettings(primary: .controlShiftCommand4, alsoF13: false)
        }
        return nil
    }
}
