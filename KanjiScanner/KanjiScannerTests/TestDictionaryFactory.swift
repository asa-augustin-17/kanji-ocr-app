import Foundation
import GRDB
@testable import KanjiScanner

/// Builds a small, throwaway SQLite database with the same schema as
/// build_dictionary.py's output, seeded with a handful of known entries —
/// so segmentation/lookup logic can be tested without the full 50MB+
/// bundled dictionary.
enum TestDictionaryFactory {
    static func makeDatabase() throws -> DictionaryDatabase {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")

        let seedQueue = try DatabaseQueue(path: url.path)
        try seedQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE kanji (
                    id INTEGER PRIMARY KEY,
                    character TEXT NOT NULL UNIQUE,
                    onyomi TEXT NOT NULL,
                    kunyomi TEXT NOT NULL,
                    meanings TEXT NOT NULL,
                    stroke_count INTEGER,
                    grade INTEGER,
                    jlpt_level INTEGER,
                    frequency_rank INTEGER,
                    radical TEXT
                );
                CREATE TABLE words (
                    id INTEGER PRIMARY KEY,
                    surface_form TEXT NOT NULL,
                    reading TEXT NOT NULL,
                    meanings TEXT NOT NULL,
                    part_of_speech TEXT,
                    is_common INTEGER NOT NULL DEFAULT 0,
                    furigana_segments TEXT
                );
                CREATE TABLE word_kanji_map (
                    word_id INTEGER NOT NULL,
                    kanji_id INTEGER NOT NULL,
                    position INTEGER NOT NULL
                );
                CREATE INDEX idx_kanji_character ON kanji(character);
                CREATE INDEX idx_words_surface_form ON words(surface_form);
                CREATE INDEX idx_words_reading ON words(reading);
                CREATE INDEX idx_word_kanji_map_word_position ON word_kanji_map(word_id, position);
                """)

            func insertKanji(_ character: String, onyomi: [String], kunyomi: [String], meanings: [String]) throws -> Int64 {
                try db.execute(
                    sql: "INSERT INTO kanji (character, onyomi, kunyomi, meanings) VALUES (?, ?, ?, ?)",
                    arguments: [character, json(onyomi), json(kunyomi), json(meanings)]
                )
                return db.lastInsertedRowID
            }

            func insertWord(
                _ surfaceForm: String,
                reading: String,
                meanings: [String],
                kanjiIDs: [Int64],
                furiganaSegments: [FuriganaSegment]? = nil
            ) throws {
                try db.execute(
                    sql: """
                    INSERT INTO words (surface_form, reading, meanings, is_common, furigana_segments)
                    VALUES (?, ?, ?, 1, ?)
                    """,
                    arguments: [surfaceForm, reading, json(meanings), furiganaSegments.map(jsonSegments)]
                )
                let wordID = db.lastInsertedRowID
                for (position, kanjiID) in kanjiIDs.enumerated() {
                    try db.execute(
                        sql: "INSERT INTO word_kanji_map (word_id, kanji_id, position) VALUES (?, ?, ?)",
                        arguments: [wordID, kanjiID, position]
                    )
                }
            }

            let kan = try insertKanji("漢", onyomi: ["カン"], kunyomi: [], meanings: ["Sino-", "China"])
            let ji = try insertKanji("字", onyomi: ["ジ"], kunyomi: ["あざ"], meanings: ["character", "letter"])
            let nichi = try insertKanji("日", onyomi: ["ニチ"], kunyomi: ["ひ"], meanings: ["day", "sun", "Japan"])
            let hon = try insertKanji("本", onyomi: ["ホン"], kunyomi: ["もと"], meanings: ["book", "origin"])
            let go = try insertKanji("語", onyomi: ["ゴ"], kunyomi: ["かた.る"], meanings: ["word", "language"])
            _ = try insertKanji("犬", onyomi: [], kunyomi: ["いぬ"], meanings: ["dog"])

            try insertWord(
                "漢字",
                reading: "かんじ",
                meanings: ["kanji", "Chinese character"],
                kanjiIDs: [kan, ji],
                furiganaSegments: [
                    FuriganaSegment(text: "漢", reading: "かん"),
                    FuriganaSegment(text: "字", reading: "じ"),
                ]
            )
            try insertWord("日本語", reading: "にほんご", meanings: ["Japanese language"], kanjiIDs: [nichi, hon, go])
            try insertWord("日本", reading: "にほん", meanings: ["Japan"], kanjiIDs: [nichi, hon])
            try insertWord("コーヒー", reading: "コーヒー", meanings: ["coffee"], kanjiIDs: [])
            // Kanji-form entry with no matching katakana-only entry of its
            // own — exercises the US-23 reading-fallback path (real-world
            // equivalent: 珈琲/コーヒー).
            try insertWord("煙草", reading: "タバコ", meanings: ["tobacco", "cigarette"], kanjiIDs: [])
        }

        return try DictionaryDatabase(path: url.path)
    }

    private static func json(_ strings: [String]) -> String {
        let data = try! JSONEncoder().encode(strings)
        return String(data: data, encoding: .utf8)!
    }

    private static func jsonSegments(_ segments: [FuriganaSegment]) -> String {
        let data = try! JSONEncoder().encode(segments)
        return String(data: data, encoding: .utf8)!
    }
}
