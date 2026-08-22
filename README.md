# Kanji Scanner

Offline iOS kanji/compound OCR + dictionary lookup. See [docs/Kanji_Scanner_PRD_v1.md.pdf](docs/Kanji_Scanner_PRD_v1.md.pdf) for the full spec, [STORIES.md](STORIES.md) for the user story log, and [BUGS.md](BUGS.md) for the bug log.

## Layout

- `data-pipeline/` — Python script that builds the bundled dictionary from KANJIDIC2 + JMdict (EDRDG, CC BY-SA).
- `KanjiScanner/` — the iOS app (XcodeGen-managed project).

## Rebuilding the dictionary database

```bash
cd data-pipeline
python3 build_dictionary.py
cp output/kanji_scanner.sqlite ../KanjiScanner/KanjiScanner/Resources/
```

Only needed if you update the source XML in `data-pipeline/sources/` or change the schema. The current output is already copied into `KanjiScanner/Resources/`.

## Opening the app project

The `.xcodeproj` is generated from `project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — don't hand-edit the `.xcodeproj` directly, edit `project.yml` and regenerate:

```bash
cd KanjiScanner
xcodegen generate
open KanjiScanner.xcodeproj
```

Requires full Xcode (not just Command Line Tools) to build/run — install from the App Store, then `sudo xcode-select -s /Applications/Xcode.app`. First build will resolve the GRDB.swift Swift Package dependency automatically.

## Status

Builds and runs on a physical iPhone: camera capture, on-device Vision OCR, longest-match dictionary segmentation, and hierarchical results UI are all working end-to-end, with pinch-to-zoom/pan on the scan overlay for precise region selection. See [BUGS.md](BUGS.md) for what's been found/fixed along the way. Still open: full on-device verification of OCR/segmentation/results accuracy against varied real-world printed text (task tracked separately), and the accidental-tap-during-pan issue (BUG-008/009) is currently unfixed after a revert.
