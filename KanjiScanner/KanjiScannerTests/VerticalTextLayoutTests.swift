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

    func testDetectColumnsFindsEvenlySpacedVerticalBars() throws {
        // 5 full-height black bars, 24px wide, separated by 24px white gaps.
        let barWidth = 24
        let gap = 24
        let barCount = 5
        let width = gap + barCount * (barWidth + gap)
        let height = 300

        let image = makeSyntheticImage(width: width, height: height) { ctx in
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            for i in 0..<barCount {
                let x = gap + i * (barWidth + gap)
                ctx.fill(CGRect(x: x, y: 0, width: barWidth, height: height))
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
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: gap, y: 0, width: realBarWidth, height: height))
            ctx.fill(CGRect(x: gap + realBarWidth + gap, y: 0, width: sliverWidth, height: height))
        }
        let buffer = try XCTUnwrap(GrayscaleBuffer(image: image))

        let columns = VerticalTextLayout.detectColumns(in: buffer)

        XCTAssertEqual(columns.count, 1)
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
