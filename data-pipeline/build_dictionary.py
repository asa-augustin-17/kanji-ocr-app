#!/usr/bin/env python3
"""
Builds kanji_scanner.sqlite from KANJIDIC2 and JMdict XML sources (EDRDG,
CC BY-SA), matching the schema in the Kanji Scanner PRD (section 5).

Usage:
    python3 build_dictionary.py

Reads sources/kanjidic2.xml and sources/JMdict_e, writes output/kanji_scanner.sqlite.
"""
import json
import re
import sqlite3
import xml.etree.ElementTree as ET
from pathlib import Path

HERE = Path(__file__).parent
SOURCES = HERE / "sources"
OUTPUT = HERE / "output"
DB_PATH = OUTPUT / "kanji_scanner.sqlite"

KANJI_RE = re.compile(r"[一-鿿㐀-䶿]")

# Standard JMdict "common word" priority markers (jmdict-simplified convention).
COMMON_MARKERS = {"news1", "ichi1", "spec1", "spec2", "gai1"}

SCHEMA = """
CREATE TABLE kanji (
    id INTEGER PRIMARY KEY,
    character TEXT NOT NULL UNIQUE,
    onyomi TEXT NOT NULL,
    kunyomi TEXT NOT NULL,
    meanings TEXT NOT NULL,
    stroke_count INTEGER,
    grade INTEGER,
    jlpt_level INTEGER,
    frequency_rank INTEGER,
    radical TEXT
);

CREATE TABLE words (
    id INTEGER PRIMARY KEY,
    surface_form TEXT NOT NULL,
    reading TEXT NOT NULL,
    meanings TEXT NOT NULL,
    part_of_speech TEXT,
    is_common INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE word_kanji_map (
    word_id INTEGER NOT NULL REFERENCES words(id),
    kanji_id INTEGER NOT NULL REFERENCES kanji(id),
    position INTEGER NOT NULL
);

CREATE INDEX idx_kanji_character ON kanji(character);
CREATE INDEX idx_words_surface_form ON words(surface_form);
CREATE INDEX idx_word_kanji_map_word_position ON word_kanji_map(word_id, position);
"""


def parse_kanjidic2(path):
    """Yields dicts of kanji field data, streaming to bound memory."""
    context = ET.iterparse(path, events=("end",))
    for event, elem in context:
        if elem.tag != "character":
            continue

        literal = elem.findtext("literal")

        misc = elem.find("misc")
        grade_text = misc.findtext("grade") if misc is not None else None
        stroke_text = misc.findtext("stroke_count") if misc is not None else None
        freq_text = misc.findtext("freq") if misc is not None else None
        jlpt_text = misc.findtext("jlpt") if misc is not None else None

        radical_el = elem.find("radical")
        radical = None
        if radical_el is not None:
            for rad_value in radical_el.findall("rad_value"):
                if rad_value.get("rad_type") == "classical":
                    radical = rad_value.text
                    break

        onyomi, kunyomi, meanings = [], [], []
        rm = elem.find("reading_meaning")
        if rm is not None:
            for rmgroup in rm.findall("rmgroup"):
                for reading in rmgroup.findall("reading"):
                    r_type = reading.get("r_type")
                    if r_type == "ja_on":
                        onyomi.append(reading.text)
                    elif r_type == "ja_kun":
                        kunyomi.append(reading.text)
                for meaning in rmgroup.findall("meaning"):
                    if meaning.get("m_lang") is None:
                        meanings.append(meaning.text)

        yield {
            "character": literal,
            "onyomi": onyomi,
            "kunyomi": kunyomi,
            "meanings": meanings,
            "stroke_count": int(stroke_text) if stroke_text else None,
            "grade": int(grade_text) if grade_text else None,
            "jlpt_level": int(jlpt_text) if jlpt_text else None,
            "frequency_rank": int(freq_text) if freq_text else None,
            "radical": radical,
        }

        elem.clear()


def parse_jmdict(path):
    """Yields dicts of word field data (one per kanji surface form), streaming."""
    context = ET.iterparse(path, events=("end",))
    for event, elem in context:
        if elem.tag != "entry":
            continue

        k_eles = elem.findall("k_ele")
        if not k_eles:
            # Kana-only entries are out of scope: the app looks up kanji/compounds.
            elem.clear()
            continue

        r_eles = elem.findall("r_ele")

        meanings = []
        pos_set = []
        for sense in elem.findall("sense"):
            for pos in sense.findall("pos"):
                if pos.text and pos.text not in pos_set:
                    pos_set.append(pos.text)
            for gloss in sense.findall("gloss"):
                lang = gloss.get("{http://www.w3.org/XML/1998/namespace}lang")
                if lang is None or lang == "eng":
                    if gloss.text:
                        meanings.append(gloss.text)

        part_of_speech = "; ".join(pos_set) if pos_set else None

        for k_ele in k_eles:
            surface_form = k_ele.findtext("keb")
            if not surface_form or not KANJI_RE.search(surface_form):
                continue

            ke_pri = {p.text for p in k_ele.findall("ke_pri")}
            ke_restr = None  # k_ele has no restriction concept itself

            # Pick the reading: prefer one whose re_restr (if any) allows this keb,
            # otherwise the first unrestricted reading, otherwise just the first.
            reading = None
            re_pri = set()
            fallback_reading = None
            for r_ele in r_eles:
                reb = r_ele.findtext("reb")
                restr = [r.text for r in r_ele.findall("re_restr")]
                this_re_pri = {p.text for p in r_ele.findall("re_pri")}
                if fallback_reading is None:
                    fallback_reading = reb
                if not restr:
                    if reading is None:
                        reading = reb
                        re_pri = this_re_pri
                elif surface_form in restr and reading is None:
                    reading = reb
                    re_pri = this_re_pri
            if reading is None:
                reading = fallback_reading
                if r_eles:
                    re_pri = {p.text for p in r_eles[0].findall("re_pri")}

            is_common = bool((ke_pri | re_pri) & COMMON_MARKERS)

            yield {
                "surface_form": surface_form,
                "reading": reading,
                "meanings": meanings,
                "part_of_speech": part_of_speech,
                "is_common": is_common,
            }

        elem.clear()


def build():
    OUTPUT.mkdir(exist_ok=True)
    if DB_PATH.exists():
        DB_PATH.unlink()

    conn = sqlite3.connect(DB_PATH)
    conn.executescript(SCHEMA)

    print("Parsing KANJIDIC2...")
    kanji_id_by_char = {}
    kanji_count = 0
    for row in parse_kanjidic2(SOURCES / "kanjidic2.xml"):
        cur = conn.execute(
            "INSERT INTO kanji (character, onyomi, kunyomi, meanings, stroke_count, "
            "grade, jlpt_level, frequency_rank, radical) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                row["character"],
                json.dumps(row["onyomi"], ensure_ascii=False),
                json.dumps(row["kunyomi"], ensure_ascii=False),
                json.dumps(row["meanings"], ensure_ascii=False),
                row["stroke_count"],
                row["grade"],
                row["jlpt_level"],
                row["frequency_rank"],
                row["radical"],
            ),
        )
        kanji_id_by_char[row["character"]] = cur.lastrowid
        kanji_count += 1
        if kanji_count % 2000 == 0:
            print(f"  {kanji_count} kanji...")
    conn.commit()
    print(f"Inserted {kanji_count} kanji.")

    print("Parsing JMdict...")
    word_count = 0
    map_count = 0
    for row in parse_jmdict(SOURCES / "JMdict_e"):
        cur = conn.execute(
            "INSERT INTO words (surface_form, reading, meanings, part_of_speech, is_common) "
            "VALUES (?, ?, ?, ?, ?)",
            (
                row["surface_form"],
                row["reading"],
                json.dumps(row["meanings"], ensure_ascii=False),
                row["part_of_speech"],
                1 if row["is_common"] else 0,
            ),
        )
        word_id = cur.lastrowid
        word_count += 1

        position = 0
        for ch in row["surface_form"]:
            kanji_id = kanji_id_by_char.get(ch)
            if kanji_id is not None:
                conn.execute(
                    "INSERT INTO word_kanji_map (word_id, kanji_id, position) VALUES (?, ?, ?)",
                    (word_id, kanji_id, position),
                )
                position += 1
                map_count += 1

        if word_count % 20000 == 0:
            print(f"  {word_count} words...")
            conn.commit()
    conn.commit()
    print(f"Inserted {word_count} words, {map_count} word-kanji mappings.")

    print("Building indexes (already created in schema)... done.")
    conn.execute("ANALYZE")
    conn.commit()
    conn.close()

    size_mb = DB_PATH.stat().st_size / (1024 * 1024)
    print(f"Wrote {DB_PATH} ({size_mb:.1f} MB)")


if __name__ == "__main__":
    build()
