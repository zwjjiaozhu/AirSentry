import AppKit
import Combine
import SwiftUI

@MainActor
final class FloatingBallController: ObservableObject {
    private let settings: AppSettings
    private let screenshotCaptureController: ScreenshotCaptureController
    private let menuModel = FloatingBallMenuModel()
    private var panel: FloatingBallPanel?
    private var contextMenuDelegate: FloatingBallContextMenuDelegate?
    private var cancellables: Set<AnyCancellable> = []

    init(settings: AppSettings, screenshotCaptureController: ScreenshotCaptureController) {
        self.settings = settings
        self.screenshotCaptureController = screenshotCaptureController

        Publishers.CombineLatest4(
            settings.$floatingBallEnabled,
            settings.$floatingBallSize,
            settings.$floatingBallOpacity,
            settings.$floatingBallPetImagePath
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] enabled, _, _, _ in
            enabled ? self?.show() : self?.hide()
        }
        .store(in: &cancellables)

        settings.$floatingBallActions
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshContent()
            }
            .store(in: &cancellables)
    }

    func show() {
        if panel == nil {
            makePanel()
        }
        refreshContent()
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() {
        let screenFrame = NSScreen.main?.visibleFrame ?? .init(x: 0, y: 0, width: 1280, height: 800)
        let windowSize = CGSize(width: 390, height: 340)
        let origin = CGPoint(
            x: screenFrame.maxX - windowSize.width - 28,
            y: screenFrame.midY - windowSize.height / 2
        )
        let panel = FloatingBallPanel(
            contentRect: NSRect(origin: origin, size: windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.onClick = { [weak self] in
            self?.toggleExpanded()
        }
        let contextMenuDelegate = FloatingBallContextMenuDelegate(controller: self, settings: settings)
        panel.contextMenuDelegate = contextMenuDelegate
        self.contextMenuDelegate = contextMenuDelegate
        self.panel = panel
    }

    private func refreshContent() {
        guard let panel else { return }
        menuModel.isExpanded = panel.isMenuExpanded
        let content = FloatingBallView(
            settings: settings,
            menuModel: menuModel,
            performAction: { [weak self] action in self?.perform(action) }
        )
        let hostingView = NSHostingView(rootView: content)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
    }

    private func toggleExpanded() {
        guard let panel else { return }
        panel.isMenuExpanded.toggle()
        menuModel.isExpanded = panel.isMenuExpanded
    }

    fileprivate func collapseMenu() {
        guard let panel else { return }
        panel.isMenuExpanded = false
        menuModel.isExpanded = false
    }

    fileprivate func resetPosition() {
        guard let panel else { return }
        let screenFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .init(x: 0, y: 0, width: 1280, height: 800)
        panel.setFrameOrigin(
            CGPoint(
                x: screenFrame.maxX - panel.frame.width - 28,
                y: screenFrame.midY - panel.frame.height / 2
            )
        )
    }

    fileprivate func openFloatingBallSettings() {
        NotificationCenter.default.post(name: .openFloatingBallSettings, object: nil)
    }

    private func perform(_ kind: FloatingBallActionKind) {
        switch kind {
        case .translation:
            NotificationCenter.default.post(name: .showTranslationPanel, object: nil)
        case .ocrCapture:
            OCRPanelController.shared.show()
            screenshotCaptureController.startOCRCapture()
        case .screenshot:
            screenshotCaptureController.startCapture()
        case .appLauncher:
            NotificationCenter.default.post(name: .showAppLauncherPanel, object: nil)
        case .pomodoro:
            showTransientMessage("番茄钟已准备", detail: "完整番茄钟面板会在下一步接入。")
        case .timer:
            showTransientMessage("计时器已准备", detail: "这里会承载快速计时入口。")
        case .focus:
            showTransientMessage("专注模式已准备", detail: "后续可接入勿扰、白名单和专注时长。")
        }
    }

    private func showTransientMessage(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }
}

@MainActor
private final class FloatingBallMenuModel: ObservableObject {
    @Published var isExpanded = false
}

private final class FloatingBallPanel: NSPanel {
    var isMenuExpanded = false
    var onClick: (() -> Void)?
    weak var contextMenuDelegate: FloatingBallContextMenuDelegate?
    private var mouseDownScreenLocation: CGPoint = .zero
    private var mouseDownFrameOrigin: CGPoint = .zero
    private var didDrag = false

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func mouseDown(with event: NSEvent) {
        guard event.type != .rightMouseDown else {
            super.mouseDown(with: event)
            return
        }
        mouseDownScreenLocation = NSEvent.mouseLocation
        mouseDownFrameOrigin = frame.origin
        didDrag = false
    }

    override func rightMouseDown(with event: NSEvent) {
        contextMenuDelegate?.showMenu(for: self, event: event)
    }

    override func mouseDragged(with event: NSEvent) {
        let location = NSEvent.mouseLocation
        let delta = CGSize(
            width: location.x - mouseDownScreenLocation.x,
            height: location.y - mouseDownScreenLocation.y
        )

        if !didDrag, hypot(delta.width, delta.height) < 3 {
            return
        }

        didDrag = true
        var nextFrame = frame
        nextFrame.origin.x = mouseDownFrameOrigin.x + delta.width
        nextFrame.origin.y = mouseDownFrameOrigin.y + delta.height

        if let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            nextFrame.origin.x = min(max(nextFrame.origin.x, visibleFrame.minX), visibleFrame.maxX - nextFrame.width)
            nextFrame.origin.y = min(max(nextFrame.origin.y, visibleFrame.minY), visibleFrame.maxY - nextFrame.height)
        }

        setFrameOrigin(nextFrame.origin)
    }

    override func mouseUp(with event: NSEvent) {
        if !didDrag {
            onClick?()
        }
    }
}

@MainActor
private final class FloatingBallContextMenuDelegate: NSObject {
    private weak var controller: FloatingBallController?
    private weak var settings: AppSettings?

    init(controller: FloatingBallController, settings: AppSettings) {
        self.controller = controller
        self.settings = settings
    }

    func showMenu(for panel: NSPanel, event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(menuItem("打开悬浮球设置", "gearshape") { [weak self] in
            self?.controller?.openFloatingBallSettings()
        })
        menu.addItem(menuItem("收起菜单", "chevron.down.circle") { [weak self] in
            self?.controller?.collapseMenu()
        })
        menu.addItem(menuItem("重置位置", "arrow.counterclockwise") { [weak self] in
            self?.controller?.resetPosition()
        })
        menu.addItem(.separator())
        menu.addItem(menuItem("关闭悬浮球", "power") { [weak self] in
            self?.settings?.floatingBallEnabled = false
        })
        guard let view = panel.contentView else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private func menuItem(_ title: String, _ systemImage: String, action: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, action: action)
        item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        return item
    }
}

private final class ClosureMenuItem: NSMenuItem {
    private let closure: () -> Void

    init(title: String, action closure: @escaping () -> Void) {
        self.closure = closure
        super.init(title: title, action: #selector(runClosure), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func runClosure() {
        closure()
    }
}

private struct FloatingBallView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var menuModel: FloatingBallMenuModel
    let performAction: (FloatingBallActionKind) -> Void
    @State private var idlePulse = false
    @State private var menuVisible = false

    private var enabledActions: [FloatingBallAction] {
        Array(settings.floatingBallActions.filter(\.isEnabled).prefix(6))
    }

    private var ballCenter: CGPoint {
        CGPoint(x: 278, y: 204)
    }

    private var ballSize: CGFloat {
        min(max(CGFloat(settings.floatingBallSize), 28), 104)
    }

    private var arcCenter: CGPoint {
        ballCenter
    }

    private var arcIconRadius: CGFloat {
        96
    }

    private var arcStartAngle: Double {
        240
    }

    private var arcEndAngle: Double {
        120
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            menuButtons
                .opacity(menuVisible ? 1 : 0)
                .scaleEffect(menuVisible ? 1 : 0.72, anchor: UnitPoint(x: ballCenter.x / 390, y: ballCenter.y / 340))
                .rotationEffect(.degrees(menuVisible ? 0 : 48), anchor: UnitPoint(x: ballCenter.x / 390, y: ballCenter.y / 340))
                .allowsHitTesting(menuVisible)

            petAvatar
                .frame(width: ballSize, height: ballSize)
                .position(ballCenter)
        }
        .frame(width: 390, height: 340)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
                idlePulse = true
            }
            menuVisible = false
            if menuModel.isExpanded {
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                        menuVisible = true
                    }
                }
            }
        }
        .onChange(of: menuModel.isExpanded) { expanded in
            withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                menuVisible = expanded
            }
        }
    }

    private var menuButtons: some View {
        ZStack(alignment: .topLeading) {
            crescentBase

            ForEach(Array(enabledActions.enumerated()), id: \.element.id) { index, action in
                let point = menuPoint(index: index, count: enabledActions.count)
                Button {
                    performAction(action.kind)
                } label: {
                    Image(systemName: action.kind.systemImage)
                        .font(.system(size: 15.5, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary)
                        .frame(width: 34, height: 34)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.13), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .help(action.kind.title)
                .scaleEffect(menuVisible ? 1 : 0.55)
                .rotationEffect(.degrees(menuVisible ? 0 : 22))
                .position(point)
                .animation(
                    .spring(response: 0.32, dampingFraction: 0.76)
                        .delay(Double(index) * 0.025),
                    value: menuVisible
                )
            }
        }
        .frame(width: 390, height: 340)
    }

    private var crescentBase: some View {
        ZStack {
            FloatingArcBandShape(
                center: arcCenter,
                outerRadius: arcIconRadius + 20,
                innerRadius: arcIconRadius - 20,
                startAngle: arcStartAngle,
                endAngle: arcEndAngle,
                progress: menuVisible ? 1 : 0
            )
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.16), radius: 16, y: 6)
            FloatingArcBandShape(
                center: arcCenter,
                outerRadius: arcIconRadius + 20,
                innerRadius: arcIconRadius - 20,
                startAngle: arcStartAngle,
                endAngle: arcEndAngle,
                progress: menuVisible ? 1 : 0
            )
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            FloatingArcGuideShape(
                center: arcCenter,
                radius: arcIconRadius + 8,
                startAngle: arcStartAngle,
                endAngle: arcEndAngle,
                progress: menuVisible ? 1 : 0
            )
                .stroke(Color.primary.opacity(0.07), lineWidth: 2)
            FloatingArcGuideShape(
                center: arcCenter,
                radius: arcIconRadius - 8,
                startAngle: arcStartAngle,
                endAngle: arcEndAngle,
                progress: menuVisible ? 1 : 0
            )
                .stroke(Color.white.opacity(0.48), lineWidth: 2)
        }
        .frame(width: 390, height: 340)
    }

    private var petAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.cyan.opacity(0.92), .indigo.opacity(0.88)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .stroke(.white.opacity(0.45), lineWidth: 1.5)
            avatarContent
                .padding(settings.floatingBallPetImagePath.isEmpty ? 0 : 7)
        }
        .opacity(settings.floatingBallOpacity)
        .scaleEffect(idlePulse ? 1.035 : 0.985)
        .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
    }

    @ViewBuilder
    private var avatarContent: some View {
        if
            !settings.floatingBallPetImagePath.isEmpty,
            let image = NSImage(contentsOfFile: settings.floatingBallPetImagePath)
        {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(Circle())
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: max(settings.floatingBallSize * 0.42, 12), weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private func menuPoint(index: Int, count: Int) -> CGPoint {
        guard count > 1 else { return pointOnArc(progress: 0.5) }
        let progress = Double(index) / Double(count - 1)
        return pointOnArc(progress: progress)
    }

    private func pointOnArc(progress: Double) -> CGPoint {
        let angle = FloatingArcMath.counterClockwiseAngle(
            from: arcStartAngle,
            to: arcEndAngle,
            progress: progress
        ) * .pi / 180
        return CGPoint(
            x: arcCenter.x + cos(angle) * arcIconRadius,
            y: arcCenter.y + sin(angle) * arcIconRadius
        )
    }
}
