import AppKit
import SwiftUI

@MainActor
final class TranslationPanelController {
    private let settings: AppSettings
    private let store: TranslationStore
    private var panel: TranslationPanel?
    private var showObserver: NSObjectProtocol?

    private let preferredPanelSize = NSSize(width: 380, height: 620)
    private let minimumPanelSize = NSSize(width: 320, height: 340)

    init(settings: AppSettings, store: TranslationStore) {
        self.settings = settings
        self.store = store
        showObserver = NotificationCenter.default.addObserver(
            forName: .showTranslationPanel,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.show()
            }
        }
    }

    deinit {
        if let showObserver {
            NotificationCenter.default.removeObserver(showObserver)
        }
    }

    func toggle() {
        if let panel, panel.isVisible, isPanelFrontmost(panel) {
            hide()
        } else {
            show()
        }
    }

    func show() {
        if panel == nil {
            let contentView = TranslationPanelView(store: store, settings: settings) { [weak self] in
                self?.hide()
            }
            let hostingController = NSHostingController(rootView: contentView)
            let panel = TranslationPanel(
                contentRect: NSRect(origin: .zero, size: preferredPanelSize),
                styleMask: [.titled, .fullSizeContentView, .resizable],
                backing: .buffered,
                defer: false
            )
            panel.title = "翻译"
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.standardWindowButton(.closeButton)?.isHidden = true
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .managed]
            panel.isExcludedFromWindowsMenu = false
            panel.hidesOnDeactivate = false
            panel.contentMinSize = minimumPanelSize
            panel.minSize = minimumPanelSize
            panel.maxSize = NSSize(width: 1400, height: 1000)
            panel.isMovableByWindowBackground = false
            panel.contentViewController = hostingController
            panel.setContentSize(preferredPanelSize)
            self.panel = panel
        }

        guard let panel else { return }
        store.prepareForPresentation()
        panel.level = store.isPinned ? .floating : .normal
        restorePreferredSizeIfNeeded(panel)
        panel.layoutIfNeeded()
        positionPanel(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func restorePreferredSizeIfNeeded(_ panel: NSPanel) {
        let currentSize = panel.frame.size
        guard currentSize.width < 520 || currentSize.height < 460 else { return }
        panel.setContentSize(preferredPanelSize)
    }

    private func positionPanel(_ panel: NSPanel) {
        let screen = screenContainingMouse() ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            panel.center()
            return
        }

        let panelSize = panel.frame.size
        let x = visibleFrame.midX - panelSize.width / 2
        let y = visibleFrame.midY - panelSize.height / 2 + 40
        panel.setFrameOrigin(
            NSPoint(
                x: min(max(visibleFrame.minX + 18, x), visibleFrame.maxX - panelSize.width - 18),
                y: min(max(visibleFrame.minY + 18, y), visibleFrame.maxY - panelSize.height - 18)
            )
        )
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
    }

    private func isPanelFrontmost(_ panel: NSPanel) -> Bool {
        NSApp.isActive && (panel.isKeyWindow || NSApp.keyWindow === panel || NSApp.mainWindow === panel)
    }
}

extension Notification.Name {
    static let showTranslationPanel = Notification.Name("AirSentryShowTranslationPanel")
}

private final class TranslationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        if firstResponder is NSTextView {
            makeFirstResponder(nil)
            return
        }

        orderOut(sender)
    }
}
