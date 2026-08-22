import Foundation
import GRDB

/// Read-only access to the bundled KANJIDIC2 + JMdict SQLite database (FR-10/11/12).
final class DictionaryDatabase {
    static let shared: DictionaryDatabase = {
        guard let url = Bundle.main.url(forResource: "kanji_scanner", withExtension: "sqlite") else {
            fatalError("kanji_scanner.sqlite is missing from the app bundle")
        }
        do {
            return try DictionaryDatabase(path: url.path)
        } catch {
            fatalError("Failed to open bundled dictionary database: \(error)")
        }
    }()

    private let dbQueue: DatabaseQueue

    /// Opens a read-only connection to a dictionary database at `path`. Exposed
    /// (rather than a bundle-only private init) so tests can point this at a
    /// small seeded database instead of the full bundled one.
    init(path: String) throws {
        var config = Configuration()
        config.readonly = true
        dbQueue = try DatabaseQueue(path: path, configuration: config)
    }

    /// Exact-match kanji lookup by character.
    func kanjiEntry(character: String) -> KanjiEntry? {
        try? dbQueue.read { db in
            try KanjiEntry.fetchOne(db, sql: "SELECT * FROM kanji WHERE character = ?", arguments: [character])
        }
    }

    /// Exact-match word lookup by surface form (kanji/kana as written).
    func wordEntry(surfaceForm: String) -> WordEntry? {
        try? dbQueue.read { db in
            try WordEntry.fetchOne(
                db,
                sql: "SELECT * FROM words WHERE surface_form = ? ORDER BY is_common DESC LIMIT 1",
                arguments: [surfaceForm]
            )
        }
    }

    /// Constituent kanji for a word, in on-page order (FR-12, US-4).
    func kanjiBreakdown(wordId: Int64) -> [KanjiEntry] {
        (try? dbQueue.read { db in
            try KanjiEntry.fetchAll(
                db,
                sql: """
                SELECT k.* FROM kanji k
                JOIN word_kanji_map wkm ON wkm.kanji_id = k.id
                WHERE wkm.word_id = ?
                ORDER BY wkm.position
                """,
                arguments: [wordId]
            )
        }) ?? []
    }

    /// Full lookup for a token already identified by the segmenter: resolves the
    /// compound word (if any) plus its kanji breakdown, or a single kanji entry.
    func lookup(token: String) -> LookupResult {
        if token.count > 1, let word = wordEntry(surfaceForm: token) {
            return LookupResult(token: token, word: word, kanjiBreakdown: kanjiBreakdown(wordId: word.id))
        }
        if let kanji = kanjiEntry(character: token) {
            return LookupResult(token: token, word: nil, kanjiBreakdown: [kanji])
        }
        return LookupResult(token: token, word: nil, kanjiBreakdown: [])
    }
}
