import Carbon.HIToolbox
import Combine
import Foundation

@MainActor
final class AppLauncherShortcutManager: ObservableObject {
    private let settings: AppSettings
    private let togglePanel: () -> Void
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings, togglePanel: @escaping () -> Void) {
        self.settings = settings
        self.togglePanel = togglePanel

        Publishers.CombineLatest(settings.$appLauncherShortcutEnabled, settings.$appLauncherShortcut)
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
        guard settings.appLauncherShortcutEnabled,
              let shortcut = settings.appLauncherShortcut else { return }

        let status = GlobalHotKeyManager.shared.register(
            shortcut: shortcut,
            signature: appLauncherHotKeySignature,
            id: 1,
            action: togglePanel
        )

        if status != noErr {
            NSLog("AirSentry app launcher hotkey registration failed: \(status)")
        }
    }

    private func removeRegistration() {
        GlobalHotKeyManager.shared.unregister(GlobalHotKeyIdentifier(signature: appLauncherHotKeySignature, id: 1))
    }
}

private let appLauncherHotKeySignature: OSType = 0x414C4E43
