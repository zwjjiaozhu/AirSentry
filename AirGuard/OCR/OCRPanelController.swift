import AppKit
import SwiftUI

@MainActor
final class OCRPanelController: ObservableObject {
    static let shared = OCRPanelController()

    private var panel: NSPanel?
    private var store: OCRStore?

    func show(image: NSImage? = nil, recognizeImmediately: Bool = false) {
        if let panel {
            panel.orderFrontRegardless()
            panel.makeKeyAndOrderFront(nil)
            if let image {
                store?.setImage(image, sourceName: "截图", recognizeImmediately: recognizeImmediately)
            }
            return
        }

        let store = OCRStore()
        self.store = store

        let view = OCRPanelView(store: store)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 720, height: 560)

        let panel = OCRWindowPanel(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "OCR 识别"
        panel.contentView = hostingView
        panel.center()
        panel.isReleasedWhenClosed = false
        panel.titlebarAppearsTransparent = true
        panel.delegate = OCRPanelDelegate.shared
        OCRPanelDelegate.shared.onClose = { [weak self] in
            self?.panel = nil
            self?.store = nil
        }

        self.panel = panel
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if let image {
            store.setImage(image, sourceName: "截图", recognizeImmediately: recognizeImmediately)
        }
    }

    func pasteFromClipboard() {
        show()
        store?.pasteFromClipboard()
    }
}

private final class OCRWindowPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class OCRPanelDelegate: NSObject, NSWindowDelegate {
    static let shared = OCRPanelDelegate()
    var onClose: (() -> Void)?

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
