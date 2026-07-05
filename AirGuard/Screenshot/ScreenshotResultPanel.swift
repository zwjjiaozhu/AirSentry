import AppKit
import SwiftUI

@MainActor
enum ScreenshotResultPanel {
    static func show(
        for image: NSImage,
        near rect: CGRect,
        actionHandler: @escaping (ScreenshotResultAction) -> Void
    ) {
        let panelSize = previewPanelSize(for: image)
        let view = ScreenshotResultPreview(image: image, previewSize: previewImageSize(for: image)) { action in
            currentPanel?.orderOut(nil)
            currentPanel = nil
            actionHandler(action)
        }

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: panelSize)

        let panel = ScreenshotToolbarPanel(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        currentPanel = panel
        panel.contentView = hostingView
        panel.setFrameOrigin(previewOrigin(for: rect, size: hostingView.frame.size))
        panel.isMovableByWindowBackground = true
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)

        ScreenshotImageWriter.copyToPasteboard(image)
    }

    private static var currentPanel: NSPanel?

    private static func previewPanelSize(for image: NSImage) -> CGSize {
        let imageSize = previewImageSize(for: image)
        return CGSize(width: imageSize.width, height: imageSize.height + 54)
    }

    private static func previewImageSize(for image: NSImage) -> CGSize {
        let maxSize = CGSize(width: 760, height: 520)
        guard image.size.width > 0, image.size.height > 0 else {
            return CGSize(width: 360, height: 240)
        }

        let ratio = min(maxSize.width / image.size.width, maxSize.height / image.size.height, 1)
        return CGSize(
            width: max(180, image.size.width * ratio),
            height: max(120, image.size.height * ratio)
        )
    }

    private static func previewOrigin(for rect: CGRect, size: CGSize) -> CGPoint {
        let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? rect
        let preferredX = rect.midX - size.width / 2
        let preferredY = rect.midY - size.height / 2
        let x = min(max(preferredX, visibleFrame.minX + 12), visibleFrame.maxX - size.width - 12)
        let y = min(max(preferredY, visibleFrame.minY + 12), visibleFrame.maxY - size.height - 12)
        return CGPoint(x: x, y: y)
    }
}

private final class ScreenshotToolbarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct ScreenshotResultPreview: View {
    let image: NSImage
    let previewSize: CGSize
    let action: (ScreenshotResultAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: previewSize.width, height: previewSize.height)
                .background(Color.black.opacity(0.08))

            HStack(spacing: 9) {
                toolbarButton("pin", "钉图") { action(.pin) }
                toolbarButton("pencil.and.outline", "批注") { action(.annotate) }
                toolbarButton("text.viewfinder", "OCR") { action(.ocr) }
                toolbarButton("doc.on.doc", "复制") { action(.copy) }
                toolbarButton("square.and.arrow.down", "保存") { action(.save) }

                Spacer(minLength: 0)

                Button {
                    action(.close)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .background(.primary.opacity(0.08), in: Circle())
                .help("关闭")
            }
            .padding(.horizontal, 10)
            .frame(height: 54)
            .background(.regularMaterial)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.20), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func toolbarButton(_ image: String, _ title: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: image)
                .font(.system(size: 12.5, weight: .semibold))
                .frame(minWidth: 58)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
