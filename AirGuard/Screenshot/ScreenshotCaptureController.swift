import AppKit
import CoreGraphics
import Foundation

@MainActor
final class ScreenshotCaptureController: ObservableObject {
    private var overlayController: ScreenshotOverlayController?
    private let pinnedImageController = PinnedImageController()
    private var ocrCaptureObserver: NSObjectProtocol?

    init() {
        ocrCaptureObserver = NotificationCenter.default.addObserver(
            forName: .ocrCaptureRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.startOCRCapture()
            }
        }
    }

    deinit {
        if let ocrCaptureObserver {
            NotificationCenter.default.removeObserver(ocrCaptureObserver)
        }
    }

    func startCapture() {
        guard overlayController == nil else { return }

        guard ScreenshotPermission.canCaptureScreen else {
            ScreenshotPermission.showScreenCapturePermissionAlert()
            return
        }

        let controller = ScreenshotOverlayController(
            onAction: { [weak self] action, payload in
                self?.overlayController = nil
                self?.handleSelection(payload, action: action)
            },
            onCancel: { [weak self] in
                self?.overlayController = nil
            }
        )
        overlayController = controller
        controller.show()
    }

    func pinClipboardImageIfAvailable() {
        guard let image = ClipboardPinnedImageFactory.image(from: NSPasteboard.general) else {
            NSSound.beep()
            return
        }
        pinnedImageController.pin(image)
    }

    func startOCRCapture() {
        startCapture()
    }

    private func handleSelection(_ payload: ScreenshotCapturePayload, action: ScreenshotResultAction) {
        let rect = payload.rect
        guard rect.width >= 4, rect.height >= 4 else {
            NSSound.beep()
            return
        }

        guard let image = payload.image ?? ScreenshotImageCapturer.capture(rect: rect) else {
            ScreenshotPermission.showScreenCapturePermissionAlert()
            return
        }

        let outputImage = ScreenshotAnnotationRenderer.render(
            baseImage: image,
            annotations: payload.annotations,
            canvasSize: payload.canvasSize
        )

        switch action {
        case .pin:
            pinnedImageController.pin(outputImage, near: rect)
        case .annotate:
            ScreenshotAnnotationPrompter.showComingSoon()
        case .ocr:
            OCRPanelController.shared.show(image: outputImage, recognizeImmediately: true)
        case .copy:
            ScreenshotImageWriter.copyToPasteboard(outputImage)
        case .save:
            ScreenshotImageWriter.saveWithPanel(outputImage)
        case .close:
            return
        }
    }
}

enum ClipboardPinnedImageFactory {
    static func image(from pasteboard: NSPasteboard) -> NSImage? {
        if let image = pasteboard.readObjects(forClasses: [NSImage.self])?.first as? NSImage {
            return image
        }

        guard let text = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }

        return textImage(for: text)
    }

    private static func textImage(for text: String) -> NSImage? {
        let maxTextWidth: CGFloat = 520
        let padding = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = 4

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let measuredSize = attributedText.boundingRect(
            with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).integral.size
        let imageSize = CGSize(
            width: ceil(measuredSize.width + padding.left + padding.right),
            height: ceil(measuredSize.height + padding.top + padding.bottom)
        )
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }

        let image = NSImage(size: imageSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = CGRect(origin: .zero, size: imageSize)
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).fill()

        NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
        let borderPath = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14)
        borderPath.lineWidth = 1
        borderPath.stroke()

        attributedText.draw(
            with: CGRect(
                x: padding.left,
                y: padding.bottom,
                width: measuredSize.width,
                height: measuredSize.height
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return image
    }
}

enum ScreenshotPermission {
    static var canCaptureScreen: Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }

    static func showScreenCapturePermissionAlert() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "需要开启屏幕录制权限"
        alert.informativeText = "截图钉图需要读取屏幕内容。请在系统设置的“隐私与安全性 > 屏幕录制”中允许 AirSentry。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")

        if alert.runModal() == .alertFirstButtonReturn {
            if #available(macOS 10.15, *) {
                _ = CGRequestScreenCaptureAccess()
            }

            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

enum ScreenshotImageCapturer {
    static func capture(rect: CGRect) -> NSImage? {
        let normalizedRect = CGRect(
            x: floor(rect.origin.x),
            y: floor(rect.origin.y),
            width: floor(rect.width),
            height: floor(rect.height)
        )

        let quartzRect = convertToQuartzScreenRect(normalizedRect)
        guard let cgImage = CGWindowListCreateImage(
            quartzRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) else {
            return nil
        }

        let image = NSImage(cgImage: cgImage, size: normalizedRect.size)
        image.isTemplate = false
        return image
    }

    static func crop(image: NSImage, rect: CGRect) -> NSImage? {
        let normalizedRect = CGRect(
            x: floor(rect.origin.x),
            y: floor(rect.origin.y),
            width: floor(rect.width),
            height: floor(rect.height)
        )
        guard normalizedRect.width >= 1,
              normalizedRect.height >= 1,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let scaleX = CGFloat(cgImage.width) / max(image.size.width, 1)
        let scaleY = CGFloat(cgImage.height) / max(image.size.height, 1)
        let pixelRect = CGRect(
            x: normalizedRect.minX * scaleX,
            y: normalizedRect.minY * scaleY,
            width: normalizedRect.width * scaleX,
            height: normalizedRect.height * scaleY
        ).integral.intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

        guard !pixelRect.isNull,
              pixelRect.width >= 1,
              pixelRect.height >= 1,
              let croppedImage = cgImage.cropping(to: pixelRect) else {
            return nil
        }

        let outputImage = NSImage(cgImage: croppedImage, size: normalizedRect.size)
        outputImage.isTemplate = false
        return outputImage
    }

    private static func convertToQuartzScreenRect(_ rect: CGRect) -> CGRect {
        let maxScreenY = NSScreen.screens.map { $0.frame.maxY }.max() ?? 0
        return CGRect(
            x: rect.origin.x,
            y: maxScreenY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}

enum ScreenshotImageWriter {
    static func copyToPasteboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    @discardableResult
    static func saveWithPanel(_ image: NSImage) -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "AirSentry Screenshot \(Self.timestamp()).png"
        panel.canCreateDirectories = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK,
              let url = panel.url else { return false }

        do {
            guard let data = pngData(from: image) else {
                NSSound.beep()
                return false
            }
            try data.write(to: url)
            return true
        } catch {
            NSSound.beep()
            NSLog("AirSentry screenshot save failed: \(error.localizedDescription)")
            return false
        }
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: Date())
    }
}

enum ScreenshotAnnotationPrompter {
    static func showComingSoon() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "批注功能正在路上"
        alert.informativeText = "当前版本先支持截图预览、复制、保存和钉图。下一步会加入画笔、箭头、矩形、文字和马赛克。"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }
}

enum ScreenshotAnnotationRenderer {
    static func render(
        baseImage: NSImage,
        annotations: [ScreenshotAnnotation],
        canvasSize: CGSize
    ) -> NSImage {
        guard !annotations.isEmpty,
              canvasSize.width > 0,
              canvasSize.height > 0 else {
            return baseImage
        }

        let outputSize = baseImage.size
        let image = NSImage(size: outputSize)
        image.lockFocus()
        baseImage.draw(in: CGRect(origin: .zero, size: outputSize))

        let scaleX = outputSize.width / canvasSize.width
        let scaleY = outputSize.height / canvasSize.height
        let mosaicSampler = ScreenshotMosaicSampler(image: baseImage)
        for annotation in annotations {
            draw(
                annotation,
                scaleX: scaleX,
                scaleY: scaleY,
                outputHeight: outputSize.height,
                mosaicSampler: mosaicSampler
            )
        }

        image.unlockFocus()
        return image
    }

    private static func draw(
        _ annotation: ScreenshotAnnotation,
        scaleX: CGFloat,
        scaleY: CGFloat,
        outputHeight: CGFloat,
        mosaicSampler: ScreenshotMosaicSampler?
    ) {
        let color = annotation.tool == .text ? annotation.effectiveNSColor : annotation.effectiveStrokeNSColor
        color.setStroke()
        color.setFill()

        let path = NSBezierPath()
        path.lineWidth = annotation.lineWidth * min(scaleX, scaleY)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        switch annotation.tool {
        case .text:
            guard let origin = annotation.points.first else { return }
            let point = transform(origin, scaleX: scaleX, scaleY: scaleY, outputHeight: outputHeight)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: annotation.nsFont(scale: min(scaleX, scaleY)),
                .foregroundColor: color
            ]
            let text = NSString(string: annotation.text)
            let textSize = text.size(withAttributes: attributes)
            text.draw(
                at: CGPoint(x: point.x, y: point.y - textSize.height),
                withAttributes: attributes
            )
        case .counter:
            drawCounterAnnotation(
                annotation,
                scaleX: scaleX,
                scaleY: scaleY,
                outputHeight: outputHeight
            )
        case .pen:
            guard let firstPoint = annotation.points.first else { return }
            path.move(to: transform(firstPoint, scaleX: scaleX, scaleY: scaleY, outputHeight: outputHeight))
            annotation.points.dropFirst().forEach {
                path.line(to: transform($0, scaleX: scaleX, scaleY: scaleY, outputHeight: outputHeight))
            }
            path.stroke()
        case .mosaic:
            drawMosaic(annotation, scaleX: scaleX, scaleY: scaleY, outputHeight: outputHeight, sampler: mosaicSampler)
        case .line:
            guard let start = annotation.points.first,
                  let end = annotation.points.last else { return }
            path.move(to: transform(start, scaleX: scaleX, scaleY: scaleY, outputHeight: outputHeight))
            path.line(to: transform(end, scaleX: scaleX, scaleY: scaleY, outputHeight: outputHeight))
            path.stroke()
        case .arrow:
            guard let start = annotation.points.first,
                  let end = annotation.points.last else { return }
            let startPoint = transform(start, scaleX: scaleX, scaleY: scaleY, outputHeight: outputHeight)
            let endPoint = transform(end, scaleX: scaleX, scaleY: scaleY, outputHeight: outputHeight)
            path.move(to: startPoint)
            path.line(to: endPoint)
            path.stroke()
            drawArrowHead(from: startPoint, to: endPoint, color: color, lineWidth: path.lineWidth)
        case .rectangle:
            guard let rect = transformedRect(for: annotation, scaleX: scaleX, scaleY: scaleY, outputHeight: outputHeight) else { return }
            path.appendRect(rect)
            if let fillColor = annotation.effectiveFillNSColor {
                fillColor.withAlphaComponent(0.24).setFill()
                path.fill()
                color.setStroke()
            }
            path.stroke()
        case .ellipse:
            guard let rect = transformedRect(for: annotation, scaleX: scaleX, scaleY: scaleY, outputHeight: outputHeight) else { return }
            path.appendOval(in: rect)
            if let fillColor = annotation.effectiveFillNSColor {
                fillColor.withAlphaComponent(0.24).setFill()
                path.fill()
                color.setStroke()
            }
            path.stroke()
        }
    }

    private static func drawCounterAnnotation(
        _ annotation: ScreenshotAnnotation,
        scaleX: CGFloat,
        scaleY: CGFloat,
        outputHeight: CGFloat
    ) {
        guard let origin = annotation.points.first else { return }
        let scale = min(scaleX, scaleY)
        let topLeft = transform(origin, scaleX: scaleX, scaleY: scaleY, outputHeight: outputHeight)
        let size = CGSize(
            width: annotation.textBoxSize.width * scaleX,
            height: annotation.textBoxSize.height * scaleY
        )
        let rect = CGRect(
            x: topLeft.x,
            y: topLeft.y - size.height,
            width: size.width,
            height: size.height
        )

        let path = NSBezierPath(ovalIn: rect)
        if let fillColor = annotation.effectiveFillNSColor {
            fillColor.withAlphaComponent(0.94).setFill()
            path.fill()
        }
        annotation.effectiveStrokeNSColor.setStroke()
        path.lineWidth = max(1.5, annotation.lineWidth * scale)
        path.stroke()

        let text = NSString(string: annotation.text)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: annotation.nsFont(scale: scale),
            .foregroundColor: annotation.effectiveFillNSColor == nil ? annotation.effectiveStrokeNSColor : NSColor.white,
            .paragraphStyle: paragraph
        ]
        let textSize = text.size(withAttributes: attributes)
        let textRect = CGRect(
            x: rect.minX,
            y: rect.midY - textSize.height / 2,
            width: rect.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)
    }

    private static func drawMosaic(
        _ annotation: ScreenshotAnnotation,
        scaleX: CGFloat,
        scaleY: CGFloat,
        outputHeight: CGFloat,
        sampler: ScreenshotMosaicSampler?
    ) {
        let blockSize = max(8, annotation.lineWidth * min(scaleX, scaleY) * 5)
        let halfBlock = blockSize / 2

        for point in annotation.points {
            let center = transform(point, scaleX: scaleX, scaleY: scaleY, outputHeight: outputHeight)
            let rect = CGRect(
                x: center.x - halfBlock,
                y: center.y - halfBlock,
                width: blockSize,
                height: blockSize
            )
            let color = sampler?.averageColor(in: rect, outputHeight: outputHeight) ?? NSColor.systemGray
            color.setFill()
            NSBezierPath(rect: rect).fill()
        }
    }

    private static func transformedRect(
        for annotation: ScreenshotAnnotation,
        scaleX: CGFloat,
        scaleY: CGFloat,
        outputHeight: CGFloat
    ) -> CGRect? {
        guard let start = annotation.points.first,
              let end = annotation.points.last else { return nil }
        let p1 = transform(start, scaleX: scaleX, scaleY: scaleY, outputHeight: outputHeight)
        let p2 = transform(end, scaleX: scaleX, scaleY: scaleY, outputHeight: outputHeight)
        return CGRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y), width: abs(p1.x - p2.x), height: abs(p1.y - p2.y))
    }

    private static func drawArrowHead(from start: CGPoint, to end: CGPoint, color: NSColor, lineWidth: CGFloat) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = max(10, lineWidth * 4)
        let spread = CGFloat.pi / 7
        let points = [
            CGPoint(x: end.x - length * cos(angle - spread), y: end.y - length * sin(angle - spread)),
            CGPoint(x: end.x - length * cos(angle + spread), y: end.y - length * sin(angle + spread))
        ]

        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()
        for point in points {
            path.move(to: end)
            path.line(to: point)
        }
        path.stroke()
    }

    private static func transform(_ point: CGPoint, scaleX: CGFloat, scaleY: CGFloat, outputHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x * scaleX, y: outputHeight - point.y * scaleY)
    }
}

private struct ScreenshotMosaicSampler {
    private let bitmap: NSBitmapImageRep
    private let imageSize: CGSize

    init?(image: NSImage) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        self.bitmap = bitmap
        self.imageSize = image.size
    }

    func color(at point: CGPoint, outputHeight: CGFloat) -> NSColor {
        let xRatio = imageSize.width > 0 ? point.x / imageSize.width : 0
        let yRatio = outputHeight > 0 ? point.y / outputHeight : 0
        let maxX = CGFloat(max(0, bitmap.pixelsWide - 1))
        let maxY = CGFloat(max(0, bitmap.pixelsHigh - 1))
        let x = Int(min(max(xRatio * CGFloat(bitmap.pixelsWide), 0), maxX))
        let y = Int(min(max((1 - yRatio) * CGFloat(bitmap.pixelsHigh), 0), maxY))
        return bitmap.colorAt(x: x, y: y) ?? .systemGray
    }

    func averageColor(in rect: CGRect, outputHeight: CGFloat) -> NSColor {
        let sampleRect = rect.intersection(CGRect(origin: .zero, size: imageSize))
        guard !sampleRect.isNull, sampleRect.width > 0, sampleRect.height > 0 else {
            return .systemGray
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
                guard let color = color(at: point, outputHeight: outputHeight).usingColorSpace(.deviceRGB) else { continue }
                red += color.redComponent
                green += color.greenComponent
                blue += color.blueComponent
                alpha += color.alphaComponent
                count += 1
            }
        }

        guard count > 0 else {
            return .systemGray
        }

        return NSColor(
            deviceRed: red / count,
            green: green / count,
            blue: blue / count,
            alpha: alpha / count
        )
    }
}

enum ScreenshotResultAction {
    case pin
    case annotate
    case ocr
    case copy
    case save
    case close
}

extension Notification.Name {
    static let ocrCaptureRequested = Notification.Name("AirSentry.OCRCaptureRequested")
}
