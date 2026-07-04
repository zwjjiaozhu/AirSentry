import AppKit
import SwiftUI

@MainActor
final class AppLauncherPanelController {
    private let store: AppLauncherStore
    private var panel: AppLauncherPanel?
    private var showObserver: NSObjectProtocol?

    init(store: AppLauncherStore) {
        self.store = store
        showObserver = NotificationCenter.default.addObserver(
            forName: .showAppLauncherPanel,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
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
            panel.orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        if panel == nil {
            store.selectedGroupID = nil
            let contentView = AppLauncherPanelView(store: store) { [weak self] in
                self?.hide()
            }
            let hostingController = NSHostingController(rootView: contentView)
            let panel = AppLauncherPanel(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.title = "程序面板"
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.level = .normal
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentViewController = hostingController
            self.panel = panel
        }

        if store.applications.isEmpty {
            store.refreshApplications()
        }
        guard let panel else { return }
        panel.layoutIfNeeded()
        positionPanel(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        refinePanelPosition(panel)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func positionPanel(_ panel: NSPanel) {
        let screen = screenContainingMouse() ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            panel.center()
            return
        }

        let panelSize = panel.frame.size
        let x = visibleFrame.midX - panelSize.width / 2
        let topOffset = max(48, visibleFrame.height * 0.16)
        let y = visibleFrame.maxY - topOffset - panelSize.height
        panel.setFrameOrigin(NSPoint(x: x, y: max(visibleFrame.minY, y)))
    }

    private func refinePanelPosition(_ panel: NSPanel) {
        [0.02, 0.12].forEach { delay in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak panel] in
                guard let panel, panel.isVisible else { return }
                panel.layoutIfNeeded()
                self.positionPanel(panel)
            }
        }
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
    static let showAppLauncherPanel = Notification.Name("AirSentryShowAppLauncherPanel")
}

private final class AppLauncherPanel: NSPanel {
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
