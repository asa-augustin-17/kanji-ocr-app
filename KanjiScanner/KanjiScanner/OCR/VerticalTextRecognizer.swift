import Foundation
import Vision
import CoreGraphics

/// Recognizes vertical (tategaki) Japanese text, which `TextRecognizer`
/// cannot: `VNRecognizeTextRequest` only reads horizontal text, confirmed
/// directly against real vertical-text photos (zero results).
///
/// The approach - validated against a real photographed novel page, not just
/// synthetic renders, before being written here - deliberately differs from
/// a first-pass design in two ways:
///
/// - Column and character-cell boundaries are found by ink-density
///   projection + local-maxima/valley detection (`VerticalTextLayout`), not
///   `VNDetectTextRectanglesRequest`. That request was tried first and
///   confirmed to badly fragment a real, dense multi-column page (55
///   detected "regions" for ~14 real columns - individual furigana glyphs
///   were picked up as separate regions). A fixed global brightness
///   threshold was tried next and also confirmed to fail on real photos:
///   both column gutters and inter-character gaps sit at a moderate
///   relative brightness, not near zero like clean synthetic renders -
///   valley detection (cut at the trough between two detected peaks) is
///   robust to that where a global threshold isn't.
/// - No image rotation happens anywhere in this pipeline. Characters within
///   a printed vertical column are already upright; compositing detected
///   cells left-to-right in top-to-bottom (reading) order directly produces
///   a strip of upright, correctly-ordered characters for the existing
///   `TextRecognizer` to read. Rotation is only needed if column detection
///   depends on Vision's own (orientation-sensitive) line detector, which
///   this pipeline doesn't use.
///
/// Character cells are intentionally NOT required to align one-to-one with
/// characters: real vertical typesetting mixes full-width kanji/kana cells
/// with half-width punctuation/small-kana cells (confirmed by measuring real
/// cell heights - punctuation-adjacent cells cluster around half the height
/// of plain-kanji cells), so a single uniform pitch can't cleanly separate
/// every position. A cell occasionally contains a character plus adjacent
/// punctuation, and that's tolerated by design: punctuation isn't a
/// dictionary lookup target, so a merged cell just means its tap target is
/// shared with a neighboring character, not a wrong or missing character.
final class VerticalTextRecognizer {
    private let textRecognizer: TextRecognizer

    init(textRecognizer: TextRecognizer = TextRecognizer()) {
        self.textRecognizer = textRecognizer
    }

    func recognizeText(in image: CGImage) async throws -> [RecognizedLine] {
        guard let pageBuffer = GrayscaleBuffer(image: image) else { return [] }

        let columns = VerticalTextLayout.detectColumns(in: pageBuffer)
        guard !columns.isEmpty else { return [] }

        let textExtent = VerticalTextLayout.detectTextBlockVerticalExtent(page: pageBuffer, columns: columns)
        let cropHeight = textExtent.bottom - textExtent.top + 1
        guard cropHeight > 0 else { return [] }

        var lines: [RecognizedLine] = []
        for column in columns {
            let columnWidth = column.end - column.start + 1
            let columnBuffer = pageBuffer.cropped(x: column.start, y: textExtent.top, width: columnWidth, height: cropHeight)

            let cellsInColumnCoords = VerticalTextLayout.detectCells(in: columnBuffer)
            guard cellsInColumnCoords.count >= 2 else { continue }
            let cells = cellsInColumnCoords.map { (start: $0.start + textExtent.top, end: $0.end + textExtent.top) }

            guard let strip = VerticalTextLayout.compositeStrip(
                originalImage: image,
                pageWidth: image.width,
                pageHeight: image.height,
                columnX: column,
                cells: cells
            ) else { continue }

            do {
                let stripLines = try await textRecognizer.recognizeText(in: strip.image)
                for stripLine in stripLines {
                    let source = VerticalRecognizedText(
                        stripText: stripLine.recognizedText,
                        stripPixelWidth: strip.image.width,
                        cellTable: strip.cellTable
                    )
                    lines.append(RecognizedLine(text: stripLine.text, recognizedText: source, confidence: stripLine.confidence))
                }
            } catch {
                continue // one column's OCR failure shouldn't drop the rest of the page
            }
        }
        return lines
    }
}

/// A `RecognizedTextSource` for text recognized from a composited vertical-
/// text strip: maps a range in the strip's recognized string back to the
/// original (un-composited) image, via the cell table `VerticalTextLayout`
/// built while assembling the strip.
struct VerticalRecognizedText: RecognizedTextSource {
    let stripText: any RecognizedTextSource
    let stripPixelWidth: Int
    /// Each cell's horizontal pixel range within the strip, and that same
    /// cell's bounding rect back in the original image (normalized,
    /// bottom-left origin - matching Vision's convention).
    let cellTable: [(stripXRange: Range<Int>, originalNormalizedRect: CGRect)]

    func regionBoundingBox(for range: Range<String.Index>) throws -> CGRect {
        let stripBox = try stripText.regionBoundingBox(for: range)
        let xStart = Int(stripBox.minX * CGFloat(stripPixelWidth))
        let xEnd = max(xStart + 1, Int(stripBox.maxX * CGFloat(stripPixelWidth)))

        let overlapping = cellTable.filter { $0.stripXRange.overlaps(xStart..<xEnd) }
        guard !overlapping.isEmpty else { throw RecognizedTextSourceError.rangeNotFound }

        let rects = overlapping.map(\.originalNormalizedRect)
        let minX = rects.map(\.minX).min()!
        let minY = rects.map(\.minY).min()!
        let maxX = rects.map(\.maxX).max()!
        let maxY = rects.map(\.maxY).max()!
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// Finds vertical-text column and character-cell boundaries via ink-density
/// projection, and composites detected cells into a horizontal strip. See
/// `VerticalTextRecognizer`'s doc comment for why this approach was chosen
/// over Vision's own line/character detection.
enum VerticalTextLayout {
    struct CompositedStrip {
        let image: CGImage
        let cellTable: [(stripXRange: Range<Int>, originalNormalizedRect: CGRect)]
    }

    static func detectColumns(in page: GrayscaleBuffer) -> [(start: Int, end: Int)] {
        guard page.width > 0, page.height > 0 else { return [] }
        let raw = columnDensityProfile(page)
        let radius = max(3, page.width / 400)
        let smooth = smoothed(raw, radius: radius)
        let minPeakDistance = page.width / 25
        let floor = backgroundFloor(smooth, aboveFraction: 0.08)
        var columns = detectBandsByValleys(smooth, minPeakDistance: minPeakDistance, backgroundFloor: floor)
        guard !columns.isEmpty else { return [] }

        // Sanity filter: drop bands too narrow or too faint to be a real
        // text column - confirmed necessary against a real photo, where a
        // band picked up the book's curved page edge as if it were a column.
        let peakDensities = columns.map { c in (c.start...c.end).map { smooth[$0] }.max() ?? 0 }
        let sanityFloor = (peakDensities.max() ?? 0) * 0.35
        let minWidth = minPeakDistance / 2
        columns = zip(columns, peakDensities)
            .filter { $0.1 >= sanityFloor && ($0.0.end - $0.0.start + 1) >= minWidth }
            .map { $0.0 }
        return columns
    }

    static func detectCells(in columnBuffer: GrayscaleBuffer) -> [(start: Int, end: Int)] {
        guard columnBuffer.width > 0, columnBuffer.height > 0 else { return [] }
        let raw = inkDensityProfile(columnBuffer)
        let radius = max(2, columnBuffer.height / 400)
        let smooth = smoothed(raw, radius: radius)
        let floor = backgroundFloor(smooth, aboveFraction: 0.1)
        // Character pitch scales with column width (characters are roughly
        // square) rather than being a fixed pixel value - deriving it per
        // column this way generalizes across font sizes/photo distances
        // without per-photo tuning. The 0.42 factor was found empirically
        // against a real photographed page and should stay somewhat below 1
        // (true pitch), since `detectBandsByValleys` needs candidate peaks
        // closer together than the true spacing to avoid under-segmenting.
        let minPeakDistance = max(20, Int(CGFloat(columnBuffer.width) * 0.42))
        let cells = detectBandsByValleys(smooth, minPeakDistance: minPeakDistance, backgroundFloor: floor)
        guard !cells.isEmpty else { return [] }

        // Sanity filter: a cell that's both unusually tall AND has no real
        // ink peak of its own is almost certainly a leftover blank/
        // background margin that the edge-walk in `detectBandsByValleys`
        // failed to trim (confirmed against a real photo whose framing
        // included background beyond the page - the trailing "cell" ran
        // hundreds of pixels into it, and it visibly dragged the whole
        // composited strip down with dead space, since `compositeStrip`
        // sizes the strip off the tallest cell). Checking density as well as
        // height matters: a merged multi-character cell can be tall AND
        // dark (real text - keep it); a background cell can be short-ish but
        // still much darker than true blank paper (mustn't be kept just for
        // being short). Both conditions together are what actually
        // distinguish "no real character here" from a legitimately large
        // merged cell.
        let cellPeakDensities = cells.map { c in (c.start...c.end).map { smooth[$0] }.max() ?? 0 }
        let overallPeakDensity = cellPeakDensities.max() ?? 0
        let densityFloor = overallPeakDensity * 0.35
        let maxReasonableCellHeight = columnBuffer.width * 3

        return zip(cells, cellPeakDensities).filter { cell, peak in
            let height = cell.end - cell.start + 1
            return peak >= densityFloor || height <= maxReasonableCellHeight
        }.map { $0.0 }
    }

    /// Finds the printed text block's overall vertical extent once, using
    /// only the ink inside already-detected columns (excluding inter-column
    /// gutters, which otherwise dilute the contrast between text-bearing and
    /// blank-margin rows). This is a best-effort pre-trim: on a tightly
    /// framed capture (the expected case - matching how the existing
    /// horizontal-text path is already used) it correctly narrows the crop;
    /// on a loosely framed photo that includes background beyond the page,
    /// it may fail to trim at all, in which case per-column cell detection
    /// still degrades gracefully for columns away from the untrimmed edges.
    static func detectTextBlockVerticalExtent(page: GrayscaleBuffer, columns: [(start: Int, end: Int)]) -> (top: Int, bottom: Int) {
        guard !columns.isEmpty, page.height > 0 else { return (0, max(0, page.height - 1)) }
        let totalWidth = columns.reduce(0) { $0 + ($1.end - $1.start + 1) }
        guard totalWidth > 0 else { return (0, page.height - 1) }

        var profile = [CGFloat](repeating: 0, count: page.height)
        for y in 0..<page.height {
            var sum = 0
            let rowStart = y * page.bytesPerRow
            for col in columns {
                for x in col.start...col.end {
                    sum += 255 - Int(page.bytes[rowStart + x])
                }
            }
            profile[y] = CGFloat(sum) / CGFloat(totalWidth * 255)
        }

        let radius = max(5, page.height / 300)
        let smooth = smoothed(profile, radius: radius)
        let threshold = (smooth.max() ?? 0) * 0.15
        var top = 0
        var bottom = smooth.count - 1
        while top < smooth.count, smooth[top] < threshold { top += 1 }
        while bottom > top, smooth[bottom] < threshold { bottom -= 1 }
        return (top, bottom)
    }

    /// Crops each detected cell from `originalImage` (not the grayscale
    /// analysis buffer, so OCR sees full original image quality) and places
    /// them left-to-right in `cells`' order, which is already top-to-bottom
    /// reading order within the column - so no reordering or rotation is
    /// needed to produce a correctly-ordered strip of upright characters.
    static func compositeStrip(
        originalImage: CGImage,
        pageWidth: Int,
        pageHeight: Int,
        columnX: (start: Int, end: Int),
        cells: [(start: Int, end: Int)]
    ) -> CompositedStrip? {
        let columnWidth = columnX.end - columnX.start + 1
        guard columnWidth > 0, !cells.isEmpty else { return nil }
        let stripHeight = cells.map { $0.end - $0.start + 1 }.max() ?? 0
        let stripWidth = columnWidth * cells.count
        guard stripHeight > 0, stripWidth > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: stripWidth,
            height: stripHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: stripWidth, height: stripHeight))

        var cellTable: [(stripXRange: Range<Int>, originalNormalizedRect: CGRect)] = []
        var cursorX = 0
        for cell in cells {
            let cellHeight = cell.end - cell.start + 1
            let cropRect = CGRect(x: columnX.start, y: cell.start, width: columnWidth, height: cellHeight)
            guard let cellImage = originalImage.cropping(to: cropRect) else { continue }

            let yOffset = stripHeight - cellHeight
            context.draw(cellImage, in: CGRect(x: cursorX, y: yOffset, width: columnWidth, height: cellHeight))

            let stripXRange = cursorX..<(cursorX + columnWidth)
            let normalizedRect = CGRect(
                x: CGFloat(columnX.start) / CGFloat(pageWidth),
                y: CGFloat(pageHeight - (cell.start + cellHeight)) / CGFloat(pageHeight),
                width: CGFloat(columnWidth) / CGFloat(pageWidth),
                height: CGFloat(cellHeight) / CGFloat(pageHeight)
            )
            cellTable.append((stripXRange, normalizedRect))
            cursorX += columnWidth
        }

        guard let stripImage = context.makeImage() else { return nil }
        return CompositedStrip(image: stripImage, cellTable: cellTable)
    }

    // MARK: - Ink-density projection primitives

    private static func columnDensityProfile(_ buf: GrayscaleBuffer) -> [CGFloat] {
        var profile = [CGFloat](repeating: 0, count: buf.width)
        for x in 0..<buf.width {
            var sum = 0
            for y in 0..<buf.height {
                sum += 255 - Int(buf.bytes[y * buf.bytesPerRow + x])
            }
            profile[x] = CGFloat(sum) / CGFloat(buf.height * 255)
        }
        return profile
    }

    private static func inkDensityProfile(_ buf: GrayscaleBuffer) -> [CGFloat] {
        var profile = [CGFloat](repeating: 0, count: buf.height)
        for y in 0..<buf.height {
            var sum = 0
            let rowStart = y * buf.bytesPerRow
            for x in 0..<buf.width {
                sum += 255 - Int(buf.bytes[rowStart + x])
            }
            profile[y] = CGFloat(sum) / CGFloat(buf.width * 255)
        }
        return profile
    }

    private static func smoothed(_ profile: [CGFloat], radius: Int) -> [CGFloat] {
        guard radius > 0, !profile.isEmpty else { return profile }
        var out = [CGFloat](repeating: 0, count: profile.count)
        for i in 0..<profile.count {
            let lo = max(0, i - radius)
            let hi = min(profile.count - 1, i + radius)
            var sum: CGFloat = 0
            for j in lo...hi { sum += profile[j] }
            out[i] = sum / CGFloat(hi - lo + 1)
        }
        return out
    }

    private static func backgroundFloor(_ profile: [CGFloat], aboveFraction: CGFloat) -> CGFloat {
        let minV = profile.min() ?? 0
        let maxV = profile.max() ?? 0
        return minV + (maxV - minV) * aboveFraction
    }

    /// Finds band boundaries via local-maxima peak-picking + inter-peak
    /// valleys, rather than a single global density threshold. Validated
    /// against a real photographed page for both column gutters and
    /// inter-character gaps, where a fixed threshold fails: real
    /// photographed "gaps" sit at a moderate relative brightness, not near
    /// zero like clean synthetic renders, so cutting at the trough between
    /// two detected peaks is what actually separates them.
    private static func detectBandsByValleys(_ profile: [CGFloat], minPeakDistance: Int, backgroundFloor: CGFloat) -> [(start: Int, end: Int)] {
        let n = profile.count
        guard n > 0 else { return [] }

        let halfWin = max(1, minPeakDistance / 2)
        var maxima: [Int] = []
        var i = 0
        while i < n {
            let lo = max(0, i - halfWin)
            let hi = min(n - 1, i + halfWin)
            let windowMax = (lo...hi).map { profile[$0] }.max() ?? 0
            if profile[i] == windowMax && profile[i] > backgroundFloor {
                maxima.append(i)
                i += halfWin
            } else {
                i += 1
            }
        }

        // Single-linkage clustering: compare each candidate to the LAST raw
        // maximum seen (not the cluster's first/anchor point). Comparing
        // against a fixed anchor lets a chain of same-height maxima (a flat
        // ink plateau - confirmed to happen with solidly-inked strokes, not
        // just contrived input) drift past `minPeakDistance` from that fixed
        // point and incorrectly split one real peak into two.
        var mergedMaxima: [Int] = []
        var clusterBestIndex: Int?
        var clusterLastIndex = -minPeakDistance
        for m in maxima {
            if m - clusterLastIndex < minPeakDistance {
                if let best = clusterBestIndex {
                    if profile[m] > profile[best] { clusterBestIndex = m }
                } else {
                    clusterBestIndex = m
                }
            } else {
                if let best = clusterBestIndex { mergedMaxima.append(best) }
                clusterBestIndex = m
            }
            clusterLastIndex = m
        }
        if let best = clusterBestIndex { mergedMaxima.append(best) }
        guard !mergedMaxima.isEmpty else { return [] }

        var boundaries: [Int] = []
        for k in 0..<(mergedMaxima.count - 1) {
            let a = mergedMaxima[k]
            let b = mergedMaxima[k + 1]
            var valleyIdx = a
            var valleyVal = profile[a]
            for x in a...b where profile[x] < valleyVal {
                valleyVal = profile[x]
                valleyIdx = x
            }
            boundaries.append(valleyIdx)
        }

        var startEdge = mergedMaxima.first!
        while startEdge > 0 && profile[startEdge - 1] > backgroundFloor { startEdge -= 1 }
        var endEdge = mergedMaxima.last!
        while endEdge < n - 1 && profile[endEdge + 1] > backgroundFloor { endEdge += 1 }

        var bands: [(start: Int, end: Int)] = []
        var start = startEdge
        for b in boundaries {
            bands.append((start, b))
            start = b
        }
        bands.append((start, endEdge))
        return bands
    }
}

/// A grayscale pixel buffer copied into Swift-owned memory (never a raw
/// pointer into a `CGContext`'s backing store, which is deallocated once the
/// context goes out of scope - returning a pointer into it is a use-after-
/// free bug, confirmed the hard way while prototyping this feature).
struct GrayscaleBuffer {
    let bytes: [UInt8]
    let width: Int
    let height: Int
    let bytesPerRow: Int

    init?(image: CGImage) {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }

        self.bytes = [UInt8](UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: bytesPerRow * height))
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
    }

    private init(bytes: [UInt8], width: Int, height: Int, bytesPerRow: Int) {
        self.bytes = bytes
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
    }

    /// `y` is top-down, matching `CGImage.cropping(to:)`'s convention (this
    /// was confirmed empirically while validating this feature, not assumed:
    /// crops taken this way lined up correctly with the source photo).
    func cropped(x: Int, y: Int, width: Int, height: Int) -> GrayscaleBuffer {
        var out = [UInt8](repeating: 255, count: max(0, width * height))
        for row in 0..<height {
            let srcRowStart = (y + row) * bytesPerRow + x
            let dstRowStart = row * width
            for col in 0..<width {
                out[dstRowStart + col] = bytes[srcRowStart + col]
            }
        }
        return GrayscaleBuffer(bytes: out, width: width, height: height, bytesPerRow: width)
    }
}
