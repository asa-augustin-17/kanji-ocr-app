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

    /// True for the full-width Katakana Unicode block (U+30A0-U+30FF, which
    /// includes the long vowel mark ー and word-separator ・) - matches the
    /// range `build_dictionary.py`'s `KATAKANA_RE` uses when importing
    /// kana-only JMdict entries as katakana words (US-23), so pipeline import
    /// and on-device segmentation agree on what counts as katakana.
    static func isKatakana(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
            return false
        }
        return (0x30A0...0x30FF).contains(scalar.value)
    }

    /// True for the two katakana-block characters that are punctuation/
    /// connectors rather than sound-bearing mora: U+30FB (・, the
    /// word-separator middle dot, e.g. コカ・コーラ) and U+30FC (ー, the
    /// long vowel mark, e.g. コーヒー). Both are legitimate *inside* a real
    /// katakana word, but meaningless standing alone as a "word" — OCR
    /// occasionally misreads a printed period as ・, which would otherwise
    /// become its own tappable "no dictionary entry found" region now that
    /// katakana runs are matched at all (US-23; see BUG-012).
    static func isKatakanaConnector(_ character: Character) -> Bool {
        character == "\u{30FB}" || character == "\u{30FC}"
    }
}

struct SegmentToken {
    let range: Range<String.Index>
    let result: LookupResult
}

/// Segments OCR'd text into lookup tokens, prioritizing the longest valid
/// dictionary compound starting at each kanji, falling back to single-kanji
/// lookup when no compound matches (FR-8, FR-9). Katakana runs are matched
/// the same way (US-23): first against a katakana-only entry (surface form
/// equal to its reading), then against a kanji-form entry whose *reading*
/// matches, so a loanword with a legacy kanji writing in JMdict (e.g.
/// コーヒー -> 珈琲) still resolves to that richer entry. Everything else
/// (hiragana, punctuation, romaji) is skipped entirely — only kanji/kanji-
/// compound and katakana-word regions are tap-to-lookup (US-2).
enum Segmenter {
    static let maxCompoundLength = 10

    static func segment(_ text: String, using database: DictionaryDatabase) -> [SegmentToken] {
        var tokens: [SegmentToken] = []
        var index = text.startIndex

        while index < text.endIndex {
            if JapaneseText.isKanji(text[index]) {
                if let match = longestCompoundMatch(in: text, from: index, database: database) {
                    tokens.append(match)
                    index = match.range.upperBound
                    continue
                }

                let run = unmatchedKanjiRun(in: text, from: index, database: database)
                tokens.append(run)
                index = run.range.upperBound
                continue
            }

            if JapaneseText.isKatakana(text[index]) {
                if let match = longestKatakanaMatch(in: text, from: index, database: database) {
                    tokens.append(match)
                    index = match.range.upperBound
                    continue
                }

                let run = unmatchedKatakanaRun(in: text, from: index, database: database)
                // BUG-012: a run made up entirely of ・/ー (no actual
                // katakana letters) isn't a word - skip it like any other
                // non-katakana punctuation, rather than making it tappable.
                if !run.result.token.allSatisfy(JapaneseText.isKatakanaConnector) {
                    tokens.append(run)
                }
                index = run.range.upperBound
                continue
            }

            index = text.index(after: index)
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

    /// Same longest-match-first search as `longestCompoundMatch`, but for a
    /// katakana run: tries an exact surface-form match first, then (US-23's
    /// kanji-fallback) a reading match against words with a distinct kanji
    /// surface form — so コーヒー, which has no katakana-only entry of its
    /// own, still resolves to 珈琲's entry instead of "no dictionary entry
    /// found". Surface-form match wins when both would match at the same
    /// length, since it's the more direct hit.
    private static func longestKatakanaMatch(
        in text: String,
        from start: String.Index,
        database: DictionaryDatabase
    ) -> SegmentToken? {
        let upperBound = maxMatchLength(in: text, from: start)
        guard upperBound >= 2 else { return nil }

        for length in stride(from: upperBound, through: 2, by: -1) {
            let end = text.index(start, offsetBy: length)
            let candidate = String(text[start..<end])
            if let word = database.wordEntry(surfaceForm: candidate) ?? database.wordEntry(reading: candidate) {
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

    /// A contiguous run of katakana starting at `start` with no dictionary
    /// match at any position within it (US-23) — mirrors `unmatchedKanjiRun`'s
    /// run-grouping so the whole run becomes one tappable "no dictionary
    /// entry found" region (US-6) instead of being silently skipped. Unlike
    /// kanji, there's no per-character breakdown to fall back to here —
    /// individual katakana characters aren't dictionary entries the way
    /// individual kanji are — so this always resolves to `hasEntry == false`.
    /// The caller (BUG-012) discards the result instead of appending it when
    /// the whole run turns out to be nothing but ・/ー connectors — this
    /// function itself doesn't know that policy, it just reports the range.
    ///
    /// Same early-stop behavior as `unmatchedKanjiRun`: the run stops as soon
    /// as a match would start at a later position, so a genuine word partway
    /// through an otherwise-unmatched run is still found on the next
    /// iteration of the outer loop.
    private static func unmatchedKatakanaRun(
        in text: String,
        from start: String.Index,
        database: DictionaryDatabase
    ) -> SegmentToken {
        var end = start

        while end < text.endIndex,
              JapaneseText.isKatakana(text[end]),
              text.distance(from: start, to: end) < maxCompoundLength,
              longestKatakanaMatch(in: text, from: end, database: database) == nil {
            end = text.index(after: end)
        }

        let token = String(text[start..<end])
        let result = LookupResult(token: token, word: nil, kanjiBreakdown: [])
        return SegmentToken(range: start..<end, result: result)
    }

    private static func maxMatchLength(in text: String, from start: String.Index) -> Int {
        min(maxCompoundLength, text.distance(from: start, to: text.endIndex))
    }
}
