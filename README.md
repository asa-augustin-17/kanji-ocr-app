# Kanji Scanner

Offline iOS kanji/compound OCR + dictionary lookup. See [docs/Kanji_Scanner_PRD_v1.md.pdf](docs/Kanji_Scanner_PRD_v1.md.pdf) for the full spec.

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

Data pipeline and full app source (camera capture, on-device Vision OCR, longest-match dictionary segmentation, hierarchical results UI, unit tests) are written and syntax-checked, but not yet compiled/run in Xcode — pending Xcode install. Next step once Xcode is ready: build, fix any compile errors, and run through the PRD's acceptance criteria on a simulator.
