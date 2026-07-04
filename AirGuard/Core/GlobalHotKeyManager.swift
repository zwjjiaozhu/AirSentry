import Carbon.HIToolbox
import Foundation

struct GlobalHotKeyIdentifier: Hashable {
    let signature: OSType
    let id: UInt32
}

@MainActor
final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()

    private var eventHandler: EventHandlerRef?
    private var registrations: [GlobalHotKeyIdentifier: EventHotKeyRef] = [:]
    private var actions: [GlobalHotKeyIdentifier: () -> Void] = [:]

    private init() {}

    @discardableResult
    func register(
        shortcut: KeyboardShortcut,
        signature: OSType,
        id: UInt32,
        action: @escaping () -> Void
    ) -> OSStatus {
        installEventHandlerIfNeeded()

        let identifier = GlobalHotKeyIdentifier(signature: signature, id: id)
        unregister(identifier)

        let eventHotKeyID = EventHotKeyID(signature: signature, id: id)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            eventHotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr, let hotKeyRef {
            registrations[identifier] = hotKeyRef
            actions[identifier] = action
        }

        return status
    }

    func unregister(_ identifier: GlobalHotKeyIdentifier) {
        if let hotKeyRef = registrations.removeValue(forKey: identifier) {
            UnregisterEventHotKey(hotKeyRef)
        }
        actions.removeValue(forKey: identifier)
    }

    func unregisterAll(signature: OSType) {
        let identifiers = registrations.keys.filter { $0.signature == signature }
        for identifier in identifiers {
            unregister(identifier)
        }
    }

    fileprivate func handleHotKey(signature: OSType, id: UInt32) {
        let identifier = GlobalHotKeyIdentifier(signature: signature, id: id)
        actions[identifier]?()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotKeyHandler,
            1,
            &eventType,
            userData,
            &eventHandler
        )

        if status != noErr {
            NSLog("AirSentry global hotkey handler installation failed: \(status)")
        }
    }
}

private let globalHotKeyHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return noErr }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    guard status == noErr else { return status }

    let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in
        manager.handleHotKey(signature: hotKeyID.signature, id: hotKeyID.id)
    }

    return noErr
}
