import AppKit
import Foundation
import Vision

enum OCRServiceError: LocalizedError {
    case invalidImage
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "无法读取图片内容"
        case .noTextFound:
            return "没有识别到文字"
        }
    }
}

struct OCRRecognitionResult {
    let text: String
    let observations: [VNRecognizedTextObservation]
}

enum OCRService {
    static func recognizeText(in image: NSImage) async throws -> OCRRecognitionResult {
        guard let cgImage = image.ocrCGImage else {
            throw OCRServiceError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    let observations = request.results as? [VNRecognizedTextObservation] ?? []
                    let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                    let text = lines.joined(separator: "\n")

                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        continuation.resume(throwing: OCRServiceError.noTextFound)
                        return
                    }

                    continuation.resume(returning: OCRRecognitionResult(text: text, observations: observations))
                }

                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
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
