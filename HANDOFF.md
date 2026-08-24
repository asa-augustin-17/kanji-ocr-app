# Session Handoff

Written at the end of a long session (2026-08-22/23) to orient the next one. For full detail, [BUGS.md](BUGS.md) and [STORIES.md](STORIES.md) are the living logs — this file is just the high-signal context that doesn't live neatly in either: current state, why things are built the way they are, and what's next.

## Current state

v1 is functionally complete and closed (see STORIES.md's "v1 closure review" section). App builds, runs on a physical iPhone, and the full scan → select → results flow works end-to-end with real printed Japanese text. Last commit: `0f7edbe`. Repo: [github.com/asa-augustin-17/kanji-ocr-app](https://github.com/asa-augustin-17/kanji-ocr-app), single `main` branch, no PR workflow — we commit and push directly.

Open items, in rough priority order:
- **US-11** (settings toggle for resume-zoom-on-back) — logged, not started.
- **BUG-010** (scan-overlay zoom-out "kink") — deferred after multiple failed fix attempts (see BUGS.md for the full saga). Known, accepted limitation.
- **FR-13 gap #2** (WaniKani-level schema column never added) — parked, pick up alongside US-16/17.
- **US-12–US-24**, the full post-v1 backlog — nothing started. US-19 (single kanji as vocab term) was specifically flagged by the user as a good next target, since the just-fixed US-4 grouping behavior was partly motivated by an edge case US-19 will introduce.
- A handful of v1 states were never explicitly *observed* on-device despite the code looking correct (flagged in STORIES.md's closure review): isolated single-kanji result screen, the low-confidence retake message, the no-dictionary-entry message, single-region auto-select, and an explicit airplane-mode check.

## Architecture decisions worth knowing before touching code

**Project setup.** `KanjiScanner/project.yml` is the source of truth (XcodeGen). Never hand-edit `.xcodeproj` — run `xcodegen generate` after changing `project.yml` or adding/removing source files it doesn't glob automatically. GRDB.swift (SPM) is the SQLite layer.

**Dictionary data.** `data-pipeline/build_dictionary.py` builds `kanji_scanner.sqlite` (~53MB) from KANJIDIC2 + JMdict XML (EDRDG, CC BY-SA), copied into `KanjiScanner/Resources/`. Raw XML sources are gitignored (re-downloadable); the compiled sqlite *is* committed since the app needs it to build. Schema: `kanji` (character, onyomi/kunyomi/meanings as JSON, stroke_count, grade, jlpt_level, frequency_rank, radical) and `words` (surface_form, reading, meanings JSON, part_of_speech, is_common), joined via `word_kanji_map`. No `wanikani_level` or `is_joyo` columns yet (that's parked gap #2).

**Camera capture pipeline** (`CameraViewModel.swift`) went through several rounds of real bugs, each now guarded against:
- `AVCaptureVideoPreviewLayer` is created **once** and reused — recreating it per-appearance caused a ~5s delay reconnecting the session (BUG-005).
- Captured photos are cropped to the preview's actual visible rect (`metadataOutputRectConverted`) — `AVCapturePhotoOutput` otherwise captures a wider FOV than the viewfinder shows (BUG-003).
- `AVCapturePhoto.cgImageRepresentation()` returns the **raw, un-rotated** pixel buffer regardless of `videoRotationAngle` — orientation is read from the photo's metadata and baked into the pixels manually after capture (BUG-004). Easy to reintroduce this bug by "simplifying" the capture path.
- `capturePhoto()` guards on `connection.isActive` before calling into AVFoundation — calling it with no active connection (e.g. Simulator, no camera hardware) raises an uncatchable Obj-C exception otherwise (BUG-001).

**Segmentation** (`Segmenter.swift`): longest-match-first at each kanji position; a run of consecutive kanji that all fail compound-matching gets grouped into one token (not fragmented per-character) so the UI can show a "no compound match" state — this only reaches that state correctly because the run-building re-checks for a real compound match at every position within the run, so it doesn't swallow a genuine compound starting partway through.

**Scan overlay zoom/pan** (`ScanOverlayView.swift`): touch-anchored pinch zoom (solves for `offset` given a fixed touch point + old/new scale, not `scaleEffect`'s anchor) with a hard `min`/`max` clamp on `offset` to prevent overscroll. This clamp is the known source of BUG-010's kink — a hard clamp mathematically can't avoid a rate discontinuity where it engages. **Do not re-attempt a `Grid`-based or `Color.clear`-cell-based fix for row/column alignment bugs** without re-reading BUGS.md first — both were tried for BUG-011 and didn't hold up on-device despite looking theoretically sound; the fix that actually worked was a hardcoded `.padding(.leading, N)` with zero dependency on measuring sibling views.

**Tap vs. pan/zoom disambiguation** (also `ScanOverlayView.swift`): region `Button`s and their hit-testing are left completely untouched (proven reliable); an `isInteracting` flag, set by the pan/pinch gestures the moment they detect real movement, gates whether a tap's *action* fires — this is intentionally the smallest possible change after a full hit-testing rewrite (BUG-008's first attempt) broke tap responsiveness for most regions (BUG-009).

**Results display** (`ResultsView.swift`): three states depending on `LookupResult` — a matched word (+ kanji breakdown), an isolated single kanji, or (new, post-v1-closure) a multi-kanji span with no compound match (shows the breakdown anyway, with a "no compound match" indicator).

## Working conventions established this session

- **Never commit until the user has explicitly confirmed a UI/gesture change on-device.** Build + unit tests passing is necessary but not sufficient — this project has repeatedly had fixes that looked correct in code and passed tests but failed on real touch/gesture behavior (see BUGS.md's saga for BUG-008/009/010/011). This is a standing rule, not situational.
- Commit messages reference the relevant `BUG-XXX`/`US-XXX` ID(s); BUGS.md/STORIES.md get updated in the **same commit** as the code change, never a separate one.
- When reverting a change, prefer `git checkout <commit> -- <path>` over manually re-editing files back to a prior state, even if it means discarding more in-progress work than a targeted manual revert would — manual reconstruction risks subtle unverified differences.
- New feature requests get logged as user stories (STORIES.md) whether or not they're implemented immediately; defects get logged in BUGS.md. Post-v1 requests go in STORIES.md's "Backlog" section with `Version: Backlog`, not `v1`.
