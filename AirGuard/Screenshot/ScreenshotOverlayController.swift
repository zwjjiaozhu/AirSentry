import AppKit
import ApplicationServices
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class ScreenshotOverlayController {
    private var windows: [ScreenshotOverlayWindow] = []
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private let escapeHotKeyIdentifier = GlobalHotKeyIdentifier(signature: screenshotEscapeHotKeySignature, id: 1)
    private let onAction: (ScreenshotResultAction, ScreenshotCapturePayload) -> Void
    private let onCancel: () -> Void
    private var didFinish = false

    init(onAction: @escaping (ScreenshotResultAction, ScreenshotCapturePayload) -> Void, onCancel: @escaping () -> Void) {
        self.onAction = onAction
        self.onCancel = onCancel
    }

    func show() {
        installKeyMonitors()

        windows = NSScreen.screens.map { screen in
            let screenImage = ScreenshotImageCapturer.capture(rect: screen.frame)
            let windowTargets = ScreenshotWindowTargetDetector.targets(on: screen.frame)
            let view = ScreenshotOverlayView(
                screenFrame: screen.frame,
                screenImage: screenImage,
                captureTargets: windowTargets,
                perform: { [weak self] action, payload in self?.perform(action, payload: payload) },
                cancel: { [weak self] in self?.cancel() }
            )

            let window = ScreenshotOverlayWindow(screen: screen)

            // 容器视图：定格背景层(NSImageView) + 交互层(NSHostingView)
            // NSImageView 直接用 draw 渲染，不经过 SwiftUI 布局系统，无 CALayer 隐式动画
            let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))

            let backgroundView = NSImageView(frame: container.bounds)
            backgroundView.image = screenImage
            backgroundView.imageScaling = .scaleProportionallyUpOrDown
            backgroundView.imageAlignment = .alignCenter
            backgroundView.imageFrameStyle = .none
            backgroundView.autoresizingMask = [.width, .height]
            container.addSubview(backgroundView)

            let hostingView = NSHostingView(rootView: view)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: container.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])

            window.contentView = container
            return window
        }

        // 强制布局完成后再显示，避免 NSHostingView 首次布局的异步过渡
        windows.forEach { window in
            window.contentView?.layoutSubtreeIfNeeded()
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            windows.forEach { $0.orderFrontRegardless() }
            windows.first?.makeKey()
        }
    }

    private func perform(_ action: ScreenshotResultAction, payload: ScreenshotCapturePayload) {
        guard !didFinish else { return }
        didFinish = true
        DispatchQueue.main.async { [weak self, onAction] in
            self?.closeWindows()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                onAction(action, payload)
            }
        }
    }

    private func cancel() {
        guard !didFinish else { return }
        didFinish = true
        closeWindows()
        onCancel()
    }

    private func closeWindows() {
        removeKeyMonitors()
        windows.forEach { window in
            window.makeFirstResponder(nil)
            window.contentView = nil
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
    }

    private func installKeyMonitors() {
        removeKeyMonitors()

        let status = GlobalHotKeyManager.shared.register(
            shortcut: KeyboardShortcut(keyCode: UInt32(kVK_Escape), modifiers: 0),
            signature: screenshotEscapeHotKeySignature,
            id: 1
        ) { [weak self] in
            self?.cancel()
        }
        if status != noErr {
            NSLog("AirSentry screenshot escape hotkey registration failed: \(status)")
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return event }
            Task { @MainActor [weak self] in
                self?.cancel()
            }
            return nil
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return }
            Task { @MainActor [weak self] in
                self?.cancel()
            }
        }
    }

    private func removeKeyMonitors() {
        GlobalHotKeyManager.shared.unregister(escapeHotKeyIdentifier)

        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
    }
}

private let screenshotEscapeHotKeySignature: OSType = 0x53434553

final class ScreenshotOverlayWindow: NSPanel {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .screenSaver
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        NotificationCenter.default.post(name: .screenshotOverlayCancelRequested, object: nil)
    }
}

private struct ScreenshotOverlayView: View {
    let screenFrame: CGRect
    let screenImage: NSImage?
    let captureTargets: [ScreenshotCaptureTarget]
    let perform: (ScreenshotResultAction, ScreenshotCapturePayload) -> Void
    let cancel: () -> Void

    @State private var startPoint: CGPoint?
    @State private var currentPoint: CGPoint?
    @State private var selectedRect: CGRect?
    @State private var interactionStartRect: CGRect?
    @State private var selectedTool: ScreenshotAnnotationTool?
    @State private var selectedColor: ScreenshotAnnotationColor = .red
    @State private var selectedLineWidth: CGFloat = 3
    @State private var selectedFontSize: CGFloat = 18
    @State private var selectedTextColor: Color = .red
    @State private var selectedFontName = ScreenshotTextStyle.defaultFontName
    @State private var selectedTextBold = true
    @State private var selectedTextItalic = false
    @State private var annotations: [ScreenshotAnnotation] = []
    @State private var redoAnnotations: [ScreenshotAnnotation] = []
    @State private var selectedAnnotationID: UUID?
    @State private var draftAnnotation: ScreenshotAnnotation?
    @State private var movingTextAnnotationStartPoint: CGPoint?
    @State private var movingAnnotationStartPoints: [CGPoint]?
    @State private var resizingAnnotationStartPoints: [CGPoint]?
    @State private var resizingTextAnnotationID: UUID?
    @State private var resizingTextStartPoint: CGPoint?
    @State private var resizingTextStartSize: CGSize?
    @State private var resizingTextStartFontSize: CGFloat?
    @State private var resizingTextHandle: TextResizeHandle?
    @State private var scalingTextAnnotationID: UUID?
    @State private var scalingTextStartSize: CGSize?
    @State private var scalingTextStartFontSize: CGFloat?
    @State private var isTextCursorPushed = false
    @State private var selectionCursorPushed: NSCursor?
    @State private var hoveredTargetID: ScreenshotCaptureTarget.ID?
    @State private var mosaicSampler: ScreenshotOverlayMosaicSampler?
    @State private var colorPanelObserver: NSObjectProtocol?
    @State private var isShortcutHintHiddenByHover = false
    @FocusState private var focusedTextAnnotationID: UUID?
    @State private var pendingFocusAnnotationID: UUID?
    @State private var ocrResult: OCRRecognitionResult?
    @State private var isOCRRecognizing = false
    @State private var selectedOCRTextIDs: Set<UUID> = []
    @State private var selectedOCRTextRanges: [UUID: Range<Int>] = [:]
    @State private var selectedQRCodeID: UUID?
    @State private var ocrSelectionStart: CGPoint?
    @State private var ocrSelectionCurrent: CGPoint?
    @State private var ocrRecognitionToken = UUID()
    @State private var copyFeedbackMessage: String?
    @State private var copyFeedbackToken = UUID()
    @State private var showAllOCRTextItems = false
    private let textBorderHitPadding: CGFloat = 8

    // Accessibility 控件检测相关状态
    @State private var controlHoverTarget: ScreenshotCaptureTarget?
    @State private var lastMousePoint: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if let selection = activeSelectionRect(in: proxy.size) {
                    SelectionShape(selection: selection)
                        .fill(style: FillStyle(eoFill: true))
                        .foregroundStyle(Color.black.opacity(0.34))

                    selectionLayer(selection, in: proxy.size)

                    Text("\(Int(selection.width)) x \(Int(selection.height))")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.66), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .position(x: selection.minX + 48, y: max(18, selection.minY - 16))

                    if selectedRect != nil {
                        ScreenshotSelectionToolbar(
                            selectedTool: $selectedTool,
                            selectedColor: $selectedColor,
                            selectedLineWidth: $selectedLineWidth,
                            selectedFontSize: $selectedFontSize,
                            controlMode: toolbarControlMode,
                            canUndo: !annotations.isEmpty,
                            canRedo: !redoAnnotations.isEmpty,
                            setColor: updateSelectedColor,
                            setLineWidth: updateSelectedLineWidth,
                            setFontSize: updateSelectedFontSize,
                            selectedTextColor: $selectedTextColor,
                            selectedFontName: $selectedFontName,
                            selectedTextBold: $selectedTextBold,
                            selectedTextItalic: $selectedTextItalic,
                            setTextColor: updateSelectedTextColor,
                            setFontName: updateSelectedFontName,
                            setTextBold: updateSelectedTextBold,
                            setTextItalic: updateSelectedTextItalic,
                            openTextColorPanel: openTextColorPanel,
                            isOCREnabled: isOCRRecognizing || ocrResult != nil,
                            hasOCRText: ocrResult?.textItems.isEmpty == false,
                            showAllOCRTextItems: $showAllOCRTextItems,
                            copyAllOCRText: copyAllOCRText
                        ) { toolbarAction in
                            handleToolbarAction(toolbarAction, selection: selection)
                        }
                        .position(toolbarPosition(for: selection, in: proxy.size))
                        .zIndex(20)
                    }
                } else if let target = hoveredTarget {
                    // 悬停窗口时挖出高亮区域，恢复原始亮度
                    SelectionShape(selection: target.screenRect)
                        .fill(style: FillStyle(eoFill: true))
                        .foregroundStyle(Color.black.opacity(0.34))
                } else {
                    Color.black.opacity(0.34)
                }

                if selectedRect == nil && startPoint == nil {
                    targetHighlightLayer()
                }

                ZStack(alignment: .bottomTrailing) {
                    Rectangle()
                        .fill(Color.white.opacity(0.001))
                        .frame(width: 340, height: 360)
                        .onHover { hovering in
                            isShortcutHintHiddenByHover = hovering
                        }

                    ScreenshotShortcutHintPanel()
                        .opacity(isShortcutHintHiddenByHover ? 0 : 1)
                        .allowsHitTesting(false)
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: shortcutHintAlignment(for: activeSelectionRect(in: proxy.size), in: proxy.size)
                )
                .padding(shortcutHintPadding(for: activeSelectionRect(in: proxy.size), in: proxy.size))
                .zIndex(0)
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .gesture(initialSelectionGesture(in: proxy.size))
            .onReceive(NotificationCenter.default.publisher(for: .screenshotOverlayCancelRequested)) { _ in
                cancel()
            }
            .onChange(of: selectedTool) { tool in
                if tool == nil {
                    selectedAnnotationID = nil
                    focusedTextAnnotationID = nil
                    pendingFocusAnnotationID = nil
                }
                if tool != .text {
                    finishTextEditing()
                    resetTextCursor()
                }
            }
            .onChange(of: focusedTextAnnotationID) { annotationID in
                syncSelectionWithFocusedText(annotationID)
            }
            .onDisappear {
                resetTextCursor()
                popSelectionCursor()
                movingAnnotationStartPoints = nil
                resizingAnnotationStartPoints = nil

                NSColorPanel.shared.orderOut(nil)
                if let colorPanelObserver {
                    NotificationCenter.default.removeObserver(colorPanelObserver)
                    self.colorPanelObserver = nil
                }
            }
            .onAppear {
                if mosaicSampler == nil, let screenImage {
                    mosaicSampler = ScreenshotOverlayMosaicSampler(image: screenImage)
                }
                // 进入截图模式时优先高亮鼠标所在/最近的窗口，避免前层小浮窗抢默认目标。
                if hoveredTargetID == nil {
                    hoveredTargetID = initialHoverTargetID()
                }
            }
            .background(ScreenshotOverlayKeyCatcher(isEnabled: focusedTextAnnotationID == nil) { event in
                handleKeyDown(event, in: proxy.size)
            })
            .background(ScreenshotMouseTracker { point in
                updateHoveredTarget(at: point)
                updateSelectionCursor(at: point)
            })
        }
    }

    private func initialSelectionGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: selectedTool == .text ? 0 : 0, coordinateSpace: .local)
            .onChanged { value in
                guard selectedRect == nil else { return }
                if isClickCandidate(value) {
                    startPoint = nil
                    currentPoint = nil
                    return
                }

                hoveredTargetID = nil
                controlHoverTarget = nil
                if startPoint == nil {
                    startPoint = value.startLocation
                }
                currentPoint = value.location
            }
            .onEnded { value in
                guard selectedRect == nil else { return }
                if isClickCandidate(value) {
                    if let target = hoveredTarget {
                        selectedRect = boundedTargetRect(target.screenRect, in: size)
                        hoveredTargetID = nil
                        controlHoverTarget = nil
                        startPoint = nil
                        currentPoint = nil
                        return
                    }
                }

                currentPoint = value.location
                guard let selection = selectionRect(in: size) else {
                    startPoint = nil
                    currentPoint = nil
                    return
                }
                selectedRect = selection
                startPoint = nil
                currentPoint = nil
            }
    }

    private func targetHighlightLayer() -> some View {
        ZStack(alignment: .topLeading) {
            if let target = hoveredTarget {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.92), lineWidth: 2)
                    .frame(width: target.screenRect.width, height: target.screenRect.height)
                    .position(x: target.screenRect.midX, y: target.screenRect.midY)
                    .shadow(color: Color.accentColor.opacity(0.85), radius: 7)
                    .allowsHitTesting(false)

                Text(target.actionTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.66), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .position(x: target.screenRect.minX + 48, y: max(18, target.screenRect.minY - 16))
                    .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(false)
    }

    private func selectionLayer(_ selection: CGRect, in size: CGSize) -> some View {
        ZStack {
            annotationCanvas(selection)

            if selectedTool == nil || selectedTool == .cursor {
                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: selection.width, height: selection.height)
                    .position(x: selection.midX, y: selection.midY)
                    .gesture(cursorGesture(in: size, selection: selection))
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: selection.width, height: selection.height)
                    .position(x: selection.midX, y: selection.midY)
                    .gesture(annotationGesture(in: selection))
            }

            textAnnotationLayer(selection)

            ocrContentLayer(selection)

            annotationHandlesLayer(selection)

            Rectangle()
                .stroke(Color.accentColor, lineWidth: 2)
                .frame(width: selection.width, height: selection.height)
                .position(x: selection.midX, y: selection.midY)
                .allowsHitTesting(false)

            ForEach(ResizeHandle.allCases) { handle in
                Group {
                    if handle.isCorner {
                        Circle()
                            .fill(.white)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 1))
                    } else {
                        Capsule()
                            .fill(.white)
                            .frame(
                                width: handle == .top || handle == .bottom ? 22 : 5,
                                height: handle == .top || handle == .bottom ? 5 : 22
                            )
                            .overlay(Capsule().stroke(.black.opacity(0.35), lineWidth: 1))
                    }
                }
                .position(handle.point(in: selection))
                .gesture(resizeGesture(handle: handle, in: size))
            }
        }
    }

    private func annotationCanvas(_ selection: CGRect) -> some View {
        Canvas { context, _ in
            for annotation in annotations {
                if annotation.tool != .text {
                    draw(annotation, selection: selection, in: &context)
                }
                drawSelectionOutline(for: annotation, in: &context)
            }
            if let draftAnnotation {
                draw(draftAnnotation, selection: selection, in: &context)
            }
        }
        .frame(width: selection.width, height: selection.height)
        .position(x: selection.midX, y: selection.midY)
        .allowsHitTesting(false)
    }

    private func draw(_ annotation: ScreenshotAnnotation, selection: CGRect, in context: inout GraphicsContext) {
        var path = Path()
        let stroke = StrokeStyle(lineWidth: annotation.lineWidth, lineCap: .round, lineJoin: .round)

        switch annotation.tool {
        case .text:
            guard let origin = annotation.points.first else { return }
            context.draw(
                Text(annotation.text)
                    .font(annotation.swiftUIFont)
                    .foregroundColor(annotation.effectiveSwiftUIColor),
                at: origin,
                anchor: .topLeading
            )
        case .pen:
            guard let firstPoint = annotation.points.first else { return }
            path.move(to: firstPoint)
            annotation.points.dropFirst().forEach { path.addLine(to: $0) }
            context.stroke(path, with: .color(annotation.color.swiftUIColor), style: stroke)
        case .mosaic:
            let blockSize = max(10, annotation.lineWidth * 5)
            guard let mosaicSampler else {
                drawMosaicFallback(annotation, blockSize: blockSize, in: &context)
                return
            }
            for point in annotation.points {
                let rect = CGRect(
                    x: point.x - blockSize / 2,
                    y: point.y - blockSize / 2,
                    width: blockSize,
                    height: blockSize
                )
                let sampleRect = rect.offsetBy(dx: selection.minX, dy: selection.minY)
                context.fill(
                    Path(rect),
                    with: .color(mosaicSampler.averageColor(in: sampleRect))
                )
            }
        case .line:
            guard let start = annotation.points.first,
                  let end = annotation.points.last else { return }
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(annotation.color.swiftUIColor), style: stroke)
        case .arrow:
            guard let start = annotation.points.first,
                  let end = annotation.points.last else { return }
            path.move(to: start)
            path.addLine(to: end)
            let heads = arrowHeadPoints(from: start, to: end, lineWidth: annotation.lineWidth)
            path.move(to: end)
            path.addLine(to: heads.0)
            path.move(to: end)
            path.addLine(to: heads.1)
            context.stroke(path, with: .color(annotation.color.swiftUIColor), style: stroke)
        case .rectangle:
            guard let rect = localRect(for: annotation) else { return }
            path.addRect(rect)
            context.stroke(path, with: .color(annotation.color.swiftUIColor), style: stroke)
        case .ellipse:
            guard let rect = localRect(for: annotation) else { return }
            path.addEllipse(in: rect)
            context.stroke(path, with: .color(annotation.color.swiftUIColor), style: stroke)
        }
    }

    private func drawMosaicFallback(
        _ annotation: ScreenshotAnnotation,
        blockSize: CGFloat,
        in context: inout GraphicsContext
    ) {
        var path = Path()
        for point in annotation.points {
            path.addRect(CGRect(
                x: point.x - blockSize / 2,
                y: point.y - blockSize / 2,
                width: blockSize,
                height: blockSize
            ))
        }
        context.fill(path, with: .color(.black.opacity(0.28)))
    }

    private func drawSelectionOutline(for annotation: ScreenshotAnnotation, in context: inout GraphicsContext) {
        // 文本框的选中虚线由 TextField 自己的 overlay 绘制。
        // 如果这里也绘制一次，文本标注会出现两层虚线。
        guard annotation.tool != .text,
              selectedAnnotationID == annotation.id,
              let rect = annotationBounds(annotation)?.insetBy(dx: -4, dy: -4) else { return }
        var path = Path()
        path.addRect(rect)
        context.stroke(path, with: .color(.accentColor.opacity(0.90)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
    }

    private func textAnnotationLayer(_ selection: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach($annotations) { $annotation in
                if shouldShowTextAnnotation(annotation), let origin = annotation.points.first {
                    TextField("文字", text: $annotation.text)
                        .textFieldStyle(.plain)
                        .focused($focusedTextAnnotationID, equals: annotation.id)
                        .font(annotation.swiftUIFont)
                        .foregroundStyle(annotation.effectiveSwiftUIColor)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 2)
                        .frame(
                            width: textBounds(for: annotation).width,
                            height: textBounds(for: annotation).height,
                            alignment: .leading
                        )
                        .background(
                            selectedAnnotationID == annotation.id ? Color.black.opacity(0.14) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(
                                    selectedAnnotationID == annotation.id ? Color.accentColor.opacity(0.90) : Color.clear,
                                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                                )
                        )
                        .overlay {
                            if selectedAnnotationID == annotation.id {
                                ZStack {
                                    textBorderDragLayer(for: annotation, in: selection)
                                    textSelectionControls(for: annotation)
                                }
                            }
                        }
                        .position(x: origin.x + textBounds(for: annotation).width / 2,
                                  y: origin.y + textBounds(for: annotation).height / 2)
                        .onTapGesture {
                            selectAnnotation(annotation)
                        }
                        .onAppear {
                            if annotation.id == pendingFocusAnnotationID {
                                DispatchQueue.main.async {
                                    selectedAnnotationID = annotation.id
                                    focusedTextAnnotationID = annotation.id
                                    pendingFocusAnnotationID = nil
                                }
                            }
                        }
                }
            }
        }
        .frame(width: selection.width, height: selection.height)
        .position(x: selection.midX, y: selection.midY)
    }

    private func ocrContentLayer(_ selection: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            if isOCRRecognizing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在识别文字和二维码...")
                        .font(.system(size: 12.5, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .foregroundStyle(.white)
                .position(x: selection.width / 2, y: 28)
            }

            if let ocrResult {
                ForEach(ocrResult.textItems) { item in
                    let rect = localOCRRect(item.boundingBox, in: selection.size)
                    if showAllOCRTextItems {
                        ocrTextItemView(item, rect: rect, isSelected: false)
                    }
                    if let range = selectedOCRTextRanges[item.id],
                       let selectedRect = ocrTextRangeRect(range, item: item, itemRect: rect) {
                        ocrTextItemView(item, rect: selectedRect, isSelected: true)
                    }
                }

                ForEach(ocrResult.qrCodeItems) { item in
                    let rect = localOCRRect(item.boundingBox, in: selection.size)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.blue.opacity(0.95), lineWidth: selectedQRCodeID == item.id ? 3 : 2)
                        .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .frame(width: max(24, rect.width), height: max(24, rect.height))
                        .position(x: rect.midX, y: rect.midY)
                        .onTapGesture {
                            selectedQRCodeID = item.id
                            selectedOCRTextIDs.removeAll()
                            selectedOCRTextRanges.removeAll()
                        }
                        .zIndex(2)

                    Label("二维码", systemImage: "qrcode")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.blue.opacity(0.9), in: Capsule())
                        .foregroundStyle(.white)
                        .position(x: rect.midX, y: max(12, rect.minY - 13))
                        .allowsHitTesting(false)
                        .zIndex(2)
                }

                if let item = selectedQRCodeItem(in: ocrResult) {
                    qrCodeActionBar(for: item, selectionSize: selection.size)
                        .zIndex(3)
                }

                if let selectionRect = currentOCRSelectionRect {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.13))
                        .overlay(Rectangle().stroke(Color.accentColor.opacity(0.82), lineWidth: 1))
                        .frame(width: selectionRect.width, height: selectionRect.height)
                        .position(x: selectionRect.midX, y: selectionRect.midY)
                        .allowsHitTesting(false)
                }

                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: selection.width, height: selection.height)
                    .gesture(ocrSelectionGesture(in: selection.size))
                    .zIndex(1)
            }

            if let copyFeedbackMessage {
                Text(copyFeedbackMessage)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .position(x: selection.width / 2, y: 28)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(4)
            }
        }
        .frame(width: selection.width, height: selection.height)
        .position(x: selection.midX, y: selection.midY)
    }

    private func qrCodeActionBar(for item: OCRQRCodeItem, selectionSize: CGSize) -> some View {
        let rect = localOCRRect(item.boundingBox, in: selectionSize)
        return HStack(spacing: 6) {
            if let url = item.url {
                Button {
                    openQRCodeURL(url)
                } label: {
                    Label("打开", systemImage: "safari")
                }
            }

            Button {
                copyToPasteboard(item.payload)
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .position(
            x: min(max(rect.midX, 70), selectionSize.width - 70),
            y: min(selectionSize.height - 22, rect.maxY + 26)
        )
    }

    private func openQRCodeURL(_ url: URL) {
        cancel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NSWorkspace.shared.open(url)
        }
    }

    private func ocrTextItemView(_ item: OCRTextItem, rect: CGRect, isSelected: Bool) -> some View {
        let fillColor = isSelected ? Color.accentColor.opacity(0.34) : Color.accentColor.opacity(0.17)
        let strokeColor = isSelected ? Color.accentColor.opacity(0.95) : Color.accentColor.opacity(0.45)

        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(fillColor)
            .frame(width: max(1, rect.width), height: max(1, rect.height))
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(strokeColor, lineWidth: isSelected ? 1.2 : 1)
            )
            .shadow(color: isSelected ? Color.accentColor.opacity(0.30) : Color.clear, radius: 5, y: 1)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }

    private var currentOCRSelectionRect: CGRect? {
        guard let start = ocrSelectionStart,
              let current = ocrSelectionCurrent else { return nil }
        let x = min(start.x, current.x)
        let y = min(start.y, current.y)
        let maxX = max(start.x, current.x)
        let maxY = max(start.y, current.y)
        let rect = CGRect(x: x, y: y, width: maxX - x, height: maxY - y)
        return rect.width >= 2 || rect.height >= 2 ? rect : nil
    }

    private func localOCRRect(_ normalizedBoundingBox: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: normalizedBoundingBox.minX * size.width,
            y: (1 - normalizedBoundingBox.maxY) * size.height,
            width: normalizedBoundingBox.width * size.width,
            height: normalizedBoundingBox.height * size.height
        )
    }

    private func selectedQRCodeItem(in result: OCRRecognitionResult) -> OCRQRCodeItem? {
        guard let selectedQRCodeID else { return nil }
        return result.qrCodeItems.first { $0.id == selectedQRCodeID }
    }

    private func updateSelectedOCRText(in size: CGSize) {
        guard let result = ocrResult else { return }
        guard let start = ocrSelectionStart,
              let current = ocrSelectionCurrent,
              currentOCRSelectionRect != nil else { return }

        if let ranges = ocrReadingOrderRanges(from: start, to: current, in: size, items: result.textItems) {
            selectedOCRTextRanges = ranges
            selectedOCRTextIDs = Set(ranges.keys)
            return
        }

        guard let rect = currentOCRSelectionRect else { return }
        let ranges = ocrRectIntersectionRanges(in: rect, size: size, items: result.textItems)
        selectedOCRTextRanges = ranges
        selectedOCRTextIDs = Set(ranges.keys)
    }

    private func selectOCRLine(at point: CGPoint, in size: CGSize) {
        guard let item = ocrTextItem(at: point, in: size) else {
            selectedOCRTextIDs.removeAll()
            selectedOCRTextRanges.removeAll()
            return
        }
        selectedOCRTextIDs = [item.id]
        selectedOCRTextRanges = [item.id: 0..<item.text.count]
    }

    private func ocrTextRange(in item: OCRTextItem, itemRect: CGRect, selectionRect: CGRect) -> Range<Int>? {
        let count = item.text.count
        guard count > 0, itemRect.width > 0 else { return nil }
        let overlap = itemRect.intersection(selectionRect)
        guard overlap.width > 0, overlap.height > 0 else { return nil }

        let startRatio = ((overlap.minX - itemRect.minX) / itemRect.width).clamped(to: 0...1)
        let endRatio = ((overlap.maxX - itemRect.minX) / itemRect.width).clamped(to: 0...1)
        var start = Int(floor(startRatio * CGFloat(count)))
        var end = Int(ceil(endRatio * CGFloat(count)))
        start = start.clamped(to: 0...count)
        end = end.clamped(to: 0...count)
        guard start < end else { return nil }
        return start..<end
    }

    private func ocrRectIntersectionRanges(in selectionRect: CGRect, size: CGSize, items: [OCRTextItem]) -> [UUID: Range<Int>] {
        var ranges: [UUID: Range<Int>] = [:]
        for item in items {
            let itemRect = localOCRRect(item.boundingBox, in: size)
            guard itemRect.intersects(selectionRect),
                  let range = ocrTextRange(in: item, itemRect: itemRect, selectionRect: selectionRect) else {
                continue
            }
            ranges[item.id] = range
        }
        return ranges
    }

    private func ocrReadingOrderRanges(
        from start: CGPoint,
        to end: CGPoint,
        in size: CGSize,
        items: [OCRTextItem]
    ) -> [UUID: Range<Int>]? {
        let orderedItems = items
            .map { item in (item: item, rect: localOCRRect(item.boundingBox, in: size)) }
            .filter { entry in
                !entry.item.text.isEmpty && selectionRectVerticallyTouches(entry.rect, from: start, to: end)
            }
            .sorted { first, second in
                let dy = abs(first.rect.midY - second.rect.midY)
                if dy > 4 {
                    return first.rect.midY < second.rect.midY
                }
                return first.rect.minX < second.rect.minX
            }

        guard let startEndpoint = ocrSelectionEndpoint(at: start, in: orderedItems),
              let endEndpoint = ocrSelectionEndpoint(at: end, in: orderedItems) else {
            return nil
        }

        let lowerEndpoint: OCRSelectionEndpoint
        let upperEndpoint: OCRSelectionEndpoint
        if ocrEndpoint(startEndpoint, isBeforeOrEqualTo: endEndpoint) {
            lowerEndpoint = startEndpoint
            upperEndpoint = endEndpoint
        } else {
            lowerEndpoint = endEndpoint
            upperEndpoint = startEndpoint
        }

        var ranges: [UUID: Range<Int>] = [:]
        for (index, entry) in orderedItems.enumerated() {
            let count = entry.item.text.count
            guard count > 0,
                  index >= lowerEndpoint.itemIndex,
                  index <= upperEndpoint.itemIndex else {
                continue
            }

            let range: Range<Int>
            if lowerEndpoint.itemIndex == upperEndpoint.itemIndex {
                let lower = min(lowerEndpoint.characterIndex, upperEndpoint.characterIndex)
                let upper = max(lowerEndpoint.characterIndex, upperEndpoint.characterIndex)
                range = lower..<upper
            } else if index == lowerEndpoint.itemIndex {
                range = lowerEndpoint.characterIndex..<count
            } else if index == upperEndpoint.itemIndex {
                range = 0..<upperEndpoint.characterIndex
            } else {
                range = 0..<count
            }

            if range.lowerBound < range.upperBound {
                ranges[entry.item.id] = range
            }
        }

        return ranges
    }

    private func ocrSelectionEndpoint(
        at point: CGPoint,
        in orderedItems: [(item: OCRTextItem, rect: CGRect)]
    ) -> OCRSelectionEndpoint? {
        guard let itemIndex = orderedItems.indices.min(by: { first, second in
            ocrVerticalDistance(from: point, to: orderedItems[first].rect) < ocrVerticalDistance(from: point, to: orderedItems[second].rect)
        }) else {
            return nil
        }

        let entry = orderedItems[itemIndex]
        let characterIndex = ocrCharacterIndex(atX: point.x, item: entry.item, itemRect: entry.rect)
        return OCRSelectionEndpoint(itemIndex: itemIndex, characterIndex: characterIndex)
    }

    private func ocrVerticalDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        if point.y < rect.minY {
            return rect.minY - point.y
        }
        if point.y > rect.maxY {
            return point.y - rect.maxY
        }
        return 0
    }

    private func selectionRectVerticallyTouches(_ rect: CGRect, from start: CGPoint, to end: CGPoint) -> Bool {
        let minY = min(start.y, end.y)
        let maxY = max(start.y, end.y)
        return rect.maxY >= minY && rect.minY <= maxY
    }

    private func ocrCharacterIndex(atX x: CGFloat, item: OCRTextItem, itemRect: CGRect) -> Int {
        let count = item.text.count
        guard count > 0, itemRect.width > 0 else { return 0 }
        let ratio = ((x - itemRect.minX) / itemRect.width).clamped(to: 0...1)
        return Int(round(ratio * CGFloat(count))).clamped(to: 0...count)
    }

    private func ocrEndpoint(_ first: OCRSelectionEndpoint, isBeforeOrEqualTo second: OCRSelectionEndpoint) -> Bool {
        if first.itemIndex != second.itemIndex {
            return first.itemIndex < second.itemIndex
        }
        return first.characterIndex <= second.characterIndex
    }

    private func ocrTextRangeRect(_ range: Range<Int>, item: OCRTextItem, itemRect: CGRect) -> CGRect? {
        let count = item.text.count
        guard count > 0, range.lowerBound < range.upperBound else { return nil }
        let lower = CGFloat(range.lowerBound.clamped(to: 0...count)) / CGFloat(count)
        let upper = CGFloat(range.upperBound.clamped(to: 0...count)) / CGFloat(count)
        return CGRect(
            x: itemRect.minX + itemRect.width * lower,
            y: itemRect.minY,
            width: max(1, itemRect.width * (upper - lower)),
            height: itemRect.height
        )
    }

    private func selectedOCRText() -> String {
        guard let result = ocrResult else { return "" }
        guard !selectedOCRTextRanges.isEmpty else {
            return orderedOCRText(result.textItems)
        }

        return result.textItems
            .filter { selectedOCRTextRanges[$0.id] != nil }
            .sorted { first, second in
                let dy = abs(first.boundingBox.midY - second.boundingBox.midY)
                if dy > 0.02 {
                    return first.boundingBox.midY > second.boundingBox.midY
                }
                return first.boundingBox.minX < second.boundingBox.minX
            }
            .compactMap { item in
                guard let range = selectedOCRTextRanges[item.id] else { return nil }
                return substring(item.text, in: range)
            }
            .joined(separator: "\n")
    }

    private func allOCRText() -> String {
        guard let result = ocrResult else { return "" }
        return orderedOCRText(result.textItems)
    }

    private func orderedOCRText(_ items: [OCRTextItem]) -> String {
        return items
            .sorted { first, second in
                let dy = abs(first.boundingBox.midY - second.boundingBox.midY)
                if dy > 0.02 {
                    return first.boundingBox.midY > second.boundingBox.midY
                }
                return first.boundingBox.minX < second.boundingBox.minX
            }
            .map(\.text)
            .joined(separator: "\n")
    }

    private func substring(_ text: String, in range: Range<Int>) -> String {
        let count = text.count
        let lower = range.lowerBound.clamped(to: 0...count)
        let upper = range.upperBound.clamped(to: 0...count)
        guard lower < upper else { return "" }
        let start = text.index(text.startIndex, offsetBy: lower)
        let end = text.index(text.startIndex, offsetBy: upper)
        return String(text[start..<end])
    }

    private func ocrTextItem(at point: CGPoint, in size: CGSize) -> OCRTextItem? {
        guard let result = ocrResult else { return nil }
        return result.textItems.first { item in
            localOCRRect(item.boundingBox, in: size).insetBy(dx: -2, dy: -2).contains(point)
        }
    }

    private func copySelectedOCRTextIfAvailable() -> Bool {
        let text = selectedOCRText()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        copyToPasteboard(text)
        return true
    }

    private func copyAllOCRText() {
        let text = allOCRText()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSSound.beep()
            return
        }
        copyToPasteboard(text)
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        showCopyFeedback()
    }

    private func showCopyFeedback(_ message: String = "已复制") {
        let token = UUID()
        copyFeedbackToken = token
        copyFeedbackMessage = message

        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard copyFeedbackToken == token else { return }
            copyFeedbackMessage = nil
        }
    }

    private func clearOCRContent() {
        ocrRecognitionToken = UUID()
        isOCRRecognizing = false
        ocrResult = nil
        selectedOCRTextIDs.removeAll()
        selectedOCRTextRanges.removeAll()
        selectedQRCodeID = nil
        ocrSelectionStart = nil
        ocrSelectionCurrent = nil
        copyFeedbackMessage = nil
        showAllOCRTextItems = false
        popSelectionCursor()
    }

    private func recognizeContent(in selection: CGRect) {
        if isOCRRecognizing || ocrResult != nil {
            clearOCRContent()
            return
        }

        guard !isOCRRecognizing else { return }
        guard let payload = capturePayload(from: selection),
              let image = payload.image else {
            NSSound.beep()
            return
        }

        finishTextEditing()
        selectedTool = nil
        selectedAnnotationID = nil
        selectedQRCodeID = nil
        selectedOCRTextIDs.removeAll()
        selectedOCRTextRanges.removeAll()
        showAllOCRTextItems = false
        ocrResult = nil
        isOCRRecognizing = true
        let token = UUID()
        ocrRecognitionToken = token

        Task {
            do {
                let result = try await OCRService.recognizeContent(in: image)
                guard ocrRecognitionToken == token else { return }
                ocrResult = result
            } catch {
                guard ocrRecognitionToken == token else { return }
                NSSound.beep()
            }
            if ocrRecognitionToken == token {
                isOCRRecognizing = false
            }
        }
    }

    private func ocrSelectionGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                selectedQRCodeID = nil
                if ocrSelectionStart == nil {
                    selectedOCRTextIDs.removeAll()
                    selectedOCRTextRanges.removeAll()
                    ocrSelectionStart = value.startLocation
                }

                guard isOCRDragSelection(value) else {
                    ocrSelectionCurrent = nil
                    return
                }
                ocrSelectionCurrent = value.location
                updateSelectedOCRText(in: size)
            }
            .onEnded { value in
                if isOCRClickSelection(value) {
                    selectedQRCodeID = nil
                    selectOCRLine(at: value.location, in: size)
                } else {
                    selectedQRCodeID = nil
                    ocrSelectionCurrent = value.location
                    updateSelectedOCRText(in: size)
                }
                ocrSelectionStart = nil
                ocrSelectionCurrent = nil
            }
    }

    private func isOCRClickSelection(_ value: DragGesture.Value) -> Bool {
        !isOCRDragSelection(value)
    }

    private func isOCRDragSelection(_ value: DragGesture.Value) -> Bool {
        abs(value.translation.width) > 3 || abs(value.translation.height) > 3
    }

    private func textBorderDragLayer(for annotation: ScreenshotAnnotation, in selection: CGRect) -> some View {
        let size = textBounds(for: annotation)
        let hit = textBorderHitPadding

        return ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(width: size.width + hit * 2, height: hit * 2)
                .position(x: size.width / 2, y: 0)

            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(width: size.width + hit * 2, height: hit * 2)
                .position(x: size.width / 2, y: size.height)

            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(width: hit * 2, height: size.height + hit * 2)
                .position(x: 0, y: size.height / 2)

            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(width: hit * 2, height: size.height + hit * 2)
                .position(x: size.width, y: size.height / 2)
        }
        .gesture(textMoveGesture(annotationID: annotation.id, in: selection))
    }

    private func annotationGesture(in selection: CGRect) -> some Gesture {
        DragGesture(minimumDistance: selectedTool == .text ? 0 : 1, coordinateSpace: .local)
            .onChanged { value in
                if selectedTool == .text {
                    return
                }

                // 检查是否拖动选中的标注（非文本）
                if movingAnnotationStartPoints == nil && draftAnnotation == nil {
                    let localStart = CGPoint(
                        x: value.startLocation.x - selection.minX,
                        y: value.startLocation.y - selection.minY
                    )
                    if let id = selectedAnnotationID,
                       let index = annotations.firstIndex(where: { $0.id == id }),
                       annotations[index].tool != .text,
                       let bounds = annotationBounds(annotations[index]),
                       bounds.insetBy(dx: -6, dy: -6).contains(localStart) {
                        movingAnnotationStartPoints = annotations[index].points
                    }
                }

                // 如果正在拖动标注，更新位置
                if let startPoints = movingAnnotationStartPoints,
                   let id = selectedAnnotationID,
                   let index = annotations.firstIndex(where: { $0.id == id }) {
                    annotations[index].points = startPoints.map { pt in
                        CGPoint(
                            x: pt.x + value.translation.width,
                            y: pt.y + value.translation.height
                        )
                    }
                    return
                }

                guard let selectedTool, selectedTool != .cursor else { return }
                let localPoint = CGPoint(
                    x: (value.location.x - selection.minX).clamped(to: 0...selection.width),
                    y: (value.location.y - selection.minY).clamped(to: 0...selection.height)
                )
                let localStart = CGPoint(
                    x: (value.startLocation.x - selection.minX).clamped(to: 0...selection.width),
                    y: (value.startLocation.y - selection.minY).clamped(to: 0...selection.height)
                )

                if draftAnnotation == nil {
                    draftAnnotation = ScreenshotAnnotation(
                        tool: selectedTool.drawableTool,
                        color: selectedColor,
                        lineWidth: selectedLineWidth,
                        fontSize: selectedFontSize,
                        points: [localStart]
                    )
                }

                guard var draftAnnotation else { return }
                if selectedTool == .pen || selectedTool == .mosaic {
                    draftAnnotation.points.append(localPoint)
                } else {
                    draftAnnotation.points = [localStart, localPoint]
                }
                self.draftAnnotation = draftAnnotation
            }
            .onEnded { value in
                // 如果正在拖动标注，清理状态
                if movingAnnotationStartPoints != nil {
                    movingAnnotationStartPoints = nil
                    return
                }

                if selectedTool == .text {
                    let localPoint = CGPoint(
                        x: value.location.x - selection.minX,
                        y: value.location.y - selection.minY
                    )
                    if let annotationID = annotationID(at: localPoint),
                       let annotation = annotations.first(where: { $0.id == annotationID }) {
                        finishTextEditing(keeping: annotationID)
                        selectAnnotation(annotation)
                    } else {
                        addTextAnnotation(at: value.location, in: selection)
                    }
                } else if let draftAnnotation, draftAnnotation.points.count >= 2 {
                    annotations.append(draftAnnotation)
                    selectedAnnotationID = draftAnnotation.id
                    redoAnnotations.removeAll()
                }
                draftAnnotation = nil
            }
    }

    private func cursorGesture(in size: CGSize, selection: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard abs(value.translation.width) > 2 || abs(value.translation.height) > 2 else { return }

                // 检查是否拖动选中的标注（非文本）
                if movingAnnotationStartPoints == nil && interactionStartRect == nil {
                    let localStart = CGPoint(
                        x: value.startLocation.x - selection.minX,
                        y: value.startLocation.y - selection.minY
                    )
                    if let id = selectedAnnotationID,
                       let index = annotations.firstIndex(where: { $0.id == id }),
                       annotations[index].tool != .text,
                       let bounds = annotationBounds(annotations[index]),
                       bounds.insetBy(dx: -6, dy: -6).contains(localStart) {
                        movingAnnotationStartPoints = annotations[index].points
                    }
                }

                // 如果正在拖动标注，更新标注位置
                if let startPoints = movingAnnotationStartPoints,
                   let id = selectedAnnotationID,
                   let index = annotations.firstIndex(where: { $0.id == id }) {
                    annotations[index].points = startPoints.map { pt in
                        CGPoint(
                            x: pt.x + value.translation.width,
                            y: pt.y + value.translation.height
                        )
                    }
                    return
                }

                // 否则移动选区
                guard let selectedRect else { return }
                if interactionStartRect == nil {
                    interactionStartRect = selectedRect
                }
                guard let startRect = interactionStartRect else { return }
                let maxX = max(0, size.width - startRect.width)
                let maxY = max(0, size.height - startRect.height)
                self.selectedRect = CGRect(
                    x: (startRect.minX + value.translation.width).clamped(to: 0...maxX),
                    y: (startRect.minY + value.translation.height).clamped(to: 0...maxY),
                    width: startRect.width,
                    height: startRect.height
                )
            }
            .onEnded { value in
                // 如果正在拖动标注，清理状态
                if movingAnnotationStartPoints != nil {
                    movingAnnotationStartPoints = nil
                    return
                }

                if abs(value.translation.width) <= 2, abs(value.translation.height) <= 2 {
                    let localPoint = CGPoint(
                        x: value.location.x - selection.minX,
                        y: value.location.y - selection.minY
                    )
                    selectedAnnotationID = annotationID(at: localPoint)
                    if let annotation = selectedAnnotation {
                        selectedColor = annotation.color
                        selectedLineWidth = annotation.lineWidth
                        selectedFontSize = annotation.fontSize
                        selectedTextColor = annotation.effectiveSwiftUIColor
                        selectedFontName = annotation.fontName
                        selectedTextBold = annotation.isBold
                        selectedTextItalic = annotation.isItalic
                        focusedTextAnnotationID = annotation.tool == .text ? annotation.id : nil
                    } else {
                        focusedTextAnnotationID = nil
                    }
                }
                interactionStartRect = nil
            }
    }

    private func resizeGesture(handle: ResizeHandle, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                guard let selectedRect else { return }
                if interactionStartRect == nil {
                    interactionStartRect = selectedRect
                }
                guard let startRect = interactionStartRect else { return }
                self.selectedRect = handle.resizedRect(
                    from: startRect,
                    translation: value.translation,
                    bounds: CGRect(origin: .zero, size: size)
                )
            }
            .onEnded { _ in
                interactionStartRect = nil
            }
    }

    private func updateTextCursor(_ shouldShow: Bool) {
        if shouldShow, !isTextCursorPushed {
            NSCursor.iBeam.push()
            isTextCursorPushed = true
        } else if !shouldShow, isTextCursorPushed {
            NSCursor.pop()
            isTextCursorPushed = false
        }
    }

    private func resetTextCursor() {
        updateTextCursor(false)
    }

    private func pushSelectionCursor(_ cursor: NSCursor) {
        if selectionCursorPushed == cursor { return }
        if selectionCursorPushed != nil {
            NSCursor.pop()
        }
        cursor.push()
        selectionCursorPushed = cursor
    }

    private func popSelectionCursor() {
        guard selectionCursorPushed != nil else { return }
        NSCursor.pop()
        selectionCursorPushed = nil
    }

    private func updateSelectionCursor(at point: CGPoint) {
        if selectedTool == .text || focusedTextAnnotationID != nil {
            resetTextCursor()

            guard let selection = selectedRect, selection.contains(point) else {
                popSelectionCursor()
                return
            }

            let localPoint = CGPoint(
                x: point.x - selection.minX,
                y: point.y - selection.minY
            )

            if resizingTextAnnotationID != nil {
                if let handle = resizingTextHandle {
                    pushSelectionCursor(handle.cursor)
                }
                return
            }

            if movingTextAnnotationStartPoint != nil {
                pushSelectionCursor(.closedHand)
                return
            }

            if let handle = selectedTextResizeHandleHit(at: localPoint) {
                pushSelectionCursor(handle.cursor)
                return
            }

            if selectedTextAnnotationBorderHit(at: localPoint) != nil {
                pushSelectionCursor(.openHand)
                return
            }

            pushSelectionCursor(.iBeam)
            return
        }

        guard let selection = selectedRect else {
            popSelectionCursor()
            return
        }

        // 拖动中不切换光标
        if interactionStartRect != nil || movingAnnotationStartPoints != nil || resizingAnnotationStartPoints != nil {
            if movingAnnotationStartPoints != nil {
                pushSelectionCursor(.openHand)
            }
            return
        }

        // 检查是否靠近拉伸手柄
        let handleRadius: CGFloat = 14
        for handle in ResizeHandle.allCases {
            let hp = handle.point(in: selection)
            let dx = point.x - hp.x
            let dy = point.y - hp.y
            if dx * dx + dy * dy <= handleRadius * handleRadius {
                pushSelectionCursor(handle.cursor)
                return
            }
        }

        // 选区中间
        if selection.contains(point) {
            let localPoint = CGPoint(x: point.x - selection.minX, y: point.y - selection.minY)
            if ocrTextItem(at: localPoint, in: selection.size) != nil {
                pushSelectionCursor(.iBeam)
                return
            }

            // 靠近标注手柄 -> 十字光标
            if let id = selectedAnnotationID,
               let index = annotations.firstIndex(where: { $0.id == id }),
               annotations[index].tool != .text,
               annotations[index].tool != .pen,
               annotations[index].tool != .mosaic {
                let handleRadius: CGFloat = 12
                let annotation = annotations[index]
                if (annotation.tool == .rectangle || annotation.tool == .ellipse),
                   let bounds = annotationBounds(annotation) {
                    // 矩形/椭圆: 检查8个手柄
                    for handle in AnnotationResizeHandle.allCases {
                        let hp = handle.point(in: bounds)
                        let dx = localPoint.x - hp.x
                        let dy = localPoint.y - hp.y
                        if dx * dx + dy * dy <= handleRadius * handleRadius {
                            pushSelectionCursor(handle.cursor)
                            return
                        }
                    }
                } else {
                    // 线条/箭头: 检查端点
                    for pt in annotations[index].points {
                        let dx = localPoint.x - pt.x
                        let dy = localPoint.y - pt.y
                        if dx * dx + dy * dy <= handleRadius * handleRadius {
                            pushSelectionCursor(.crosshair)
                            return
                        }
                    }
                }
            }

            // 任何工具下，靠近选中的标注 -> 拖动光标
            if let id = selectedAnnotationID,
               let index = annotations.firstIndex(where: { $0.id == id }),
               annotations[index].tool != .text,
               let bounds = annotationBounds(annotations[index]) {
                if bounds.insetBy(dx: -6, dy: -6).contains(localPoint) {
                    pushSelectionCursor(.openHand)
                    return
                }
            }

            if selectedTool != nil && selectedTool != .cursor {
                // 绘制工具 -> 十字光标
                pushSelectionCursor(.crosshair)
            } else {
                popSelectionCursor()
            }
            return
        }

        popSelectionCursor()
    }

    private func annotationHandlesLayer(_ selection: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            if let id = selectedAnnotationID,
               let index = annotations.firstIndex(where: { $0.id == id }),
               annotations[index].tool != .text,
               annotations[index].tool != .pen,
               annotations[index].tool != .mosaic {
                let annotation = annotations[index]
                if annotation.tool == .rectangle || annotation.tool == .ellipse,
                   let bounds = annotationBounds(annotation) {
                    // 矩形/椭圆: 8个手柄 (4角+4边)
                    ForEach(AnnotationResizeHandle.allCases) { handle in
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(.white, lineWidth: 1.2))
                            .position(handle.point(in: bounds))
                            .gesture(annotationEdgeResizeGesture(annotationID: id, handle: handle, in: selection))
                    }
                } else {
                    // 线条/箭头: 2个端点手柄
                    ForEach(Array(annotation.points.enumerated()), id: \.offset) { idx, point in
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(.white, lineWidth: 1.2))
                            .position(point)
                            .gesture(annotationResizeGesture(annotationID: id, pointIndex: idx, in: selection))
                    }
                }
            }
        }
        .frame(width: selection.width, height: selection.height)
        .position(x: selection.midX, y: selection.midY)
        .allowsHitTesting(true)
    }

    private func annotationEdgeResizeGesture(annotationID: UUID, handle: AnnotationResizeHandle, in selection: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if resizingAnnotationStartPoints == nil {
                    if let index = annotations.firstIndex(where: { $0.id == annotationID }) {
                        resizingAnnotationStartPoints = annotations[index].points
                    }
                }
                guard let startPoints = resizingAnnotationStartPoints,
                      let index = annotations.firstIndex(where: { $0.id == annotationID }),
                      startPoints.count >= 2 else { return }

                annotations[index].points = handle.applyResize(
                    to: startPoints,
                    translation: value.translation,
                    bounds: selection
                )
            }
            .onEnded { _ in
                resizingAnnotationStartPoints = nil
            }
    }

    private func annotationResizeGesture(annotationID: UUID, pointIndex: Int, in selection: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if resizingAnnotationStartPoints == nil {
                    if let index = annotations.firstIndex(where: { $0.id == annotationID }) {
                        resizingAnnotationStartPoints = annotations[index].points
                    }
                }
                guard let startPoints = resizingAnnotationStartPoints,
                      let index = annotations.firstIndex(where: { $0.id == annotationID }),
                      pointIndex < startPoints.count else { return }

                let newPoint = CGPoint(
                    x: (startPoints[pointIndex].x + value.translation.width).clamped(to: 0...selection.width),
                    y: (startPoints[pointIndex].y + value.translation.height).clamped(to: 0...selection.height)
                )
                annotations[index].points[pointIndex] = newPoint
            }
            .onEnded { _ in
                resizingAnnotationStartPoints = nil
            }
    }

    private func textSelectionControls(for annotation: ScreenshotAnnotation) -> some View {
        let bounds = CGRect(origin: .zero, size: textBounds(for: annotation))

        return ZStack {
            ForEach(TextResizeHandle.allCases) { handle in
                Circle()
                    .fill(Color.blue)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(.white, lineWidth: 1.2))
                    .contentShape(Circle().inset(by: -8))
                    .position(handle.point(in: bounds))
                    .gesture(textResizeGesture(annotationID: annotation.id, handle: handle))
            }

            Button {
                deleteAnnotation(id: annotation.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .buttonStyle(.plain)
            .position(x: bounds.width + 8, y: -8)
        }
        .allowsHitTesting(true)
    }

    private func textResizeGesture(annotationID: UUID, handle: TextResizeHandle) -> some Gesture {
        // 使用 global 坐标，避免拉伸时 TextField/手柄自身移动导致 local 坐标系跟着变化。
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                guard let index = annotations.firstIndex(where: { $0.id == annotationID }),
                      annotations[index].tool == .text,
                      let origin = annotations[index].points.first else { return }

                if resizingTextAnnotationID != annotationID {
                    resizingTextAnnotationID = annotationID
                    resizingTextStartPoint = origin
                    resizingTextStartSize = textBounds(for: annotations[index])
                    resizingTextStartFontSize = annotations[index].fontSize
                    resizingTextHandle = handle
                    selectedAnnotationID = annotationID
                    focusedTextAnnotationID = nil
                }

                guard let startPoint = resizingTextStartPoint,
                      let startSize = resizingTextStartSize,
                      let startFontSize = resizingTextStartFontSize else { return }

                let result = handle.resized(
                    origin: startPoint,
                    size: startSize,
                    translation: value.translation,
                    bounds: selectionBoundsForTextResize()
                )
                let scale = handle.scale(startSize: startSize, newSize: result.size)
                let fontSize = max(12, min(72, startFontSize * scale))

                annotations[index].points = [result.origin]
                annotations[index].textBoxSize = result.size
                annotations[index].fontSize = fontSize
                selectedFontSize = fontSize
            }
            .onEnded { _ in
                resizingTextAnnotationID = nil
                resizingTextStartPoint = nil
                resizingTextStartSize = nil
                resizingTextStartFontSize = nil
                resizingTextHandle = nil
            }
    }

    private func textScaleGesture(annotationID: UUID) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                guard let index = annotations.firstIndex(where: { $0.id == annotationID }),
                      annotations[index].tool == .text else { return }

                if scalingTextAnnotationID != annotationID {
                    scalingTextAnnotationID = annotationID
                    scalingTextStartSize = annotations[index].textBoxSize
                    scalingTextStartFontSize = annotations[index].fontSize
                    selectedAnnotationID = annotationID
                    focusedTextAnnotationID = annotationID
                }

                guard let startSize = scalingTextStartSize,
                      let startFontSize = scalingTextStartFontSize else { return }

                let delta = max(value.translation.width, value.translation.height)
                let scale = max(0.45, min(3.0, 1 + delta / 90))
                annotations[index].textBoxSize = CGSize(
                    width: max(72, startSize.width * scale),
                    height: max(26, startSize.height * scale)
                )
                annotations[index].fontSize = max(12, min(72, startFontSize * scale))
                selectedFontSize = annotations[index].fontSize
            }
            .onEnded { _ in
                scalingTextAnnotationID = nil
                scalingTextStartSize = nil
                scalingTextStartFontSize = nil
            }
    }

    private func textMoveGesture(annotationID: UUID, in selection: CGRect) -> some Gesture {
        // 使用 global 坐标，避免拖动时 TextField 自身移动导致 local 坐标系跟着变化，出现抖动。
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                guard let index = annotations.firstIndex(where: { $0.id == annotationID }),
                      annotations[index].tool == .text,
                      let origin = annotations[index].points.first else { return }

                if movingTextAnnotationStartPoint == nil {
                    movingTextAnnotationStartPoint = origin
                    selectedAnnotationID = annotationID
                    focusedTextAnnotationID = nil
                }

                guard let startPoint = movingTextAnnotationStartPoint else { return }
                let textSize = textBounds(for: annotations[index])
                annotations[index].points = [
                    CGPoint(
                        x: (startPoint.x + value.translation.width).clamped(to: 0...max(0, selection.width - textSize.width)),
                        y: (startPoint.y + value.translation.height).clamped(to: 0...max(0, selection.height - textSize.height))
                    )
                ]
            }
            .onEnded { _ in
                movingTextAnnotationStartPoint = nil
            }
    }

    private func selectionRect(in size: CGSize) -> CGRect? {
        guard let startPoint, let currentPoint else { return nil }
        let x = min(startPoint.x, currentPoint.x).clamped(to: 0...size.width)
        let y = min(startPoint.y, currentPoint.y).clamped(to: 0...size.height)
        let maxX = max(startPoint.x, currentPoint.x).clamped(to: 0...size.width)
        let maxY = max(startPoint.y, currentPoint.y).clamped(to: 0...size.height)
        let rect = CGRect(x: x, y: y, width: maxX - x, height: maxY - y)
        return rect.width >= 2 && rect.height >= 2 ? rect : nil
    }

    private func activeSelectionRect(in size: CGSize) -> CGRect? {
        selectedRect ?? selectionRect(in: size)
    }

    private var hoveredTarget: ScreenshotCaptureTarget? {
        // 只有鼠标仍在控件矩形内时才返回控件级结果
        if let control = controlHoverTarget,
           let mouse = lastMousePoint,
           control.hitRect.contains(mouse) {
            return control
        }
        guard let hoveredTargetID else { return nil }
        return mergedCaptureTargets.first { $0.id == hoveredTargetID }
    }

    private var mergedCaptureTargets: [ScreenshotCaptureTarget] {
        // 仅窗口候选；控件候选由 Accessibility 按需补充
        captureTargets
    }

    private func updateHoveredTarget(at point: CGPoint) {
        lastMousePoint = point
        guard selectedRect == nil, startPoint == nil else {
            controlHoverTarget = nil
            return
        }

        // 鼠标仍在当前控件矩形内 -> 保持，不重复检测
        if let control = controlHoverTarget, control.hitRect.contains(point) {
            hoveredTargetID = nil
            return
        }

        // 同步 Accessibility 检测：直接拿命中元素的 AXFrame
        // AX 单次调用 1~5ms，同步调不会卡 UI（Snipaste 也是这么做）
        // point 已由 MouseTrackingView.isFlipped 对齐到 SwiftUI 本地坐标(左上原点,y向下)
        // AXUIElementCopyElementAtPosition 使用全局屏幕坐标(左上原点,y向下)
        let maxScreenY = NSScreen.screens.map { $0.frame.maxY }.max() ?? screenFrame.maxY
        let globalPoint = CGPoint(
            x: screenFrame.minX + point.x,
            y: maxScreenY - screenFrame.maxY + point.y
        )
        if let windowTarget = captureTarget(at: point) {
            if let control = ScreenshotAccessibilityDetector.target(
                at: globalPoint,
                screenFrame: screenFrame,
                maxScreenY: maxScreenY,
                within: windowTarget
            ) {
                controlHoverTarget = control
                hoveredTargetID = nil
                return
            }
        }

        // AX 未命中或未授权 -> 回退到窗口高亮
        controlHoverTarget = nil
        hoveredTargetID = captureTarget(at: point)?.id
    }

    private func captureTarget(at point: CGPoint) -> ScreenshotCaptureTarget? {
        mergedCaptureTargets
            .filter { $0.hitRect.contains(point) }
            .sorted { first, second in
                // 系统 UI（Dock、菜单栏）优先级最低，避免覆盖其他窗口
                if first.isSystemUI != second.isSystemUI {
                    return !first.isSystemUI
                }
                if first.shouldPreferOver(second) {
                    return true
                }
                if second.shouldPreferOver(first) {
                    return false
                }
                if abs(first.priority - second.priority) > 0.001 {
                    return first.priority > second.priority
                }
                let firstArea = first.screenRect.width * first.screenRect.height
                let secondArea = second.screenRect.width * second.screenRect.height
                return firstArea < secondArea
            }
            .first
    }

    private func initialHoverTargetID() -> ScreenshotCaptureTarget.ID? {
        let mousePoint = localMousePoint()
        let localBounds = CGRect(origin: .zero, size: screenFrame.size)
        guard localBounds.contains(mousePoint) else { return nil }

        if let target = captureTarget(at: mousePoint) {
            return target.id
        }
        if let nearest = nearestCaptureTarget(to: mousePoint) {
            return nearest.id
        }
        return captureTargets.first?.id
    }

    private func localMousePoint() -> CGPoint {
        let mouseLocation = NSEvent.mouseLocation
        return CGPoint(
            x: mouseLocation.x - screenFrame.minX,
            y: screenFrame.maxY - mouseLocation.y
        )
    }

    private func nearestCaptureTarget(to point: CGPoint) -> ScreenshotCaptureTarget? {
        mergedCaptureTargets
            .filter { !$0.isSystemUI }
            .min { first, second in
                distanceSquared(from: point, to: first.screenRect) < distanceSquared(from: point, to: second.screenRect)
            }
    }

    private func distanceSquared(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx: CGFloat
        if point.x < rect.minX {
            dx = rect.minX - point.x
        } else if point.x > rect.maxX {
            dx = point.x - rect.maxX
        } else {
            dx = 0
        }

        let dy: CGFloat
        if point.y < rect.minY {
            dy = rect.minY - point.y
        } else if point.y > rect.maxY {
            dy = point.y - rect.maxY
        } else {
            dy = 0
        }
        return dx * dx + dy * dy
    }

    private func boundedTargetRect(_ rect: CGRect, in size: CGSize) -> CGRect {
        rect.intersection(CGRect(origin: .zero, size: size))
    }

    private func isClickCandidate(_ value: DragGesture.Value) -> Bool {
        abs(value.translation.width) <= 4 && abs(value.translation.height) <= 4
    }

    private func globalRect(from selection: CGRect) -> CGRect? {
        guard selection.width >= 4, selection.height >= 4 else { return nil }
        return CGRect(
            x: screenFrame.minX + selection.minX,
            y: screenFrame.maxY - selection.maxY,
            width: selection.width,
            height: selection.height
        )
    }

    private func capturePayload(from selection: CGRect) -> ScreenshotCapturePayload? {
        guard let rect = globalRect(from: selection) else { return nil }
        let frozenImage = screenImage.flatMap {
            ScreenshotImageCapturer.crop(image: $0, rect: selection)
        }
        return ScreenshotCapturePayload(
            rect: rect,
            image: frozenImage,
            canvasSize: selection.size,
            annotations: visibleAnnotations
        )
    }

    private func handleToolbarAction(_ toolbarAction: ScreenshotToolbarAction, selection: CGRect) {
        switch toolbarAction {
        case .perform(let action):
            if case .ocr = action {
                recognizeContent(in: selection)
                return
            }
            guard let payload = capturePayload(from: selection) else { return }
            perform(action, payload)
        case .undo:
            undoLastAnnotation()
        case .redo:
            redoLastAnnotation()
        case .cancel:
            cancel()
        }
    }

    private func toolbarPosition(for selection: CGRect, in size: CGSize) -> CGPoint {
        let toolbarSize = CGSize(width: 580, height: 80)
        let rightEdge = min(max(selection.maxX, toolbarSize.width + 10), size.width - 10)
        let x = rightEdge - toolbarSize.width / 2
        let preferredY = selection.maxY + toolbarSize.height / 2 + 10
        let y = preferredY <= size.height - 12 ? preferredY : max(toolbarSize.height / 2 + 12, selection.minY - toolbarSize.height / 2 - 10)
        return CGPoint(x: x, y: y)
    }


    private func shortcutHintAlignment(for selection: CGRect?, in size: CGSize) -> Alignment {
        shortcutHintPlacement(for: selection, in: size).alignment
    }

    private func shortcutHintPadding(for selection: CGRect?, in size: CGSize) -> EdgeInsets {
        shortcutHintPlacement(for: selection, in: size).padding
    }

    private func shortcutHintPlacement(for selection: CGRect?, in size: CGSize) -> (alignment: Alignment, padding: EdgeInsets) {
        let marginX: CGFloat = 22
        let marginY: CGFloat = 24
        let panelSize = CGSize(width: 286, height: 252)

        struct Candidate {
            let alignment: Alignment
            let padding: EdgeInsets
            let rect: CGRect
        }

        let candidates = [
            Candidate(
                alignment: .bottomTrailing,
                padding: EdgeInsets(top: 0, leading: 0, bottom: marginY, trailing: marginX),
                rect: CGRect(x: size.width - marginX - panelSize.width, y: size.height - marginY - panelSize.height, width: panelSize.width, height: panelSize.height)
            ),
            Candidate(
                alignment: .topTrailing,
                padding: EdgeInsets(top: marginY, leading: 0, bottom: 0, trailing: marginX),
                rect: CGRect(x: size.width - marginX - panelSize.width, y: marginY, width: panelSize.width, height: panelSize.height)
            ),
            Candidate(
                alignment: .bottomLeading,
                padding: EdgeInsets(top: 0, leading: marginX, bottom: marginY, trailing: 0),
                rect: CGRect(x: marginX, y: size.height - marginY - panelSize.height, width: panelSize.width, height: panelSize.height)
            ),
            Candidate(
                alignment: .topLeading,
                padding: EdgeInsets(top: marginY, leading: marginX, bottom: 0, trailing: 0),
                rect: CGRect(x: marginX, y: marginY, width: panelSize.width, height: panelSize.height)
            )
        ]

        guard let selection else { return (candidates[0].alignment, candidates[0].padding) }
        let protectedRect = selection.insetBy(dx: -12, dy: -12)

        if let candidate = candidates.first(where: { !$0.rect.intersects(protectedRect) }) {
            return (candidate.alignment, candidate.padding)
        }

        let best = candidates.min { first, second in
            first.rect.intersection(protectedRect).area < second.rect.intersection(protectedRect).area
        } ?? candidates[0]
        return (best.alignment, best.padding)
    }

    private func handleKeyDown(_ event: NSEvent, in size: CGSize) {
        if event.keyCode == 53 {
            cancel()
            return
        }

        if event.modifierFlags.contains(.command),
           (event.charactersIgnoringModifiers ?? "").lowercased() == "c",
           copySelectedOCRTextIfAvailable() {
            return
        }

        if event.keyCode == 36 || event.keyCode == 76 {
            performActiveSelection(.copy, in: size)
            return
        }

        if event.keyCode == 51 || event.keyCode == 117 {
            // 有选中的标注时删除选中的，否则撤销最后一个
            if let id = selectedAnnotationID {
                deleteAnnotation(id: id)
            } else {
                undoLastAnnotation()
            }
            return
        }

        if event.modifierFlags.contains(.command),
           (event.charactersIgnoringModifiers ?? "").lowercased() == "s" {
            performActiveSelection(.save, in: size)
            return
        }

        switch event.keyCode {
        case 126:
            moveSelectionBy(dx: 0, dy: -keyboardStep(for: event), in: size)
            return
        case 125:
            moveSelectionBy(dx: 0, dy: keyboardStep(for: event), in: size)
            return
        case 123:
            moveSelectionBy(dx: -keyboardStep(for: event), dy: 0, in: size)
            return
        case 124:
            moveSelectionBy(dx: keyboardStep(for: event), dy: 0, in: size)
            return
        default:
            break
        }

        switch (event.charactersIgnoringModifiers ?? "").lowercased() {
        case "w":
            moveSelectionBy(dx: 0, dy: -keyboardStep(for: event), in: size)
        case "a":
            moveSelectionBy(dx: -keyboardStep(for: event), dy: 0, in: size)
        case "s":
            moveSelectionBy(dx: 0, dy: keyboardStep(for: event), in: size)
        case "d":
            moveSelectionBy(dx: keyboardStep(for: event), dy: 0, in: size)
        case "p":
            performActiveSelection(.pin, in: size)
        case "c":
            performActiveSelection(.copy, in: size)
        default:
            break
        }
    }

    private func performActiveSelection(_ action: ScreenshotResultAction, in size: CGSize) {
        guard let selection = activeSelectionRect(in: size),
              let payload = capturePayload(from: selection) else { return }
        perform(action, payload)
    }

    private func moveSelectionBy(dx: CGFloat, dy: CGFloat, in size: CGSize) {
        guard let selectedRect else { return }
        let maxX = max(0, size.width - selectedRect.width)
        let maxY = max(0, size.height - selectedRect.height)
        self.selectedRect = CGRect(
            x: (selectedRect.minX + dx).clamped(to: 0...maxX),
            y: (selectedRect.minY + dy).clamped(to: 0...maxY),
            width: selectedRect.width,
            height: selectedRect.height
        )
    }

    private func keyboardStep(for event: NSEvent) -> CGFloat {
        event.modifierFlags.contains(.shift) ? 10 : 1
    }

    private func undoLastAnnotation() {
        guard let annotation = annotations.popLast() else { return }
        redoAnnotations.append(annotation)
    }

    private func redoLastAnnotation() {
        guard let annotation = redoAnnotations.popLast() else { return }
        annotations.append(annotation)
        selectedAnnotationID = annotation.id
    }

    private var selectedAnnotation: ScreenshotAnnotation? {
        guard let selectedAnnotationID else { return nil }
        return annotations.first { $0.id == selectedAnnotationID }
    }

    private var toolbarControlMode: ScreenshotToolbarControlMode? {
        if ocrResult?.textItems.isEmpty == false {
            return .ocr
        }
        if selectedAnnotation?.tool == .text || selectedTool == .text {
            return .text
        }
        if selectedTool != nil, selectedTool != .cursor {
            return .shape
        }
        if selectedAnnotation != nil {
            return .shape
        }
        return nil
    }

    private func addTextAnnotation(at point: CGPoint, in selection: CGRect) {
        finishTextEditing()
        let localPoint = CGPoint(
            x: (point.x - selection.minX).clamped(to: 0...selection.width),
            y: (point.y - selection.minY).clamped(to: 0...selection.height)
        )
        let annotation = ScreenshotAnnotation(
            tool: .text,
            color: selectedColor,
            lineWidth: selectedLineWidth,
            fontSize: selectedFontSize,
            textColor: NSColor(selectedTextColor),
            fontName: selectedFontName,
            isBold: selectedTextBold,
            isItalic: selectedTextItalic,
            text: "",
            textBoxSize: CGSize(width: 128, height: selectedFontSize + 16),
            points: [localPoint]
        )
        annotations.append(annotation)
        selectedAnnotationID = annotation.id
        focusedTextAnnotationID = nil
        // 记录待聚焦的批注 ID，在 TextField 的 onAppear 中设置焦点
        pendingFocusAnnotationID = annotation.id
        redoAnnotations.removeAll()
    }

    private func selectAnnotation(_ annotation: ScreenshotAnnotation) {
        selectedAnnotationID = annotation.id
        selectedColor = annotation.color
        selectedLineWidth = annotation.lineWidth
        selectedFontSize = annotation.fontSize
        selectedTextColor = annotation.effectiveSwiftUIColor
        selectedFontName = annotation.fontName
        selectedTextBold = annotation.isBold
        selectedTextItalic = annotation.isItalic
        focusedTextAnnotationID = annotation.tool == .text ? annotation.id : nil
    }

    private func syncSelectionWithFocusedText(_ annotationID: UUID?) {
        guard let annotationID,
              let annotation = annotations.first(where: { $0.id == annotationID }),
              annotation.tool == .text else { return }
        selectedAnnotationID = annotation.id
        selectedColor = annotation.color
        selectedLineWidth = annotation.lineWidth
        selectedFontSize = annotation.fontSize
        selectedTextColor = annotation.effectiveSwiftUIColor
        selectedFontName = annotation.fontName
        selectedTextBold = annotation.isBold
        selectedTextItalic = annotation.isItalic
    }

    private func updateSelectedColor(_ color: ScreenshotAnnotationColor) {
        selectedColor = color
        updateSelectedAnnotation { $0.color = color }
    }

    private func updateSelectedLineWidth(_ width: CGFloat) {
        selectedLineWidth = width
        updateSelectedAnnotation { $0.lineWidth = width }
    }

    private func updateSelectedFontSize(_ size: CGFloat) {
        selectedFontSize = size
        updateSelectedAnnotation { $0.fontSize = size }
    }

    private func updateSelectedTextColor(_ color: Color) {
        selectedTextColor = color
        updateSelectedAnnotation { annotation in
            guard annotation.tool == .text else { return }
            annotation.textColor = NSColor(color)
        }
    }

    private func openTextColorPanel() {
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.color = NSColor(selectedTextColor)

        // 截图遮罩窗口是 .screenSaver 层级，系统调色盘默认会被遮住，这里强制置顶到遮罩之上。
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        if let colorPanelObserver {
            NotificationCenter.default.removeObserver(colorPanelObserver)
            self.colorPanelObserver = nil
        }

        colorPanelObserver = NotificationCenter.default.addObserver(
            forName: NSColorPanel.colorDidChangeNotification,
            object: panel,
            queue: .main
        ) { _ in
            let color = Color(panel.color)
            selectedTextColor = color
            updateSelectedTextColor(color)
        }

        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    private func updateSelectedFontName(_ fontName: String) {
        selectedFontName = fontName
        updateSelectedAnnotation { annotation in
            guard annotation.tool == .text else { return }
            annotation.fontName = fontName
        }
    }

    private func updateSelectedTextBold(_ isBold: Bool) {
        selectedTextBold = isBold
        updateSelectedAnnotation { annotation in
            guard annotation.tool == .text else { return }
            annotation.isBold = isBold
        }
    }

    private func updateSelectedTextItalic(_ isItalic: Bool) {
        selectedTextItalic = isItalic
        updateSelectedAnnotation { annotation in
            guard annotation.tool == .text else { return }
            annotation.isItalic = isItalic
        }
    }

    private func updateSelectedAnnotation(_ update: (inout ScreenshotAnnotation) -> Void) {
        guard let selectedAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == selectedAnnotationID }) else { return }
        update(&annotations[index])
    }

    private func deleteAnnotation(id: UUID) {
        // 先清除焦点和选中状态，避免 ForEach 重入导致卡死
        if focusedTextAnnotationID == id {
            focusedTextAnnotationID = nil
        }
        if selectedAnnotationID == id {
            selectedAnnotationID = nil
        }
        // 延迟到下一个 runloop 再从数组中移除
        DispatchQueue.main.async {
            guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
            redoAnnotations.removeAll()
            annotations.remove(at: index)
        }
    }

    private var visibleAnnotations: [ScreenshotAnnotation] {
        annotations.filter { annotation in
            annotation.tool != .text || !annotation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func shouldShowTextAnnotation(_ annotation: ScreenshotAnnotation) -> Bool {
        annotation.tool == .text &&
        (annotation.id == selectedAnnotationID ||
         annotation.id == focusedTextAnnotationID ||
         !annotation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func finishTextEditing(keeping annotationID: UUID? = nil) {
        if focusedTextAnnotationID != annotationID {
            focusedTextAnnotationID = nil
        }
        if pendingFocusAnnotationID != annotationID {
            pendingFocusAnnotationID = nil
        }
        removeEmptyTextAnnotations(keeping: annotationID)
    }

    private func removeEmptyTextAnnotations(keeping annotationID: UUID? = nil) {
        let idsToRemove = annotations.filter {
            $0.tool == .text &&
            $0.id != annotationID &&
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.map { $0.id }

        if let selectedAnnotationID, idsToRemove.contains(selectedAnnotationID) {
            self.selectedAnnotationID = nil
        }

        guard !idsToRemove.isEmpty else { return }

        // 延迟到下一个 runloop 再从数组中移除，避免 ForEach 中 TextField 焦点绑定重入导致崩溃
        DispatchQueue.main.async {
            annotations.removeAll { idsToRemove.contains($0.id) }
        }
    }

    private func textFrame(for annotation: ScreenshotAnnotation) -> CGRect? {
        guard annotation.tool == .text,
              let origin = annotation.points.first else { return nil }

        return CGRect(origin: origin, size: textBounds(for: annotation))
    }

    private func isTextBorderHit(annotation: ScreenshotAnnotation, at localPoint: CGPoint) -> Bool {
        guard selectedAnnotationID == annotation.id,
              let rect = textFrame(for: annotation) else { return false }

        let outer = rect.insetBy(dx: -textBorderHitPadding, dy: -textBorderHitPadding)
        let inner = rect.insetBy(dx: textBorderHitPadding, dy: textBorderHitPadding)
        return outer.contains(localPoint) && !inner.contains(localPoint)
    }

    private func selectedTextAnnotationBorderHit(at localPoint: CGPoint) -> UUID? {
        guard let selectedAnnotationID,
              let annotation = annotations.first(where: { $0.id == selectedAnnotationID }),
              annotation.tool == .text,
              isTextBorderHit(annotation: annotation, at: localPoint) else {
            return nil
        }

        return selectedAnnotationID
    }


    private func selectedTextResizeHandleHit(at localPoint: CGPoint) -> TextResizeHandle? {
        guard let selectedAnnotationID,
              let annotation = annotations.first(where: { $0.id == selectedAnnotationID }),
              annotation.tool == .text,
              let rect = textFrame(for: annotation) else { return nil }

        let hitRadius: CGFloat = 13
        return TextResizeHandle.allCases.first { handle in
            let point = handle.point(in: rect)
            let dx = localPoint.x - point.x
            let dy = localPoint.y - point.y
            return dx * dx + dy * dy <= hitRadius * hitRadius
        }
    }

    private func selectionBoundsForTextResize() -> CGRect {
        guard let selectedRect else {
            return CGRect(x: 0, y: 0, width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
        return CGRect(origin: .zero, size: selectedRect.size)
    }

    private func annotationID(at point: CGPoint) -> UUID? {
        annotations.reversed().first { annotation in
            annotationBounds(annotation)?.insetBy(dx: -6, dy: -6).contains(point) == true
        }?.id
    }

    private func annotationBounds(_ annotation: ScreenshotAnnotation) -> CGRect? {
        switch annotation.tool {
        case .text:
            guard let origin = annotation.points.first else { return nil }
            let size = textBounds(for: annotation)
            return CGRect(origin: origin, size: size)
        case .pen, .mosaic:
            guard let first = annotation.points.first else { return nil }
            return annotation.points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { rect, point in
                rect.union(CGRect(origin: point, size: .zero))
            }
        default:
            return localRect(for: annotation)
        }
    }

    private func textBounds(for annotation: ScreenshotAnnotation) -> CGSize {
        let intrinsicSize = textBoxSize(text: annotation.text, fontSize: annotation.fontSize)
        return CGSize(
            width: max(annotation.textBoxSize.width, intrinsicSize.width),
            height: max(annotation.textBoxSize.height, intrinsicSize.height)
        )
    }

    private func textBoxSize(text: String, fontSize: CGFloat) -> CGSize {
        let textWidth = max(72, CGFloat(max(text.count, 1)) * fontSize * 0.62 + 16)
        return CGSize(width: textWidth, height: max(26, fontSize + 14))
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}

private struct OCRSelectionEndpoint {
    let itemIndex: Int
    let characterIndex: Int
}

private struct ScreenshotTextPaletteColor: Identifiable {
    let id: String
    let title: String
    let color: Color
    let nsColor: NSColor

    static let common: [ScreenshotTextPaletteColor] = [
        ScreenshotTextPaletteColor(id: "red", title: "红色", color: .red, nsColor: .systemRed),
        ScreenshotTextPaletteColor(id: "yellow", title: "黄色", color: .yellow, nsColor: .systemYellow),
        ScreenshotTextPaletteColor(id: "blue", title: "蓝色", color: .blue, nsColor: .systemBlue),
        ScreenshotTextPaletteColor(id: "green", title: "绿色", color: .green, nsColor: .systemGreen),
        ScreenshotTextPaletteColor(id: "white", title: "白色", color: .white, nsColor: .white),
        ScreenshotTextPaletteColor(id: "black", title: "黑色", color: .black, nsColor: .black)
    ]

    var borderColor: Color {
        id == "white" ? Color.black.opacity(0.35) : Color.white.opacity(0.72)
    }

    func matches(_ other: Color) -> Bool {
        let lhs = nsColor.usingColorSpace(.sRGB) ?? nsColor
        let rhs = NSColor(other).usingColorSpace(.sRGB) ?? NSColor(other)
        return abs(lhs.redComponent - rhs.redComponent) < 0.02 &&
            abs(lhs.greenComponent - rhs.greenComponent) < 0.02 &&
            abs(lhs.blueComponent - rhs.blueComponent) < 0.02 &&
            abs(lhs.alphaComponent - rhs.alphaComponent) < 0.02
    }
}

private struct ScreenshotSelectionToolbar: View {
    @Binding var selectedTool: ScreenshotAnnotationTool?
    @Binding var selectedColor: ScreenshotAnnotationColor
    @Binding var selectedLineWidth: CGFloat
    @Binding var selectedFontSize: CGFloat
    let controlMode: ScreenshotToolbarControlMode?
    let canUndo: Bool
    let canRedo: Bool
    let setColor: (ScreenshotAnnotationColor) -> Void
    let setLineWidth: (CGFloat) -> Void
    let setFontSize: (CGFloat) -> Void
    @Binding var selectedTextColor: Color
    @Binding var selectedFontName: String
    @Binding var selectedTextBold: Bool
    @Binding var selectedTextItalic: Bool
    let setTextColor: (Color) -> Void
    let setFontName: (String) -> Void
    let setTextBold: (Bool) -> Void
    let setTextItalic: (Bool) -> Void
    let openTextColorPanel: () -> Void
    let isOCREnabled: Bool
    let hasOCRText: Bool
    @Binding var showAllOCRTextItems: Bool
    let copyAllOCRText: () -> Void
    let action: (ScreenshotToolbarAction) -> Void
    @State private var hoveredTooltip: String?
    @State private var hoveredItemID: String?

    var body: some View {
        ZStack(alignment: .top) {
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 2) {
                    ForEach(ScreenshotAnnotationTool.allCases) { tool in
                        iconButton(tool.systemImage, tool.title, isSelected: selectedTool == tool) {
                            selectedTool = selectedTool == tool ? nil : tool
                            hoveredTooltip = nil
                        }
                    }

                    Divider()
                        .frame(height: 24)
                        .overlay(Color.black.opacity(0.16))
                        .padding(.horizontal, 4)

                    iconButton("arrow.uturn.backward", "撤销", isSelected: false) {
                        action(.undo)
                    }
                    .disabled(!canUndo)
                    .opacity(canUndo ? 1 : 0.42)

                    iconButton("arrow.uturn.forward", "恢复", isSelected: false) {
                        action(.redo)
                    }
                    .disabled(!canRedo)
                    .opacity(canRedo ? 1 : 0.42)

                    iconButton("xmark", "取消本次截图", isSelected: false) {
                        action(.cancel)
                    }

                    iconButton("pin", "钉住当前截图", isSelected: false) {
                        action(.perform(.pin))
                    }

                    iconButton("text.viewfinder", "OCR 识别文字", isSelected: isOCREnabled) {
                        action(.perform(.ocr))
                    }

                    iconButton("tray.and.arrow.down", "保存为 PNG", isSelected: false) {
                        action(.perform(.save))
                    }

                    iconButton("doc.on.doc", "复制截图到剪贴板", isSelected: false) {
                        action(.perform(.copy))
                    }
                }

                if let controlMode {
                    HStack(spacing: 4) {
                        if controlMode == .ocr {
                            iconButton(
                                showAllOCRTextItems ? "eye.slash" : "eye",
                                showAllOCRTextItems ? "隐藏所有识别区域" : "显示所有识别区域",
                                isSelected: showAllOCRTextItems
                            ) {
                                showAllOCRTextItems.toggle()
                            }
                            .disabled(!hasOCRText)
                            .opacity(hasOCRText ? 1 : 0.45)

                            iconButton("doc.on.doc", "复制所有 OCR 文本", isSelected: false) {
                                copyAllOCRText()
                            }
                            .disabled(!hasOCRText)
                            .opacity(hasOCRText ? 1 : 0.45)
                        } else if controlMode == .text {
                            textToggleButton("B", "加粗", id: "bold", isSelected: selectedTextBold) {
                                setTextBold(!selectedTextBold)
                            }

                            textToggleButton("I", "斜体", id: "italic", isSelected: selectedTextItalic) {
                                setTextItalic(!selectedTextItalic)
                            }

                            Divider()
                                .frame(height: 18)
                                .overlay(Color.black.opacity(0.16))
                                .padding(.horizontal, 4)

                            Menu {
                                ForEach([CGFloat(12), CGFloat(14), CGFloat(18), CGFloat(24), CGFloat(32), CGFloat(48)], id: \.self) { size in
                                    Button("\(Int(size))") {
                                        setFontSize(size)
                                    }
                                }
                            } label: {
                                toolbarLabelItem(id: "font-size", isSelected: false) {
                                    Text("\(Int(selectedFontSize))")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.black.opacity(0.72))
                                }
                            }
                            .menuStyle(.borderlessButton)
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                hoveredItemID = hovering ? "font-size" : nil
                                hoveredTooltip = hovering ? "字体大小" : nil
                            }

                            ForEach(ScreenshotTextPaletteColor.common) { item in
                                Button {
                                    setTextColor(item.color)
                                } label: {
                                    toolbarItemFrame(id: "text-palette-\(item.id)", isSelected: item.matches(selectedTextColor)) {
                                        Circle()
                                            .fill(item.color)
                                            .frame(width: 15, height: 15)
                                            .overlay(
                                                Circle()
                                                    .stroke(item.borderColor, lineWidth: item.matches(selectedTextColor) ? 2 : 1.2)
                                            )
                                    }
                                }
                                .buttonStyle(.plain)
                                .onHover { hovering in
                                    hoveredItemID = hovering ? "text-palette-\(item.id)" : nil
                                    hoveredTooltip = hovering ? "字体颜色：\(item.title)" : nil
                                }
                            }

                            Button {
                                openTextColorPanel()
                            } label: {
                                toolbarItemFrame(id: "text-color-picker", isSelected: false) {
                                    Image(systemName: "paintpalette")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.black.opacity(0.72))
                                }
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                hoveredItemID = hovering ? "text-color-picker" : nil
                                hoveredTooltip = hovering ? "更多颜色" : nil
                            }

                            Menu {
                                ForEach(ScreenshotTextStyle.fontChoices, id: \.name) { font in
                                    Button(font.title) {
                                        setFontName(font.name)
                                    }
                                }
                            } label: {
                                toolbarLabelItem(id: "font-family", isSelected: false) {
                                    Text(ScreenshotTextStyle.title(for: selectedFontName))
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundStyle(.black.opacity(0.72))
                                        .lineLimit(1)
                                        .frame(width: 78)
                                }
                            }
                            .menuStyle(.borderlessButton)
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                hoveredItemID = hovering ? "font-family" : nil
                                hoveredTooltip = hovering ? "字体" : nil
                            }
                        } else {
                            ForEach(ScreenshotAnnotationColor.allCases) { color in
                                Button {
                                    setColor(color)
                                } label: {
                                    toolbarItemFrame(id: "color-\(color.id)", isSelected: selectedColor == color) {
                                        Circle()
                                            .fill(color.swiftUIColor)
                                            .frame(width: 15, height: 15)
                                            .overlay(
                                                Circle()
                                                    .stroke(selectedColor == color ? Color.black.opacity(0.40) : Color.white.opacity(0.62), lineWidth: 1.5)
                                            )
                                    }
                                }
                                .buttonStyle(.plain)
                                .onHover { hovering in
                                    hoveredItemID = hovering ? "color-\(color.id)" : nil
                                    hoveredTooltip = hovering ? "批注颜色：\(color.title)" : nil
                                }
                            }

                            Divider()
                                .frame(height: 18)
                                .overlay(Color.black.opacity(0.16))
                                .padding(.horizontal, 4)

                            ForEach([CGFloat(2), CGFloat(4), CGFloat(7)], id: \.self) { width in
                                Button {
                                    setLineWidth(width)
                                } label: {
                                    toolbarItemFrame(id: "line-\(Int(width))", isSelected: selectedLineWidth == width) {
                                        Circle()
                                            .fill(selectedLineWidth == width ? Color.white : Color.black.opacity(0.72))
                                            .frame(width: width + 5, height: width + 5)
                                    }
                                }
                                .buttonStyle(.plain)
                                .onHover { hovering in
                                    hoveredItemID = hovering ? "line-\(Int(width))" : nil
                                    hoveredTooltip = hovering ? "批注线宽：\(lineWidthTitle(width))" : nil
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(.black.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.16), radius: 10, y: 4)

            if let hoveredTooltip {
                Text(hoveredTooltip)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.90), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(.white.opacity(0.24), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.20), radius: 8, y: 3)
                    .offset(y: 82)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }

    private func iconButton(_ image: String, _ title: String, isSelected: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            toolbarItemFrame(id: "icon-\(title)", isSelected: isSelected) {
                Group {
                    if image == ScreenshotAnnotationTool.textGlyphName {
                        Text("T")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    } else {
                        Image(systemName: image)
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .foregroundStyle(isSelected ? .white : .black.opacity(0.68))
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredItemID = hovering ? "icon-\(title)" : nil
            hoveredTooltip = hovering ? title : nil
        }
        .accessibilityLabel(title)
    }

    private func textToggleButton(_ title: String, _ tooltip: String, id: String, isSelected: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            toolbarItemFrame(id: id, isSelected: isSelected) {
                if title == "I" {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .italic()
                        .foregroundStyle(isSelected ? .white : .black.opacity(0.72))
                } else {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(isSelected ? .white : .black.opacity(0.72))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredItemID = hovering ? id : nil
            hoveredTooltip = hovering ? tooltip : nil
        }
    }

    private func toolbarItemFrame<Content: View>(
        id: String,
        isSelected: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack(alignment: .bottom) {
            content()
                .frame(width: 34, height: 32)
                .background(
                    isSelected ? Color.blue.opacity(0.92) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                )

            Rectangle()
                .fill(Color.blue.opacity(0.95))
                .frame(height: 2)
                .opacity(hoveredItemID == id ? 1 : 0)
                .padding(.horizontal, 4)
        }
        .frame(width: 34, height: 34)
        .contentShape(Rectangle())
    }

    private func toolbarLabelItem<Content: View>(
        id: String,
        isSelected: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack(alignment: .bottom) {
            content()
                .frame(height: 32)
                .padding(.horizontal, 7)
                .background(
                    isSelected ? Color.blue.opacity(0.92) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                )

            Rectangle()
                .fill(Color.blue.opacity(0.95))
                .frame(height: 2)
                .opacity(hoveredItemID == id ? 1 : 0)
                .padding(.horizontal, 4)
        }
        .frame(height: 34)
        .contentShape(Rectangle())
    }

    private func lineWidthTitle(_ width: CGFloat) -> String {
        switch Int(width) {
        case 2:
            return "细"
        case 4:
            return "中"
        default:
            return "粗"
        }
    }
}

private struct ScreenshotShortcutHintPanel: View {
    private let rows: [(keys: [String], title: String)] = [
        (["WASD", "↑↓←→"], "移动选区 1 像素"),
        (["Shift", "WASD/↑↓←→"], "移动选区 10 像素"),
        (["↩"], "完成并复制"),
        (["C"], "复制到剪贴板"),
        (["⌘", "S"], "保存为 PNG"),
        (["P"], "钉住当前截图"),
        (["Delete"], "撤销批注"),
        (["Esc"], "取消截图")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        ForEach(rows[index].keys, id: \.self) { key in
                            ScreenshotShortcutKeyCap(title: key)
                        }
                    }
                    .frame(width: 112, alignment: .trailing)

                    Text(rows[index].title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
    }
}

private struct ScreenshotShortcutKeyCap: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, title.count > 1 ? 7 : 0)
            .frame(minWidth: title.count > 1 ? 0 : 22, minHeight: 22)
            .background(.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(.white.opacity(0.80), lineWidth: 1.2)
            )
    }
}

private enum ScreenshotTargetKind {
    case window
    case contour
}

private struct ScreenshotCaptureTarget: Identifiable {
    let id: Int
    let kind: ScreenshotTargetKind
    let globalRect: CGRect
    let screenRect: CGRect
    let title: String?
    let priority: Double
    let pid: pid_t
    let layer: Int

    /// 系统 UI（Dock、菜单栏）的 bounds 远大于实际可见区域，悬停检测时降低优先级
    var isSystemUI: Bool {
        layer == 20 || layer == 24
    }

    var hitRect: CGRect {
        screenRect.insetBy(dx: -6, dy: -6)
    }

    var actionTitle: String {
        switch kind {
        case .window:
            return "点击选择窗口"
        case .contour:
            return "点击选择区域"
        }
    }

    func shouldPreferOver(_ other: ScreenshotCaptureTarget) -> Bool {
        guard kind == .contour, other.kind == .window else { return false }
        let ownArea = screenRect.width * screenRect.height
        let otherArea = other.screenRect.width * other.screenRect.height
        return other.screenRect.insetBy(dx: -4, dy: -4).contains(screenRect) && ownArea < otherArea * 0.72
    }
}

private enum ScreenshotWindowTargetDetector {
    private static let debugLogger = LogArchiver.shared

    static func targets(on screenFrame: CGRect) -> [ScreenshotCaptureTarget] {
        guard let windowInfoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            debugLogger.info("Failed to get window info list")
            return []
        }

        let currentProcessID = Int(ProcessInfo.processInfo.processIdentifier)
        let maxScreenY = NSScreen.screens.map(\.frame.maxY).max() ?? screenFrame.maxY
        var targets: [ScreenshotCaptureTarget] = []
        var frontWindowRects: [CGRect] = []

        debugLogger.info("=== Start === PID=\(currentProcessID) totalWindows=\(windowInfoList.count)")

        for (index, info) in windowInfoList.enumerated() {
            let layer = intValue(info[kCGWindowLayer as String]) ?? -999
            let alpha = doubleValue(info[kCGWindowAlpha as String]) ?? 0
            let onscreen = boolValue(info[kCGWindowIsOnscreen as String]) ?? false
            let ownerPID = intValue(info[kCGWindowOwnerPID as String]) ?? 0
            let windowNumber = intValue(info[kCGWindowNumber as String]) ?? 0
            let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
            let windowName = info[kCGWindowName as String] as? String ?? ""
            let displayName = [ownerName, windowName].filter { !$0.isEmpty }.joined(separator: " - ")

            guard let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let quartzRect = CGRect(dictionaryRepresentation: boundsDictionary) else {
                debugLogger.info("#\(index) SKIP(no bounds) layer=\(layer) \(displayName)")
                continue
            }

            // 允许的窗口层级：0=普通窗口, 3=浮动面板, 20=Dock, 24=菜单栏, 25=控制中心项, 101=弹出菜单（右键菜单等）
            let allowedLayers: Set<Int> = [0, 3, 20, 24, 25, 101]
            guard allowedLayers.contains(layer) else {
                debugLogger.info("#\(index) SKIP(layer) layer=\(layer) \(displayName)")
                continue
            }

            // 系统 UI（Dock、菜单栏）的 bounds 远大于实际可见区域，特殊处理
            let isSystemUI = (layer == 20 || layer == 24)

            guard alpha > 0.05, onscreen == true else {
                debugLogger.info("#\(index) SKIP(alpha/onscreen) layer=\(layer) alpha=\(alpha) onScr=\(onscreen) \(displayName)")
                continue
            }

            let globalRect = CGRect(
                x: quartzRect.minX,
                y: maxScreenY - quartzRect.maxY,
                width: quartzRect.width,
                height: quartzRect.height
            )
            guard globalRect.width * globalRect.height >= 500 else {
                debugLogger.info("#\(index) SKIP(size) w=\(Int(globalRect.width)) h=\(Int(globalRect.height)) \(displayName)")
                continue
            }

            let clippedGlobalRect = globalRect.intersection(screenFrame)
            guard !clippedGlobalRect.isNull else {
                debugLogger.info("#\(index) SKIP(clip) \(displayName)")
                continue
            }

            let visibleRects = visibleRects(for: clippedGlobalRect, occludedBy: frontWindowRects)
            let visibleArea = visibleRects.reduce(CGFloat.zero) { $0 + $1.width * $1.height }
            let totalArea = clippedGlobalRect.width * clippedGlobalRect.height

            // 系统 UI 不加入遮挡计算（其 bounds 远大于实际可见区域，会影响其他窗口检测）
            if !isSystemUI {
                frontWindowRects.append(clippedGlobalRect)
            }

            let isFloatingPanel = (layer == 3)
            // 可见性检查：系统 UI 放宽（总是可见），普通窗口需要 >= 200 像素
            let minVisibleArea: CGFloat = isSystemUI ? 0 : 200
            // 排除自身进程的高层级窗口（overlay layer=27），
            // 但允许自身的普通窗口（如六边形工具箱 layer=0）通过
            let isSelfHighLayer = (ownerPID == currentProcessID && layer >= 24)
            guard !isSelfHighLayer,
                  visibleArea >= minVisibleArea else {
                debugLogger.info("#\(index) SKIP(visibility) pid=\(ownerPID) self=\(ownerPID == currentProcessID) selfHigh=\(isSelfHighLayer) visArea=\(Int(visibleArea))/\(Int(totalArea)) floating=\(isFloatingPanel) \(displayName)")
                continue
            }

            debugLogger.info("#\(index) ADD layer=\(layer) w=\(Int(globalRect.width)) h=\(Int(globalRect.height)) pid=\(ownerPID) \(displayName)")

            let screenRect = CGRect(
                x: clippedGlobalRect.minX - screenFrame.minX,
                y: screenFrame.maxY - clippedGlobalRect.maxY,
                width: clippedGlobalRect.width,
                height: clippedGlobalRect.height
            )
            let title = [displayName.isEmpty ? nil : displayName]
                .compactMap { $0 }
                .joined(separator: " - ")

            targets.append(ScreenshotCaptureTarget(
                id: windowNumber,
                kind: .window,
                globalRect: clippedGlobalRect,
                screenRect: screenRect,
                title: title.isEmpty ? nil : title,
                priority: Double(windowInfoList.count - index),
                pid: pid_t(ownerPID),
                layer: layer
            ))
        }

        return targets
    }

    private static func visibleRects(for rect: CGRect, occludedBy occluders: [CGRect]) -> [CGRect] {
        occluders.reduce([rect]) { visibleRects, occluder in
            visibleRects.flatMap { subtract(occluder, from: $0) }
        }
    }

    private static func subtract(_ occluder: CGRect, from rect: CGRect) -> [CGRect] {
        let intersection = rect.intersection(occluder)
        guard !intersection.isNull,
              intersection.width > 0,
              intersection.height > 0 else {
            return [rect]
        }

        var pieces: [CGRect] = []
        if intersection.minY > rect.minY {
            pieces.append(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: intersection.minY - rect.minY))
        }
        if intersection.maxY < rect.maxY {
            pieces.append(CGRect(x: rect.minX, y: intersection.maxY, width: rect.width, height: rect.maxY - intersection.maxY))
        }
        if intersection.minX > rect.minX {
            pieces.append(CGRect(x: rect.minX, y: intersection.minY, width: intersection.minX - rect.minX, height: intersection.height))
        }
        if intersection.maxX < rect.maxX {
            pieces.append(CGRect(x: intersection.maxX, y: intersection.minY, width: rect.maxX - intersection.maxX, height: intersection.height))
        }
        return pieces.filter { $0.width > 0 && $0.height > 0 }
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        return (value as? NSNumber)?.intValue
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }
        return (value as? NSNumber)?.doubleValue
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }
        return (value as? NSNumber)?.boolValue
    }
}

private enum ScreenshotAccessibilityDetector {
    /// 在全局 Quartz 坐标点命中一个 Accessibility 控件，直接返回命中元素的 AXFrame。
    /// 静默降级：未授权或无控件命中时返回 nil。
    ///
    /// 与 Snipaste 同方案：同步调 AXUIElementCopyElementAtPosition，
    /// 命中的就是最精确的那个控件（按钮、图标、文本框），不走 parent walk。
    /// 关键：用 AXUIElementCreateApplication(pid) 而非 systemWide，
    /// 因为 Overlay 窗口在最顶层会拦截 systemWide 的命中。
    static func target(
        at globalPoint: CGPoint,
        screenFrame: CGRect,
        maxScreenY: CGFloat,
        within windowTarget: ScreenshotCaptureTarget
    ) -> ScreenshotCaptureTarget? {
        guard AXIsProcessTrusted() else { return nil }

        let appElement = AXUIElementCreateApplication(windowTarget.pid)
        var hitElement: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            appElement,
            Float(globalPoint.x),
            Float(globalPoint.y),
            &hitElement
        )
        guard result == .success,
              let element = hitElement else { return nil }

        guard let axRect = axFrame(of: element) else { return nil }

        // AXFrame 与 CGWindowBounds 一样是全局屏幕坐标(左上原点,y向下)。
        // 这里走和 ScreenshotWindowTargetDetector 完全相同的转换路径：
        // 先转为 AppKit 全局坐标(globalRect)，再转为 SwiftUI 本地坐标(screenRect)。
        let globalRect = CGRect(
            x: axRect.minX,
            y: maxScreenY - axRect.maxY,
            width: axRect.width,
            height: axRect.height
        )
        let clippedRect = globalRect.intersection(screenFrame)
        guard !clippedRect.isNull else { return nil }
        let screenRect = CGRect(
            x: clippedRect.minX - screenFrame.minX,
            y: screenFrame.maxY - clippedRect.maxY,
            width: clippedRect.width,
            height: clippedRect.height
        )

        // 控件矩形必须比窗口候选小（否则就是窗口本身，无意义）
        guard screenRect.width < windowTarget.screenRect.width - 2
                || screenRect.height < windowTarget.screenRect.height - 2 else { return nil }

        // 控件矩形必须在窗口范围内（允许略微超出边界）
        guard screenRect.width >= 8,
              screenRect.height >= 8,
              windowTarget.screenRect.insetBy(dx: -4, dy: -4).intersects(screenRect) else { return nil }

        return ScreenshotCaptureTarget(
            id: windowTarget.id - 200_000,
            kind: .contour,
            globalRect: clippedRect,
            screenRect: screenRect,
            title: axTitle(of: element) ?? windowTarget.title,
            priority: windowTarget.priority + 1.0,
            pid: windowTarget.pid,
            layer: 0 // AX 控件始终为普通窗口层级
        )
    }

    private static func axFrame(of element: AXUIElement) -> CGRect? {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXFrame" as CFString, &rawValue) == .success,
              let value = rawValue else { return nil }
        let axValue = value as! AXValue
        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect) else { return nil }
        return rect
    }

    private static func axTitle(of element: AXUIElement) -> String? {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXTitle" as CFString, &rawValue) == .success,
              let value = rawValue as? String, !value.isEmpty else { return nil }
        return value
    }

}

private enum ScreenshotToolbarAction {
    case perform(ScreenshotResultAction)
    case undo
    case redo
    case cancel
}

private enum ScreenshotToolbarControlMode {
    case ocr
    case shape
    case text
}

struct ScreenshotCapturePayload {
    let rect: CGRect
    let image: NSImage?
    let canvasSize: CGSize
    let annotations: [ScreenshotAnnotation]
}

struct ScreenshotAnnotation: Identifiable {
    let id = UUID()
    let tool: ScreenshotDrawableTool
    var color: ScreenshotAnnotationColor
    var lineWidth: CGFloat
    var fontSize: CGFloat = 18
    var textColor: NSColor?
    var fontName: String = ScreenshotTextStyle.defaultFontName
    var isBold = true
    var isItalic = false
    var text: String = ""
    var textBoxSize: CGSize = CGSize(width: 128, height: 34)
    var points: [CGPoint]

    var effectiveNSColor: NSColor {
        textColor ?? color.nsColor
    }

    var effectiveSwiftUIColor: Color {
        Color(nsColor: effectiveNSColor)
    }

    var swiftUIFont: Font {
        var font = Font.custom(fontName, size: fontSize)
        if isBold {
            font = font.weight(.semibold)
        }
        if isItalic {
            font = font.italic()
        }
        return font
    }

    func nsFont(scale: CGFloat = 1) -> NSFont {
        ScreenshotTextStyle.nsFont(
            name: fontName,
            size: fontSize * scale,
            isBold: isBold,
            isItalic: isItalic
        )
    }
}

enum ScreenshotTextStyle {
    static let defaultFontName = ".AppleSystemUIFont"
    static let fontChoices: [(title: String, name: String)] = [
        ("系统", ".AppleSystemUIFont"),
        ("苹方", "PingFang SC"),
        ("Helvetica", "Helvetica Neue"),
        ("Menlo", "Menlo"),
        ("Georgia", "Georgia")
    ]

    static func title(for fontName: String) -> String {
        fontChoices.first { $0.name == fontName }?.title ?? fontName
    }

    static func nsFont(name: String, size: CGFloat, isBold: Bool, isItalic: Bool) -> NSFont {
        let baseFont = NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)
        var traits: NSFontTraitMask = []
        if isBold {
            traits.insert(.boldFontMask)
        }
        if isItalic {
            traits.insert(.italicFontMask)
        }
        return NSFontManager.shared.convert(baseFont, toHaveTrait: traits)
    }
}

enum ScreenshotDrawableTool {
    case text
    case pen
    case mosaic
    case line
    case arrow
    case rectangle
    case ellipse
}

enum ScreenshotAnnotationTool: CaseIterable, Identifiable {
    static let textGlyphName = "airsentry.text.tool"

    case cursor
    case text
    case rectangle
    case ellipse
    case line
    case arrow
    case pen
    case mosaic

    var id: Self { self }

    var drawableTool: ScreenshotDrawableTool {
        switch self {
        case .cursor:
            return .pen
        case .text:
            return .text
        case .rectangle:
            return .rectangle
        case .ellipse:
            return .ellipse
        case .line:
            return .line
        case .arrow:
            return .arrow
        case .pen:
            return .pen
        case .mosaic:
            return .mosaic
        }
    }

    var systemImage: String {
        switch self {
        case .cursor:
            return "cursorarrow"
        case .text:
            return Self.textGlyphName
        case .rectangle:
            return "rectangle"
        case .ellipse:
            return "circle"
        case .line:
            return "line.diagonal"
        case .arrow:
            return "arrow.up.right"
        case .pen:
            return "pencil.tip"
        case .mosaic:
            return "square.grid.3x3.fill"
        }
    }

    var title: String {
        switch self {
        case .cursor:
            return "移动选区"
        case .text:
            return "文字"
        case .rectangle:
            return "矩形"
        case .ellipse:
            return "椭圆"
        case .line:
            return "直线"
        case .arrow:
            return "箭头"
        case .pen:
            return "画笔"
        case .mosaic:
            return "马赛克"
        }
    }
}

enum ScreenshotAnnotationColor: CaseIterable, Identifiable {
    case red
    case yellow
    case blue
    case white
    case black

    var id: Self { self }

    var swiftUIColor: Color {
        switch self {
        case .red:
            return .red
        case .yellow:
            return .yellow
        case .blue:
            return .blue
        case .white:
            return .white
        case .black:
            return .black
        }
    }

    var nsColor: NSColor {
        switch self {
        case .red:
            return .systemRed
        case .yellow:
            return .systemYellow
        case .blue:
            return .systemBlue
        case .white:
            return .white
        case .black:
            return .black
        }
    }

    var title: String {
        switch self {
        case .red:
            return "红色"
        case .yellow:
            return "黄色"
        case .blue:
            return "蓝色"
        case .white:
            return "白色"
        case .black:
            return "黑色"
        }
    }
}

private struct ScreenshotOverlayMosaicSampler {
    private let bitmap: NSBitmapImageRep
    private let imageSize: CGSize

    init?(image: NSImage) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        self.bitmap = bitmap
        self.imageSize = image.size
    }

    func averageColor(in rect: CGRect) -> Color {
        let sampleRect = rect.intersection(CGRect(origin: .zero, size: imageSize))
        guard !sampleRect.isNull, sampleRect.width > 0, sampleRect.height > 0 else {
            return Color(nsColor: .systemGray)
        }

        let sampleColumns = 4
        let sampleRows = 4
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        var count: CGFloat = 0

        for column in 0..<sampleColumns {
            for row in 0..<sampleRows {
                let point = CGPoint(
                    x: sampleRect.minX + (CGFloat(column) + 0.5) * sampleRect.width / CGFloat(sampleColumns),
                    y: sampleRect.minY + (CGFloat(row) + 0.5) * sampleRect.height / CGFloat(sampleRows)
                )
                guard let color = color(at: point)?.usingColorSpace(.deviceRGB) else { continue }
                red += color.redComponent
                green += color.greenComponent
                blue += color.blueComponent
                alpha += color.alphaComponent
                count += 1
            }
        }

        guard count > 0 else {
            return Color(nsColor: .systemGray)
        }

        return Color(nsColor: NSColor(
            deviceRed: red / count,
            green: green / count,
            blue: blue / count,
            alpha: alpha / count
        ))
    }

    private func color(at point: CGPoint) -> NSColor? {
        let xRatio = imageSize.width > 0 ? point.x / imageSize.width : 0
        let yRatio = imageSize.height > 0 ? point.y / imageSize.height : 0
        let maxX = CGFloat(max(0, bitmap.pixelsWide - 1))
        let maxY = CGFloat(max(0, bitmap.pixelsHigh - 1))
        let x = Int(min(max(xRatio * CGFloat(bitmap.pixelsWide), 0), maxX))
        let y = Int(min(max(yRatio * CGFloat(bitmap.pixelsHigh), 0), maxY))
        return bitmap.colorAt(x: x, y: y)
    }
}

private func localRect(for annotation: ScreenshotAnnotation) -> CGRect? {
    guard let start = annotation.points.first,
          let end = annotation.points.last else { return nil }
    return CGRect(
        x: min(start.x, end.x),
        y: min(start.y, end.y),
        width: abs(start.x - end.x),
        height: abs(start.y - end.y)
    )
}

private func arrowHeadPoints(from start: CGPoint, to end: CGPoint, lineWidth: CGFloat) -> (CGPoint, CGPoint) {
    let angle = atan2(end.y - start.y, end.x - start.x)
    let length = max(10, lineWidth * 4)
    let spread = CGFloat.pi / 7
    return (
        CGPoint(x: end.x - length * cos(angle - spread), y: end.y - length * sin(angle - spread)),
        CGPoint(x: end.x - length * cos(angle + spread), y: end.y - length * sin(angle + spread))
    )
}

private enum ResizeHandle: CaseIterable, Identifiable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left

    var id: Self { self }

    var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            return true
        default:
            return false
        }
    }

    var cursor: NSCursor {
        switch self {
        case .top, .bottom:
            return .resizeUpDown
        case .left, .right:
            return .resizeLeftRight
        default:
            return .crosshair
        }
    }

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft:
            return CGPoint(x: rect.minX, y: rect.minY)
        case .top:
            return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight:
            return CGPoint(x: rect.maxX, y: rect.minY)
        case .right:
            return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight:
            return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom:
            return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft:
            return CGPoint(x: rect.minX, y: rect.maxY)
        case .left:
            return CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    func resizedRect(from rect: CGRect, translation: CGSize, bounds: CGRect) -> CGRect {
        let minimumSize: CGFloat = 16
        var minX = rect.minX
        var minY = rect.minY
        var maxX = rect.maxX
        var maxY = rect.maxY

        switch self {
        case .topLeft:
            minX = (rect.minX + translation.width).clamped(to: bounds.minX...(rect.maxX - minimumSize))
            minY = (rect.minY + translation.height).clamped(to: bounds.minY...(rect.maxY - minimumSize))
        case .top:
            minY = (rect.minY + translation.height).clamped(to: bounds.minY...(rect.maxY - minimumSize))
        case .topRight:
            maxX = (rect.maxX + translation.width).clamped(to: (rect.minX + minimumSize)...bounds.maxX)
            minY = (rect.minY + translation.height).clamped(to: bounds.minY...(rect.maxY - minimumSize))
        case .right:
            maxX = (rect.maxX + translation.width).clamped(to: (rect.minX + minimumSize)...bounds.maxX)
        case .bottomRight:
            maxX = (rect.maxX + translation.width).clamped(to: (rect.minX + minimumSize)...bounds.maxX)
            maxY = (rect.maxY + translation.height).clamped(to: (rect.minY + minimumSize)...bounds.maxY)
        case .bottom:
            maxY = (rect.maxY + translation.height).clamped(to: (rect.minY + minimumSize)...bounds.maxY)
        case .bottomLeft:
            minX = (rect.minX + translation.width).clamped(to: bounds.minX...(rect.maxX - minimumSize))
            maxY = (rect.maxY + translation.height).clamped(to: (rect.minY + minimumSize)...bounds.maxY)
        case .left:
            minX = (rect.minX + translation.width).clamped(to: bounds.minX...(rect.maxX - minimumSize))
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

private enum AnnotationResizeHandle: CaseIterable, Identifiable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var id: Self { self }

    var cursor: NSCursor {
        switch self {
        case .top, .bottom: return .resizeUpDown
        case .left, .right: return .resizeLeftRight
        default: return .crosshair
        }
    }

    func point(in bounds: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: bounds.minX, y: bounds.minY)
        case .top: return CGPoint(x: bounds.midX, y: bounds.minY)
        case .topRight: return CGPoint(x: bounds.maxX, y: bounds.minY)
        case .right: return CGPoint(x: bounds.maxX, y: bounds.midY)
        case .bottomRight: return CGPoint(x: bounds.maxX, y: bounds.maxY)
        case .bottom: return CGPoint(x: bounds.midX, y: bounds.maxY)
        case .bottomLeft: return CGPoint(x: bounds.minX, y: bounds.maxY)
        case .left: return CGPoint(x: bounds.minX, y: bounds.midY)
        }
    }

    func applyResize(to points: [CGPoint], translation: CGSize, bounds: CGRect) -> [CGPoint] {
        guard points.count >= 2 else { return points }
        let p0 = points[0], p1 = points[1]
        let minX = min(p0.x, p1.x), maxX = max(p0.x, p1.x)
        let minY = min(p0.y, p1.y), maxY = max(p0.y, p1.y)

        var newMinX = minX, newMaxX = maxX, newMinY = minY, newMaxY = maxY
        let minSize: CGFloat = 8

        switch self {
        case .topLeft:
            newMinX = (minX + translation.width).clamped(to: 0...(maxX - minSize))
            newMinY = (minY + translation.height).clamped(to: 0...(maxY - minSize))
        case .top:
            newMinY = (minY + translation.height).clamped(to: 0...(maxY - minSize))
        case .topRight:
            newMaxX = (maxX + translation.width).clamped(to: (minX + minSize)...bounds.width)
            newMinY = (minY + translation.height).clamped(to: 0...(maxY - minSize))
        case .right:
            newMaxX = (maxX + translation.width).clamped(to: (minX + minSize)...bounds.width)
        case .bottomRight:
            newMaxX = (maxX + translation.width).clamped(to: (minX + minSize)...bounds.width)
            newMaxY = (maxY + translation.height).clamped(to: (minY + minSize)...bounds.height)
        case .bottom:
            newMaxY = (maxY + translation.height).clamped(to: (minY + minSize)...bounds.height)
        case .bottomLeft:
            newMinX = (minX + translation.width).clamped(to: 0...(maxX - minSize))
            newMaxY = (maxY + translation.height).clamped(to: (minY + minSize)...bounds.height)
        case .left:
            newMinX = (minX + translation.width).clamped(to: 0...(maxX - minSize))
        }

        // 归一化返回 [topLeft, bottomRight]
        return [
            CGPoint(x: newMinX, y: newMinY),
            CGPoint(x: newMaxX, y: newMaxY)
        ]
    }
}


private extension NSCursor {
    static let diagonalResizeNWSE: NSCursor = {
        if let image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: nil) {
            image.size = NSSize(width: 18, height: 18)
            return NSCursor(image: image, hotSpot: NSPoint(x: 9, y: 9))
        }
        return .crosshair
    }()

    static let diagonalResizeNESW: NSCursor = {
        if let image = NSImage(systemSymbolName: "arrow.up.right.and.arrow.down.left", accessibilityDescription: nil) {
            image.size = NSSize(width: 18, height: 18)
            return NSCursor(image: image, hotSpot: NSPoint(x: 9, y: 9))
        }
        return .crosshair
    }()
}

private enum TextResizeHandle: CaseIterable, Identifiable {
    case topLeft
    case top
    case topRight
    case left
    case right
    case bottomLeft
    case bottom
    case bottomRight

    var id: Self { self }

    var cursor: NSCursor {
        switch self {
        case .topLeft, .bottomRight:
            return NSCursor.diagonalResizeNWSE
        case .topRight, .bottomLeft:
            return NSCursor.diagonalResizeNESW
        case .top, .bottom:
            return NSCursor.resizeUpDown
        case .left, .right:
            return NSCursor.resizeLeftRight
        }
    }

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft:
            return CGPoint(x: rect.minX, y: rect.minY)
        case .top:
            return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight:
            return CGPoint(x: rect.maxX, y: rect.minY)
        case .left:
            return CGPoint(x: rect.minX, y: rect.midY)
        case .right:
            return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomLeft:
            return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottom:
            return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomRight:
            return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    func resized(origin: CGPoint, size: CGSize, translation: CGSize, bounds: CGRect) -> TextResizeResult {
        let minimumWidth: CGFloat = 72
        let minimumHeight: CGFloat = 26
        var minX = origin.x
        var minY = origin.y
        var maxX = origin.x + size.width
        var maxY = origin.y + size.height

        switch self {
        case .topLeft:
            minX = (origin.x + translation.width).clamped(to: bounds.minX...(maxX - minimumWidth))
            minY = (origin.y + translation.height).clamped(to: bounds.minY...(maxY - minimumHeight))
        case .top:
            minY = (origin.y + translation.height).clamped(to: bounds.minY...(maxY - minimumHeight))
        case .topRight:
            maxX = (maxX + translation.width).clamped(to: (minX + minimumWidth)...bounds.maxX)
            minY = (origin.y + translation.height).clamped(to: bounds.minY...(maxY - minimumHeight))
        case .left:
            minX = (origin.x + translation.width).clamped(to: bounds.minX...(maxX - minimumWidth))
        case .right:
            maxX = (maxX + translation.width).clamped(to: (minX + minimumWidth)...bounds.maxX)
        case .bottomLeft:
            minX = (origin.x + translation.width).clamped(to: bounds.minX...(maxX - minimumWidth))
            maxY = (maxY + translation.height).clamped(to: (minY + minimumHeight)...bounds.maxY)
        case .bottom:
            maxY = (maxY + translation.height).clamped(to: (minY + minimumHeight)...bounds.maxY)
        case .bottomRight:
            maxX = (maxX + translation.width).clamped(to: (minX + minimumWidth)...bounds.maxX)
            maxY = (maxY + translation.height).clamped(to: (minY + minimumHeight)...bounds.maxY)
        }

        return TextResizeResult(
            origin: CGPoint(x: minX, y: minY),
            size: CGSize(width: maxX - minX, height: maxY - minY)
        )
    }

    func scale(startSize: CGSize, newSize: CGSize) -> CGFloat {
        let widthScale = newSize.width / max(startSize.width, 1)
        let heightScale = newSize.height / max(startSize.height, 1)

        switch self {
        case .left, .right:
            return widthScale
        case .top, .bottom:
            return heightScale
        default:
            // 四角拖动时，用变化更明显的方向作为字体缩放比例，拖横向或纵向都能明显反馈。
            return abs(widthScale - 1) > abs(heightScale - 1) ? widthScale : heightScale
        }
    }

}

private struct TextResizeResult {
    let origin: CGPoint
    let size: CGSize

    func fontSize(current: CGFloat) -> CGFloat {
        max(12, min(48, max(current, size.height - 16)))
    }
}

private final class FrozenBackgroundView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let screen = window?.screen {
            layer?.contentsScale = screen.backingScaleFactor
        }
    }
}

private struct ScreenshotFrozenBackground: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> FrozenBackgroundView {
        let view = FrozenBackgroundView()
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            view.layer?.contents = cgImage
            view.layer?.contentsGravity = .resizeAspectFill
            view.layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            view.layer?.actions = [
                "contents": NSNull(),
                "bounds": NSNull(),
                "position": NSNull(),
                "transform": NSNull(),
                "opacity": NSNull()
            ]
        }
        return view
    }

    func updateNSView(_ nsView: FrozenBackgroundView, context: Context) {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            nsView.layer?.contents = cgImage
        }
    }
}

private struct SelectionShape: Shape {
    let selection: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRect(selection)
        return path
    }
}

private struct ScreenshotMouseTracker: NSViewRepresentable {
    let onMove: (CGPoint) -> Void

    func makeNSView(context: Context) -> MouseTrackingView {
        let view = MouseTrackingView()
        view.onMove = onMove
        return view
    }

    func updateNSView(_ nsView: MouseTrackingView, context: Context) {
        nsView.onMove = onMove
        DispatchQueue.main.async {
            nsView.window?.acceptsMouseMovedEvents = true
        }
    }
}

private final class MouseTrackingView: NSView {
    var onMove: ((CGPoint) -> Void)?
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.activeInKeyWindow, .mouseMoved, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func mouseMoved(with event: NSEvent) {
        onMove?(convert(event.locationInWindow, from: nil))
    }
}

private struct ScreenshotOverlayKeyCatcher: NSViewRepresentable {
    let isEnabled: Bool
    let handleKeyDown: (NSEvent) -> Void

    func makeNSView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView()
        view.isEnabled = isEnabled
        view.handleKeyDown = handleKeyDown
        if isEnabled {
            DispatchQueue.main.async {
                view.window?.makeFirstResponder(view)
            }
        }
        return view
    }

    func updateNSView(_ nsView: KeyCatcherView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.handleKeyDown = handleKeyDown
        if isEnabled {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

private final class KeyCatcherView: NSView {
    var isEnabled = true
    var handleKeyDown: ((NSEvent) -> Void)?

    override var acceptsFirstResponder: Bool { isEnabled }

    override func keyDown(with event: NSEvent) {
        if isEnabled {
            handleKeyDown?(event)
        } else {
            super.keyDown(with: event)
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension Notification.Name {
    static let screenshotOverlayCancelRequested = Notification.Name("AirSentry.ScreenshotOverlayCancelRequested")
}
