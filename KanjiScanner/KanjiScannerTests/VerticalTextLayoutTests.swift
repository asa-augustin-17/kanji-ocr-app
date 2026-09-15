import XCTest
import CoreGraphics
@testable import KanjiScanner

final class VerticalTextLayoutTests: XCTestCase {
    private func makeSyntheticImage(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        draw(context)
        return context.makeImage()!
    }

    /// Fills a column with alternating ink/gap segments along its height,
    /// simulating real printed text's character-vs-gap structure - a solid,
    /// unbroken bar (uniform along its whole height) doesn't have this, and
    /// `detectColumns`'s row-variation sanity filter specifically depends on
    /// it to tell real text apart from background texture.
    private func fillTexturedBar(_ ctx: CGContext, x: Int, width: Int, height: Int) {
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        let segment = 20
        var y = 0
        while y < height {
            ctx.fill(CGRect(x: x, y: y, width: width, height: min(segment, height - y)))
            y += segment * 2
        }
    }

    func testDetectColumnsFindsEvenlySpacedVerticalBars() throws {
        // 5 full-height black bars, 24px wide, separated by 24px white gaps.
        let barWidth = 24
        let gap = 24
        let barCount = 5
        let width = gap + barCount * (barWidth + gap)
        let height = 300

        let image = makeSyntheticImage(width: width, height: height) { ctx in
            for i in 0..<barCount {
                let x = gap + i * (barWidth + gap)
                fillTexturedBar(ctx, x: x, width: barWidth, height: height)
            }
        }
        let buffer = try XCTUnwrap(GrayscaleBuffer(image: image))

        let columns = VerticalTextLayout.detectColumns(in: buffer)

        XCTAssertEqual(columns.count, barCount)
        // Valley cuts land wherever the profile's minimum falls within a gap,
        // not necessarily its center, so a detected band's edges can extend
        // into a neighboring gap by close to that gap's full width - bound
        // the tolerance by `gap` rather than expecting bar-tight precision.
        for (i, column) in columns.enumerated() {
            let expectedBarStart = gap + i * (barWidth + gap)
            let expectedCenter = expectedBarStart + barWidth / 2
            let actualCenter = (column.start + column.end) / 2
            XCTAssertLessThanOrEqual(abs(actualCenter - expectedCenter), gap / 2, "column \(i) center should land close to the drawn bar's center")

            let detectedWidth = column.end - column.start + 1
            XCTAssertLessThanOrEqual(detectedWidth, barWidth + 2 * gap, "column \(i) width shouldn't balloon past bar+adjacent gaps")
            XCTAssertGreaterThanOrEqual(detectedWidth, barWidth - 4, "column \(i) width shouldn't be narrower than the drawn bar")
        }
    }

    func testDetectColumnsDropsNarrowNonTextBands() throws {
        // One real (wide, dark) column plus one thin sliver too narrow to be
        // real text - mirrors a real photo's page-edge/binding artifact,
        // which the sanity filter is specifically there to reject.
        let realBarWidth = 40
        let gap = 30
        let sliverWidth = 2
        let width = gap + realBarWidth + gap + sliverWidth + gap
        let height = 300

        let image = makeSyntheticImage(width: width, height: height) { ctx in
            fillTexturedBar(ctx, x: gap, width: realBarWidth, height: height)
            // The sliver stays solid - it's meant to be rejected on width
            // alone (mirrors a page-edge/binding artifact), regardless of
            // whether it happens to have internal texture.
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: gap + realBarWidth + gap, y: 0, width: sliverWidth, height: height))
        }
        let buffer = try XCTUnwrap(GrayscaleBuffer(image: image))

        let columns = VerticalTextLayout.detectColumns(in: buffer)

        XCTAssertEqual(columns.count, 1)
    }

    func testDetectColumnsDropsUniformNonTextBands() throws {
        // A real (textured) column plus a wide, dark, but UNIFORM band -
        // mirrors a real photo's background texture (e.g. a wood-grain
        // desk surface), which is dark/wide enough to pass the density and
        // width checks but lacks real text's ink/gap alternation.
        let barWidth = 40
        let gap = 30
        let uniformWidth = 60
        let width = gap + barWidth + gap + uniformWidth + gap
        let height = 300

        let image = makeSyntheticImage(width: width, height: height) { ctx in
            fillTexturedBar(ctx, x: gap, width: barWidth, height: height)
            ctx.setFillColor(CGColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1))
            ctx.fill(CGRect(x: gap + barWidth + gap, y: 0, width: uniformWidth, height: height))
        }
        let buffer = try XCTUnwrap(GrayscaleBuffer(image: image))

        let columns = VerticalTextLayout.detectColumns(in: buffer)

        XCTAssertEqual(columns.count, 1)
        XCTAssertLessThanOrEqual(columns[0].start, gap + barWidth, "the surviving column should be the textured bar, not the uniform band")
    }

    func testRotated90SwapsDimensions() throws {
        let image = makeSyntheticImage(width: 40, height: 100) { _ in }

        let clockwise = try XCTUnwrap(VerticalTextLayout.rotated90(image, clockwise: true))
        let counterclockwise = try XCTUnwrap(VerticalTextLayout.rotated90(image, clockwise: false))

        XCTAssertEqual(clockwise.width, 100)
        XCTAssertEqual(clockwise.height, 40)
        XCTAssertEqual(counterclockwise.width, 100)
        XCTAssertEqual(counterclockwise.height, 40)
    }
}
