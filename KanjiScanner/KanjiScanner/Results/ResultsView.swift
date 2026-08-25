import SwiftUI

/// Displays a lookup result: for a compound, the word first with its
/// constituent kanji broken out below (US-4, FR-14); for an isolated kanji,
/// just the character detail (US-3, FR-15); for a multi-kanji span that
/// isn't a recognized compound, a "no compound match" indicator plus each
/// kanji's own breakdown (US-4's fallback acceptance criterion) — mirroring
/// Yomitan's pop-up dictionary pattern. "Back" returns to the same captured
/// photo so the user can pick another detected region; "Scan Again" starts
/// a fresh capture (US-7, FR-16).
struct ResultsView: View {
    let result: LookupResult
    var onBack: () -> Void
    var onScanAgain: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                }
                Spacer()
            }
            .padding()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let word = result.word {
                        WordSection(word: word)
                        if !result.kanjiBreakdown.isEmpty {
                            KanjiBreakdownSection(entries: result.kanjiBreakdown)
                        }
                    } else if result.kanjiBreakdown.count == 1 {
                        KanjiDetailView(entry: result.kanjiBreakdown[0])
                    } else if result.kanjiBreakdown.count > 1 {
                        NoCompoundMatchView(token: result.token)
                        KanjiBreakdownSection(entries: result.kanjiBreakdown)
                    } else if !result.hasEntry {
                        NoMatchView(token: result.token)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            Button(action: onScanAgain) {
                Label("Scan Again", systemImage: "camera.viewfinder")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }
}

/// Shown in place of `WordSection` when a multi-kanji span was scanned but
/// no compound match was found for it in the dictionary — the constituent
/// kanji are still shown individually via `KanjiBreakdownSection` right
/// below this (US-4's "falls back to kanji-level results... with a clear
/// indicator" acceptance criterion).
private struct NoCompoundMatchView: View {
    let token: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(token)
                .font(.system(size: 48, weight: .bold))
            Label("No compound match found", systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// The compound word entry: reading and meanings at the top (US-4 AC). The
/// reading is shown as furigana directly above the surface form (US-18),
/// positioned per-character/per-run rather than as one line spanning the
/// whole word (US-25) whenever `word.furiganaSegments` has that alignment
/// data; otherwise it falls back to the whole-word furigana US-18 shipped
/// first, for the small fraction of words JmdictFurigana doesn't cover. A
/// katakana word (US-23) has no separate kanji writing — its surface form
/// *is* its reading — so real printed Japanese never glosses it with
/// furigana; showing the identical string as ruby text above itself would
/// just be visual noise, so that case skips furigana entirely.
private struct WordSection: View {
    let word: WordEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if word.surfaceForm == word.reading {
                Text(word.surfaceForm)
                    .font(.system(size: 48, weight: .bold))
            } else if let segments = word.furiganaSegments, !segments.isEmpty {
                SegmentedFuriganaText(segments: segments)
            } else {
                WholeWordFuriganaText(surfaceForm: word.surfaceForm, reading: word.reading)
            }
            GroupedMeaningsList(groups: word.senseGroups)
        }
    }
}

/// True per-character furigana (US-25): each run (one or more kanji sharing
/// a reading, or a bare kana run with none) gets its own small reading
/// positioned directly above just that run, the way real printed Japanese
/// and tools like Yomitan do — rather than one reading spanning the whole
/// word, which doesn't help a learner tell which reading belongs to which
/// character in a mixed kanji/kana compound.
///
/// `HStack(alignment: .bottom)` is enough to keep every run's base
/// characters sitting on the same visual line regardless of whether that
/// run has a reading above it: each run is its own `VStack` (furigana line
/// only present when that segment has one), and aligning the row by
/// `.bottom` lines up the base-character `Text` views' bottom edges across
/// runs of differing total height. No cross-segment width measurement
/// needed — deliberately avoiding the kind of measured/shared-layout
/// approach that repeatedly failed for the kanji breakdown rows (BUG-011).
private struct SegmentedFuriganaText: View {
    let segments: [FuriganaSegment]

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                VStack(spacing: 0) {
                    if let reading = segment.reading {
                        Text(reading)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(segment.text)
                        .font(.system(size: 48, weight: .bold))
                }
                .padding(.horizontal, 1)
            }
        }
    }
}

/// Fallback for the small fraction of words with no per-character alignment
/// data (US-25's coverage gap): the whole reading centered above the whole
/// surface form — the behavior US-18 originally shipped. A `VStack` with
/// `alignment: .center` is enough: since neither `Text` has a forced width,
/// the stack sizes itself to its widest child (the surface form) and
/// centers the other (the reading) over it.
private struct WholeWordFuriganaText: View {
    let surfaceForm: String
    let reading: String

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            Text(reading)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(surfaceForm)
                .font(.system(size: 48, weight: .bold))
        }
    }
}

/// Constituent kanji, visually subordinate to the word entry above (FR-14).
/// See `KanjiRow`'s doc comment for why its column alignment is a fixed
/// indent rather than a measured width.
private struct KanjiBreakdownSection: View {
    let entries: [KanjiEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kanji Breakdown")
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    KanjiRow(entry: entry)
                    if index < entries.count - 1 {
                        Divider()
                    }
                }
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

/// One row of the kanji breakdown. The character is drawn as an overlay at
/// a fixed inset, on top of a reading/meaning block that's itself given a
/// fixed leading indent — so its position can't be influenced by the
/// character's rendered width, the row's height, or any other row's content.
///
/// The indent is a hardcoded number, not a width measured from any sibling
/// view. Four earlier attempts measured instead: HStack top/center
/// alignment, an explicit `.frame(width:)` on the character, and two Grid
/// variants (a plain cell, then a fixed-size `Color` cell) — the last of
/// which used one `Grid` correctly scoped around the whole row list (not
/// one `Grid` per row), which should have guaranteed matching column widths
/// but still didn't hold up in on-device testing. Rather than keep
/// debugging why, this drops measurement from the equation entirely: a
/// literal `.padding(.leading, N)` cannot depend on any other view's
/// content, by construction.
///
/// `textLeadingIndent` (64) needs to clear `characterLeadingInset` (12) +
/// the widest character glyph at 36pt semibold (a single CJK character is
/// reliably under 44pt at this size/weight) + a small gap — the `frame`
/// below defensively caps the glyph's width to the remaining space so an
/// unexpectedly wide glyph gets clipped rather than overlapping the text.
private struct KanjiRow: View {
    let entry: KanjiEntry

    private static let characterLeadingInset: CGFloat = 12
    private static let textLeadingIndent: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ReadingsLine(onyomi: entry.onyomi, kunyomi: entry.kunyomi)
            Text(entry.meanings.joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .padding(.leading, Self.textLeadingIndent - 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Text(entry.character)
                .font(.system(size: 36, weight: .semibold))
                .lineLimit(1)
                .frame(
                    width: Self.textLeadingIndent - Self.characterLeadingInset,
                    alignment: .leading
                )
                .clipped()
                .padding(.leading, Self.characterLeadingInset)
        }
    }
}

/// Full-detail isolated-kanji display (US-3 AC): character, on'yomi in
/// katakana, kun'yomi in hiragana, and meanings.
struct KanjiDetailView: View {
    let entry: KanjiEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(entry.character)
                .font(.system(size: 96, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .center)

            ReadingsLine(onyomi: entry.onyomi, kunyomi: entry.kunyomi)
                .font(.title3)

            MeaningsList(meanings: entry.meanings)
        }
    }
}

private struct ReadingsLine: View {
    let onyomi: [String]
    let kunyomi: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !onyomi.isEmpty {
                Text("On'yomi: \(onyomi.joined(separator: "、"))")
            }
            if !kunyomi.isEmpty {
                Text("Kun'yomi: \(kunyomi.joined(separator: "、"))")
            }
        }
    }
}

private struct MeaningsList: View {
    let meanings: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(meanings.enumerated()), id: \.offset) { _, meaning in
                Text("• \(meaning)")
            }
        }
        .font(.body)
    }
}

/// Word meanings grouped by usage context (US-21) - Jisho.org-style, e.g.
/// 切る's core "to cut" senses separated from its "-切る" suffix senses,
/// instead of one long flat bullet per gloss. Every sense is numbered,
/// continuously across all groups starting at 1 - including a genuinely
/// single-sense word, which just shows "1." rather than an unlabeled
/// bullet, so numbering is never a signal of "this word has many senses."
/// A group's pos header is shown once per group (not repeated per sense,
/// unlike real Jisho) when non-empty - repeating it added no information
/// and worked against this story's main goal of a shorter results screen.
private struct GroupedMeaningsList: View {
    let groups: [SenseGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(groups.enumerated()), id: \.offset) { groupIndex, group in
                VStack(alignment: .leading, spacing: 4) {
                    if !group.pos.isEmpty {
                        Text(group.pos.map(PosDisplay.label).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(group.senses.enumerated()), id: \.offset) { senseIndex, sense in
                        Text("\(senseNumber(groupIndex: groupIndex, senseIndex: senseIndex)). \(sense.glosses.joined(separator: "; "))")
                    }
                }
            }
        }
        .font(.body)
    }

    private func senseNumber(groupIndex: Int, senseIndex: Int) -> Int {
        groups[..<groupIndex].reduce(0) { $0 + $1.senses.count } + senseIndex + 1
    }
}

/// Maps a raw JMdict pos tag to its display form (US-36). Default is just
/// capitalizing the tag's own first letter - JMdict's raw text is otherwise
/// already reasonably concise. A few tags get an explicit override instead:
/// verified against real Jisho.org entries that it does NOT blanket-strip a
/// tag's bracketed Japanese romaji term (it keeps "(fukushi)" for adverb,
/// "(keiyoushi)" for i-adjective, etc.) - the *only* tag it fully collapses
/// is the noun one, and it also drops that tag's "(common)" qualifier, not
/// just the romaji part. The two adjective-class tags get renamed to the
/// standard learner terms (I-adjective/Na-adjective) rather than JMdict's
/// generic "adjective"/"adjectival noun" wording, matching Jisho, but keep
/// their Japanese term. Every other tag (including adverb, interjection,
/// pre-noun adjectival, and JMdict's ~76 verb-conjugation-class tags) is
/// left as JMdict's own wording, sentence-cased only - not guessed at
/// beyond what was actually verified.
enum PosDisplay {
    private static let overrides: [String: String] = [
        "noun (common) (futsuumeishi)": "Noun",
        "adjective (keiyoushi)": "I-adjective (keiyoushi)",
        "adjective (keiyoushi) - yoi/ii class": "I-adjective (keiyoushi) - yoi/ii class",
        "adjectival nouns or quasi-adjectives (keiyodoshi)": "Na-adjective (keiyodoshi)",
    ]

    static func label(for tag: String) -> String {
        if let override = overrides[tag] {
            return override
        }
        guard let firstLetterIndex = tag.firstIndex(where: { $0.isLetter }) else { return tag }
        var result = tag
        result.replaceSubrange(firstLetterIndex...firstLetterIndex, with: tag[firstLetterIndex].uppercased())
        return result
    }
}
