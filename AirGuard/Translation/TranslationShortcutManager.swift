import Carbon.HIToolbox
import Combine
import Foundation

@MainActor
final class TranslationShortcutManager: ObservableObject {
    private let settings: AppSettings
    private let togglePanel: () -> Void
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings, togglePanel: @escaping () -> Void) {
        self.settings = settings
        self.togglePanel = togglePanel

        Publishers.CombineLatest(settings.$translationShortcutEnabled, settings.$translationShortcut)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.refreshRegistration()
            }
            .store(in: &cancellables)

        refreshRegistration()
    }

    func stop() {
        removeRegistration()
    }

    private func refreshRegistration() {
        removeRegistration()
        guard settings.translationShortcutEnabled,
              let shortcut = settings.translationShortcut else { return }

        let status = GlobalHotKeyManager.shared.register(
            shortcut: shortcut,
            signature: translationHotKeySignature,
            id: 1,
            action: togglePanel
        )

        if status != noErr {
            NSLog("AirSentry translation hotkey registration failed: \(status)")
        }
    }

    private func removeRegistration() {
        GlobalHotKeyManager.shared.unregister(GlobalHotKeyIdentifier(signature: translationHotKeySignature, id: 1))
    }
}

private let translationHotKeySignature: OSType = 0x54524E53
