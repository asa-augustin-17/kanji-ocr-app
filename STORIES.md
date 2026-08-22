# User Story Log

Tracks every user story driving Kanji Scanner — both the original PRD stories and enhancement requests that came up afterward. New stories go at the bottom of their section (numbering is chronological, not priority order). Cross-reference [BUGS.md](BUGS.md) for defects found while building/testing these.

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
| US-9 | Pinch-to-zoom on the captured photo | Implemented | User request | 2026-08-22 | v1 |
| US-8 | Return to the captured photo to select a different region | Implemented | User request | 2026-08-22 | v1 |

**US-8 — Return to the captured photo to select a different region.** As a learner, when a scan detects multiple words/kanji, I want to go back to the photo I just captured after viewing one result, so that I can look up the other regions without retaking the photo.
- A "Back" action on the results screen returns to the same captured photo with all its detected regions still tappable.
- Distinct from "Scan Again," which starts an entirely new capture.
- *Implemented as part of the same fix as BUG-002; pending re-confirmation on-device.*

**US-9 — Pinch-to-zoom on the captured photo.** As a learner, I want to pinch-zoom and pan around the captured photo before selecting a region, so that I can accurately tap small or tightly-packed kanji that the app doesn't let me manually crop.
- Pinch zooms in/out (1x–6x); drag pans once zoomed in.
- Zoom is anchored to wherever the user's fingers are, not always the view's center (see BUG-006 for the anchor-jump issue this required fixing).
- Detected regions' tap targets scale and pan in sync with the image.
- Pinching back to 1x resets pan.
- *Implemented and iteratively refined against live user feedback (initial center-anchored version → per-touch anchor → jump-free offset-based zoom). Awaiting confirmation of the latest fix.*
