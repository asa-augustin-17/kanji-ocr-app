import XCTest
@testable import KanjiScanner

/// Tests for `PosDisplay.label(for:)` (US-36) - pure logic, no DB needed.
final class PosDisplayTests: XCTestCase {
    func testNounTagCollapsesToBareNoun() {
        XCTAssertEqual(PosDisplay.label(for: "noun (common) (futsuumeishi)"), "Noun")
    }

    func testIAdjectiveTagIsRenamedButKeepsRomaji() {
        XCTAssertEqual(PosDisplay.label(for: "adjective (keiyoushi)"), "I-adjective (keiyoushi)")
    }

    func testIAdjectiveYoiIiClassVariantIsRenamedButKeepsRomaji() {
        XCTAssertEqual(
            PosDisplay.label(for: "adjective (keiyoushi) - yoi/ii class"),
            "I-adjective (keiyoushi) - yoi/ii class"
        )
    }

    func testNaAdjectiveTagIsRenamedButKeepsRomaji() {
        XCTAssertEqual(
            PosDisplay.label(for: "adjectival nouns or quasi-adjectives (keiyodoshi)"),
            "Na-adjective (keiyodoshi)"
        )
    }

    func testAdverbTagIsOnlySentenceCasedNotStripped() {
        // Verified against real Jisho.org: unlike the noun tag, adverb keeps
        // its romaji term - this is not a blanket "strip the parenthetical"
        // rule.
        XCTAssertEqual(PosDisplay.label(for: "adverb (fukushi)"), "Adverb (fukushi)")
    }

    func testOrdinaryTagIsOnlySentenceCased() {
        XCTAssertEqual(PosDisplay.label(for: "transitive verb"), "Transitive verb")
        XCTAssertEqual(PosDisplay.label(for: "suffix"), "Suffix")
    }

    func testTagAlreadyCapitalizedIsUnchanged() {
        XCTAssertEqual(PosDisplay.label(for: "Godan verb with 'ru' ending"), "Godan verb with 'ru' ending")
    }

    func testTagStartingWithPunctuationCapitalizesFirstLetterNotPunctuation() {
        XCTAssertEqual(PosDisplay.label(for: "'taru' adjective"), "'Taru' adjective")
    }
}
