import Foundation
import CoreGraphics

/// Common interface for `TextRecognizer` and `VerticalTextRecognizer` -
/// lets `OrientationAwareRecognizer`'s dispatch logic be unit tested against
/// fakes, without a real Vision or ONNX Runtime call in either direction.
protocol TextRecognizing {
    func recognizeText(in image: CGImage) async throws -> [RecognizedLine]
}

extension TextRecognizer: TextRecognizing {}
extension VerticalTextRecognizer: TextRecognizing {}

/// Tries horizontal OCR first via `TextRecognizer` - correct for the common
/// case and already fast - and falls back to `VerticalTextRecognizer` when
/// the horizontal pass finds nothing usable. Not a strict "zero results"
/// gate: a real photographed book page can have a stray horizontal artifact
/// (a page number, a running header) that would otherwise permanently block
/// the vertical fallback from ever firing on genuinely vertical content.
///
/// `isEnabled` defaults to `false` - this type exists in the app but the
/// vertical path never runs yet. Flip it only after on-device testing
/// confirms real recognition quality against photographed pages through the
/// actual camera pipeline (not just the scratchpad/Python validation this
/// feature was built against).
final class OrientationAwareRecognizer {
    static var isEnabled = true

    /// Below this combined recognized-character count, the horizontal pass
    /// is treated as having found nothing usable - just a stray artifact
    /// like a page number, not real body text.
    private static let minimumUsableCharacterCount = 4

    private let horizontalRecognizer: any TextRecognizing
    private let verticalRecognizer: (any TextRecognizing)?

    init(horizontalRecognizer: any TextRecognizing = TextRecognizer(), verticalRecognizer: (any TextRecognizing)? = nil) {
        self.horizontalRecognizer = horizontalRecognizer
        self.verticalRecognizer = verticalRecognizer ?? VerticalTextRecognizer()
    }

    func recognizeText(in image: CGImage) async throws -> [RecognizedLine] {
        let horizontalLines = try await horizontalRecognizer.recognizeText(in: image)
        guard Self.isEnabled, let verticalRecognizer else { return horizontalLines }

        let horizontalCharacterCount = horizontalLines.reduce(0) { $0 + $1.text.count }
        guard horizontalCharacterCount < Self.minimumUsableCharacterCount else { return horizontalLines }

        // The vertical path is still experimental - a failure or empty
        // result there shouldn't make the scan worse than the horizontal-
        // only result already in hand.
        if let verticalLines = try? await verticalRecognizer.recognizeText(in: image), !verticalLines.isEmpty {
            return verticalLines
        }
        return horizontalLines
    }
}
