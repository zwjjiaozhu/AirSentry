import AppKit
import CoreGraphics
import Foundation

@MainActor
final class ScreenshotCaptureController: ObservableObject {
    private var overlayController: ScreenshotOverlayController?
    private let pinnedImageController = PinnedImageController()

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
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage else {
            NSSound.beep()
            return
        }
        pinnedImageController.pin(image)
    }

    private func handleSelection(_ payload: ScreenshotCapturePayload, action: ScreenshotResultAction) {
        let rect = payload.rect
        guard rect.width >= 4, rect.height >= 4 else {
            NSSound.beep()
            return
        }

        guard let image = ScreenshotImageCapturer.capture(rect: rect) else {
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
        case .copy:
            ScreenshotImageWriter.copyToPasteboard(outputImage)
        case .save:
            ScreenshotImageWriter.saveWithPanel(outputImage)
        case .close:
            return
        }
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
        for annotation in annotations {
            draw(annotation, scaleX: scaleX, scaleY: scaleY, outputHeight: outputSize.height)
        }

        image.unlockFocus()
        return image
    }

    private static func draw(_ annotation: ScreenshotAnnotation, scaleX: CGFloat, scaleY: CGFloat, outputHeight: CGFloat) {
        let color = annotation.color.nsColor
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
                .font: NSFont.systemFont(ofSize: annotation.fontSize * min(scaleX, scaleY), weight: .semibold),
                .foregroundColor: color
            ]
            let text = NSString(string: annotation.text)
            let textSize = text.size(withAttributes: attributes)
            text.draw(
                at: CGPoint(x: point.x, y: point.y - textSize.height),
                withAttributes: attributes
            )
        case .pen:
            guard let firstPoint = annotation.points.first else { return }
            path.move(to: transform(firstPoint, scaleX: scaleX, scaleY: scaleY, outputHeight: outputHeight))
            annotation.points.dropFirst().forEach {
                path.line(to: transform($0, scaleX: scaleX, scaleY: scaleY, outputHeight: outputHeight))
            }
            path.stroke()
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
            path.stroke()
        case .ellipse:
            guard let rect = transformedRect(for: annotation, scaleX: scaleX, scaleY: scaleY, outputHeight: outputHeight) else { return }
            path.appendOval(in: rect)
            path.stroke()
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

enum ScreenshotResultAction {
    case pin
    case annotate
    case copy
    case save
    case close
}
