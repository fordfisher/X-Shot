import Carbon
import Foundation

public protocol HotkeyHandling: AnyObject {
    @MainActor func hotkeyTriggered()
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
                DispatchQueue.main.async {
                    HotkeyManager.sharedInstance?.handler?.hotkeyTriggered()
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
        let primary = settings.primary
        register(keyCode: primary.keyCode, modifiers: primary.carbonModifiers, id: 1)

        let primaryIsF13 = primary.keyCode == HotkeyBinding.f13.keyCode && primary.carbonModifiers == 0
        if settings.alsoF13 && !primaryIsF13 {
            register(keyCode: HotkeyBinding.f13.keyCode, modifiers: 0, id: 2)
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
