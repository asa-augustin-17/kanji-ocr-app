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
