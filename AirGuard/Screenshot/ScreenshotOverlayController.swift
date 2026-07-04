import AppKit
import SwiftUI

@MainActor
final class ScreenshotOverlayController {
    private var windows: [ScreenshotOverlayWindow] = []
    private let onAction: (ScreenshotResultAction, ScreenshotCapturePayload) -> Void
    private let onCancel: () -> Void
    private var didFinish = false

    init(onAction: @escaping (ScreenshotResultAction, ScreenshotCapturePayload) -> Void, onCancel: @escaping () -> Void) {
        self.onAction = onAction
        self.onCancel = onCancel
    }

    func show() {
        windows = NSScreen.screens.map { screen in
            let view = ScreenshotOverlayView(
                screenFrame: screen.frame,
                perform: { [weak self] action, payload in self?.perform(action, payload: payload) },
                cancel: { [weak self] in self?.cancel() }
            )

            let window = ScreenshotOverlayWindow(screen: screen)
            window.contentView = NSHostingView(rootView: view)
            return window
        }

        NSApp.activate(ignoringOtherApps: true)
        windows.forEach { $0.orderFrontRegardless() }
        windows.first?.makeKeyAndOrderFront(nil)
    }

    private func perform(_ action: ScreenshotResultAction, payload: ScreenshotCapturePayload) {
        guard !didFinish else { return }
        didFinish = true
        closeWindows()
        onAction(action, payload)
    }

    private func cancel() {
        guard !didFinish else { return }
        didFinish = true
        closeWindows()
        onCancel()
    }

    private func closeWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}

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
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        NotificationCenter.default.post(name: .screenshotOverlayCancelRequested, object: nil)
    }
}

private struct ScreenshotOverlayView: View {
    let screenFrame: CGRect
    let perform: (ScreenshotResultAction, ScreenshotCapturePayload) -> Void
    let cancel: () -> Void

    @State private var startPoint: CGPoint?
    @State private var currentPoint: CGPoint?
    @State private var selectedRect: CGRect?
    @State private var interactionStartRect: CGRect?
    @State private var selectedTool: ScreenshotAnnotationTool = .cursor
    @State private var selectedColor: ScreenshotAnnotationColor = .red
    @State private var selectedLineWidth: CGFloat = 3
    @State private var annotations: [ScreenshotAnnotation] = []
    @State private var draftAnnotation: ScreenshotAnnotation?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.34)

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
                            canUndo: !annotations.isEmpty
                        ) { toolbarAction in
                            handleToolbarAction(toolbarAction, selection: selection)
                        }
                        .position(toolbarPosition(for: selection, in: proxy.size))
                    }
                }
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .gesture(initialSelectionGesture(in: proxy.size))
            .onReceive(NotificationCenter.default.publisher(for: .screenshotOverlayCancelRequested)) { _ in
                cancel()
            }
            .background(ScreenshotOverlayKeyCatcher(cancel: cancel))
        }
    }

    private func initialSelectionGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                guard selectedRect == nil else { return }
                if startPoint == nil {
                    startPoint = value.startLocation
                }
                currentPoint = value.location
            }
            .onEnded { value in
                guard selectedRect == nil else { return }
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

    private func selectionLayer(_ selection: CGRect, in size: CGSize) -> some View {
        ZStack {
            annotationCanvas(selection)

            if selectedTool == .cursor {
                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: selection.width, height: selection.height)
                    .position(x: selection.midX, y: selection.midY)
                    .gesture(moveGesture(in: size))
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: selection.width, height: selection.height)
                    .position(x: selection.midX, y: selection.midY)
                    .gesture(annotationGesture(in: selection))
            }

            Rectangle()
                .stroke(.white, lineWidth: 1)
                .frame(width: selection.width, height: selection.height)
                .position(x: selection.midX, y: selection.midY)
                .allowsHitTesting(false)

            ForEach(ResizeHandle.allCases) { handle in
                Circle()
                    .fill(.white)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 1))
                    .position(handle.point(in: selection))
                    .gesture(resizeGesture(handle: handle, in: size))
            }
        }
    }

    private func annotationCanvas(_ selection: CGRect) -> some View {
        Canvas { context, _ in
            for annotation in annotations {
                draw(annotation, in: &context)
            }
            if let draftAnnotation {
                draw(draftAnnotation, in: &context)
            }
        }
        .frame(width: selection.width, height: selection.height)
        .position(x: selection.midX, y: selection.midY)
        .allowsHitTesting(false)
    }

    private func draw(_ annotation: ScreenshotAnnotation, in context: inout GraphicsContext) {
        var path = Path()
        let stroke = StrokeStyle(lineWidth: annotation.lineWidth, lineCap: .round, lineJoin: .round)

        switch annotation.tool {
        case .pen:
            guard let firstPoint = annotation.points.first else { return }
            path.move(to: firstPoint)
            annotation.points.dropFirst().forEach { path.addLine(to: $0) }
            context.stroke(path, with: .color(annotation.color.swiftUIColor), style: stroke)
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

    private func annotationGesture(in selection: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
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
                        points: [localStart]
                    )
                }

                guard var draftAnnotation else { return }
                if selectedTool == .pen {
                    draftAnnotation.points.append(localPoint)
                } else {
                    draftAnnotation.points = [localStart, localPoint]
                }
                self.draftAnnotation = draftAnnotation
            }
            .onEnded { _ in
                if let draftAnnotation, draftAnnotation.points.count >= 2 {
                    annotations.append(draftAnnotation)
                }
                draftAnnotation = nil
            }
    }

    private func moveGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
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
            .onEnded { _ in
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
        return ScreenshotCapturePayload(
            rect: rect,
            canvasSize: selection.size,
            annotations: annotations
        )
    }

    private func handleToolbarAction(_ toolbarAction: ScreenshotToolbarAction, selection: CGRect) {
        switch toolbarAction {
        case .perform(let action):
            guard let payload = capturePayload(from: selection) else { return }
            perform(action, payload)
        case .undo:
            _ = annotations.popLast()
        case .cancel:
            cancel()
        }
    }

    private func toolbarPosition(for selection: CGRect, in size: CGSize) -> CGPoint {
        let toolbarSize = CGSize(width: 430, height: 76)
        let x = min(max(selection.midX, toolbarSize.width / 2 + 10), size.width - toolbarSize.width / 2 - 10)
        let preferredY = selection.maxY + toolbarSize.height / 2 + 10
        let y = preferredY <= size.height - 12 ? preferredY : max(toolbarSize.height / 2 + 12, selection.minY - toolbarSize.height / 2 - 10)
        return CGPoint(x: x, y: y)
    }
}

private struct ScreenshotSelectionToolbar: View {
    @Binding var selectedTool: ScreenshotAnnotationTool
    @Binding var selectedColor: ScreenshotAnnotationColor
    @Binding var selectedLineWidth: CGFloat
    let canUndo: Bool
    let action: (ScreenshotToolbarAction) -> Void

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 6) {
                ForEach(ScreenshotAnnotationTool.allCases) { tool in
                    iconButton(tool.systemImage, tool.title, isSelected: selectedTool == tool) {
                        selectedTool = tool
                    }
                }

                Divider()
                    .frame(height: 22)

                iconButton("arrow.uturn.backward", "撤销", isSelected: false) {
                    action(.undo)
                }
                .disabled(!canUndo)
                .opacity(canUndo ? 1 : 0.42)

                iconButton("pin", "钉图", isSelected: false) {
                    action(.perform(.pin))
                }

                iconButton("doc.on.doc", "复制", isSelected: false) {
                    action(.perform(.copy))
                }

                iconButton("square.and.arrow.down", "保存", isSelected: false) {
                    action(.perform(.save))
                }

                iconButton("checkmark", "完成并复制", isSelected: false) {
                    action(.perform(.copy))
                }

                iconButton("xmark", "关闭", isSelected: false) {
                    action(.cancel)
                }
            }

            HStack(spacing: 8) {
                ForEach(ScreenshotAnnotationColor.allCases) { color in
                    Button {
                        selectedColor = color
                    } label: {
                        Circle()
                            .fill(color.swiftUIColor)
                            .frame(width: 16, height: 16)
                            .overlay(
                                Circle()
                                    .stroke(selectedColor == color ? Color.white : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(color.title)
                }

                Divider()
                    .frame(height: 18)

                ForEach([CGFloat(2), CGFloat(4), CGFloat(7)], id: \.self) { width in
                    Button {
                        selectedLineWidth = width
                    } label: {
                        Circle()
                            .fill(Color.white)
                            .frame(width: width + 5, height: width + 5)
                            .frame(width: 20, height: 20)
                            .background(
                                selectedLineWidth == width ? Color.white.opacity(0.18) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("线宽 \(Int(width))")
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.30), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.24), radius: 14, y: 6)
    }

    private func iconButton(_ image: String, _ title: String, isSelected: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: image)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 24, height: 24)
                .foregroundStyle(.white)
                .background(
                    isSelected ? Color.blue : Color.black.opacity(0.54),
                    in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(isSelected ? Color.white.opacity(0.45) : Color.white.opacity(0.34), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

private enum ScreenshotToolbarAction {
    case perform(ScreenshotResultAction)
    case undo
    case cancel
}

struct ScreenshotCapturePayload {
    let rect: CGRect
    let canvasSize: CGSize
    let annotations: [ScreenshotAnnotation]
}

struct ScreenshotAnnotation: Identifiable {
    let id = UUID()
    let tool: ScreenshotDrawableTool
    let color: ScreenshotAnnotationColor
    let lineWidth: CGFloat
    var points: [CGPoint]
}

enum ScreenshotDrawableTool {
    case pen
    case line
    case arrow
    case rectangle
    case ellipse
}

enum ScreenshotAnnotationTool: CaseIterable, Identifiable {
    case cursor
    case rectangle
    case ellipse
    case line
    case arrow
    case pen

    var id: Self { self }

    var drawableTool: ScreenshotDrawableTool {
        switch self {
        case .cursor:
            return .pen
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
        }
    }

    var systemImage: String {
        switch self {
        case .cursor:
            return "cursorarrow"
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
        }
    }

    var title: String {
        switch self {
        case .cursor:
            return "移动选区"
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
    case topRight
    case bottomLeft
    case bottomRight

    var id: Self { self }

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft:
            return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight:
            return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft:
            return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight:
            return CGPoint(x: rect.maxX, y: rect.maxY)
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
        case .topRight:
            maxX = (rect.maxX + translation.width).clamped(to: (rect.minX + minimumSize)...bounds.maxX)
            minY = (rect.minY + translation.height).clamped(to: bounds.minY...(rect.maxY - minimumSize))
        case .bottomLeft:
            minX = (rect.minX + translation.width).clamped(to: bounds.minX...(rect.maxX - minimumSize))
            maxY = (rect.maxY + translation.height).clamped(to: (rect.minY + minimumSize)...bounds.maxY)
        case .bottomRight:
            maxX = (rect.maxX + translation.width).clamped(to: (rect.minX + minimumSize)...bounds.maxX)
            maxY = (rect.maxY + translation.height).clamped(to: (rect.minY + minimumSize)...bounds.maxY)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
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

private struct ScreenshotOverlayKeyCatcher: NSViewRepresentable {
    let cancel: () -> Void

    func makeNSView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView()
        view.cancel = cancel
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: KeyCatcherView, context: Context) {
        nsView.cancel = cancel
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

private final class KeyCatcherView: NSView {
    var cancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            cancel?()
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
