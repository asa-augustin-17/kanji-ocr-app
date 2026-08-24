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

    /// True for ASCII digits 0-9 (US-31). Confirmed empirically — a small
    /// standalone Vision script run against this app's exact production OCR
    /// configuration (`recognitionLanguages: ["ja-JP"]`, `.accurate`,
    /// `usesLanguageCorrection: false`) — that a printed full-width digit
    /// (１２３...) is normalized to ASCII by OCR before this code ever sees
    /// it, while kanji numerals (一二三...) are left untouched. So only
    /// ASCII needs to be recognized here; a full-width digit reaching this
    /// code at all would indicate OCR behavior has changed.
    static func isDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
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
/// コーヒー -> 珈琲) still resolves to that richer entry. An Arabic-numeral
/// digit run followed by a counter (josūshi) is matched against the
/// equivalent kanji-numeral entry (US-31, e.g. "1匹" -> 一匹), since that's
/// almost always how JMdict actually stores these. Everything else
/// (hiragana, punctuation, romaji) is skipped entirely — only kanji/kanji-
/// compound, katakana-word, and numeral+counter regions are tap-to-lookup
/// (US-2).
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

            if JapaneseText.isDigit(text[index]) {
                if let match = numeralCounterMatch(in: text, from: index, database: database) {
                    tokens.append(match)
                    index = match.range.upperBound
                    continue
                }

                // US-31: no fallback "unmatched" token for a bare digit run,
                // unlike kanji/katakana — ordinary numbers (prices, page
                // numbers, phone numbers) are common in photographed text
                // and shouldn't become dead tap targets just because they
                // don't happen to precede a recognized counter.
                index = text.index(after: index)
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

    /// Converts a run of ASCII digits to its kanji-numeral equivalent, for
    /// matching against JMdict's kanji-numeral-form counter entries (US-31).
    /// Deliberately limited to 0-10: real counter+number dictionary entries
    /// are concentrated in that range (confirmed against the bundled data —
    /// every kanji-numeral-prefixed 2-character word starts with 一 through
    /// 十; nothing systematic beyond that for any given counter), so this
    /// covers the overwhelming majority of real matches without the added
    /// complexity of a general place-value converter (十/百/千 combination
    /// rules, the leading-一 omission rule, etc.).
    private static func smallKanjiNumeral(_ digits: String) -> String? {
        switch digits {
        case "0": return "〇"
        case "1": return "一"
        case "2": return "二"
        case "3": return "三"
        case "4": return "四"
        case "5": return "五"
        case "6": return "六"
        case "7": return "七"
        case "8": return "八"
        case "9": return "九"
        case "10": return "十"
        default: return nil
        }
    }

    /// Matches an Arabic-numeral digit run followed by a counter (josūshi)
    /// against the equivalent kanji-numeral dictionary entry (US-31) — e.g.
    /// "1匹" matches 一匹's entry, even though "1匹" itself is never the
    /// literal `surface_form` stored in the dictionary. The returned
    /// token's *range* covers the original digit+counter text (so the
    /// bounding box covers what was actually printed), but `result.word`/
    /// `kanjiBreakdown` come from the matched kanji-numeral entry — the
    /// same split `longestKatakanaMatch` (US-23) uses for a katakana
    /// loanword resolving to its legacy kanji entry: the range reflects
    /// reality, the content reflects the richer match.
    private static func numeralCounterMatch(
        in text: String,
        from start: String.Index,
        database: DictionaryDatabase
    ) -> SegmentToken? {
        var digitsEnd = start
        while digitsEnd < text.endIndex, JapaneseText.isDigit(text[digitsEnd]) {
            digitsEnd = text.index(after: digitsEnd)
        }
        guard let numeral = smallKanjiNumeral(String(text[start..<digitsEnd])) else { return nil }

        // Most counters are a single kanji; a small number are two - try
        // the longer candidate first.
        let remaining = text.distance(from: digitsEnd, to: text.endIndex)
        let maxCounterLength = min(2, remaining)
        guard maxCounterLength >= 1 else { return nil }

        for counterLength in stride(from: maxCounterLength, through: 1, by: -1) {
            let counterEnd = text.index(digitsEnd, offsetBy: counterLength)
            let counter = String(text[digitsEnd..<counterEnd])
            guard counter.allSatisfy(JapaneseText.isKanji) else { continue }
            if let word = database.wordEntry(surfaceForm: numeral + counter) {
                let result = LookupResult(
                    token: String(text[start..<counterEnd]),
                    word: word,
                    kanjiBreakdown: database.kanjiBreakdown(wordId: word.id)
                )
                return SegmentToken(range: start..<counterEnd, result: result)
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
    ///
    /// When the run turns out to be exactly one character (US-19), that
    /// character might *also* be a standalone word in its own right — many
    /// common kanji are (目/め "eye", 手/て "hand") — which
    /// `longestCompoundMatch` above never checks, since it only ever tries
    /// candidates of length 2 or more. This is the one place a length-1
    /// word lookup belongs: only for a truly isolated kanji, not for any
    /// individual kanji inside a longer unmatched run (those stay grouped
    /// together as a single fallback token, per US-4's acceptance
    /// criterion — this doesn't change that).
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
        let word = token.count == 1 ? database.wordEntry(surfaceForm: token) : nil
        let result = LookupResult(token: token, word: word, kanjiBreakdown: entries)
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
