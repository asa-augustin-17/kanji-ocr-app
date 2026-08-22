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

            let remaining = text.distance(from: index, to: text.endIndex)
            let upperBound = min(maxCompoundLength, remaining)

            if let match = longestCompoundMatch(in: text, from: index, upperBound: upperBound, database: database) {
                tokens.append(match)
                index = match.range.upperBound
                continue
            }

            let end = text.index(after: index)
            let candidate = String(text[index])
            let result = database.lookup(token: candidate)
            tokens.append(SegmentToken(range: index..<end, result: result))
            index = end
        }

        return tokens
    }

    private static func longestCompoundMatch(
        in text: String,
        from start: String.Index,
        upperBound: Int,
        database: DictionaryDatabase
    ) -> SegmentToken? {
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
}
