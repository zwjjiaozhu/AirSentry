import AppKit
import SwiftUI

@MainActor
final class AppLauncherPanelController {
    private let store: AppLauncherStore
    private var panel: AppLauncherPanel?
    private var showObserver: NSObjectProtocol?
    private var hostingController: NSHostingController<AppLauncherPanelView>?

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
            let hc = NSHostingController(rootView: contentView)
            self.hostingController = hc
            // 一开始就以居中坐标创建窗口，避免显示后再移动
            let panelSize = NSSize(width: 760, height: 540)
            let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            // 居中并向下偏移，确保窗口顶部与屏幕顶部有足够间距
            let verticalOffset: CGFloat = -30
            let originY = screenFrame.midY - panelSize.height / 2 - verticalOffset
            let centeredRect = NSRect(
                x: screenFrame.midX - panelSize.width / 2,
                y: originY,
                width: panelSize.width,
                height: panelSize.height
            )
            let panel = AppLauncherPanel(
                contentRect: centeredRect,
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.title = "程序面板"
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.level = .normal
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            // 直接设置 contentView 而非 contentViewController，避免 hosting controller 自动调整窗口位置
            panel.contentView = hc.view
            self.panel = panel
        }

        if store.applications.isEmpty {
            store.refreshApplications()
        }
        guard let panel else { return }
        panel.layoutIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func hide() {
        panel?.orderOut(nil)
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
