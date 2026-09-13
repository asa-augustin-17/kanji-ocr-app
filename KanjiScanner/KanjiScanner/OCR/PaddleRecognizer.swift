import Foundation
import CoreGraphics
import OnnxRuntimeBindings

/// Wraps the bundled PP-OCRv5 recognition ONNX model: given a single column
/// crop that's already been rotated to a horizontal, upright-arrangement
/// text line (see `VerticalTextLayout.rotated90`), runs CTC-based text
/// recognition and recovers approximate per-character source positions from
/// the CTC decode itself.
///
/// This works where Vision's recognizer couldn't: PP-OCR's recognizer was
/// trained on vertical text rotated to horizontal as its canonical
/// representation for that case (confirmed via PaddleOCR maintainer
/// discussions, and confirmed again directly here - a Python/onnxruntime
/// script run against real photographed columns before this file was
/// written produced coherent, substantially-correct phrases, not the
/// single-character fragmentation the earlier Vision-based attempt hit).
/// Vision was never trained on sideways glyphs at all, which is why that
/// attempt needed fragile per-character segmentation to keep every glyph
/// upright instead.
///
/// Bounding boxes come from the CTC decode's own alignment, not a second,
/// independently-detected set of character cells: PaddleOCR's own
/// `return_word_box` feature and RapidOCR's `CTCLabelDecode`/`CalRecBoxes`
/// do the same thing - take the argmax class per timestep, group timesteps
/// into maximal runs of the same class (the standard CTC collapse, but kept
/// as spans instead of discarded), and map non-blank runs to pixel ranges
/// via the model's width-downsample ratio (input width ÷ output timestep
/// count - read directly off the actual tensor shapes here, not hardcoded).
/// This avoids the N-recognized-characters-vs-M-detected-cells reconciliation
/// problem the earlier attempt had: there's exactly one recovered span per
/// decoded character, by construction, from the same pass that produced it.
final class PaddleRecognizer {
    struct Recognition {
        let text: String
        /// One entry per character in `text`, same order: the contiguous
        /// range of *resized-input* pixel columns (x) whose timesteps
        /// decoded to that character. Approximate by nature (a timestep's
        /// receptive field isn't a tight character box) - good enough for
        /// tap targets, not pixel-perfect.
        let characterSpans: [Range<Int>]
        let confidence: Float
    }

    private static let targetHeight = 48

    private let session: ORTSession
    private let env: ORTEnv
    /// Index 0 is the CTC blank; real characters start at 1. PP-OCRv5's
    /// dictionary is appended with a trailing space character (confirmed by
    /// the arithmetic: 18383 dictionary entries + 1 blank + 1 space = 18385,
    /// exactly the bundled model's output class count) - this is PaddleOCR's
    /// documented `use_space_char` convention, not assumed without checking.
    private let labels: [String]

    init?(modelURL: URL, dictionaryURL: URL) {
        guard let dictText = try? String(contentsOf: dictionaryURL, encoding: .utf8) else { return nil }
        var chars = dictText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if chars.last == "" { chars.removeLast() } // trailing newline in the dict file
        self.labels = ["<blank>"] + chars + [" "]

        guard let env = try? ORTEnv(loggingLevel: .warning),
              let session = try? ORTSession(env: env, modelPath: modelURL.path, sessionOptions: nil) else { return nil }
        self.env = env
        self.session = session
    }

    /// `crop` must already be rotated per `VerticalTextLayout.rotated90` -
    /// this expects the same "clean, upright, roughly-horizontal text-line
    /// image" any PP-OCR recognizer call expects.
    func recognize(_ crop: CGImage) -> Recognition? {
        guard let (pixels, inputWidth) = Self.preprocess(crop) else { return nil }

        let shape: [NSNumber] = [1, 3, NSNumber(value: Self.targetHeight), NSNumber(value: inputWidth)]
        let tensorData = pixels.withUnsafeBufferPointer { NSMutableData(bytes: $0.baseAddress, length: $0.count * MemoryLayout<Float>.size) }
        guard let inputTensor = try? ORTValue(tensorData: tensorData, elementType: .float, shape: shape) else { return nil }

        guard let outputs = try? session.run(withInputs: ["x": inputTensor], outputNames: ["fetch_name_0"], runOptions: nil),
              let outputValue = outputs["fetch_name_0"],
              let outputData = try? outputValue.tensorData(),
              let shapeInfo = try? outputValue.tensorTypeAndShapeInfo() else { return nil }

        let outputShape = shapeInfo.shape.map(\.intValue)
        guard outputShape.count == 3 else { return nil }
        let seqLen = outputShape[1]
        let numClasses = outputShape[2]
        guard seqLen > 0, numClasses > 0 else { return nil }

        let floatCount = outputData.length / MemoryLayout<Float>.size
        guard floatCount == seqLen * numClasses else { return nil }
        let logits = (outputData as Data).withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            Array(raw.bindMemory(to: Float.self))
        }

        let downsampleRatio = Double(inputWidth) / Double(seqLen)
        return Self.ctcDecode(logits: logits, seqLen: seqLen, numClasses: numClasses, labels: labels, downsampleRatio: downsampleRatio)
    }

    /// Resizes to the model's fixed input height (48px), preserving aspect
    /// ratio (so width varies with how long the column/chunk is - the model's
    /// width input dimension is dynamic, matching this), and normalizes to
    /// PP-OCR's documented `(x/255 - 0.5)/0.5` range in CHW layout.
    private static func preprocess(_ image: CGImage) -> (pixels: [Float], width: Int)? {
        let scale = Double(targetHeight) / Double(image.height)
        let newWidth = max(1, Int((Double(image.width) * scale).rounded()))

        guard let context = CGContext(
            data: nil, width: newWidth, height: targetHeight, bitsPerComponent: 8,
            bytesPerRow: newWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: targetHeight))
        guard let data = context.data else { return nil }
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = newWidth * 4

        var pixels = [Float](repeating: 0, count: 3 * targetHeight * newWidth)
        let plane = targetHeight * newWidth
        for y in 0..<targetHeight {
            for x in 0..<newWidth {
                let offset = y * bytesPerRow + x * 4
                let r = (Float(bytes[offset]) / 255.0 - 0.5) / 0.5
                let g = (Float(bytes[offset + 1]) / 255.0 - 0.5) / 0.5
                let b = (Float(bytes[offset + 2]) / 255.0 - 0.5) / 0.5
                let pixelIndex = y * newWidth + x
                pixels[pixelIndex] = r
                pixels[plane + pixelIndex] = g
                pixels[2 * plane + pixelIndex] = b
            }
        }
        return (pixels, newWidth)
    }

    /// Internal (not private) so its CTC-collapse-and-span-recovery math can
    /// be unit tested directly against synthetic logits, without needing a
    /// real ONNX inference call.
    static func ctcDecode(logits: [Float], seqLen: Int, numClasses: Int, labels: [String], downsampleRatio: Double) -> Recognition {
        var text = ""
        var spans: [Range<Int>] = []
        var confidences: [Float] = []
        var runStart = -1
        var runClass = -1
        var runBestScore: Float = -.infinity

        func flushRun(endExclusive: Int) {
            defer { runStart = -1 }
            guard runStart >= 0, runClass > 0, runClass < labels.count else { return }
            text += labels[runClass]
            let startPixel = Int((Double(runStart) * downsampleRatio).rounded())
            let endPixel = Int((Double(endExclusive) * downsampleRatio).rounded())
            spans.append(startPixel..<max(startPixel + 1, endPixel))
            confidences.append(runBestScore)
        }

        for t in 0..<seqLen {
            let base = t * numClasses
            var bestClass = 0
            var bestScore = logits[base]
            for c in 1..<numClasses where logits[base + c] > bestScore {
                bestScore = logits[base + c]
                bestClass = c
            }
            if bestClass != runClass {
                flushRun(endExclusive: t)
                runStart = t
                runClass = bestClass
                runBestScore = bestScore
            } else if bestScore > runBestScore {
                runBestScore = bestScore
            }
        }
        flushRun(endExclusive: seqLen)

        let avgConfidence = confidences.isEmpty ? 0 : Self.softmaxConfidence(confidences)
        return Recognition(text: text, characterSpans: spans, confidence: avgConfidence)
    }

    /// `rawScores` are pre-softmax logit maxima, one per decoded character -
    /// converting each through a numerically-stable sigmoid-style squash
    /// gives a rough [0,1] confidence without needing the full per-timestep
    /// softmax denominator (which class-count-18385-wide would cost far more
    /// to compute than this recognizer's actual accuracy needs justify).
    private static func softmaxConfidence(_ rawScores: [Float]) -> Float {
        let squashed = rawScores.map { 1 / (1 + exp(-$0)) }
        return squashed.reduce(0, +) / Float(squashed.count)
    }
}
