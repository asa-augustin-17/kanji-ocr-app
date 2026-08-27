import Foundation
import Vision
import CoreGraphics

/// A source that can locate an already-recognized substring's bounding box
/// after the fact - the one capability `TokenBoxBuilder` needs from a line's
/// recognizer, abstracted so a non-Vision-native recognizer (e.g. a vertical-
/// text pipeline compositing/remapping through an intermediate image) can
/// provide it too, without `TokenBoxBuilder`/`Segmenter` needing to know or
/// care which recognizer produced a given `RecognizedLine`.
protocol RecognizedTextSource {
    /// `range` must be a valid range into whatever string this source's
    /// `RecognizedLine.text` holds. Returns a normalized (0...1, bottom-left
    /// origin) axis-aligned rect, already flattened from whatever the
    /// underlying recognizer's native geometry looks like.
    ///
    /// Deliberately NOT named `boundingBox(for:)` - `VNRecognizedText`
    /// already has a native method with that exact name and parameter list,
    /// differing only in return type (`VNRectangleObservation` vs `CGRect`
    /// here); overloading on return type alone is a known rough edge for
    /// Swift's type checker (confirmed directly - it produced a nondeterministic
    /// internal compiler error, not a normal type error, when tried that way).
    func regionBoundingBox(for range: Range<String.Index>) throws -> CGRect
}

enum RecognizedTextSourceError: Error {
    /// `range` doesn't correspond to a locatable region - e.g. an invalid
    /// range, or (for a custom `RecognizedTextSource`) a range that falls
    /// outside whatever positional data that source actually tracked.
    case rangeNotFound
}

extension VNRecognizedText: RecognizedTextSource {
    func regionBoundingBox(for range: Range<String.Index>) throws -> CGRect {
        // VNRecognizedText has two `boundingBox(for:)` overloads (confirmed
        // directly against the SDK's .swiftinterface, not assumed): a newer
        // non-throwing one returning `RectangleObservation?`, and this
        // legacy one - `throws -> VNRectangleObservation?` - which is the
        // one `TokenBoxBuilder.axisAlignedRect(for:)` expects.
        let observation: VNRectangleObservation? = try boundingBox(for: range)
        guard let observation else {
            throw RecognizedTextSourceError.rangeNotFound
        }
        return TokenBoxBuilder.axisAlignedRect(for: observation)
    }
}

/// One recognized line of text plus a way to compute sub-ranges' bounding
/// boxes later (see TokenBoxBuilder) - `recognizedText` may be backed by
/// Vision's own `VNRecognizedText` (the common, horizontal-text case) or a
/// custom `RecognizedTextSource` (the vertical-text pipeline).
struct RecognizedLine {
    let text: String
    let recognizedText: any RecognizedTextSource
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
