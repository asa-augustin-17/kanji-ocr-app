import XCTest
import CoreGraphics
@testable import KanjiScanner

/// A `RecognizedTextSource` double that returns a fixed, known box regardless
/// of the requested range - lets `VerticalRecognizedText`'s strip-to-original
/// coordinate mapping be tested in isolation, without a real Vision call.
private struct FixedBoxTextSource: RecognizedTextSource {
    let box: CGRect
    func regionBoundingBox(for range: Range<String.Index>) throws -> CGRect {
        box
    }
}

private let anyRange = "x".startIndex..<"x".endIndex

final class VerticalRecognizedTextTests: XCTestCase {
    /// Three cells, each a 100px-wide slot in a 300px strip, each mapping to
    /// a distinct, known rect in the original image.
    private let cellTable: [(stripXRange: Range<Int>, originalNormalizedRect: CGRect)] = [
        (0..<100, CGRect(x: 0.10, y: 0.70, width: 0.08, height: 0.08)),
        (100..<200, CGRect(x: 0.10, y: 0.60, width: 0.08, height: 0.08)),
        (200..<300, CGRect(x: 0.10, y: 0.50, width: 0.08, height: 0.08)),
    ]

    func testMapsStripRangeEntirelyWithinOneCellToThatCellsRect() throws {
        // Normalized box [0.4, 0.7) of a 300px strip -> pixel x [120, 210) -
        // entirely inside cell 1 (stripXRange 100..<200)... actually spans
        // into cell 2 slightly; use a tighter box fully inside cell 1.
        let source = VerticalRecognizedText(
            stripText: FixedBoxTextSource(box: CGRect(x: 0.35, y: 0, width: 0.2, height: 1)), // px [105, 165)
            stripPixelWidth: 300,
            cellTable: cellTable
        )

        let result = try source.regionBoundingBox(for: anyRange)

        let expected = cellTable[1].originalNormalizedRect
        XCTAssertEqual(result.minX, expected.minX, accuracy: 0.0001)
        XCTAssertEqual(result.minY, expected.minY, accuracy: 0.0001)
        XCTAssertEqual(result.width, expected.width, accuracy: 0.0001)
        XCTAssertEqual(result.height, expected.height, accuracy: 0.0001)
    }

    func testUnionsAllCellsTheStripRangeOverlaps() throws {
        // Normalized box [0.2, 0.9) of a 300px strip -> pixel x [60, 270) -
        // overlaps all three cells (0..<100, 100..<200, 200..<300).
        let source = VerticalRecognizedText(
            stripText: FixedBoxTextSource(box: CGRect(x: 0.2, y: 0, width: 0.7, height: 1)),
            stripPixelWidth: 300,
            cellTable: cellTable
        )

        let result = try source.regionBoundingBox(for: anyRange)

        let expected = CGRect(x: 0.10, y: 0.50, width: 0.08, height: 0.28) // union of all three rects
        XCTAssertEqual(result.minX, expected.minX, accuracy: 0.0001)
        XCTAssertEqual(result.minY, expected.minY, accuracy: 0.0001)
        XCTAssertEqual(result.maxX, expected.maxX, accuracy: 0.0001)
        XCTAssertEqual(result.maxY, expected.maxY, accuracy: 0.0001)
    }

    func testThrowsWhenStripRangeFallsOutsideEveryCell() {
        // A cell table that leaves a gap at strip x [100, 150).
        let sparseTable: [(stripXRange: Range<Int>, originalNormalizedRect: CGRect)] = [
            (0..<100, CGRect(x: 0, y: 0, width: 0.1, height: 0.1)),
            (150..<300, CGRect(x: 0.2, y: 0, width: 0.1, height: 0.1)),
        ]
        let source = VerticalRecognizedText(
            stripText: FixedBoxTextSource(box: CGRect(x: 0.35, y: 0, width: 0.03, height: 1)), // px [105, 114)
            stripPixelWidth: 300,
            cellTable: sparseTable
        )

        XCTAssertThrowsError(try source.regionBoundingBox(for: anyRange)) { error in
            guard case RecognizedTextSourceError.rangeNotFound = error else {
                XCTFail("expected rangeNotFound, got \(error)")
                return
            }
        }
    }
}

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

    func testDetectCellsFindsEvenlySpacedCharacterBars() throws {
        // A narrow "column" with 6 evenly-spaced horizontal ink bars,
        // simulating characters stacked top-to-bottom with real gaps
        // between them (not near-zero, like a real photographed column).
        let columnWidth = 60
        let barHeight = 50
        let gap = 18
        let barCount = 6
        let height = gap + barCount * (barHeight + gap)

        let image = makeSyntheticImage(width: columnWidth, height: height) { ctx in
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            for i in 0..<barCount {
                let y = gap + i * (barHeight + gap)
                ctx.fill(CGRect(x: 0, y: y, width: columnWidth, height: barHeight))
            }
        }
        let buffer = try XCTUnwrap(GrayscaleBuffer(image: image))

        let cells = VerticalTextLayout.detectCells(in: buffer)

        XCTAssertEqual(cells.count, barCount)
        // Same rationale as the column test above: a valley cut can land
        // anywhere within a gap, so bound the tolerance by `gap` rather than
        // expecting bar-tight precision.
        for cell in cells {
            let detectedHeight = cell.end - cell.start + 1
            XCTAssertLessThanOrEqual(detectedHeight, barHeight + 2 * gap, "each detected cell shouldn't balloon past bar+adjacent gaps")
            XCTAssertGreaterThanOrEqual(detectedHeight, barHeight - 4, "each detected cell shouldn't be narrower than the drawn bar")
        }
    }

    func testCompositeStripPreservesCellCountAndOrder() throws {
        let columnWidth = 60
        let barHeight = 50
        let gap = 18
        let barCount = 4
        let height = gap + barCount * (barHeight + gap)

        let image = makeSyntheticImage(width: columnWidth, height: height) { ctx in
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            for i in 0..<barCount {
                let y = gap + i * (barHeight + gap)
                ctx.fill(CGRect(x: 0, y: y, width: columnWidth, height: barHeight))
            }
        }
        let cells = [
            (start: 0, end: 60),
            (start: 70, end: 130),
            (start: 140, end: 200),
            (start: 210, end: 270),
        ]

        let strip = try XCTUnwrap(VerticalTextLayout.compositeStrip(
            originalImage: image,
            pageWidth: columnWidth,
            pageHeight: height,
            columnX: (start: 0, end: columnWidth - 1),
            cells: cells
        ))

        XCTAssertEqual(strip.cellTable.count, cells.count)
        // Cells should be laid out left-to-right in the same order as given
        // (top-to-bottom reading order within the column), each occupying a
        // columnWidth-wide slot.
        for (i, entry) in strip.cellTable.enumerated() {
            XCTAssertEqual(entry.stripXRange, (i * columnWidth)..<((i + 1) * columnWidth))
        }
        XCTAssertEqual(strip.image.width, columnWidth * cells.count)
    }
}
