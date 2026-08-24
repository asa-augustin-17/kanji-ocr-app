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

    func testIsolatedSingleKanjiPrefersWordEntryWhenOneExists() {
        // US-19: 目 is both a kanji and a standalone word in its own right -
        // an isolated single-kanji selection should surface the word (with
        // its one-kanji breakdown), not just the plain kanji detail view.
        let tokens = Segmenter.segment("目", using: database)

        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].result.word?.surfaceForm, "目")
        XCTAssertEqual(tokens[0].result.word?.meanings, ["eye"])
        XCTAssertEqual(tokens[0].result.kanjiBreakdown.map(\.character), ["目"])
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

    func testMatchesKatakanaWord() {
        // US-23: a katakana loanword should be looked up the same way a
        // kanji compound is, even with no kanji involved at all.
        let tokens = Segmenter.segment("コーヒー", using: database)

        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].result.word?.surfaceForm, "コーヒー")
        XCTAssertEqual(tokens[0].result.word?.meanings, ["coffee"])
    }

    func testUnmatchedKatakanaRunProducesNoEntryResult() {
        // A katakana run not seeded in the test database should still become
        // one tappable token resolving to "no dictionary entry found"
        // (US-6), not be silently skipped like hiragana/romaji are.
        let tokens = Segmenter.segment("メロン", using: database)

        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].result.token, "メロン")
        XCTAssertFalse(tokens[0].result.hasEntry)
    }

    func testSingleUnmatchedKatakanaCharacterProducesNoToken() {
        // US-33: a lone unmatched katakana character (e.g. ト) shouldn't get
        // a tappable "no dictionary entry found" region at all - unlike a
        // multi-character run (testUnmatchedKatakanaRunProducesNoEntryResult
        // above), which still should, and unlike a single unmatched *kanji*
        // (US-6's original behavior, deliberately unchanged).
        let tokens = Segmenter.segment("ト", using: database)

        XCTAssertTrue(tokens.isEmpty)
    }

    func testKatakanaWordAmongMixedKanjiAndHiraganaText() {
        // "私" (unseeded kanji) + "は...です" (hiragana, skipped) +
        // "コーヒー" (katakana word) — the katakana word should be found
        // alongside the kanji token, not swallowed or skipped.
        let tokens = Segmenter.segment("私はコーヒーです", using: database)

        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].result.token, "私")
        XCTAssertEqual(tokens[1].result.word?.surfaceForm, "コーヒー")
    }

    func testKatakanaWordFallsBackToKanjiEntryByReading() {
        // US-23's kanji-fallback: "タバコ" has no katakana-only entry of its
        // own, but "煙草" (seeded with reading タバコ) does — scanning the
        // katakana spelling should still surface the richer kanji entry
        // (real-world equivalent: コーヒー -> 珈琲), not "no entry found".
        let tokens = Segmenter.segment("タバコ", using: database)

        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].result.word?.surfaceForm, "煙草")
        XCTAssertEqual(tokens[0].result.word?.reading, "タバコ")
        XCTAssertEqual(tokens[0].result.word?.meanings, ["tobacco", "cigarette"])
    }

    func testKatakanaOnlyEntryTakesPriorityOverReadingFallback() {
        // When both a direct katakana-only entry and a same-length
        // reading-fallback candidate could apply, the direct surface-form
        // match should win (it's already covered by testMatchesKatakanaWord
        // finding "コーヒー" itself; this asserts the fallback doesn't
        // accidentally take over even though `wordEntry(reading:)` would
        // never match here, since コーヒー's own entry has surface_form ==
        // reading and is excluded from the fallback query by design).
        let tokens = Segmenter.segment("コーヒー", using: database)

        XCTAssertEqual(tokens[0].result.word?.surfaceForm, "コーヒー")
    }

    func testStandaloneKatakanaMiddleDotProducesNoToken() {
        // BUG-012: a lone ・ (e.g. from OCR misreading a printed period)
        // shouldn't become its own tappable "no dictionary entry found"
        // region - it's punctuation, not a word.
        let tokens = Segmenter.segment("・", using: database)

        XCTAssertTrue(tokens.isEmpty)
    }

    func testStandaloneLongVowelMarkProducesNoToken() {
        // Same as the middle-dot case, for the other katakana connector: ー
        // alone isn't a word either.
        let tokens = Segmenter.segment("ー", using: database)

        XCTAssertTrue(tokens.isEmpty)
    }

    func testKatakanaMiddleDotBetweenTwoWordsIsSkippedNotTapped() {
        // "コーヒー・パソコン" - a real-world-shaped separator use (like a
        // menu listing コーヒー・紅茶). Both words should still be found;
        // the ・ between them should be silently skipped, not produce its
        // own dead-end token (BUG-012), and shouldn't get swallowed into
        // either neighboring word's token either.
        let tokens = Segmenter.segment("コーヒー・パソコン", using: database)

        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].result.word?.surfaceForm, "コーヒー")
        XCTAssertEqual(tokens[1].result.word?.surfaceForm, "パソコン")
    }

    func testMatchesArabicNumeralPlusCounterViaKanjiConversion() {
        // US-31: "1匹" isn't itself a dictionary surface form, but converts
        // to "一匹", which is - the whole "1匹" span (as actually printed)
        // should become one tappable token resolving to that richer entry.
        let tokens = Segmenter.segment("1匹", using: database)

        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].result.token, "1匹")
        XCTAssertEqual(tokens[0].result.word?.surfaceForm, "一匹")
        XCTAssertEqual(tokens[0].result.word?.reading, "いっぴき")
        XCTAssertEqual(tokens[0].result.word?.meanings, ["one (small animal)"])
    }

    func testUnmatchedDigitRunProducesNoToken() {
        // A bare number with nothing after it (or nothing matching) should
        // never become its own dead tap target the way an unmatched kanji
        // or katakana run does - ordinary numbers (prices, page numbers)
        // are common in photographed text and shouldn't be tappable noise.
        let tokens = Segmenter.segment("42", using: database)

        XCTAssertTrue(tokens.isEmpty)
    }

    func testNumeralCounterMatchWithinSentence() {
        // "犬" (kanji, no word entry - falls back to kanji-only) + "が"
        // (hiragana, skipped) + "1匹" (numeral+counter, matches 一匹) +
        // "いる" (hiragana, skipped) - the numeral match shouldn't disturb
        // segmentation of the surrounding text.
        let tokens = Segmenter.segment("犬が1匹いる", using: database)

        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].result.token, "犬")
        XCTAssertNil(tokens[0].result.word)
        XCTAssertEqual(tokens[1].result.word?.surfaceForm, "一匹")
    }
}
