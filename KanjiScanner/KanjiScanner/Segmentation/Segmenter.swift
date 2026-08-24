import Foundation

enum JapaneseText {
    /// True for CJK Unified Ideographs (common + extension A) and the
    /// CJK Compatibility Ideographs block — i.e. "looks like a kanji".
    static func isKanji(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
            return false
        }
        switch scalar.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }
}

struct SegmentToken {
    let range: Range<String.Index>
    let result: LookupResult
}

/// Segments OCR'd text into lookup tokens, prioritizing the longest valid
/// dictionary compound starting at each kanji, falling back to single-kanji
/// lookup when no compound matches (FR-8, FR-9). Non-kanji characters (kana,
/// punctuation, romaji) are skipped entirely — v1 only surfaces kanji and
/// kanji-compound regions for tap-to-lookup (US-2).
enum Segmenter {
    static let maxCompoundLength = 10

    static func segment(_ text: String, using database: DictionaryDatabase) -> [SegmentToken] {
        var tokens: [SegmentToken] = []
        var index = text.startIndex

        while index < text.endIndex {
            guard JapaneseText.isKanji(text[index]) else {
                index = text.index(after: index)
                continue
            }

            if let match = longestCompoundMatch(in: text, from: index, database: database) {
                tokens.append(match)
                index = match.range.upperBound
                continue
            }

            let run = unmatchedKanjiRun(in: text, from: index, database: database)
            tokens.append(run)
            index = run.range.upperBound
        }

        return tokens
    }

    private static func longestCompoundMatch(
        in text: String,
        from start: String.Index,
        database: DictionaryDatabase
    ) -> SegmentToken? {
        let upperBound = maxMatchLength(in: text, from: start)
        guard upperBound >= 2 else { return nil }

        for length in stride(from: upperBound, through: 2, by: -1) {
            let end = text.index(start, offsetBy: length)
            let candidate = String(text[start..<end])
            if let word = database.wordEntry(surfaceForm: candidate) {
                let result = LookupResult(
                    token: candidate,
                    word: word,
                    kanjiBreakdown: database.kanjiBreakdown(wordId: word.id)
                )
                return SegmentToken(range: start..<end, result: result)
            }
        }
        return nil
    }

    /// A contiguous run of kanji starting at `start`, none of which begins a
    /// valid compound — i.e. every position in the run already failed (or
    /// would fail) `longestCompoundMatch` by the time it's included. Grouping
    /// these into one token — instead of fragmenting each into its own
    /// separate, unlabeled single-kanji region — lets the results screen show
    /// "no compound match found" alongside every kanji's own breakdown
    /// together (US-4's fallback acceptance criterion, previously
    /// unreachable since segmentation never produced a multi-kanji token
    /// without a word match).
    ///
    /// The run still stops as soon as a compound would match starting at a
    /// later kanji, so a genuine compound partway through an otherwise
    /// non-dictionary run (e.g. "犬日本" where "日本" matches) is still
    /// found correctly on the next iteration of the outer loop.
    private static func unmatchedKanjiRun(
        in text: String,
        from start: String.Index,
        database: DictionaryDatabase
    ) -> SegmentToken {
        var end = start
        var entries: [KanjiEntry] = []

        while end < text.endIndex,
              JapaneseText.isKanji(text[end]),
              text.distance(from: start, to: end) < maxCompoundLength,
              longestCompoundMatch(in: text, from: end, database: database) == nil {
            if let entry = database.kanjiEntry(character: String(text[end])) {
                entries.append(entry)
            }
            end = text.index(after: end)
        }

        let token = String(text[start..<end])
        let result = LookupResult(token: token, word: nil, kanjiBreakdown: entries)
        return SegmentToken(range: start..<end, result: result)
    }

    private static func maxMatchLength(in text: String, from start: String.Index) -> Int {
        min(maxCompoundLength, text.distance(from: start, to: text.endIndex))
    }
}
