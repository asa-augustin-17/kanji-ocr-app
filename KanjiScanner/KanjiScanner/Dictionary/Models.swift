import Foundation
import GRDB

struct KanjiEntry: Identifiable, Equatable {
    let id: Int64
    let character: String
    let onyomi: [String]
    let kunyomi: [String]
    let meanings: [String]
    let strokeCount: Int?
    let grade: Int?
    let jlptLevel: Int?
    let frequencyRank: Int?
    let radical: String?
}

extension KanjiEntry: FetchableRecord {
    init(row: Row) {
        id = row["id"]
        character = row["character"]
        onyomi = Self.decodeStringArray(row["onyomi"])
        kunyomi = Self.decodeStringArray(row["kunyomi"])
        meanings = Self.decodeStringArray(row["meanings"])
        strokeCount = row["stroke_count"]
        grade = row["grade"]
        jlptLevel = row["jlpt_level"]
        frequencyRank = row["frequency_rank"]
        radical = row["radical"]
    }

    private static func decodeStringArray(_ json: String?) -> [String] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}

/// One furigana run within a word (US-25): `text` is a substring of the
/// word's surface form, `reading` is the kana that goes above it, or `nil`
/// if `text` is already kana in the surface form (no reading needed). A run
/// can span more than one character when kanji share one indivisible
/// reading (jukujikun, e.g. "大人" -> "おとな" within 大人買い) - this
/// mirrors how the source data (JmdictFurigana) segments it, rather than
/// forcing one character per run.
struct FuriganaSegment: Equatable, Codable {
    let text: String
    let reading: String?
}

/// One JMdict `<sense>`: its own part-of-speech tags (unordered - JMdict's
/// real data has entries where the same tags appear in a different order
/// across senses, so grouping must compare `pos` as a set, never by string
/// or ordered-array equality) and its English glosses (US-21).
struct WordSense: Equatable, Codable {
    let pos: [String]
    let glosses: [String]
}

/// A run of consecutive `WordSense`s that share the same usage context
/// (identical `pos`, as a set) - JMdict's own structural signal for a
/// meaning-context boundary (e.g. 切る's core "to cut" senses vs. its
/// `suf`-tagged "-切る" senses), the same signal Jisho.org's numbered
/// sense groups are built from (US-21).
struct SenseGroup: Equatable {
    let pos: [String]
    let senses: [WordSense]

    /// Merges consecutive senses whose `pos` sets are equal into one group,
    /// preserving order. Pure/stateless - no semantic clustering, since
    /// JMdict has no signal finer than pos for this.
    static func group(_ senses: [WordSense]) -> [SenseGroup] {
        var groups: [SenseGroup] = []
        for sense in senses {
            if let last = groups.last, Set(last.pos) == Set(sense.pos) {
                groups[groups.count - 1] = SenseGroup(pos: last.pos, senses: last.senses + [sense])
            } else {
                groups.append(SenseGroup(pos: sense.pos, senses: [sense]))
            }
        }
        return groups
    }
}

struct WordEntry: Identifiable, Equatable {
    let id: Int64
    let surfaceForm: String
    let reading: String
    let senses: [WordSense]
    let partOfSpeech: String?
    let isCommon: Bool
    /// Per-character furigana alignment (US-25), or `nil` for the ~4% of
    /// words JmdictFurigana doesn't cover - those fall back to whole-word
    /// furigana in the UI (US-18's original behavior).
    let furiganaSegments: [FuriganaSegment]?

    /// Consecutive senses grouped by shared usage context (US-21), for
    /// Jisho-style numbered/headed display. Computed on access rather than
    /// stored at decode time - cheap, and keeps `init(row:)` simple.
    var senseGroups: [SenseGroup] { SenseGroup.group(senses) }
}

extension WordEntry: FetchableRecord {
    init(row: Row) {
        id = row["id"]
        surfaceForm = row["surface_form"]
        reading = row["reading"]
        let json = row["meanings"] as String?
        if let json, let data = json.data(using: .utf8) {
            senses = (try? JSONDecoder().decode([WordSense].self, from: data)) ?? []
        } else {
            senses = []
        }
        partOfSpeech = row["part_of_speech"]
        isCommon = row["is_common"]

        let furiganaJSON = row["furigana_segments"] as String?
        if let furiganaJSON, let data = furiganaJSON.data(using: .utf8) {
            furiganaSegments = try? JSONDecoder().decode([FuriganaSegment].self, from: data)
        } else {
            furiganaSegments = nil
        }
    }
}

/// The outcome of looking up a single scanned token: either a compound word
/// with its constituent kanji broken out (US-4), an isolated kanji (US-3),
/// or a recognized-but-unlisted kanji (US-6's "no dictionary entry found").
struct LookupResult: Identifiable, Equatable {
    var id: String { token }
    let token: String
    let word: WordEntry?
    let kanjiBreakdown: [KanjiEntry]

    var hasEntry: Bool { word != nil || !kanjiBreakdown.isEmpty }
}
