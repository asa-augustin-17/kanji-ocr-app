import Foundation
import CoreGraphics

/// Recognizes vertical (tategaki) Japanese text: detects columns
/// (`VerticalTextLayout`), rotates each one (or a length-bounded chunk of
/// one) to a horizontal, upright-arrangement text line, and runs it through
/// `PaddleRecognizer` - see that type's doc comment for why this pipeline
/// works where a Vision-based one didn't.
final class VerticalTextRecognizer {
    /// Column chunks are kept under this *resized* input width as a safety
    /// margin against the recognizer's effective sequence-length limit
    /// (SVTR-style recognizers are sized for a bounded sequence). Every real
    /// column tested directly against a photographed page so far resized
    /// well under this (~1000-1800px), so this is a defensive ceiling, not a
    /// value chosen to fit observed failures.
    private static let maxResizedWidth = 2500

    private let paddleRecognizer: PaddleRecognizer

    init?(paddleRecognizer: PaddleRecognizer? = nil) {
        if let paddleRecognizer {
            self.paddleRecognizer = paddleRecognizer
        } else {
            guard let modelURL = Bundle.main.url(forResource: "ppocrv5_rec", withExtension: "onnx"),
                  let dictURL = Bundle.main.url(forResource: "ppocrv5_dict", withExtension: "txt"),
                  let recognizer = PaddleRecognizer(modelURL: modelURL, dictionaryURL: dictURL) else { return nil }
            self.paddleRecognizer = recognizer
        }
    }

    func recognizeText(in rawImage: CGImage) async throws -> [RecognizedLine] {
        // See `VerticalTextLayout.materialized`'s doc comment: cropping an
        // un-materialized image (as a captured photo's CGImage may be) can
        // silently produce zeroed-out data past the first portion of the
        // crop - confirmed against a real photo in the iOS Simulator.
        guard let image = VerticalTextLayout.materialized(rawImage) else { return [] }
        guard let pageBuffer = GrayscaleBuffer(image: image) else { return [] }
        let columns = VerticalTextLayout.detectColumns(in: pageBuffer)
        guard !columns.isEmpty else { return [] }

        let pageHeight = image.height
        var lines: [RecognizedLine] = []

        for column in columns {
            let columnWidth = column.end - column.start + 1
            guard columnWidth > 0 else { continue }

            // Trim to where this column's own real text actually is, rather
            // than blindly using the full page height - see
            // `textBearingExtent`'s doc comment for why a short column needs
            // this even though a long one gets away without it.
            let extent = VerticalTextLayout.textBearingExtent(page: pageBuffer, xStart: column.start, xEnd: column.end)
            let textHeight = extent.bottom - extent.top + 1
            guard textHeight > 0 else { continue }

            let resizeScale = 48.0 / Double(columnWidth)
            let wouldBeResizedWidth = Int(Double(textHeight) * resizeScale)
            let chunkCount = max(1, Int((Double(wouldBeResizedWidth) / Double(Self.maxResizedWidth)).rounded(.up)))
            let chunkHeight = Int((Double(textHeight) / Double(chunkCount)).rounded(.up))

            for chunkIndex in 0..<chunkCount {
                let yStart = extent.top + chunkIndex * chunkHeight
                let yEnd = min(extent.top + textHeight, yStart + chunkHeight)
                guard yEnd > yStart else { continue }
                guard let columnCrop = image.cropping(to: CGRect(x: column.start, y: yStart, width: columnWidth, height: yEnd - yStart)) else { continue }
                // CCW confirmed (not assumed) against a real photographed
                // page: it's the direction that maps "top of column" (start
                // of tategaki reading order) to "left of rotated strip"
                // (start of the recognizer's left-to-right reading order) -
                // the other direction produced empty or nonsense output.
                guard let rotated = VerticalTextLayout.rotated90(columnCrop, clockwise: false) else { continue }
                guard let recognition = paddleRecognizer.recognize(rotated), !recognition.text.isEmpty else { continue }

                let source = PaddleRecognizedText(
                    text: recognition.text,
                    characterSpans: recognition.characterSpans,
                    resizeScale: resizeScale,
                    columnPageXRange: column.start..<(column.end + 1),
                    pageWidth: image.width,
                    pageHeight: pageHeight,
                    chunkPageYOffset: yStart
                )
                lines.append(RecognizedLine(text: recognition.text, recognizedText: source, confidence: recognition.confidence))
            }
        }
        return lines
    }
}

/// A `RecognizedTextSource` backed by `PaddleRecognizer`'s CTC-derived
/// per-character spans, mapping a recognized substring back to the original
/// (pre-rotation, pre-crop) page image.
///
/// The rotation direction (`VerticalTextLayout.rotated90(clockwise: false)`)
/// was confirmed empirically to map a *resized-input* x-coordinate directly
/// (unflipped) back to the original page's top-down pixel row: a marker
/// placed near the top of a column crop landed at the left edge of its CCW
/// rotation, and a marker near the bottom landed at the right edge - so
/// `pageRow = chunkPageYOffset + (resizedX / resizeScale)`, with no extra
/// flip or offset math needed beyond that.
struct PaddleRecognizedText: RecognizedTextSource {
    let text: String
    let characterSpans: [Range<Int>]
    let resizeScale: Double
    let columnPageXRange: Range<Int>
    let pageWidth: Int
    let pageHeight: Int
    let chunkPageYOffset: Int

    func regionBoundingBox(for range: Range<String.Index>) throws -> CGRect {
        let lowerOffset = text.distance(from: text.startIndex, to: range.lowerBound)
        let upperOffset = text.distance(from: text.startIndex, to: range.upperBound)
        guard lowerOffset >= 0, upperOffset <= characterSpans.count, lowerOffset < upperOffset else {
            throw RecognizedTextSourceError.rangeNotFound
        }

        let relevantSpans = characterSpans[lowerOffset..<upperOffset]
        guard let minResizedX = relevantSpans.map(\.lowerBound).min(),
              let maxResizedX = relevantSpans.map(\.upperBound).max() else {
            throw RecognizedTextSourceError.rangeNotFound
        }

        let rowStart = chunkPageYOffset + Int(Double(minResizedX) / resizeScale)
        let rowEnd = chunkPageYOffset + Int(Double(maxResizedX) / resizeScale)
        let clampedRowStart = max(0, min(rowStart, pageHeight))
        let clampedRowEnd = max(clampedRowStart, min(rowEnd, pageHeight))

        let normalizedX = Double(columnPageXRange.lowerBound) / Double(pageWidth)
        let normalizedWidth = Double(columnPageXRange.count) / Double(pageWidth)
        let normalizedY = Double(pageHeight - clampedRowEnd) / Double(pageHeight)
        let normalizedHeight = Double(clampedRowEnd - clampedRowStart) / Double(pageHeight)

        return CGRect(x: normalizedX, y: normalizedY, width: normalizedWidth, height: normalizedHeight)
    }
}
