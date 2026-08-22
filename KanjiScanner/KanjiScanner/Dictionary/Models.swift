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

struct WordEntry: Identifiable, Equatable {
    let id: Int64
    let surfaceForm: String
    let reading: String
    let meanings: [String]
    let partOfSpeech: String?
    let isCommon: Bool
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
