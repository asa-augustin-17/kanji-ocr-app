import XCTest
import CoreGraphics
@testable import KanjiScanner

final class PaddleRecognizedTextTests: XCTestCase {
    // Column occupies x=[100,150) of a 1000-wide, 2000-tall page.
    // columnWidth=50 -> resizeScale = 48/50 = 0.96.
    // Three characters, each spanning 100 rotated-crop px (i.e. 100 page
    // rows), back-to-back: resized-input spans are those rotated-crop pixel
    // ranges scaled up by resizeScale (span = rotatedCropRange * 0.96).
    private let source = PaddleRecognizedText(
        text: "abc",
        characterSpans: [0..<96, 96..<192, 192..<288],
        resizeScale: 0.96,
        columnPageXRange: 100..<150,
        pageWidth: 1000,
        pageHeight: 2000,
        chunkPageYOffset: 0
    )

    private func range(_ lower: Int, _ upper: Int) -> Range<String.Index> {
        source.text.index(source.text.startIndex, offsetBy: lower)..<source.text.index(source.text.startIndex, offsetBy: upper)
    }

    func testMapsASingleCharacterToItsPageRow() throws {
        // "b" -> rotatedCropX [100,200) -> page rows [100,200).
        let box = try source.regionBoundingBox(for: range(1, 2))

        XCTAssertEqual(box.minX, 0.1, accuracy: 0.0001) // 100/1000
        XCTAssertEqual(box.width, 0.05, accuracy: 0.0001) // 50/1000
        XCTAssertEqual(box.minY, 0.9, accuracy: 0.0001) // (2000-200)/2000
        XCTAssertEqual(box.height, 0.05, accuracy: 0.0001) // (200-100)/2000
    }

    func testUnionsAMultiCharacterRange() throws {
        // "bc" -> rotatedCropX [100,300) -> page rows [100,300).
        let box = try source.regionBoundingBox(for: range(1, 3))

        XCTAssertEqual(box.minY, 0.85, accuracy: 0.0001) // (2000-300)/2000
        XCTAssertEqual(box.height, 0.1, accuracy: 0.0001) // (300-100)/2000
    }

    func testHonorsAChunkYOffsetForLaterChunksOfALongColumn() throws {
        let chunked = PaddleRecognizedText(
            text: "x",
            characterSpans: [0..<96],
            resizeScale: 0.96,
            columnPageXRange: 100..<150,
            pageWidth: 1000,
            pageHeight: 2000,
            chunkPageYOffset: 500
        )
        let box = try chunked.regionBoundingBox(for: chunked.text.startIndex..<chunked.text.endIndex)

        // rotatedCropX [0,100) + chunkPageYOffset 500 -> page rows [500,600).
        XCTAssertEqual(box.minY, 0.7, accuracy: 0.0001) // (2000-600)/2000
        XCTAssertEqual(box.height, 0.05, accuracy: 0.0001) // 100/2000
    }

    func testThrowsForRangeOutsideRecoveredSpans() {
        let empty = PaddleRecognizedText(
            text: "a",
            characterSpans: [],
            resizeScale: 1,
            columnPageXRange: 0..<10,
            pageWidth: 100,
            pageHeight: 100,
            chunkPageYOffset: 0
        )

        XCTAssertThrowsError(try empty.regionBoundingBox(for: empty.text.startIndex..<empty.text.endIndex)) { error in
            guard case RecognizedTextSourceError.rangeNotFound = error else {
                XCTFail("expected rangeNotFound, got \(error)")
                return
            }
        }
    }
}
