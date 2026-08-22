import Foundation
import Vision
import CoreGraphics

/// A tappable, dictionary-backed region overlaid on the captured photo (US-2).
struct ScanRegion: Identifiable {
    let id = UUID()
    /// Normalized Vision coordinates: origin bottom-left, 0...1 on each axis.
    let normalizedRect: CGRect
    let result: LookupResult
}

/// Bridges OCR lines + dictionary segmentation into tappable regions: for each
/// recognized line, the segmenter picks out kanji/compound tokens (FR-8/9),
/// then Vision's per-range bounding box gives each token its own tap target —
/// so no manual cropping step is needed (US-2's "no cropping" requirement).
enum TokenBoxBuilder {
    static func buildRegions(from lines: [RecognizedLine], database: DictionaryDatabase) -> [ScanRegion] {
        var regions: [ScanRegion] = []

        for line in lines {
            let tokens = Segmenter.segment(line.text, using: database)
            for token in tokens {
                guard let rectObservation = try? line.recognizedText.boundingBox(for: token.range) else { continue }
                regions.append(ScanRegion(normalizedRect: axisAlignedRect(for: rectObservation), result: token.result))
            }
        }

        return regions
    }

    private static func axisAlignedRect(for observation: VNRectangleObservation) -> CGRect {
        let points = [observation.topLeft, observation.topRight, observation.bottomLeft, observation.bottomRight]
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
