import AppKit
import Combine
import SwiftUI

@MainActor
final class FloatingBallController: ObservableObject {
    private let settings: AppSettings
    private let timerStore: FocusTimerStore
    private let screenshotCaptureController: ScreenshotCaptureController
    private let menuModel = FloatingBallMenuModel()
    private var panel: FloatingBallPanel?
    private var contextMenuDelegate: FloatingBallContextMenuDelegate?
    private var timerDisplayHiddenByUser = false
    private var autoCollapseTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    init(settings: AppSettings, timerStore: FocusTimerStore, screenshotCaptureController: ScreenshotCaptureController) {
        self.settings = settings
        self.timerStore = timerStore
        self.screenshotCaptureController = screenshotCaptureController

        Publishers.CombineLatest4(
            settings.$floatingBallEnabled,
            settings.$floatingBallSize,
            settings.$floatingBallOpacity,
            settings.$floatingBallPetImagePath
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] enabled, _, _, _ in
            self?.syncVisibility(settingsEnabled: enabled)
        }
        .store(in: &cancellables)

        settings.$floatingBallActions
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshContent()
            }
            .store(in: &cancellables)

        Publishers.MergeMany(
            timerStore.$remainingSeconds.map { _ in () }.eraseToAnyPublisher(),
            timerStore.$isRunning.map { _ in () }.eraseToAnyPublisher(),
            timerStore.$isPaused.map { _ in () }.eraseToAnyPublisher(),
            timerStore.$showsFloatingReminder.map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.syncVisibility(settingsEnabled: self?.settings.floatingBallEnabled ?? false)
            self?.updatePanelVisibleBounds()
        }
        .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .focusTimerDidStart)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.timerDisplayHiddenByUser = false
                self?.collapseMenu()
                self?.show()
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
        let visibleHalfWidth = currentBallVisibleHalfWidth
        let origin = CGPoint(
            x: screenFrame.maxX - FloatingBallPanel.ballAnchorX - visibleHalfWidth - 8,
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
        panel.acceptsMouseMovedEvents = true
        panel.visibleHalfWidth = visibleHalfWidth
        panel.visibleHalfHeight = currentBallVisibleHalfHeight
        panel.onClick = { [weak self] in
            self?.handlePanelClick()
        }
        let contextMenuDelegate = FloatingBallContextMenuDelegate(
            controller: self,
            settings: settings,
            timerStore: timerStore
        )
        panel.contextMenuDelegate = contextMenuDelegate
        self.contextMenuDelegate = contextMenuDelegate
        self.panel = panel
    }

    private func refreshContent() {
        guard let panel else { return }
        menuModel.isExpanded = panel.isMenuExpanded
        updatePanelVisibleBounds()
        let content = FloatingBallView(
            settings: settings,
            timerStore: timerStore,
            menuModel: menuModel,
            setExpanded: { [weak self] expanded in self?.setMenuExpanded(expanded) },
            keepExpanded: { [weak self] in self?.keepMenuExpanded() },
            registerInteraction: { [weak self] in self?.registerMenuInteraction() },
            performAction: { [weak self] action in self?.perform(action) }
        )
        let hostingView = FloatingBallHostingView(rootView: content)
        hostingView.visibleHalfWidth = panel.visibleHalfWidth
        hostingView.visibleHalfHeight = panel.visibleHalfHeight
        hostingView.onHoverChanged = { [weak self] isOverBall in
            self?.handleBallHoverChanged(isOverBall)
        }
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
    }

    private func updatePanelVisibleBounds() {
        panel?.visibleHalfWidth = currentBallVisibleHalfWidth
        panel?.visibleHalfHeight = currentBallVisibleHalfHeight
    }

    private var currentBallSize: CGFloat {
        min(max(CGFloat(settings.floatingBallSize), 28), 104)
    }

    private var currentBallVisibleHalfWidth: CGFloat {
        let ballSize = currentBallSize
        if timerStore.isActive || timerStore.showsFloatingReminder {
            return max(ballSize * 1.72, 112) / 2
        }
        return ballSize / 2
    }

    private var currentBallVisibleHalfHeight: CGFloat {
        currentBallSize / 2
    }

    private func setMenuExpanded(_ expanded: Bool) {
        guard let panel else { return }
        panel.isMenuExpanded = expanded
        menuModel.isExpanded = panel.isMenuExpanded
        expanded ? scheduleAutoCollapse() : cancelAutoCollapse()
    }

    private func registerMenuInteraction() {
        guard panel?.isMenuExpanded == true else { return }
        scheduleAutoCollapse()
    }

    private func keepMenuExpanded() {
        guard panel?.isMenuExpanded == true else { return }
        cancelAutoCollapse()
    }

    private func handlePanelClick() {
        if panel?.isMenuExpanded == true {
            collapseMenu()
        } else {
            setMenuExpanded(true)
        }
    }

    private func handleBallHoverChanged(_ isOverBall: Bool) {
        if isOverBall {
            setMenuExpanded(true)
        } else {
            registerMenuInteraction()
        }
    }

    private func scheduleAutoCollapse() {
        cancelAutoCollapse()
        autoCollapseTimer = Timer.scheduledTimer(withTimeInterval: 3.2, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.collapseMenu()
            }
        }
    }

    private func cancelAutoCollapse() {
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil
    }

    private func syncVisibility(settingsEnabled: Bool) {
        let shouldShowTimerDisplay = (timerStore.isActive || timerStore.showsFloatingReminder) && !timerDisplayHiddenByUser
        if settingsEnabled || shouldShowTimerDisplay {
            if panel?.isVisible == true {
                updatePanelVisibleBounds()
            } else {
                show()
            }
        } else {
            hide()
        }
    }

    fileprivate func collapseMenu() {
        guard let panel else { return }
        panel.isMenuExpanded = false
        menuModel.isExpanded = false
        cancelAutoCollapse()
    }

    fileprivate func resetPosition() {
        guard let panel else { return }
        let screenFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .init(x: 0, y: 0, width: 1280, height: 800)
        panel.setFrameOrigin(
            CGPoint(
                x: screenFrame.maxX - FloatingBallPanel.ballAnchorX - panel.visibleHalfWidth - 8,
                y: screenFrame.midY - FloatingBallPanel.ballAnchorY
            )
        )
    }

    fileprivate func openFloatingBallSettings() {
        NotificationCenter.default.post(name: .openFloatingBallSettings, object: nil)
    }

    fileprivate func openFocusTimerLauncher() {
        collapseMenu()
        NotificationCenter.default.post(name: .showFocusTimerLauncher, object: nil)
    }

    fileprivate func closeFromContextMenu() {
        if timerStore.isActive || timerStore.showsFloatingReminder {
            timerDisplayHiddenByUser = true
            hide()
        } else {
            settings.floatingBallEnabled = false
        }
    }

    fileprivate func stopFocusTimerFromContextMenu() {
        timerStore.stop()
        timerDisplayHiddenByUser = false
        syncVisibility(settingsEnabled: settings.floatingBallEnabled)
    }

    private func perform(_ kind: FloatingBallActionKind) {
        collapseMenu()
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
            NotificationCenter.default.post(name: .showFocusTimerLauncher, object: nil)
        case .timer:
            NotificationCenter.default.post(name: .showFocusTimerLauncher, object: nil)
        case .focus:
            NotificationCenter.default.post(name: .showFocusTimerLauncher, object: nil)
        }
    }
}

@MainActor
private final class FloatingBallMenuModel: ObservableObject {
    @Published var isExpanded = false
}

private final class FloatingBallPanel: NSPanel {
    static let ballAnchorX: CGFloat = 278
    static let ballAnchorY: CGFloat = 204

    var isMenuExpanded = false
    var onClick: (() -> Void)?
    var visibleHalfWidth: CGFloat = 32
    var visibleHalfHeight: CGFloat = 32
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
            let edgePadding: CGFloat = 4
            let minX = visibleFrame.minX - Self.ballAnchorX + visibleHalfWidth + edgePadding
            let maxX = visibleFrame.maxX - Self.ballAnchorX - visibleHalfWidth - edgePadding
            let minY = visibleFrame.minY - Self.ballAnchorY + visibleHalfHeight + edgePadding
            let maxY = visibleFrame.maxY - Self.ballAnchorY - visibleHalfHeight - edgePadding
            nextFrame.origin.x = min(max(nextFrame.origin.x, minX), maxX)
            nextFrame.origin.y = min(max(nextFrame.origin.y, minY), maxY)
        }

        setFrameOrigin(nextFrame.origin)
    }

    override func mouseUp(with event: NSEvent) {
        if !didDrag {
            onClick?()
        }
    }

}

private final class FloatingBallHostingView<Content: View>: NSHostingView<Content> {
    var onHoverChanged: ((Bool) -> Void)?
    var visibleHalfWidth: CGFloat = 32
    var visibleHalfHeight: CGFloat = 32
    private var trackingArea: NSTrackingArea?
    private var isMouseOverVisibleBall = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        updateVisibleBallHoverState(for: convert(event.locationInWindow, from: nil))
        super.mouseMoved(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        updateVisibleBallHoverState(for: convert(event.locationInWindow, from: nil))
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        updateVisibleBallHoverState(false)
        super.mouseExited(with: event)
    }

    private func updateVisibleBallHoverState(for point: CGPoint) {
        let normalizedX = (point.x - Self.ballAnchorX) / visibleHalfWidth
        let normalizedY = (point.y - Self.ballAnchorY) / visibleHalfHeight

        if visibleHalfWidth <= visibleHalfHeight + 2 {
            updateVisibleBallHoverState((normalizedX * normalizedX + normalizedY * normalizedY) <= 1)
            return
        }

        let hitRect = NSRect(
            x: Self.ballAnchorX - visibleHalfWidth,
            y: Self.ballAnchorY - visibleHalfHeight,
            width: visibleHalfWidth * 2,
            height: visibleHalfHeight * 2
        )
        updateVisibleBallHoverState(hitRect.contains(point))
    }

    private func updateVisibleBallHoverState(_ isHovering: Bool) {
        guard isMouseOverVisibleBall != isHovering else { return }
        isMouseOverVisibleBall = isHovering
        onHoverChanged?(isHovering)
    }

    private static var ballAnchorX: CGFloat { FloatingBallPanel.ballAnchorX }
    private static var ballAnchorY: CGFloat { FloatingBallPanel.ballAnchorY }
}

@MainActor
private final class FloatingBallContextMenuDelegate: NSObject {
    private weak var controller: FloatingBallController?
    private weak var settings: AppSettings?
    private weak var timerStore: FocusTimerStore?

    init(controller: FloatingBallController, settings: AppSettings, timerStore: FocusTimerStore) {
        self.controller = controller
        self.settings = settings
        self.timerStore = timerStore
    }

    func showMenu(for panel: NSPanel, event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(menuItem("打开时间节律", "timer") { [weak self] in
            self?.controller?.openFocusTimerLauncher()
        })
        if timerStore?.isActive == true || timerStore?.showsFloatingReminder == true {
            menu.addItem(menuItem("关闭番茄钟", "timer.circle.fill") { [weak self] in
                self?.controller?.stopFocusTimerFromContextMenu()
            })
        }
        menu.addItem(.separator())
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
            self?.controller?.closeFromContextMenu()
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
    @ObservedObject var timerStore: FocusTimerStore
    @ObservedObject var menuModel: FloatingBallMenuModel
    let setExpanded: (Bool) -> Void
    let keepExpanded: () -> Void
    let registerInteraction: () -> Void
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

    private var ballWidth: CGFloat {
        timerStore.isActive || timerStore.showsFloatingReminder ? max(ballSize * 1.72, 112) : ballSize
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
                .onHover { hovering in
                    hovering ? keepExpanded() : registerInteraction()
                }

            petAvatar
                .frame(width: ballWidth, height: ballSize)
                .contentShape(RoundedRectangle(cornerRadius: ballSize / 2, style: .continuous))
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
            RoundedRectangle(cornerRadius: ballSize / 2, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: timerGradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: ballSize / 2, style: .continuous)
                .stroke(.white.opacity(0.45), lineWidth: 1.5)
            if timerStore.isActive || timerStore.showsFloatingReminder {
                timerProgressOverlay
            }
            avatarContent
                .padding(settings.floatingBallPetImagePath.isEmpty ? 0 : 7)
        }
        .opacity(settings.floatingBallOpacity)
        .scaleEffect(idlePulse ? 1.035 : 0.985)
        .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
    }

    private var timerGradientColors: [Color] {
        guard let mode = timerStore.mode else {
            return [.cyan.opacity(0.92), .indigo.opacity(0.88)]
        }
        switch mode {
        case .focus:
            return [.orange.opacity(0.95), .red.opacity(0.86)]
        case .breakTime:
            return [.mint.opacity(0.95), .teal.opacity(0.88)]
        case .quickTimer:
            return [.cyan.opacity(0.94), .blue.opacity(0.88)]
        }
    }

    private var timerProgressOverlay: some View {
        VStack(spacing: 0) {
            Spacer()
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.22))
                    Capsule()
                        .fill(Color.white.opacity(0.72))
                        .frame(width: proxy.size.width * max(timerStore.progress, 0.02))
                }
            }
            .frame(height: 2)
            .padding(.horizontal, 14)
            .padding(.bottom, 3)
        }
    }

    @ViewBuilder
    private var avatarContent: some View {
        if
            !(timerStore.isActive || timerStore.showsFloatingReminder),
            !settings.floatingBallPetImagePath.isEmpty,
            let image = NSImage(contentsOfFile: settings.floatingBallPetImagePath)
        {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(Circle())
        } else if timerStore.isActive || timerStore.showsFloatingReminder {
            HStack(spacing: 7) {
                Image(systemName: timerStore.mode?.icon ?? "timer")
                    .font(.system(size: 17, weight: .bold))
                Text(timerStore.remainingSeconds > 0 ? timerStore.displayTime : "完成")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .offset(y: -2)
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
