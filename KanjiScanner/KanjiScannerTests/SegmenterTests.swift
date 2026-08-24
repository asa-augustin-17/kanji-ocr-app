import XCTest
@testable import KanjiScanner

final class SegmenterTests: XCTestCase {
    private var database: DictionaryDatabase!

    override func setUpWithError() throws {
        database = try TestDictionaryFactory.makeDatabase()
    }

    func testLongestMatchPrefersThreeKanjiCompoundOverTwo() {
        // "日本語" contains both the 2-kanji "日本" and 3-kanji "日本語";
        // FR-9 requires the longest valid compound to win.
        let tokens = Segmenter.segment("日本語", using: database)

        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].result.word?.surfaceForm, "日本語")
        XCTAssertEqual(tokens[0].result.kanjiBreakdown.map(\.character), ["日", "本", "語"])
    }

    func testFallsBackToSingleKanjiWhenNoCompoundMatches() {
        let tokens = Segmenter.segment("犬", using: database)

        XCTAssertEqual(tokens.count, 1)
        XCTAssertNil(tokens[0].result.word)
        XCTAssertEqual(tokens[0].result.kanjiBreakdown.map(\.character), ["犬"])
    }

    func testSkipsNonKanjiCharacters() {
        // は and です are kana and should produce no tokens; only 漢字 should.
        let tokens = Segmenter.segment("は漢字です", using: database)

        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].result.token, "漢字")
    }

    func testUnknownKanjiProducesNoEntryResult() {
        // 亜 isn't seeded in the test database, simulating a recognized
        // character with no dictionary entry (US-6's graceful-failure case).
        let tokens = Segmenter.segment("亜", using: database)

        XCTAssertEqual(tokens.count, 1)
        XCTAssertFalse(tokens[0].result.hasEntry)
    }

    func testConsecutiveUnmatchedKanjiAreGroupedIntoOneToken() {
        // "本" and "犬" are each individually seeded, but "本犬" itself is
        // not a word — should be one token covering both characters, not
        // two separate single-kanji tokens (US-4's fallback AC).
        let tokens = Segmenter.segment("本犬", using: database)

        XCTAssertEqual(tokens.count, 1)
        XCTAssertNil(tokens[0].result.word)
        XCTAssertEqual(tokens[0].result.token, "本犬")
        XCTAssertEqual(tokens[0].result.kanjiBreakdown.map(\.character), ["本", "犬"])
    }

    func testUnmatchedRunStopsBeforeARealCompoundStartingLater() {
        // "犬" alone doesn't start a compound, but "日本" (right after it)
        // does — the unmatched run should stop at "犬" rather than
        // swallowing "日" into it, so "日本" still gets found separately.
        let tokens = Segmenter.segment("犬日本", using: database)

        XCTAssertEqual(tokens.count, 2)
        XCTAssertNil(tokens[0].result.word)
        XCTAssertEqual(tokens[0].result.kanjiBreakdown.map(\.character), ["犬"])
        XCTAssertEqual(tokens[1].result.word?.surfaceForm, "日本")
    }
}
