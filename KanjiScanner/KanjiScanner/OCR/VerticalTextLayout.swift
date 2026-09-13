import Foundation
import CoreGraphics

/// Finds vertical-text column boundaries via ink-density projection, for
/// recognizing tategaki Japanese text - which `TextRecognizer` (Apple's
/// Vision framework) cannot read at all, confirmed directly against real
/// vertical-text photos (zero results).
///
/// Column boundaries are found by ink-density projection + local-maxima/
/// valley detection, not `VNDetectTextRectanglesRequest`: that request was
/// tried first and confirmed to badly fragment a real, dense multi-column
/// page (55 detected "regions" for ~14 real columns - individual furigana
/// glyphs were picked up as separate regions). A fixed global brightness
/// threshold was tried next and also confirmed to fail on real photos: both
/// column gutters and inter-character gaps sit at a moderate relative
/// brightness, not near zero like clean synthetic renders - valley detection
/// (cut at the trough between two detected peaks) is robust to that where a
/// global threshold isn't. This part of an earlier vertical-text attempt
/// worked well and carries forward unchanged; what didn't work (per-
/// character cell slicing + strip compositing, to keep glyphs upright for
/// Vision's benefit) is deliberately not part of this design - see
/// `PaddleRecognizer`'s doc comment for why a whole-column rotation is
/// viable this time.
enum VerticalTextLayout {
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

    /// Forces `image` into a fully-realized bitmap, copying it through a
    /// plain `CGContext` round-trip. Confirmed necessary the hard way: a
    /// `CGImage` straight out of `CGImageSourceCreateThumbnailAtIndex` can be
    /// backed by a lazy/tiled data provider that doesn't fully decode under
    /// `cropping(to:)` in every environment - cropping such an image and
    /// reading it back produced valid pixels only near row 0 and zeros for
    /// everything else when run in the iOS Simulator against a real photo,
    /// despite the exact same code working fine in a standalone macOS
    /// process. Call this once on the page image before cropping anything
    /// out of it; nothing downstream needs to be defensive about it again,
    /// since every other CGImage in this pipeline already comes from a
    /// `CGContext.makeImage()` call, not a lazy decoder.
    static func materialized(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    /// Rotates `image` 90 degrees. `clockwise` controls which edge becomes
    /// which: a vertical column reads top-to-bottom, and the recognizer
    /// downstream reads left-to-right, so whichever direction maps "top" to
    /// "left" is the one that preserves reading order - confirmed by visual
    /// inspection against a real photo before this is relied on (see the
    /// scratchpad validation this feature's plan calls for), not assumed.
    static func rotated90(_ image: CGImage, clockwise: Bool) -> CGImage? {
        let w = image.width
        let h = image.height
        // Deliberately normalized to a fixed, known-good color space/pixel
        // format rather than inheriting the source image's own - a real
        // photo's color space (e.g. a wide-gamut/HEIC-derived profile) isn't
        // guaranteed to round-trip cleanly through a freshly created
        // CGContext on every platform. Confirmed the hard way: inheriting
        // `image.colorSpace`/`image.bitmapInfo` rendered as a mostly-black
        // image when run in the iOS Simulator against a real photo, despite
        // working fine in a standalone macOS scratchpad test against the
        // same file - this pipeline doesn't need to preserve the original
        // color profile anyway, just approximately correct RGB for the
        // recognizer.
        guard let context = CGContext(
            data: nil,
            width: h,
            height: w,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.translateBy(x: CGFloat(h) / 2, y: CGFloat(w) / 2)
        context.rotate(by: clockwise ? -CGFloat.pi / 2 : CGFloat.pi / 2)
        context.translateBy(x: -CGFloat(w) / 2, y: -CGFloat(h) / 2)
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return context.makeImage()
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
    /// against a real photographed page: real photographed gutters sit at a
    /// moderate relative brightness, not near zero like clean synthetic
    /// renders, so cutting at the trough between two detected peaks is what
    /// actually separates them.
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
}
