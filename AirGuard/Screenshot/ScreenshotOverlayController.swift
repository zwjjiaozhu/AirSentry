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
                screenImage: ScreenshotImageCapturer.capture(rect: screen.frame),
                perform: { [weak self] action, payload in self?.perform(action, payload: payload) },
                cancel: { [weak self] in self?.cancel() }
            )

            let window = ScreenshotOverlayWindow(screen: screen)
            window.contentView = NSHostingView(rootView: view)
            return window
        }

        windows.forEach { $0.orderFrontRegardless() }
        windows.first?.makeKeyAndOrderFront(nil)
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
        windows.forEach { window in
            window.makeFirstResponder(nil)
            window.contentView = nil
            window.orderOut(nil)
            window.close()
        }
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
    let screenImage: NSImage?
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
    @State private var resizingTextAnnotationID: UUID?
    @State private var resizingTextStartPoint: CGPoint?
    @State private var resizingTextStartSize: CGSize?
    @State private var resizingTextStartFontSize: CGFloat?
    @State private var scalingTextAnnotationID: UUID?
    @State private var scalingTextStartSize: CGSize?
    @State private var scalingTextStartFontSize: CGFloat?
    @State private var isTextCursorPushed = false
    @State private var mosaicSampler: ScreenshotOverlayMosaicSampler?
    @FocusState private var focusedTextAnnotationID: UUID?

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
                            setTextItalic: updateSelectedTextItalic
                        ) { toolbarAction in
                            handleToolbarAction(toolbarAction, selection: selection)
                        }
                        .position(toolbarPosition(for: selection, in: proxy.size))
                    }
                } else {
                    Color.black.opacity(0.34)
                }

                ScreenshotShortcutHintPanel()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 22)
                    .padding(.bottom, 24)
                    .allowsHitTesting(false)
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
            }
            .onAppear {
                if mosaicSampler == nil, let screenImage {
                    mosaicSampler = ScreenshotOverlayMosaicSampler(image: screenImage)
                }
            }
            .background(ScreenshotOverlayKeyCatcher(isEnabled: focusedTextAnnotationID == nil) { event in
                handleKeyDown(event, in: proxy.size)
            })
        }
    }

    private func initialSelectionGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: selectedTool == .text ? 0 : 1, coordinateSpace: .local)
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
                    .onHover { hovering in
                        updateTextCursor(hovering && selectedTool == .text)
                    }
                    .gesture(annotationGesture(in: selection))
            }

            textAnnotationLayer(selection)

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
        guard selectedAnnotationID == annotation.id,
              let rect = annotationBounds(annotation)?.insetBy(dx: -4, dy: -4) else { return }
        var path = Path()
        path.addRect(rect)
        context.stroke(path, with: .color(.white.opacity(0.80)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
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
                                    selectedAnnotationID == annotation.id ? Color.white.opacity(0.82) : Color.clear,
                                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                                )
                        )
                        .overlay {
                            if selectedAnnotationID == annotation.id {
                                textSelectionControls(for: annotation)
                            }
                        }
                        .position(x: origin.x + textBounds(for: annotation).width / 2,
                                  y: origin.y + textBounds(for: annotation).height / 2)
                        .onTapGesture {
                            selectAnnotation(annotation)
                        }
                        .simultaneousGesture(textMoveGesture(annotationID: annotation.id, in: selection))
                }
            }
        }
        .frame(width: selection.width, height: selection.height)
        .position(x: selection.midX, y: selection.midY)
    }

    private func annotationGesture(in selection: CGRect) -> some Gesture {
        DragGesture(minimumDistance: selectedTool == .text ? 0 : 1, coordinateSpace: .local)
            .onChanged { value in
                if selectedTool == .text {
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

    private func textSelectionControls(for annotation: ScreenshotAnnotation) -> some View {
        ZStack {
            ForEach(TextResizeHandle.allCases) { handle in
                Circle()
                    .fill(Color.blue)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(.white, lineWidth: 1.2))
                    .position(handle.point(in: CGRect(origin: .zero, size: textBounds(for: annotation))))
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
            .position(x: textBounds(for: annotation).width + 8, y: -8)

            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.blue, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .position(x: textBounds(for: annotation).width + 8, y: textBounds(for: annotation).height + 8)
                .gesture(textScaleGesture(annotationID: annotation.id))
        }
        .allowsHitTesting(true)
    }

    private func textResizeGesture(annotationID: UUID, handle: TextResizeHandle) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                guard let index = annotations.firstIndex(where: { $0.id == annotationID }),
                      annotations[index].tool == .text,
                      let origin = annotations[index].points.first else { return }

                if resizingTextAnnotationID != annotationID {
                    resizingTextAnnotationID = annotationID
                    resizingTextStartPoint = origin
                    resizingTextStartSize = annotations[index].textBoxSize
                    resizingTextStartFontSize = annotations[index].fontSize
                    selectedAnnotationID = annotationID
                    focusedTextAnnotationID = annotationID
                }

                guard let startPoint = resizingTextStartPoint,
                      let startSize = resizingTextStartSize,
                      let startFontSize = resizingTextStartFontSize else { return }

                let scale = handle.scale(
                    size: startSize,
                    translation: value.translation
                )
                let fontSize = max(12, min(72, startFontSize * scale))
                let size = textBoxSize(text: annotations[index].text, fontSize: fontSize)
                let scaledOrigin = handle.originForScaledText(
                    startOrigin: startPoint,
                    startSize: startSize,
                    newSize: size
                )
                annotations[index].points = [scaledOrigin]
                annotations[index].fontSize = fontSize
                annotations[index].textBoxSize = size
                selectedFontSize = fontSize
            }
            .onEnded { _ in
                resizingTextAnnotationID = nil
                resizingTextStartPoint = nil
                resizingTextStartSize = nil
                resizingTextStartFontSize = nil
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
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                guard let index = annotations.firstIndex(where: { $0.id == annotationID }),
                      annotations[index].tool == .text,
                      let origin = annotations[index].points.first else { return }

                if movingTextAnnotationStartPoint == nil {
                    movingTextAnnotationStartPoint = origin
                    selectedAnnotationID = annotationID
                    focusedTextAnnotationID = annotationID
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
            annotations: visibleAnnotations
        )
    }

    private func handleToolbarAction(_ toolbarAction: ScreenshotToolbarAction, selection: CGRect) {
        switch toolbarAction {
        case .perform(let action):
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
        let toolbarSize = CGSize(width: 540, height: 80)
        let rightEdge = min(max(selection.maxX, toolbarSize.width + 10), size.width - 10)
        let x = rightEdge - toolbarSize.width / 2
        let preferredY = selection.maxY + toolbarSize.height / 2 + 10
        let y = preferredY <= size.height - 12 ? preferredY : max(toolbarSize.height / 2 + 12, selection.minY - toolbarSize.height / 2 - 10)
        return CGPoint(x: x, y: y)
    }

    private func handleKeyDown(_ event: NSEvent, in size: CGSize) {
        if event.keyCode == 53 {
            cancel()
            return
        }

        if event.keyCode == 36 || event.keyCode == 76 {
            performActiveSelection(.copy, in: size)
            return
        }

        if event.keyCode == 51 || event.keyCode == 117 {
            undoLastAnnotation()
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
        DispatchQueue.main.async {
            focusedTextAnnotationID = annotation.id
        }
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
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        redoAnnotations.removeAll()
        annotations.remove(at: index)
        if selectedAnnotationID == id {
            selectedAnnotationID = nil
        }
        if focusedTextAnnotationID == id {
            focusedTextAnnotationID = nil
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
        removeEmptyTextAnnotations(keeping: annotationID)
    }

    private func removeEmptyTextAnnotations(keeping annotationID: UUID? = nil) {
        annotations.removeAll { annotation in
            annotation.tool == .text &&
            annotation.id != annotationID &&
            annotation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if let selectedAnnotationID,
           !annotations.contains(where: { $0.id == selectedAnnotationID }) {
            self.selectedAnnotationID = nil
        }
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

                    iconButton("square.and.arrow.down", "保存为 PNG", isSelected: false) {
                        action(.perform(.save))
                    }

                    iconButton("doc.on.doc", "复制到剪贴板", isSelected: false) {
                        action(.perform(.copy))
                    }
                }

                if let controlMode {
                    HStack(spacing: 4) {
                        if controlMode == .text {
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

                            ColorPicker("", selection: Binding(
                                get: { selectedTextColor },
                                set: { setTextColor($0) }
                            ))
                            .labelsHidden()
                            .frame(width: 34, height: 34)
                            .background(alignment: .bottom) {
                                Rectangle()
                                    .fill(Color.blue.opacity(0.95))
                                    .frame(height: 2)
                                    .opacity(hoveredItemID == "text-color" ? 1 : 0)
                                    .padding(.horizontal, 4)
                            }
                            .onHover { hovering in
                                hoveredItemID = hovering ? "text-color" : nil
                                hoveredTooltip = hovering ? "字体颜色" : nil
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

private enum ScreenshotToolbarAction {
    case perform(ScreenshotResultAction)
    case undo
    case redo
    case cancel
}

private enum ScreenshotToolbarControlMode {
    case shape
    case text
}

struct ScreenshotCapturePayload {
    let rect: CGRect
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

private enum TextResizeHandle: CaseIterable, Identifiable {
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

    func resized(origin: CGPoint, size: CGSize, translation: CGSize) -> TextResizeResult {
        let minimumWidth: CGFloat = 72
        let minimumHeight: CGFloat = 26
        var newOrigin = origin
        var newSize = size

        switch self {
        case .topLeft:
            newOrigin.x = origin.x + min(translation.width, size.width - minimumWidth)
            newOrigin.y = origin.y + min(translation.height, size.height - minimumHeight)
            newSize.width = max(minimumWidth, size.width - translation.width)
            newSize.height = max(minimumHeight, size.height - translation.height)
        case .topRight:
            newOrigin.y = origin.y + min(translation.height, size.height - minimumHeight)
            newSize.width = max(minimumWidth, size.width + translation.width)
            newSize.height = max(minimumHeight, size.height - translation.height)
        case .bottomLeft:
            newOrigin.x = origin.x + min(translation.width, size.width - minimumWidth)
            newSize.width = max(minimumWidth, size.width - translation.width)
            newSize.height = max(minimumHeight, size.height + translation.height)
        case .bottomRight:
            newSize.width = max(minimumWidth, size.width + translation.width)
            newSize.height = max(minimumHeight, size.height + translation.height)
        }

        return TextResizeResult(origin: newOrigin, size: newSize)
    }

    func scale(size: CGSize, translation: CGSize) -> CGFloat {
        let widthScale: CGFloat
        let heightScale: CGFloat

        switch self {
        case .topLeft:
            widthScale = (size.width - translation.width) / max(size.width, 1)
            heightScale = (size.height - translation.height) / max(size.height, 1)
        case .topRight:
            widthScale = (size.width + translation.width) / max(size.width, 1)
            heightScale = (size.height - translation.height) / max(size.height, 1)
        case .bottomLeft:
            widthScale = (size.width - translation.width) / max(size.width, 1)
            heightScale = (size.height + translation.height) / max(size.height, 1)
        case .bottomRight:
            widthScale = (size.width + translation.width) / max(size.width, 1)
            heightScale = (size.height + translation.height) / max(size.height, 1)
        }

        let candidate = abs(widthScale - 1) > abs(heightScale - 1) ? widthScale : heightScale
        return max(0.45, min(3.0, candidate))
    }

    func originForScaledText(startOrigin: CGPoint, startSize: CGSize, newSize: CGSize) -> CGPoint {
        switch self {
        case .topLeft:
            return CGPoint(
                x: startOrigin.x + startSize.width - newSize.width,
                y: startOrigin.y + startSize.height - newSize.height
            )
        case .topRight:
            return CGPoint(
                x: startOrigin.x,
                y: startOrigin.y + startSize.height - newSize.height
            )
        case .bottomLeft:
            return CGPoint(
                x: startOrigin.x + startSize.width - newSize.width,
                y: startOrigin.y
            )
        case .bottomRight:
            return startOrigin
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
