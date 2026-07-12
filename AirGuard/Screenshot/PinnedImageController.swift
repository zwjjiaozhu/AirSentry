import AppKit
import SwiftUI

@MainActor
final class PinnedImageController {
    private var windows: [PinnedImageWindow] = []

    func pin(_ image: NSImage, near sourceRect: CGRect? = nil) {
        let initialSize = fittedSize(for: image.size)
        let focusState = PinnedImageFocusState()
        let window = PinnedImageWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.focusState = focusState
        window.originalImageSize = image.size
        window.contentView = PinnedImageHostingView(
            rootView: pinnedImageView(for: image, in: window, focusState: focusState),
            onDoubleClick: { [weak self, weak window] in
                guard let window else { return }
                self?.closeAfterDoubleClickConfirmation(window)
            },
            onScroll: { [weak window] event in
                window?.resizeByScroll(event)
            },
            onMagnify: { [weak window] event in
                window?.resizeByMagnify(event)
            }
        )
        window.minSize = NSSize(width: 120, height: 80)
        window.aspectRatio = image.size
        window.setFrameOrigin(origin(for: initialSize, near: sourceRect))
        window.onClose = { [weak self, weak window] in
            guard let window else { return }
            self?.close(window)
        }
        windows.append(window)

        window.orderFrontRegardless()
        focus(window)
    }

    private func replace(_ window: PinnedImageWindow, with image: NSImage) {
        let size = fittedSize(for: image.size)
        let oldFrame = window.frame
        let focusState = window.focusState ?? PinnedImageFocusState()
        window.focusState = focusState
        window.originalImageSize = image.size
        window.aspectRatio = image.size
        window.contentView = PinnedImageHostingView(
            rootView: pinnedImageView(for: image, in: window, focusState: focusState),
            onDoubleClick: { [weak self, weak window] in
                guard let window else { return }
                self?.closeAfterDoubleClickConfirmation(window)
            },
            onScroll: { [weak window] event in
                window?.resizeByScroll(event)
            },
            onMagnify: { [weak window] event in
                window?.resizeByMagnify(event)
            }
        )
        window.minSize = NSSize(width: 120, height: 80)
        window.setFrame(
            CGRect(x: oldFrame.midX - size.width / 2, y: oldFrame.midY - size.height / 2, width: size.width, height: size.height),
            display: true,
            animate: false
        )
    }

    private func pinnedImageView(
        for image: NSImage,
        in window: PinnedImageWindow,
        focusState: PinnedImageFocusState
    ) -> PinnedImageView {
        PinnedImageView(
            image: image,
            focusState: focusState,
            close: { [weak self, weak window] in
                guard let window else { return }
                self?.close(window)
            },
            copyImage: {
                ScreenshotImageWriter.copyToPasteboard(image)
            },
            saveImage: { [weak self, weak window] in
                guard let window else { return }
                self?.savePinnedImage(image, from: window)
            },
            pasteImage: { [weak self, weak window] in
                guard let window,
                      let pastedImage = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage else {
                    NSSound.beep()
                    return
                }
                self?.replace(window, with: pastedImage)
            },
            resetSize: { [weak window] in
                window?.resetToOriginalSize()
            },
            scale: { [weak window] factor in
                window?.scale(by: factor)
            },
            toggleAlwaysOnTop: { [weak window] in
                window?.setAlwaysOnTop(!(window?.isAlwaysOnTop ?? true))
            },
            alwaysOnTopEnabled: { [weak window] in
                window?.isAlwaysOnTop ?? true
            }
        )
    }

    private func savePinnedImage(_ image: NSImage, from window: PinnedImageWindow) {
        window.orderOut(nil)
        let didSave = ScreenshotImageWriter.saveWithPanel(image)
        if didSave {
            close(window)
        } else {
            window.orderFrontRegardless()
            focus(window)
        }
    }

    private func closeAfterDoubleClickConfirmation(_ window: PinnedImageWindow) {
        guard PinnedImageDoubleClickClosePrompt.shouldClose() else {
            focus(window)
            return
        }

        close(window)
    }

    private func focus(_ window: PinnedImageWindow) {
        windows.forEach { $0.focusState?.isFocused = ($0 === window) }
    }

    private func close(_ window: PinnedImageWindow) {
        window.focusState?.isFocused = false
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

private enum PinnedImageDoubleClickClosePrompt {
    private static let skipPromptKey = "pinnedImageDoubleClickCloseSkipPrompt"

    @MainActor
    static func shouldClose() -> Bool {
        guard !UserDefaults.standard.bool(forKey: skipPromptKey) else {
            return true
        }

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "关闭这张钉图？"
        alert.informativeText = "以后双击钉图会直接关闭它，也可以继续用右键菜单里的「关闭」。"
        alert.addButton(withTitle: "关闭")
        alert.addButton(withTitle: "取消")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "以后双击直接关闭"

        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: skipPromptKey)
        }

        return response == .alertFirstButtonReturn
    }
}

@MainActor
fileprivate final class PinnedImageFocusState: ObservableObject {
    @Published var isFocused = false
}

final class PinnedImageWindow: NSPanel {
    var onClose: (() -> Void)?
    fileprivate var focusState: PinnedImageFocusState? {
        didSet {
            focusState?.isFocused = isKeyWindow
        }
    }
    var originalImageSize: CGSize = .zero
    private(set) var isAlwaysOnTop = true
    private let minimumPinnedSize = CGSize(width: 120, height: 80)
    private let maximumPinnedSize = CGSize(width: 1600, height: 1200)

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
        hasShadow = false
        level = .statusBar
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovableByWindowBackground = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func becomeKey() {
        super.becomeKey()
        focusState?.isFocused = true
    }

    override func resignKey() {
        super.resignKey()
        focusState?.isFocused = false
    }

    override func cancelOperation(_ sender: Any?) {
        onClose?()
    }

    override func scrollWheel(with event: NSEvent) {
        resizeByScroll(event)
    }

    override func magnify(with event: NSEvent) {
        resizeByMagnify(event)
    }

    func resetToOriginalSize() {
        guard originalImageSize.width > 0, originalImageSize.height > 0 else { return }
        let targetSize = CGSize(
            width: originalImageSize.width.clamped(to: minimumPinnedSize.width...maximumPinnedSize.width),
            height: originalImageSize.height.clamped(to: minimumPinnedSize.height...maximumPinnedSize.height)
        )
        resizeAroundCenter(to: targetSize)
    }

    func scale(by factor: CGFloat) {
        let currentSize = frame.size
        let minimumScale = max(
            minimumPinnedSize.width / currentSize.width,
            minimumPinnedSize.height / currentSize.height
        )
        let maximumScale = min(
            maximumPinnedSize.width / currentSize.width,
            maximumPinnedSize.height / currentSize.height
        )
        resizeByScale(min(max(factor, minimumScale), maximumScale))
    }

    func setAlwaysOnTop(_ enabled: Bool) {
        isAlwaysOnTop = enabled
        level = enabled ? .statusBar : .floating
        if enabled {
            orderFrontRegardless()
        }
    }

    func resizeByScroll(_ event: NSEvent) {
        let scrollDelta = event.scrollingDeltaY == 0 ? -event.scrollingDeltaX : event.scrollingDeltaY
        guard scrollDelta != 0 else { return }

        let factor = scrollDelta > 0 ? 1.08 : 0.92
        scale(by: factor)
    }

    func resizeByMagnify(_ event: NSEvent) {
        let factor = 1 + event.magnification
        guard factor > 0 else { return }
        scale(by: factor)
    }

    private func resizeByScale(_ scale: CGFloat) {
        let currentFrame = frame
        let currentSize = currentFrame.size
        let newSize = CGSize(
            width: currentSize.width * scale,
            height: currentSize.height * scale
        )
        guard abs(newSize.width - currentSize.width) > 0.5,
              abs(newSize.height - currentSize.height) > 0.5 else { return }

        resizeAroundCenter(to: newSize)
    }

    private func resizeAroundCenter(to newSize: CGSize) {
        let currentFrame = frame
        let center = CGPoint(x: currentFrame.midX, y: currentFrame.midY)
        let newFrame = CGRect(
            x: center.x - newSize.width / 2,
            y: center.y - newSize.height / 2,
            width: newSize.width,
            height: newSize.height
        )
        setFrame(newFrame, display: true, animate: false)
    }
}

private final class PinnedImageHostingView<Content: View>: NSHostingView<Content> {
    private let onDoubleClick: (() -> Void)?
    private let onScroll: ((NSEvent) -> Void)?
    private let onMagnify: ((NSEvent) -> Void)?

    init(
        rootView: Content,
        onDoubleClick: @escaping () -> Void,
        onScroll: @escaping (NSEvent) -> Void,
        onMagnify: @escaping (NSEvent) -> Void
    ) {
        self.onDoubleClick = onDoubleClick
        self.onScroll = onScroll
        self.onMagnify = onMagnify
        super.init(rootView: rootView)
    }

    required init(rootView: Content) {
        self.onDoubleClick = nil
        self.onScroll = nil
        self.onMagnify = nil
        super.init(rootView: rootView)
    }

    @MainActor @preconcurrency required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func scrollWheel(with event: NSEvent) {
        if let onScroll {
            onScroll(event)
        } else {
            super.scrollWheel(with: event)
        }
    }

    override func magnify(with event: NSEvent) {
        if let onMagnify {
            onMagnify(event)
        } else {
            super.magnify(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKeyAndOrderFront(nil)
        if event.clickCount >= 2 {
            onDoubleClick?()
            return
        }
        super.mouseDown(with: event)
    }
}

private struct PinnedImageView: View {
    let image: NSImage
    @ObservedObject var focusState: PinnedImageFocusState
    let close: () -> Void
    let copyImage: () -> Void
    let saveImage: () -> Void
    let pasteImage: () -> Void
    let resetSize: () -> Void
    let scale: (CGFloat) -> Void
    let toggleAlwaysOnTop: () -> Void
    let alwaysOnTopEnabled: () -> Bool

    @State private var opacity = 1.0
    @State private var shadowOn = true

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .opacity(opacity)
            .background(.black.opacity(0.001))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(focusState.isFocused ? Color.blue.opacity(0.95) : Color.white.opacity(0.24),
                            lineWidth: focusState.isFocused ? 2 : 1)
            )
            .shadow(color: shadowOn ? (focusState.isFocused ? Color.blue.opacity(0.50) : Color.black.opacity(0.18)) : .clear,
                    radius: focusState.isFocused ? 12 : 8,
                    x: 0,
                    y: focusState.isFocused ? 0 : 4)
            .animation(.easeOut(duration: 0.12), value: focusState.isFocused)
            .contextMenu {
            Button("复制图像", action: copyImage)
            Button("复制原始大小图像", action: copyImage)
            Button("图像另存为...", action: saveImage)
            Button("原始大小图像另存为...", action: saveImage)

            Divider()

            Button(alwaysOnTopEnabled() ? "取消窗口置顶" : "窗口置顶", action: toggleAlwaysOnTop)
            Button(shadowOn ? "隐藏窗口阴影" : "显示窗口阴影") { shadowOn.toggle() }

            Divider()

            Menu("透明度") {
                opacityMenuItem(title: "100%", value: 1.0)
                opacityMenuItem(title: "75%", value: 0.75)
                opacityMenuItem(title: "50%", value: 0.50)
                opacityMenuItem(title: "25%", value: 0.25)
            }

            Menu("缩放") {
                Button("放大 10%") { scale(1.1) }
                Button("缩小 10%") { scale(0.9) }
                Button("原始大小", action: resetSize)
            }

            Menu("图像处理") {
                Button("灰度") { NSSound.beep() }
                    .disabled(true)
                Button("反色") { NSSound.beep() }
                    .disabled(true)
            }

            Divider()

            Button("粘贴", action: pasteImage)
            Button("替换为剪贴板图像", action: pasteImage)
            Button("在文件夹中查看") { NSSound.beep() }
                .disabled(true)

            Divider()

            Button("关闭", action: close)

            Divider()

            Menu("\(Int(image.size.width)) x \(Int(image.size.height))") {
                Button("复制尺寸文本") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString("\(Int(image.size.width)) x \(Int(image.size.height))", forType: .string)
                }
            }
        }
    }

    private func opacityMenuItem(title: String, value: Double) -> some View {
        Button(opacity == value ? "✓ \(title)" : title) {
            opacity = value
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
