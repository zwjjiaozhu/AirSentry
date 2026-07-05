import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageProcessingOutputFormat: String, CaseIterable, Identifiable {
    case jpeg = "JPEG"
    case png = "PNG"
    case heic = "HEIC"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .heic: "heic"
        }
    }

    var contentType: UTType {
        switch self {
        case .jpeg: .jpeg
        case .png: .png
        case .heic: .heic
        }
    }

    var supportsQuality: Bool {
        self != .png
    }
}

enum ImageProcessingCompressionMode: String, CaseIterable, Identifiable {
    case quality = "按质量"
    case targetSize = "按大小"

    var id: String { rawValue }
}

enum ImageProcessingCropMode: String, CaseIterable, Identifiable {
    case none = "不裁剪"
    case square = "1:1"
    case landscape43 = "4:3"
    case landscape169 = "16:9"
    case portrait34 = "3:4"
    case portrait916 = "9:16"

    var id: String { rawValue }

    var aspectRatio: CGFloat? {
        switch self {
        case .none: nil
        case .square: 1
        case .landscape43: 4 / 3
        case .landscape169: 16 / 9
        case .portrait34: 3 / 4
        case .portrait916: 9 / 16
        }
    }
}

struct ImageProcessingItem: Identifiable {
    let id = UUID()
    let url: URL
    let sourceImage: NSImage
    let originalBytes: Int?
    var previewImage: NSImage?
    var outputBytes: Int?
    var errorMessage: String?

    var displayName: String {
        url.lastPathComponent
    }

    var originalPixelSize: CGSize {
        sourceImage.pixelSize
    }

    var previewPixelSize: CGSize? {
        previewImage?.pixelSize
    }

    var compressionRatioText: String? {
        guard let originalBytes, let outputBytes, originalBytes > 0 else { return nil }
        let ratio = 1 - (Double(outputBytes) / Double(originalBytes))
        return ratio.formatted(.percent.precision(.fractionLength(0)))
    }
}

@MainActor
final class ImageProcessingStore: ObservableObject {
    @Published private(set) var items: [ImageProcessingItem] = []
    @Published var selectedItemID: UUID?
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    @Published var outputFormat: ImageProcessingOutputFormat = .jpeg {
        didSet { rebuildPreviews() }
    }
    @Published var compressionMode: ImageProcessingCompressionMode = .quality {
        didSet { rebuildPreviews() }
    }
    @Published var qualityPercent: Double = 72 {
        didSet { rebuildPreviews() }
    }
    @Published var targetSizeKB: Double = 500 {
        didSet { rebuildPreviews() }
    }
    @Published var longestSidePixels: Double = 1600 {
        didSet { rebuildPreviews() }
    }
    @Published var shouldResize = true {
        didSet { rebuildPreviews() }
    }
    @Published var cropMode: ImageProcessingCropMode = .none {
        didSet { rebuildPreviews() }
    }

    var hasImages: Bool {
        !items.isEmpty
    }

    var selectedItem: ImageProcessingItem? {
        guard let selectedItemID else { return items.first }
        return items.first { $0.id == selectedItemID } ?? items.first
    }

    var totalOriginalBytes: Int {
        items.compactMap(\.originalBytes).reduce(0, +)
    }

    var totalOutputBytes: Int {
        items.compactMap(\.outputBytes).reduce(0, +)
    }

    var exportableCount: Int {
        items.filter { $0.outputBytes != nil && $0.errorMessage == nil }.count
    }

    var failedCount: Int {
        items.filter { $0.errorMessage != nil }.count
    }

    var totalCompressionRatioText: String? {
        guard totalOriginalBytes > 0, totalOutputBytes > 0 else { return nil }
        let ratio = 1 - (Double(totalOutputBytes) / Double(totalOriginalBytes))
        return ratio.formatted(.percent.precision(.fractionLength(0)))
    }

    func chooseImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK else { return }
        loadImages(from: panel.urls)
    }

    func remove(_ item: ImageProcessingItem) {
        items.removeAll { $0.id == item.id }
        if selectedItemID == item.id {
            selectedItemID = items.first?.id
        }
        updateStatusAfterQueueChange()
    }

    func clearImages() {
        items.removeAll()
        selectedItemID = nil
        statusMessage = nil
        errorMessage = nil
    }

    func exportImages() {
        guard hasImages else {
            errorMessage = "请先选择图片。"
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "导出到这里"
        panel.message = "选择批量导出的目标文件夹"

        guard panel.runModal() == .OK, let directoryURL = panel.url else { return }

        var successCount = 0
        var failureMessages: [String] = []

        for item in items {
            do {
                let result = try render(item.sourceImage)
                let outputURL = uniqueOutputURL(for: item, in: directoryURL)
                try result.data.write(to: outputURL, options: .atomic)
                successCount += 1
            } catch {
                failureMessages.append("\(item.displayName)：\(error.localizedDescription)")
            }
        }

        statusMessage = "已导出 \(successCount) 张图片到：\(directoryURL.path)"
        errorMessage = failureMessages.first
    }

    func reset() {
        qualityPercent = 72
        targetSizeKB = 500
        longestSidePixels = 1600
        shouldResize = true
        cropMode = .none
        outputFormat = .jpeg
        compressionMode = .quality
        rebuildPreviews()
    }

    private func loadImages(from urls: [URL]) {
        var loadedItems: [ImageProcessingItem] = []
        var failures: [String] = []

        for url in urls {
            guard let image = NSImage(contentsOf: url) else {
                failures.append(url.lastPathComponent)
                continue
            }

            let originalBytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
            loadedItems.append(
                ImageProcessingItem(
                    url: url,
                    sourceImage: image,
                    originalBytes: originalBytes,
                    previewImage: nil,
                    outputBytes: nil,
                    errorMessage: nil
                )
            )
        }

        items = loadedItems
        selectedItemID = loadedItems.first?.id
        statusMessage = loadedItems.isEmpty ? nil : "已载入 \(loadedItems.count) 张图片"
        errorMessage = failures.isEmpty ? nil : "有 \(failures.count) 张图片无法读取：\(failures.prefix(3).joined(separator: "、"))"
        rebuildPreviews()
    }

    private func rebuildPreviews() {
        guard !items.isEmpty else { return }

        for index in items.indices {
            do {
                let result = try render(items[index].sourceImage)
                items[index].previewImage = result.image
                items[index].outputBytes = result.data.count
                items[index].errorMessage = nil
            } catch {
                items[index].previewImage = nil
                items[index].outputBytes = nil
                items[index].errorMessage = error.localizedDescription
            }
        }
    }

    private func render(_ image: NSImage) throws -> ImageProcessingResult {
        var workingImage = image

        if cropMode != .none {
            workingImage = try workingImage.centerCropped(to: cropMode)
        }

        if shouldResize, longestSidePixels > 0 {
            workingImage = try workingImage.resizedToFit(longestSide: CGFloat(longestSidePixels))
        }

        let data: Data
        if compressionMode == .targetSize, outputFormat.supportsQuality {
            data = try workingImage.encoded(
                as: outputFormat,
                fittingTargetBytes: max(1, Int(targetSizeKB * 1024))
            )
        } else {
            data = try workingImage.encoded(
                as: outputFormat,
                quality: CGFloat(qualityPercent / 100)
            )
        }

        return ImageProcessingResult(image: workingImage, data: data)
    }

    private func updateStatusAfterQueueChange() {
        if items.isEmpty {
            statusMessage = nil
            errorMessage = nil
        } else {
            statusMessage = "队列中还有 \(items.count) 张图片"
        }
    }

    private func uniqueOutputURL(for item: ImageProcessingItem, in directoryURL: URL) -> URL {
        let baseName = item.url.deletingPathExtension().lastPathComponent
        let preferredName = "\(baseName)-processed.\(outputFormat.fileExtension)"
        var outputURL = directoryURL.appendingPathComponent(preferredName)

        var index = 2
        while FileManager.default.fileExists(atPath: outputURL.path) {
            outputURL = directoryURL.appendingPathComponent("\(baseName)-processed-\(index).\(outputFormat.fileExtension)")
            index += 1
        }

        return outputURL
    }
}

private struct ImageProcessingResult {
    let image: NSImage
    let data: Data
}

private extension NSImage {
    var pixelSize: CGSize {
        if let representation = representations.max(by: { ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh) }) {
            return CGSize(width: representation.pixelsWide, height: representation.pixelsHigh)
        }
        return size
    }

    func centerCropped(to cropMode: ImageProcessingCropMode) throws -> NSImage {
        guard let aspectRatio = cropMode.aspectRatio else { return self }
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageProcessingError.renderFailed
        }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let currentRatio = width / height
        let cropSize: CGSize

        if currentRatio > aspectRatio {
            cropSize = CGSize(width: height * aspectRatio, height: height)
        } else {
            cropSize = CGSize(width: width, height: width / aspectRatio)
        }

        let cropRect = CGRect(
            x: (width - cropSize.width) / 2,
            y: (height - cropSize.height) / 2,
            width: cropSize.width,
            height: cropSize.height
        ).integral

        guard let cropped = cgImage.cropping(to: cropRect) else {
            throw ImageProcessingError.renderFailed
        }

        return NSImage(cgImage: cropped, size: CGSize(width: cropped.width, height: cropped.height))
    }

    func resizedToFit(longestSide: CGFloat) throws -> NSImage {
        guard longestSide > 0 else { return self }
        let pixelSize = pixelSize
        let currentLongestSide = max(pixelSize.width, pixelSize.height)
        guard currentLongestSide > longestSide else { return self }

        let scale = longestSide / currentLongestSide
        let targetSize = CGSize(
            width: max(1, floor(pixelSize.width * scale)),
            height: max(1, floor(pixelSize.height * scale))
        )

        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageProcessingError.renderFailed
        }

        let image = NSImage(size: targetSize)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: cgImage, size: pixelSize).draw(in: CGRect(origin: .zero, size: targetSize))
        image.unlockFocus()
        return image
    }

    func encoded(as format: ImageProcessingOutputFormat, quality: CGFloat) throws -> Data {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageProcessingError.renderFailed
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            format.contentType.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageProcessingError.encodingFailed
        }

        let properties: [CFString: Any]
        if format.supportsQuality {
            properties = [kCGImageDestinationLossyCompressionQuality: min(1, max(0.01, quality))]
        } else {
            properties = [:]
        }

        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageProcessingError.encodingFailed
        }

        return data as Data
    }

    func encoded(as format: ImageProcessingOutputFormat, fittingTargetBytes targetBytes: Int) throws -> Data {
        var low: CGFloat = 0.05
        var high: CGFloat = 0.95
        var best = try encoded(as: format, quality: high)

        for _ in 0..<8 {
            let middle = (low + high) / 2
            let data = try encoded(as: format, quality: middle)
            if data.count > targetBytes {
                high = middle
            } else {
                low = middle
                best = data
            }
        }

        if best.count > targetBytes {
            best = try encoded(as: format, quality: 0.05)
        }

        return best
    }
}

private enum ImageProcessingError: LocalizedError {
    case renderFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .renderFailed: "图片渲染失败，请换一张图片试试。"
        case .encodingFailed: "图片编码失败，当前格式可能不支持这张图片。"
        }
    }
}
