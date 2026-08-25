import XCTest
@testable import KanjiScanner

/// Pure logic tests for `SenseGroup.group(_:)` (US-21) - no DB needed, since
/// grouping only operates on `[WordSense]`.
final class SenseGroupingTests: XCTestCase {
    func testSingleSenseWithNoPosFormsOneGroup() {
        let senses = [WordSense(pos: [], glosses: ["eye"])]

        let groups = SenseGroup.group(senses)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].pos, [])
        XCTAssertEqual(groups[0].senses, senses)
    }

    func testTwoAdjacentSensesWithSamePosMerge() {
        let a = WordSense(pos: ["Godan verb", "transitive verb"], glosses: ["to cut"])
        let b = WordSense(pos: ["Godan verb", "transitive verb"], glosses: ["to sever"])

        let groups = SenseGroup.group([a, b])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].senses, [a, b])
    }

    func testKiruShapeGroupsAtThePosBoundary() {
        // Mirrors the real 切る entry: 17 senses sharing one pos, then a pos
        // change for the trailing 3 suffix senses - exactly 2 groups, split
        // at the right point.
        let verbSenses = (1...17).map { WordSense(pos: ["Godan verb with 'ru' ending", "transitive verb"], glosses: ["sense \($0)"]) }
        let suffixSenses = (18...20).map { WordSense(pos: ["suffix", "Godan verb with 'ru' ending"], glosses: ["sense \($0)"]) }

        let groups = SenseGroup.group(verbSenses + suffixSenses)

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].senses.count, 17)
        XCTAssertEqual(groups[1].senses.count, 3)
        XCTAssertEqual(Set(groups[0].pos), Set(["Godan verb with 'ru' ending", "transitive verb"]))
        XCTAssertEqual(Set(groups[1].pos), Set(["suffix", "Godan verb with 'ru' ending"]))
    }

    func testToruShapeStaysOneGroupOfManySenses() {
        // Mirrors 取る: every sense shares one pos throughout, so grouping
        // yields a single group - senses stay individually numbered by the
        // view, not collapsed together.
        let senses = (1...18).map { WordSense(pos: ["Godan verb with 'ru' ending", "transitive verb"], glosses: ["sense \($0)"]) }

        let groups = SenseGroup.group(senses)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].senses.count, 18)
    }

    func testPosEqualityIsOrderInsensitive() {
        // Real JMdict entries (e.g. シングル, くたくた) have two senses whose
        // pos tags are identical as a set but appear in a different order -
        // these must still merge into one group.
        let a = WordSense(pos: ["noun (common)", "adjectival nouns"], glosses: ["single"])
        let b = WordSense(pos: ["adjectival nouns", "noun (common)"], glosses: ["one person"])

        let groups = SenseGroup.group([a, b])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].senses, [a, b])
    }

    func testNonMonotonicPosPatternFormsThreeGroups() {
        // A, B, A shouldn't re-merge the two "A" runs into one group - only
        // *consecutive* equal-pos senses merge.
        let a1 = WordSense(pos: ["A"], glosses: ["first A"])
        let b = WordSense(pos: ["B"], glosses: ["a B"])
        let a2 = WordSense(pos: ["A"], glosses: ["second A"])

        let groups = SenseGroup.group([a1, b, a2])

        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups[0].senses, [a1])
        XCTAssertEqual(groups[1].senses, [b])
        XCTAssertEqual(groups[2].senses, [a2])
    }
}
