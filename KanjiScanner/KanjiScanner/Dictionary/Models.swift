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

struct WordEntry: Identifiable, Equatable {
    let id: Int64
    let surfaceForm: String
    let reading: String
    let meanings: [String]
    let partOfSpeech: String?
    let isCommon: Bool
    /// Per-character furigana alignment (US-25), or `nil` for the ~4% of
    /// words JmdictFurigana doesn't cover - those fall back to whole-word
    /// furigana in the UI (US-18's original behavior).
    let furiganaSegments: [FuriganaSegment]?
}

extension WordEntry: FetchableRecord {
    init(row: Row) {
        id = row["id"]
        surfaceForm = row["surface_form"]
        reading = row["reading"]
        let json = row["meanings"] as String?
        if let json, let data = json.data(using: .utf8) {
            meanings = (try? JSONDecoder().decode([String].self, from: data)) ?? []
        } else {
            meanings = []
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
