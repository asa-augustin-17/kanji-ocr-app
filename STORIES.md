# User Story Log

Tracks every user story driving Kanji Scanner — both the original PRD stories and enhancement requests that came up afterward. New stories go at the top of their table (numbering is chronological, not priority order — tables sort newest-ID-first). Cross-reference [BUGS.md](BUGS.md) for defects found while building/testing these.

## Status values
- **Not Started**
- **Implemented** — code complete, built against the acceptance criteria below
- **Verified** — confirmed working on a physical device by the user
- **Closed** — implemented, but not receiving further iteration under this ID; either superseded by a follow-up story or intentionally settled as-is

## v1 closure review (2026-08-23)

Went through every v1-scoped story (US-1–US-11) and PRD functional requirement against the current code, updating statuses where extensive on-device use during the BUG-008/009/010/011 investigations effectively already verified something. Two real gaps surfaced; per the user's decision, gap 1 was fixed immediately (it also removes an edge case US-19 would otherwise have inherited) and gap 2 was explicitly parked until US-16/17's data-sourcing research:

1. **Fixed.** US-4's third bullet ("falls back to kanji-level results if no compound match is found") wasn't actually reachable — `Segmenter` only ever emitted a multi-kanji token when a compound match *was* found, silently splitting a non-dictionary compound into single-kanji lookups instead. `Segmenter` now groups a run of consecutive kanji that all fail compound-matching into one token, and `ResultsView` shows a new "no compound match found" indicator alongside the individual breakdown for that case — see US-4's notes below.
2. **Parked.** FR-13's schema requirement is only half met: it asked v1's schema to reserve columns for JLPT level, WaniKani-style level, and common-use/frequency flags so a *later* version could populate them without a migration. JLPT and frequency/common-use columns exist; a WaniKani-level column was never added to either table. Directly relevant to backlog items US-16/US-17, which will need it anyway — revisit alongside those.

Also worth a few quick explicit spot-checks before considering v1 fully signed off, since they haven't been directly observed yet even though the code looks correct: an isolated single-kanji result (every screenshot so far has been a multi-kanji compound), the low-confidence "couldn't confidently read this" state, the "no dictionary entry found" state, single-region auto-select, and an explicit airplane-mode check for US-5.

Per-story detail and status updates are below.

## From the original PRD (v1)

| ID | Story | Status | Version |
|----|---|---|---|
| US-1 | Capture a photo of printed Japanese text | Verified | v1 |
| US-2 | Select the specific text region to look up | Verified | v1 |
| US-3 | View dictionary results for an isolated kanji | Implemented | v1 |
| US-4 | View dictionary results for a kanji compound/word | Verified | v1 |
| US-5 | Use the app with no network connection | Implemented | v1 |
| US-6 | Handle unrecognized or low-confidence scans gracefully | Implemented | v1 |
| US-7 | Retain the option to re-scan quickly | Verified | v1 |

**US-1 — Capture a photo of printed Japanese text.** As a learner, I want to open the app and immediately point my camera at text, so that I can capture kanji with minimal steps.
- App opens directly to a live camera viewfinder — no landing page, no login.
- Tap-to-capture; camera permission requested on first launch with a clear explanation.
- Denied permission shows a clear message directing the user to Settings.
- *Verified on-device: capture works, image comes out upright and cropped to match the viewfinder (see BUG-001, BUG-003, BUG-004).*

**US-2 — Select the specific text region to look up.** As a learner, I want to select the specific kanji/word I'm interested in, so that I get an accurate, targeted lookup even if other text is in frame.
- After capture, bounding boxes overlay all detected text regions — no manual cropping step.
- Tapping a region selects it for lookup; a single detected region auto-selects.
- User can retake the photo if no usable text was detected.
- *Verified on-device: tap-to-select has been exercised repeatedly and reliably across many real scans during the BUG-008/009/011 investigations (e.g. 読書感想文, 事故, 栃木県, 仕事). The specific "only one region detected → auto-selects without a tap" path hasn't been explicitly observed, though the code path is unconditional and simple — worth one quick spot-check with an image containing exactly one kanji region.*

**US-3 — View dictionary results for an isolated kanji.** As a learner, I want to see the reading(s) and meaning(s) of a single kanji I've scanned, so that I understand what it means and how to say it.
- Results show the character, on'yomi (katakana), kun'yomi (hiragana), and English meaning(s).
- Multiple meanings all shown.
- Results render within 2 seconds, fully offline.
- *Implemented (`KanjiDetailView`), and its layout building blocks (character/readings/meanings rendering) are the same ones proven working in every compound-breakdown screenshot — but the specific top-level "tapped a standalone kanji that isn't part of any recognized compound" screen hasn't actually been seen on-device yet; every screenshot so far has been a multi-kanji compound. Worth one explicit spot-check on an isolated kanji.*

**US-4 — View dictionary results for a kanji compound/word.** As a learner, I want to see the compound word's reading and meaning first, with each constituent kanji broken out below it, so that I understand both the word as a whole and its building blocks (Yomitan-style).
- Compound word, reading, and meaning(s) shown at the top.
- Each constituent kanji listed below with its own readings/meanings.
- Falls back to kanji-level-only results (with a clear indicator) if no compound match is found.
- *Verified on-device for the first two bullets (読書感想文, 事故, 栃木県, 仕事 all confirmed rendering correctly through the BUG-011 alignment work). Third bullet's gap **fixed**: `Segmenter` now groups a run of consecutive kanji that all fail compound-matching into one token (instead of silently fragmenting into separate single-kanji tokens), and `ResultsView` has a new `NoCompoundMatchView` state for `word == nil && kanjiBreakdown.count > 1` showing the "no compound match found" indicator plus every kanji's breakdown. The run-grouping still correctly detects a real compound starting partway through (e.g. "犬日本" still finds "日本"), covered by new unit tests. Gap #2 (FR-13's WaniKani schema column) explicitly parked — will be picked up alongside US-16/17's data-sourcing research. User-confirmed on-device.*

**US-5 — Use the app with no network connection.** As a learner, I want the app to work exactly the same on a subway with no signal or in airplane mode as it does with full connectivity, so that I never lose functionality when I need it most.
- OCR, segmentation, and dictionary lookup all run fully on-device; no network code exists in the app.
- *Structurally guaranteed (there is no networking code anywhere in the app to fail), but never explicitly exercised with an actual airplane-mode test on-device. Worth a quick explicit check before calling v1 fully done, even though it's very low-risk.*

**US-6 — Handle unrecognized or low-confidence scans gracefully.** As a learner, I want clear feedback when the app can't confidently identify text, so that I know to retake the photo rather than getting a wrong answer.
- Below-threshold OCR confidence shows "couldn't confidently read this — try retaking the photo" instead of a guessed result.
- Recognized-but-not-in-dictionary text clearly states "no dictionary entry found."
- *Implemented (`lowConfidenceState` in `ScanOverlayView`, `NoMatchView` in results), but neither state has been explicitly seen on-device yet — no screenshot so far has shown either. Note: a photo with text that OCR reads confidently but contains zero kanji (pure kana/romaji) currently also lands on the "couldn't confidently read this" message, since no tappable regions get built for it — the wording is a bit of a mismatch for that specific case (it wasn't a confidence problem), though the suggested action (retake) is still reasonable. Not a blocker, just a minor phrasing note.*

**US-7 — Retain the option to re-scan quickly.** As a learner, I want to return to the camera quickly after viewing a result, so that I can look up the next unfamiliar kanji without extra taps.
- A single, obvious "Scan Again" action returns to the live camera view.
- No re-granting permissions or reloading the app.
- *Verified on-device: confirmed fast/responsive after fixing BUG-005 (previously ~5s delay).*

## Enhancement requests delivered in v1

| ID | Story | Status | Source | Date Added | Version |
|----|---|---|---|---|---|
| US-11 | Setting to toggle resume-zoom-on-back behavior on/off | Not Started | User request | 2026-08-23 | v1 |
| US-10 | Resume the same zoom/pan level when backing out of a result | Verified | User request | 2026-08-23 | v1 |
| US-9 | Pinch-to-zoom on the captured photo | Verified | User request | 2026-08-22 | v1 |
| US-8 | Return to the captured photo to select a different region | Verified | User request | 2026-08-22 | v1 |

**US-8 — Return to the captured photo to select a different region.** As a learner, when a scan detects multiple words/kanji, I want to go back to the photo I just captured after viewing one result, so that I can look up the other regions without retaking the photo.
- A "Back" action on the results screen returns to the same captured photo with all its detected regions still tappable.
- Distinct from "Scan Again," which starts an entirely new capture.
- *Verified on-device: used repeatedly and reliably throughout the BUG-011 alignment investigation to navigate back and re-select different kanji within the same photo.*

**US-9 — Pinch-to-zoom on the captured photo.** As a learner, I want to pinch-zoom and pan around the captured photo before selecting a region, so that I can accurately tap small or tightly-packed kanji that the app doesn't let me manually crop.
- Pinch zooms in/out (1x–6x); drag pans once zoomed in.
- Zoom is anchored to wherever the user's fingers are, not always the view's center (see BUG-006 for the anchor-jump issue this required fixing).
- Detected regions' tap targets scale and pan in sync with the image.
- Pinching back to 1x resets pan.
- *Verified on-device: core zoom/pan/tap-target behavior confirmed working across many rounds of testing. One known, deliberately deferred limitation remains — see [BUG-010](BUGS.md)/US-14 — where zooming out while panned toward an edge has a brief "kink" in motion; doesn't block the core feature being verified.*

**US-10 — Resume the same zoom/pan level when backing out of a result.** As a learner, after tapping a word/kanji and viewing its results, I want the photo to still be zoomed to where I left it when I hit "Back," so that I can quickly tap another nearby word without having to re-find and re-zoom to the same spot — since the next word I want is often right next to the one I just looked up.
- Zoom scale and pan position from the scan overlay are preserved across a Results → Back → overlay round trip.
- A genuinely new capture (via "Retake" or "Scan Again" leading to a new photo) starts fresh at 1x, unzoomed — the resumed state only applies to revisiting the *same* captured photo.
- No user-facing setting for this yet — it's the only behavior; making it optional is tracked separately as US-11.
- *Implemented by lifting the zoom/pan state out of `ScanOverlayView` into `RootView`, so it survives the view being recreated on Back navigation, instead of resetting to defaults each time. User-confirmed on-device.*

**US-11 — Setting to toggle resume-zoom-on-back behavior on/off.** As a learner, I want to be able to turn off the "resume zoom on back" behavior (US-10) if I don't like it, so that I can get the old always-reset-to-1x behavior back instead.
- Explicitly out of scope for the initial US-10 implementation — logged separately since it's a distinct piece of work (a settings surface, a persisted preference, and branching behavior based on it) rather than part of the core feature.
- The app currently has no settings/preferences screen at all (PRD explicitly excludes one from v1 — see PRD §4.7/§6), so this would also be the first thing to require one.
- *Not started.*

## Backlog (post-v1)

Requested by the user on 2026-08-23 but explicitly scoped as future work, not part of v1 — logged for planning purposes only, nothing here is implemented or scheduled to a specific version yet.

| ID | Story | Status | Source | Date Added | Version |
|----|---|---|---|---|---|
| US-26 | Tune per-character furigana sizing/legibility | Not Started | User request | 2026-08-23 | Backlog |
| US-25 | Per-character furigana for compound words (supersedes US-18) | Closed | User request | 2026-08-23 | Backlog |
| US-24 | Expand vocab matching to names of people and organizations | Not Started | User request | 2026-08-23 | Backlog |
| US-23 | Expand vocab matching to katakana words | Not Started | User request | 2026-08-23 | Backlog |
| US-22 | Tap a kanji breakdown entry for a detail page with more tags | Not Started | User request | 2026-08-23 | Backlog |
| US-21 | Group similar/related dictionary senses instead of one long list | Not Started | User request | 2026-08-23 | Backlog |
| US-20 | Show vocab tags (part of speech, common, JLPT, WaniKani) in results | Not Started | User request | 2026-08-23 | Backlog |
| US-19 | Treat a single detected character as a vocab term, not just a kanji | Not Started | User request | 2026-08-23 | Backlog |
| US-18 | Display vocab furigana above the characters, not below | Closed | User request | 2026-08-23 | Backlog |
| US-17 | Add WaniKani level and JLPT level to the words table | Not Started | User request | 2026-08-23 | Backlog |
| US-16 | Add WaniKani level and Jōyō status to the kanji table | Not Started | User request | 2026-08-23 | Backlog |
| US-15 | Smooth, decaying scroll deceleration on the captured photo | Not Started | User request | 2026-08-23 | Backlog |
| US-14 | Fix the scan-overlay zoom-out "kink" (see BUG-010) | Not Started | User request | 2026-08-23 | Backlog |
| US-13 | Tap to focus the camera before capturing | Not Started | User request | 2026-08-23 | Backlog |
| US-12 | Pinch-to-zoom the live camera before capturing | Not Started | User request | 2026-08-23 | Backlog |

### Camera

**US-12 — Pinch-to-zoom the live camera before capturing.** As a learner, I want to zoom in on the live camera view before I tap capture, so that I can focus on small text (e.g. a single line on a crowded sign) without having to get physically closer or rely entirely on post-capture zoom.
- Distinct from US-9 (zooming the *captured photo* after the fact) — this is zooming the *live viewfinder*, changing what's actually captured.
- *Not started.*

**US-13 — Tap to focus the camera before capturing.** As a learner, I want to tap on the live camera view to focus on a specific spot, so that blurry or off-focus text becomes sharp before I capture it, improving OCR accuracy.
- *Not started.*

### Captured Picture

**US-14 — Fix the scan-overlay zoom-out "kink" (see BUG-010).** As a learner, I want zooming out on the captured photo to feel like one smooth motion, so that the interaction feels polished rather than glitchy.
- Same underlying issue as [BUG-010](BUGS.md) (deferred after multiple failed fix attempts) — logged here as a story too per the user's request, since it's a piece of desired product behavior, not just a defect to patch.
- *Not started.*

**US-15 — Smooth, decaying scroll deceleration on the captured photo.** As a learner, I want panning around the zoomed-in photo to slow down gradually after I lift my finger (like the Photos app), instead of stopping dead the instant I release, so that panning around a large zoomed-in image feels natural rather than abrupt.
- Currently panning has no momentum at all — motion stops exactly when the touch ends.
- Distinct from US-14/BUG-010: this is about adding inertia/momentum to panning, not about the zoom-out kink.
- *Not started.*

### Databases

**US-16 — Add WaniKani level and Jōyō status to the kanji table.** As a learner, I want to (eventually) see a kanji's WaniKani level and whether it's a Jōyō (standard-use) kanji, so that I can gauge how commonly-taught/important a character is.
- `is_joyo` may not need new source data: KANJIDIC2's existing `grade` field (already in the schema) encodes this — grades 1–8 are Jōyō kanji (taught in grades 1–6, plus remaining secondary-school Jōyō), grade 9/10 is Jinmeiyō (name-use only), and no grade means neither — so `is_joyo` could likely be derived from `grade` rather than sourced externally.
- WaniKani level is *not* part of KANJIDIC2 and has no official public dataset from WaniKani itself — sourcing it would need either a community-maintained mapping or manual curation. Flagged by the user as "if this data is available" — needs research before implementation.
- Per FR-13, the schema is already designed to accept fields like this without a breaking migration.
- *Not started.*

**US-17 — Add WaniKani level and JLPT level to the words table.** As a learner, I want to (eventually) see a vocab word's WaniKani level and JLPT level, so that I can gauge how commonly-taught the word is, the same way I could for individual kanji.
- JMdict does not carry current JLPT-level tags for words (the old tagging was deprecated); a JLPT word list would need to come from a separate, community-maintained source. Same "if available" caveat as US-16 applies, doubly so here.
- *Not started.*

### Dictionary

**US-18 — Display vocab furigana above the characters, not below.** As a learner, I want the reading of a compound word shown as furigana directly above its kanji (as it appears in real printed Japanese), so that the results screen reads the way native materials actually present readings, rather than as a separate line underneath.
- Currently the word's reading is shown as a full separate line below the surface form (`WordSection` in `ResultsView.swift`), not per-character ruby-style furigana above each kanji.
- *Closed.* Implemented first as whole-word furigana (the reading centered above the entire surface form, since JMdict only provides one reading per word with no per-kanji alignment data). On review, the user determined this wasn't sufficient for mixed kanji/kana compounds (e.g. 生み心地) — a single reading spanning multiple characters doesn't help a learner tell which reading belongs to which kanji. Superseded by **US-25**, which solves the actual per-character alignment problem; closing this story rather than continuing to iterate under it. The whole-word rendering built here (`WholeWordFuriganaText` in `ResultsView.swift`) survives as US-25's fallback for words outside its data source's coverage.

**US-25 — Per-character furigana for compound words (supersedes US-18).** As a learner, when I look up a compound word that mixes kanji and kana (e.g. 生み心地), I want the furigana reading split and positioned over each individual kanji (or kanji run), the way real printed Japanese and tools like Yomitan do, so that I can tell which reading belongs to which character and actually learn the word instead of just seeing one undifferentiated reading string above it.
- JMdict itself has no per-kanji reading alignment data, so this required a new external data source: [JmdictFurigana](https://github.com/Doublevil/JmdictFurigana) (CC BY-SA, same license family as JMdict/KANJIDIC2), bundled into `data-pipeline/build_dictionary.py` and joined to `words` by `(surface_form, reading)` into a new `furigana_segments` column. Covers 221,811 of 230,958 words in the bundled dictionary (96%); the remaining ~4% fall back to US-18's whole-word furigana.
- Rendered via a new `SegmentedFuriganaText` view in `ResultsView.swift`: a plain SwiftUI `HStack(alignment: .bottom)` of per-run mini-`VStack`s (small reading above + big characters below, or just the bare characters for a run that's already kana), rather than CoreText's `CTRubyAnnotation` — deliberately kept to plain SwiftUI, consistent with this codebase's preference for simple explicit layout over clever/measured layout (see BUG-011's saga in BUGS.md).
- Correctly groups jukujikun (irregular readings spanning multiple kanji as one indivisible unit, e.g. 大人 → おとな within 大人買い) as a single run rather than forcing one kanji per segment, matching how the source data itself segments these.
- *Closed.* User-confirmed on-device ("This is a pass"). Follow-up sizing/legibility tuning (the reading font was bumped once already, `.caption2` → `.caption`, per user feedback that jukujikun readings looked too small) is tracked separately as **US-26** rather than continuing under this ID.

**US-26 — Tune per-character furigana sizing/legibility.** As a learner, after getting true per-character furigana (US-25), I want its size/legibility kept tunable and refined further, so that readings stay comfortably legible across different words and screen sizes rather than settling permanently on whatever size shipped first.
- Direct follow-up to US-25: the reading font was already bumped once this session (`Font.caption2` → `Font.caption` in `SegmentedFuriganaText`, `ResultsView.swift`) after the user found jukujikun readings (e.g. おとな over 大人) too small at the original size — this story tracks continuing that tuning.
- *Not started.*

**US-19 — Treat a single detected character as a vocab term, not just a kanji.** As a learner, when I tap a single kanji that's also a standalone valid word (many single kanji are), I want to see the vocab-term layout (word meaning/reading at top, kanji breakdown below it) — the same hierarchy multi-kanji compounds already get — rather than only the plain kanji detail view.
- Today, per FR-15/US-3, a single-kanji selection always shows the isolated-kanji detail view (`KanjiDetailView`) — it never checks whether that single character is *also* a `words` table entry in its own right.
- New behavior: default to showing the word entry (if the single character matches one) at the top, with its one-kanji breakdown below — mirroring the exact layout `WordSection` + `KanjiBreakdownSection` already use for 2+ kanji compounds.
- *Not started.*

**US-20 — Show vocab tags (part of speech, common, JLPT, WaniKani) in results.** As a learner, I want to see a word's part of speech, whether it's a common word, and (once available) its JLPT/WaniKani level directly on the results screen, so that I get more context about the word without leaving the app.
- `part_of_speech` and `is_common` already exist in the `words` schema (populated from JMdict) but per FR-13 are deliberately not surfaced in the v1 UI — this story is exactly the "later version" FR-13 anticipated.
- JLPT/WaniKani display depends on US-17 actually having that data available.
- *Not started.*

**US-21 — Group similar/related dictionary senses instead of one long list.** As a learner, I want related meanings for a word or kanji grouped together (the way Jisho.org visually clusters related senses), instead of a single flat bulleted list, so that I can more quickly tell which meanings are closely related versus genuinely distinct usages.
- Would likely require re-examining how `meanings` are stored/parsed from JMdict's `<sense>` groupings (currently flattened into one JSON array per entry in `build_dictionary.py`) to preserve sense-group boundaries.
- *Not started.*

**US-22 — Tap a kanji breakdown entry for a detail page with more tags.** As a learner, I want to tap on one of the kanji rows in a compound's breakdown and open a dedicated, more detailed page for that character — including tags like Jōyō status, frequency rank, JLPT level, and WaniKani level — so that I can dig deeper into one specific kanji without that detail cluttering the compact breakdown row.
- `frequency_rank` and `jlpt_level` already exist in the `kanji` schema (populated from KANJIDIC2) but aren't surfaced anywhere in the UI yet.
- Depends on US-16 for Jōyō/WaniKani fields existing at all.
- *Not started.*

**US-23 — Expand vocab matching to katakana words.** As a learner, I want katakana words (loanwords, onomatopoeia, etc.) to be recognized and looked up too, not just kanji and kanji compounds, so that I don't hit a dead end scanning text that's partly or fully katakana.
- Current segmentation (`Segmenter.swift`) and dictionary import (`build_dictionary.py`'s kanji-only filter) are deliberately scoped to kanji/kanji-compounds only, per the PRD's v1 non-goals — this is an explicit expansion beyond that original scope.
- *Not started.*

**US-24 — Expand vocab matching to names of people and organizations.** As a learner, I want proper nouns (people's names, company/organization names) to resolve to a dictionary entry when possible, instead of always hitting "no dictionary entry found," so that I'm not stuck on names I encounter while reading.
- JMdict itself excludes most proper nouns; this would likely need EDRDG's separate `ENAMDICT`/`JMnedict` name dictionary as an additional data source in the build pipeline.
- *Not started.*
