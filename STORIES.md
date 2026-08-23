# User Story Log

Tracks every user story driving Kanji Scanner — both the original PRD stories and enhancement requests that came up afterward. New stories go at the top of the enhancement-requests table (numbering is chronological, not priority order — the table sorts newest-ID-first). Cross-reference [BUGS.md](BUGS.md) for defects found while building/testing these.

## Status values
- **Not Started**
- **Implemented** — code complete, built against the acceptance criteria below
- **Verified** — confirmed working on a physical device by the user

## From the original PRD (v1)

| ID | Story | Status | Version |
|----|---|---|---|
| US-1 | Capture a photo of printed Japanese text | Verified | v1 |
| US-2 | Select the specific text region to look up | Implemented | v1 |
| US-3 | View dictionary results for an isolated kanji | Implemented | v1 |
| US-4 | View dictionary results for a kanji compound/word | Implemented | v1 |
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
- *Implemented; end-to-end verification with real printed text against the dictionary is still pending.*

**US-3 — View dictionary results for an isolated kanji.** As a learner, I want to see the reading(s) and meaning(s) of a single kanji I've scanned, so that I understand what it means and how to say it.
- Results show the character, on'yomi (katakana), kun'yomi (hiragana), and English meaning(s).
- Multiple meanings all shown.
- Results render within 2 seconds, fully offline.

**US-4 — View dictionary results for a kanji compound/word.** As a learner, I want to see the compound word's reading and meaning first, with each constituent kanji broken out below it, so that I understand both the word as a whole and its building blocks (Yomitan-style).
- Compound word, reading, and meaning(s) shown at the top.
- Each constituent kanji listed below with its own readings/meanings.
- Falls back to kanji-level-only results (with a clear indicator) if no compound match is found.

**US-5 — Use the app with no network connection.** As a learner, I want the app to work exactly the same on a subway with no signal or in airplane mode as it does with full connectivity, so that I never lose functionality when I need it most.
- OCR, segmentation, and dictionary lookup all run fully on-device; no network code exists in the app.

**US-6 — Handle unrecognized or low-confidence scans gracefully.** As a learner, I want clear feedback when the app can't confidently identify text, so that I know to retake the photo rather than getting a wrong answer.
- Below-threshold OCR confidence shows "couldn't confidently read this — try retaking the photo" instead of a guessed result.
- Recognized-but-not-in-dictionary text clearly states "no dictionary entry found."

**US-7 — Retain the option to re-scan quickly.** As a learner, I want to return to the camera quickly after viewing a result, so that I can look up the next unfamiliar kanji without extra taps.
- A single, obvious "Scan Again" action returns to the live camera view.
- No re-granting permissions or reloading the app.
- *Verified on-device: confirmed fast/responsive after fixing BUG-005 (previously ~5s delay).*

## Enhancement requests (post-v1 build)

| ID | Story | Status | Source | Date Added | Version |
|----|---|---|---|---|---|
| US-24 | Expand vocab matching to names of people and organizations | Not Started | User request | 2026-08-23 | v1 |
| US-23 | Expand vocab matching to katakana words | Not Started | User request | 2026-08-23 | v1 |
| US-22 | Tap a kanji breakdown entry for a detail page with more tags | Not Started | User request | 2026-08-23 | v1 |
| US-21 | Group similar/related dictionary senses instead of one long list | Not Started | User request | 2026-08-23 | v1 |
| US-20 | Show vocab tags (part of speech, common, JLPT, WaniKani) in results | Not Started | User request | 2026-08-23 | v1 |
| US-19 | Treat a single detected character as a vocab term, not just a kanji | Not Started | User request | 2026-08-23 | v1 |
| US-18 | Display vocab furigana above the characters, not below | Not Started | User request | 2026-08-23 | v1 |
| US-17 | Add WaniKani level and JLPT level to the words table | Not Started | User request | 2026-08-23 | v1 |
| US-16 | Add WaniKani level and Jōyō status to the kanji table | Not Started | User request | 2026-08-23 | v1 |
| US-15 | Smooth, decaying scroll deceleration on the captured photo | Not Started | User request | 2026-08-23 | v1 |
| US-14 | Fix the scan-overlay zoom-out "kink" (see BUG-010) | Not Started | User request | 2026-08-23 | v1 |
| US-13 | Tap to focus the camera before capturing | Not Started | User request | 2026-08-23 | v1 |
| US-12 | Pinch-to-zoom the live camera before capturing | Not Started | User request | 2026-08-23 | v1 |
| US-11 | Setting to toggle resume-zoom-on-back behavior on/off | Not Started | User request | 2026-08-23 | v1 |
| US-10 | Resume the same zoom/pan level when backing out of a result | Verified | User request | 2026-08-23 | v1 |
| US-9 | Pinch-to-zoom on the captured photo | Implemented | User request | 2026-08-22 | v1 |
| US-8 | Return to the captured photo to select a different region | Implemented | User request | 2026-08-22 | v1 |

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

**US-8 — Return to the captured photo to select a different region.** As a learner, when a scan detects multiple words/kanji, I want to go back to the photo I just captured after viewing one result, so that I can look up the other regions without retaking the photo.
- A "Back" action on the results screen returns to the same captured photo with all its detected regions still tappable.
- Distinct from "Scan Again," which starts an entirely new capture.
- *Implemented as part of the same fix as BUG-002; pending re-confirmation on-device.*

**US-11 — Setting to toggle resume-zoom-on-back behavior on/off.** As a learner, I want to be able to turn off the "resume zoom on back" behavior (US-10) if I don't like it, so that I can get the old always-reset-to-1x behavior back instead.
- Explicitly out of scope for the initial US-10 implementation — logged separately since it's a distinct piece of work (a settings surface, a persisted preference, and branching behavior based on it) rather than part of the core feature.
- The app currently has no settings/preferences screen at all (PRD explicitly excludes one from v1 — see PRD §4.7/§6), so this would also be the first thing to require one.
- *Not started.*

**US-10 — Resume the same zoom/pan level when backing out of a result.** As a learner, after tapping a word/kanji and viewing its results, I want the photo to still be zoomed to where I left it when I hit "Back," so that I can quickly tap another nearby word without having to re-find and re-zoom to the same spot — since the next word I want is often right next to the one I just looked up.
- Zoom scale and pan position from the scan overlay are preserved across a Results → Back → overlay round trip.
- A genuinely new capture (via "Retake" or "Scan Again" leading to a new photo) starts fresh at 1x, unzoomed — the resumed state only applies to revisiting the *same* captured photo.
- No user-facing setting for this yet — it's the only behavior; making it optional is tracked separately as US-11.
- *Implemented by lifting the zoom/pan state out of `ScanOverlayView` into `RootView`, so it survives the view being recreated on Back navigation, instead of resetting to defaults each time. User-confirmed on-device.*

**US-9 — Pinch-to-zoom on the captured photo.** As a learner, I want to pinch-zoom and pan around the captured photo before selecting a region, so that I can accurately tap small or tightly-packed kanji that the app doesn't let me manually crop.
- Pinch zooms in/out (1x–6x); drag pans once zoomed in.
- Zoom is anchored to wherever the user's fingers are, not always the view's center (see BUG-006 for the anchor-jump issue this required fixing).
- Detected regions' tap targets scale and pan in sync with the image.
- Pinching back to 1x resets pan.
- *Implemented and iteratively refined against live user feedback (initial center-anchored version → per-touch anchor → jump-free offset-based zoom). Awaiting confirmation of the latest fix.*
