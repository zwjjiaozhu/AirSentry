import AppKit
import Foundation
import Vision

enum OCRServiceError: LocalizedError {
    case invalidImage
    case noRecognizableContent

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "无法读取图片内容"
        case .noRecognizableContent:
            return "没有识别到文字或二维码"
        }
    }
}

struct OCRTextItem: Identifiable {
    let id = UUID()
    let text: String
    let boundingBox: CGRect
}

struct OCRQRCodeItem: Identifiable {
    let id = UUID()
    let payload: String
    let boundingBox: CGRect

    var url: URL? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return nil
        }
        return url
    }
}

struct OCRRecognitionResult {
    let text: String
    let textItems: [OCRTextItem]
    let qrCodeItems: [OCRQRCodeItem]

    var observations: [OCRTextItem] { textItems }
    var hasContent: Bool { !textItems.isEmpty || !qrCodeItems.isEmpty }

    var displayText: String {
        var sections: [String] = []
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(text)
        }
        if !qrCodeItems.isEmpty {
            let qrText = qrCodeItems.enumerated().map { index, item in
                qrCodeItems.count == 1 ? item.payload : "\(index + 1). \(item.payload)"
            }.joined(separator: "\n")
            sections.append("二维码\n\(qrText)")
        }
        return sections.joined(separator: "\n\n")
    }
}

enum OCRService {
    static func recognizeText(in image: NSImage) async throws -> OCRRecognitionResult {
        try await recognizeContent(in: image)
    }

    static func recognizeContent(in image: NSImage) async throws -> OCRRecognitionResult {
        guard let cgImage = image.ocrCGImage else {
            throw OCRServiceError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var textItems: [OCRTextItem] = []
                var qrCodeItems: [OCRQRCodeItem] = []
                var requestError: Error?

                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        requestError = error
                        return
                    }

                    let observations = request.results as? [VNRecognizedTextObservation] ?? []
                    textItems = observations.compactMap { observation in
                        guard let text = observation.topCandidates(1).first?.string,
                              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            return nil
                        }
                        return OCRTextItem(text: text, boundingBox: observation.boundingBox)
                    }
                }

                let barcodeRequest = VNDetectBarcodesRequest { request, error in
                    if let error {
                        requestError = error
                        return
                    }

                    let observations = request.results as? [VNBarcodeObservation] ?? []
                    qrCodeItems = observations.compactMap { observation in
                        guard observation.symbology == .qr,
                              let payload = observation.payloadStringValue,
                              !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            return nil
                        }
                        return OCRQRCodeItem(payload: payload, boundingBox: observation.boundingBox)
                    }
                }

                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
                barcodeRequest.symbologies = [.qr]

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request, barcodeRequest])
                    if let requestError {
                        continuation.resume(throwing: requestError)
                        return
                    }
                    let text = textItems.map(\.text).joined(separator: "\n")
                    let result = OCRRecognitionResult(
                        text: text,
                        textItems: textItems,
                        qrCodeItems: qrCodeItems
                    )
                    guard result.hasContent else {
                        continuation.resume(throwing: OCRServiceError.noRecognizableContent)
                        return
                    }
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

extension NSImage {
    var ocrCGImage: CGImage? {
        var proposedRect = CGRect(origin: .zero, size: size)
        if let cgImage = cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) {
            return cgImage
        }

        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.cgImage
    }
}
