import XCTest
import CoreGraphics
@testable import KanjiScanner

private struct DummyTextSource: RecognizedTextSource {
    func regionBoundingBox(for range: Range<String.Index>) throws -> CGRect { .zero }
}

private func makeLine(_ text: String) -> RecognizedLine {
    RecognizedLine(text: text, recognizedText: DummyTextSource(), confidence: 1.0)
}

private enum FakeError: Error { case boom }

private struct FakeRecognizer: TextRecognizing {
    var lines: [RecognizedLine] = []
    var throwsError = false
    func recognizeText(in image: CGImage) async throws -> [RecognizedLine] {
        if throwsError { throw FakeError.boom }
        return lines
    }
}

private func makeTinyImage() -> CGImage {
    let context = CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return context.makeImage()!
}

final class OrientationAwareRecognizerTests: XCTestCase {
    private let image = makeTinyImage()
    private var wasEnabled = false

    override func setUpWithError() throws {
        wasEnabled = OrientationAwareRecognizer.isEnabled
    }

    override func tearDownWithError() throws {
        OrientationAwareRecognizer.isEnabled = wasEnabled
    }

    func testDisabledAlwaysReturnsHorizontalRegardlessOfContent() async throws {
        OrientationAwareRecognizer.isEnabled = false
        let recognizer = OrientationAwareRecognizer(
            horizontalRecognizer: FakeRecognizer(lines: []),
            verticalRecognizer: FakeRecognizer(lines: [makeLine("縦書きの結果")])
        )

        let result = try await recognizer.recognizeText(in: image)

        XCTAssertEqual(result.map(\.text), [])
    }

    func testEnabledReturnsHorizontalWhenItHasEnoughContent() async throws {
        OrientationAwareRecognizer.isEnabled = true
        let recognizer = OrientationAwareRecognizer(
            horizontalRecognizer: FakeRecognizer(lines: [makeLine("横書きのテスト")]),
            verticalRecognizer: FakeRecognizer(lines: [makeLine("縦書きの結果")])
        )

        let result = try await recognizer.recognizeText(in: image)

        XCTAssertEqual(result.map(\.text), ["横書きのテスト"])
    }

    func testEnabledFallsBackToVerticalWhenHorizontalIsJustAPageNumber() async throws {
        OrientationAwareRecognizer.isEnabled = true
        let recognizer = OrientationAwareRecognizer(
            horizontalRecognizer: FakeRecognizer(lines: [makeLine("88")]),
            verticalRecognizer: FakeRecognizer(lines: [makeLine("縦書きの結果")])
        )

        let result = try await recognizer.recognizeText(in: image)

        XCTAssertEqual(result.map(\.text), ["縦書きの結果"])
    }

    func testEnabledFallsBackToHorizontalWhenVerticalFindsNothing() async throws {
        OrientationAwareRecognizer.isEnabled = true
        let recognizer = OrientationAwareRecognizer(
            horizontalRecognizer: FakeRecognizer(lines: [makeLine("88")]),
            verticalRecognizer: FakeRecognizer(lines: [])
        )

        let result = try await recognizer.recognizeText(in: image)

        XCTAssertEqual(result.map(\.text), ["88"])
    }

    func testEnabledFallsBackToHorizontalWhenVerticalThrows() async throws {
        OrientationAwareRecognizer.isEnabled = true
        let recognizer = OrientationAwareRecognizer(
            horizontalRecognizer: FakeRecognizer(lines: [makeLine("88")]),
            verticalRecognizer: FakeRecognizer(throwsError: true)
        )

        let result = try await recognizer.recognizeText(in: image)

        XCTAssertEqual(result.map(\.text), ["88"])
    }
}
