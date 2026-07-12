import AppKit
import SwiftUI

@MainActor
final class FinderRenamePanelController {
    static let shared = FinderRenamePanelController()

    private var panel: FinderRenamePanel?
    private var viewModel: FinderRenamePanelViewModel?

    func show(fileURL: URL) {
        let configStore = FinderRenameConfigStore()
        let viewModel = FinderRenamePanelViewModel(fileURL: fileURL, configStore: configStore)
        self.viewModel = viewModel

        let view = FinderRenamePanelView(viewModel: viewModel) { [weak self] in
            self?.close()
        }
        let hostingController = NSHostingController(rootView: view)

        if panel == nil {
            let panel = FinderRenamePanel(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 610),
                styleMask: [.titled, .closable, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.title = "重命名"
            panel.titlebarAppearsTransparent = false
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.isReleasedWhenClosed = false
            panel.delegate = FinderRenamePanelDelegate.shared
            FinderRenamePanelDelegate.shared.onClose = { [weak self] in
                self?.panel = nil
                self?.viewModel = nil
            }
            self.panel = panel
        }

        guard let panel else { return }
        panel.contentViewController = hostingController
        panel.setContentSize(NSSize(width: 560, height: 610))
        panel.center()
        panel.orderFrontRegardless()
        panel.orderFront(nil)
    }

    private func close() {
        panel?.close()
    }
}

private final class FinderRenamePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class FinderRenamePanelDelegate: NSObject, NSWindowDelegate {
    static let shared = FinderRenamePanelDelegate()
    var onClose: (() -> Void)?

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
