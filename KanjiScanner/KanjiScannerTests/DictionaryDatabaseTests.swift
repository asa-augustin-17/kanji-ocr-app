import XCTest
@testable import KanjiScanner

final class DictionaryDatabaseTests: XCTestCase {
    private var database: DictionaryDatabase!

    override func setUpWithError() throws {
        database = try TestDictionaryFactory.makeDatabase()
    }

    func testIsolatedKanjiLookupReturnsReadingsAndMeanings() {
        // US-3: character, on'yomi (katakana), kun'yomi (hiragana), meanings.
        let entry = database.kanjiEntry(character: "字")

        XCTAssertEqual(entry?.onyomi, ["ジ"])
        XCTAssertEqual(entry?.kunyomi, ["あざ"])
        XCTAssertEqual(entry?.meanings, ["character", "letter"])
    }

    func testCompoundLookupReturnsWordThenOrderedKanjiBreakdown() {
        // US-4: word first, then each constituent kanji in position order.
        let result = database.lookup(token: "漢字")

        XCTAssertEqual(result.word?.reading, "かんじ")
        XCTAssertEqual(result.word?.meanings, ["kanji", "Chinese character"])
        XCTAssertEqual(result.kanjiBreakdown.map(\.character), ["漢", "字"])
    }

    func testCompoundLookupReturnsPerCharacterFuriganaSegments() {
        // US-25: each kanji gets its own reading rather than one reading
        // spanning the whole word.
        let result = database.lookup(token: "漢字")

        XCTAssertEqual(
            result.word?.furiganaSegments,
            [
                FuriganaSegment(text: "漢", reading: "かん"),
                FuriganaSegment(text: "字", reading: "じ"),
            ]
        )
    }

    func testWordWithNoFuriganaDataHasNilSegments() {
        // US-25's fallback path: words JmdictFurigana doesn't cover should
        // decode to nil, not an empty array or a crash.
        let result = database.lookup(token: "日本語")

        XCTAssertNil(result.word?.furiganaSegments)
    }

    func testMissingSurfaceFormReturnsNoWord() {
        XCTAssertNil(database.wordEntry(surfaceForm: "存在しない単語"))
    }

    func testLookupOfUnlistedCharacterHasNoEntry() {
        let result = database.lookup(token: "亜")

        XCTAssertFalse(result.hasEntry)
        XCTAssertNil(result.word)
        XCTAssertTrue(result.kanjiBreakdown.isEmpty)
    }
}
