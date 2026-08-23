import SwiftUI

/// Displays a lookup result: for a compound, the word first with its
/// constituent kanji broken out below (US-4, FR-14); for an isolated kanji,
/// just the character detail (US-3, FR-15) — mirroring Yomitan's pop-up
/// dictionary pattern. "Back" returns to the same captured photo so the
/// user can pick another detected region; "Scan Again" starts a fresh
/// capture (US-7, FR-16).
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

/// The compound word entry: reading and meanings at the top (US-4 AC).
private struct WordSection: View {
    let word: WordEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(word.surfaceForm)
                .font(.system(size: 48, weight: .bold))
            Text(word.reading)
                .font(.title3)
                .foregroundStyle(.secondary)
            MeaningsList(meanings: word.meanings)
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
