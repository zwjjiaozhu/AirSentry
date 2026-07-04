import AppKit
import SwiftUI

@MainActor
final class PinnedImageController {
    private var windows: [PinnedImageWindow] = []

    func pin(_ image: NSImage, near sourceRect: CGRect? = nil) {
        let initialSize = fittedSize(for: image.size)
        let window = PinnedImageWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        let view = PinnedImageView(image: image) { [weak self, weak window] in
            guard let window else { return }
            self?.close(window)
        }

        window.contentView = NSHostingView(rootView: view)
        window.minSize = NSSize(width: 120, height: 80)
        window.aspectRatio = image.size
        window.setFrameOrigin(origin(for: initialSize, near: sourceRect))
        window.onClose = { [weak self, weak window] in
            guard let window else { return }
            self?.close(window)
        }
        windows.append(window)

        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    private func close(_ window: PinnedImageWindow) {
        window.orderOut(nil)
        windows.removeAll { $0 === window }
    }

    private func fittedSize(for imageSize: CGSize) -> CGSize {
        let maxSize = CGSize(width: 720, height: 520)
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGSize(width: 320, height: 220)
        }

        let ratio = min(maxSize.width / imageSize.width, maxSize.height / imageSize.height, 1)
        return CGSize(width: max(120, imageSize.width * ratio), height: max(80, imageSize.height * ratio))
    }

    private func origin(for size: CGSize, near sourceRect: CGRect?) -> CGPoint {
        let screen = sourceRect.flatMap { rect in
            NSScreen.screens.first { $0.frame.intersects(rect) }
        } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero

        if let sourceRect {
            let x = min(max(sourceRect.minX, visibleFrame.minX + 12), visibleFrame.maxX - size.width - 12)
            let y = min(max(sourceRect.maxY - size.height, visibleFrame.minY + 12), visibleFrame.maxY - size.height - 12)
            return CGPoint(x: x, y: y)
        }

        return CGPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2
        )
    }
}

final class PinnedImageWindow: NSPanel {
    var onClose: (() -> Void)?

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onClose?()
    }
}

private struct PinnedImageView: View {
    let image: NSImage
    let close: () -> Void

    @State private var opacity = 1.0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .opacity(opacity)
                .background(.black.opacity(0.001))

            HStack(spacing: 7) {
                Slider(value: $opacity, in: 0.25...1)
                    .frame(width: 82)
                    .help("透明度")

                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .background(.black.opacity(0.48), in: Circle())
                .foregroundStyle(.white)
                .help("关闭")
            }
            .padding(8)
            .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.white.opacity(0.24), lineWidth: 1)
        )
    }
}
