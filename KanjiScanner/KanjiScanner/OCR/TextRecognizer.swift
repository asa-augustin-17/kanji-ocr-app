import Foundation
import Vision
import CoreGraphics

/// One recognized line of text plus the Vision object needed to compute
/// sub-ranges' bounding boxes later (see TokenBoxBuilder).
struct RecognizedLine {
    let text: String
    let recognizedText: VNRecognizedText
    let confidence: Float
}

enum TextRecognitionError: Error {
    case noResults
}

/// Wraps VNRecognizeTextRequest for on-device, offline Japanese OCR (FR-4, FR-7).
final class TextRecognizer {
    /// Lines below this confidence are dropped before segmentation/lookup ever
    /// sees them, per the graceful-failure requirement in US-6/FR-6.
    static let confidenceThreshold: Float = 0.3

    func recognizeText(in image: CGImage) async throws -> [RecognizedLine] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines: [RecognizedLine] = observations.compactMap { observation in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    guard candidate.confidence >= Self.confidenceThreshold else { return nil }
                    return RecognizedLine(text: candidate.string, recognizedText: candidate, confidence: candidate.confidence)
                }
                continuation.resume(returning: lines)
            }

            request.recognitionLanguages = ["ja-JP"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
