import Carbon.HIToolbox
import Combine
import Foundation

@MainActor
final class InputMethodShortcutManager: ObservableObject {
    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()
    private var eventHandler: EventHandlerRef?
    private var registrations: [UInt32: EventHotKeyRef] = [:]
    private var inputSourceIDsByHotKeyID: [UInt32: String] = [:]

    init(settings: AppSettings) {
        self.settings = settings

        Publishers.CombineLatest(settings.$inputMethodShortcutsEnabled, settings.$inputMethodShortcutRules)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.refreshRegistrations()
            }
            .store(in: &cancellables)

        refreshRegistrations()
    }

    func stop() {
        removeRegistrations()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func refreshRegistrations() {
        removeRegistrations()
        guard settings.inputMethodShortcutsEnabled else { return }
        installEventHandlerIfNeeded()

        for (index, rule) in settings.inputMethodShortcutRules.enumerated() {
            guard let shortcut = rule.shortcut,
                  let inputSourceID = rule.inputSourceID,
                  !inputSourceID.isEmpty else {
                continue
            }

            let hotKeyID = UInt32(index + 1)
            let eventHotKeyID = EventHotKeyID(signature: hotKeySignature, id: hotKeyID)
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
                registrations[hotKeyID] = hotKeyRef
                inputSourceIDsByHotKeyID[hotKeyID] = inputSourceID
            } else {
                NSLog("AirSentry input method hotkey registration failed: \(status)")
            }
        }
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
            inputMethodHotKeyHandler,
            1,
            &eventType,
            userData,
            &eventHandler
        )

        if status != noErr {
            NSLog("AirSentry input method hotkey handler installation failed: \(status)")
        }
    }

    private func removeRegistrations() {
        for ref in registrations.values {
            UnregisterEventHotKey(ref)
        }
        registrations.removeAll()
        inputSourceIDsByHotKeyID.removeAll()
    }

    fileprivate func handleHotKey(id: UInt32) {
        guard let inputSourceID = inputSourceIDsByHotKeyID[id] else { return }
        InputMethodSwitcher.selectInputSource(id: inputSourceID)
    }
}

@MainActor
final class InputMethodShortcutController: ObservableObject {
    private let settings: AppSettings
    private var manager: InputMethodShortcutManager?
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings) {
        self.settings = settings

        settings.$inputMethodShortcutsEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.setShortcutManagerEnabled(enabled)
            }
            .store(in: &cancellables)

        setShortcutManagerEnabled(settings.inputMethodShortcutsEnabled)
    }

    private func setShortcutManagerEnabled(_ enabled: Bool) {
        if enabled {
            if manager == nil {
                manager = InputMethodShortcutManager(settings: settings)
            }
        } else {
            manager?.stop()
            manager = nil
        }
    }
}

private let hotKeySignature: OSType = 0x41495357

private let inputMethodHotKeyHandler: EventHandlerUPP = { _, event, userData in
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

    let manager = Unmanaged<InputMethodShortcutManager>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in
        manager.handleHotKey(id: hotKeyID.id)
    }

    return noErr
}
