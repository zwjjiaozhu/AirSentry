import Carbon.HIToolbox
import Combine
import Foundation

@MainActor
final class ScreenshotShortcutManager: ObservableObject {
    private let settings: AppSettings
    private let captureController: ScreenshotCaptureController
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings, captureController: ScreenshotCaptureController) {
        self.settings = settings
        self.captureController = captureController

        Publishers.CombineLatest(settings.$screenshotShortcutEnabled, settings.$screenshotShortcut)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.refreshRegistration()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(settings.$clipboardPinShortcutEnabled, settings.$clipboardPinShortcut)
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

        if settings.screenshotShortcutEnabled,
           let shortcut = settings.screenshotShortcut {
            let status = GlobalHotKeyManager.shared.register(
                shortcut: shortcut,
                signature: screenshotHotKeySignature,
                id: 1
            ) { [weak captureController] in
                captureController?.startCapture()
            }

            if status != noErr {
                NSLog("AirSentry screenshot hotkey registration failed: \(status)")
            }
        }

        if settings.clipboardPinShortcutEnabled,
           let shortcut = settings.clipboardPinShortcut {
            let status = GlobalHotKeyManager.shared.register(
                shortcut: shortcut,
                signature: screenshotHotKeySignature,
                id: 2
            ) { [weak captureController] in
                captureController?.pinClipboardImageIfAvailable()
            }

            if status != noErr {
                NSLog("AirSentry clipboard pin hotkey registration failed: \(status)")
            }
        }
    }

    private func removeRegistration() {
        GlobalHotKeyManager.shared.unregister(GlobalHotKeyIdentifier(signature: screenshotHotKeySignature, id: 1))
        GlobalHotKeyManager.shared.unregister(GlobalHotKeyIdentifier(signature: screenshotHotKeySignature, id: 2))
    }
}

private let screenshotHotKeySignature: OSType = 0x53434E50
