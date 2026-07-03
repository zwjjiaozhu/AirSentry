import Carbon.HIToolbox
import Combine
import Foundation

@MainActor
final class InputMethodShortcutManager: ObservableObject {
    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()

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
    }

    private func refreshRegistrations() {
        removeRegistrations()
        guard settings.inputMethodShortcutsEnabled else { return }

        for (index, rule) in settings.inputMethodShortcutRules.enumerated() {
            guard let shortcut = rule.shortcut,
                  let inputSourceID = rule.inputSourceID,
                  !inputSourceID.isEmpty else {
                continue
            }

            let hotKeyID = UInt32(index + 1)
            let status = GlobalHotKeyManager.shared.register(
                shortcut: shortcut,
                signature: inputMethodHotKeySignature,
                id: hotKeyID
            ) {
                InputMethodSwitcher.selectInputSource(id: inputSourceID)
            }

            if status != noErr {
                NSLog("AirSentry input method hotkey registration failed: \(status)")
            }
        }
    }

    private func removeRegistrations() {
        GlobalHotKeyManager.shared.unregisterAll(signature: inputMethodHotKeySignature)
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

private let inputMethodHotKeySignature: OSType = 0x41495357
