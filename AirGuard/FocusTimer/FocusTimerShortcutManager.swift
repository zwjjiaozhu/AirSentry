import Carbon.HIToolbox
import Foundation

@MainActor
final class FocusTimerShortcutManager: ObservableObject {
    private let toggleLauncher: () -> Void

    init(toggleLauncher: @escaping () -> Void) {
        self.toggleLauncher = toggleLauncher
        register()
    }

    func stop() {
        GlobalHotKeyManager.shared.unregister(GlobalHotKeyIdentifier(signature: focusTimerHotKeySignature, id: 1))
    }

    private func register() {
        let shortcut = KeyboardShortcut(keyCode: 17, modifiers: UInt32(optionKey | controlKey))
        let status = GlobalHotKeyManager.shared.register(
            shortcut: shortcut,
            signature: focusTimerHotKeySignature,
            id: 1,
            action: toggleLauncher
        )

        if status != noErr {
            NSLog("AirSentry focus timer hotkey registration failed: \(status)")
        }
    }
}

private let focusTimerHotKeySignature: OSType = 0x46544D52
