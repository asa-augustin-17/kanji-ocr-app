import XCTest
@testable import KanjiScanner

final class PaddleRecognizerCTCDecodeTests: XCTestCase {
    private let labels = ["<blank>", "A", "B", "C"]

    private func makeLogits(classSequence: [Int], numClasses: Int) -> [Float] {
        var logits = [Float](repeating: 0, count: classSequence.count * numClasses)
        for (t, cls) in classSequence.enumerated() {
            logits[t * numClasses + cls] = 10.0 // clear winner, no ties
        }
        return logits
    }

    func testCollapsesRepeatedTimestepsIntoOneCharacterPerRun() {
        // blank, A,A,A, blank, B, C,C
        let classSequence = [0, 1, 1, 1, 0, 2, 3, 3]
        let logits = makeLogits(classSequence: classSequence, numClasses: 4)

        let result = PaddleRecognizer.ctcDecode(logits: logits, seqLen: classSequence.count, numClasses: 4, labels: labels, downsampleRatio: 2.0)

        XCTAssertEqual(result.text, "ABC")
        XCTAssertEqual(result.characterSpans, [2..<8, 10..<12, 12..<16])
    }

    func testTwoRunsOfTheSameCharacterSeparatedByBlankAreNotMerged() {
        // A, blank, A - real CTC repeats separated by blank stay as two characters.
        let classSequence = [1, 0, 1]
        let logits = makeLogits(classSequence: classSequence, numClasses: 4)

        let result = PaddleRecognizer.ctcDecode(logits: logits, seqLen: classSequence.count, numClasses: 4, labels: labels, downsampleRatio: 1.0)

        XCTAssertEqual(result.text, "AA")
        XCTAssertEqual(result.characterSpans.count, 2)
    }

    func testAllBlankProducesEmptyText() {
        let classSequence = [0, 0, 0, 0]
        let logits = makeLogits(classSequence: classSequence, numClasses: 4)

        let result = PaddleRecognizer.ctcDecode(logits: logits, seqLen: classSequence.count, numClasses: 4, labels: labels, downsampleRatio: 1.0)

        XCTAssertEqual(result.text, "")
        XCTAssertTrue(result.characterSpans.isEmpty)
    }
}
