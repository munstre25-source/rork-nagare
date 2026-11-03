#!/usr/bin/env python3
"""Build a compact JMdict-derived Dictionary.json for Jojo.

Downloads the jmdict-simplified "common" subset (CC BY-SA), keeps the top
FREQUENCY_CAP entries, merges any existing hand-curated Dictionary.json
entries (those win on conflict), and writes:

  ios-nagare/Jojo/Resources/Dictionary.json

Usage:
  python3 Tools/build_jmdict_bundle.py
  python3 Tools/build_jmdict_bundle.py --limit 15000
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "ios-nagare" / "Jojo" / "Resources" / "Dictionary.json"
CACHE = ROOT / ".tmp_venv" / "jmdict-eng-common.json"
CACHE_ZIP = ROOT / ".tmp_venv" / "jmdict-eng-common.json.zip"
# GitHub release of jmdict-simplified (common words only). Bump when outdated.
URL = (
    "https://github.com/scriptin/jmdict-simplified/releases/download/"
    "3.6.2%2B20261102210542/jmdict-eng-common-3.6.2%2B20261102210542.json.zip"
)

# Rough Hepburn without macrons — good enough for offline display.
_KANA = {
    "あ": "a", "い": "i", "う": "u", "え": "e", "お": "o",
    "か": "ka", "き": "ki", "く": "ku", "け": "ke", "こ": "ko",
    "さ": "sa", "し": "shi", "す": "su", "せ": "se", "そ": "so",
    "た": "ta", "ち": "chi", "つ": "tsu", "て": "te", "と": "to",
    "な": "na", "に": "ni", "ぬ": "nu", "ね": "ne", "の": "no",
    "は": "ha", "ひ": "hi", "ふ": "fu", "へ": "he", "ほ": "ho",
    "ま": "ma", "み": "mi", "む": "mu", "め": "me", "も": "mo",
    "や": "ya", "ゆ": "yu", "よ": "yo",
    "ら": "ra", "り": "ri", "る": "ru", "れ": "re", "ろ": "ro",
    "わ": "wa", "を": "wo", "ん": "n",
    "が": "ga", "ぎ": "gi", "ぐ": "gu", "げ": "ge", "ご": "go",
    "ざ": "za", "じ": "ji", "ず": "zu", "ぜ": "ze", "ぞ": "zo",
    "だ": "da", "ぢ": "ji", "づ": "zu", "で": "de", "ど": "do",
    "ば": "ba", "び": "bi", "ぶ": "bu", "べ": "be", "ぼ": "bo",
    "ぱ": "pa", "ぴ": "pi", "ぷ": "pu", "ぺ": "pe", "ぽ": "po",
    "きゃ": "kya", "きゅ": "kyu", "きょ": "kyo",
    "しゃ": "sha", "しゅ": "shu", "しょ": "sho",
    "ちゃ": "cha", "ちゅ": "chu", "ちょ": "cho",
    "にゃ": "nya", "にゅ": "nyu", "にょ": "nyo",
    "ひゃ": "hya", "ひゅ": "hyu", "ひょ": "hyo",
    "みゃ": "mya", "みゅ": "myu", "みょ": "myo",
    "りゃ": "rya", "りゅ": "ryu", "りょ": "ryo",
    "ぎゃ": "gya", "ぎゅ": "gyu", "ぎょ": "gyo",
    "じゃ": "ja", "じゅ": "ju", "じょ": "jo",
    "びゃ": "bya", "びゅ": "byu", "びょ": "byo",
    "ぴゃ": "pya", "ぴゅ": "pyu", "ぴょ": "pyo",
    "っ": "", "ー": "", "、": "", "。": "",
}


def _kata_to_hira(text: str) -> str:
    out = []
    for ch in text:
        code = ord(ch)
        if 0x30A1 <= code <= 0x30F6:
            out.append(chr(code - 0x60))
        else:
            out.append(ch)
    return "".join(out)


def to_romaji(kana: str) -> str:
    text = _kata_to_hira(kana)
    i = 0
    parts: list[str] = []
    while i < len(text):
        if text[i] == "っ" and i + 1 < len(text):
            # Geminate next consonant.
            nxt = to_romaji(text[i + 1 :])
            if nxt:
                parts.append(nxt[0])
            i += 1
            continue
        digraph = text[i : i + 2]
        if digraph in _KANA:
            parts.append(_KANA[digraph])
            i += 2
            continue
        parts.append(_KANA.get(text[i], text[i] if ord(text[i]) < 128 else ""))
        i += 1
    return re.sub(r"[^a-z0-9]", "", "".join(parts))


_POS_MAP = {
    "n": "noun",
    "n-adv": "noun",
    "n-t": "noun",
    "pn": "pronoun",
    "prt": "particle",
    "aux": "auxiliary",
    "aux-v": "auxiliary",
    "aux-adj": "auxiliary",
    "conj": "conjunction",
    "int": "interjection",
    "pref": "prefix",
    "suf": "suffix",
    "exp": "expression",
    "adv": "adverb",
    "adv-to": "adverb",
    "adj-i": "adjective",
    "adj-na": "adjective",
    "adj-no": "adjective",
    "adj-pn": "adjective",
    "adj-t": "adjective",
    "adj-f": "adjective",
    "v1": "verb",
    "v5u": "verb",
    "v5k": "verb",
    "v5g": "verb",
    "v5s": "verb",
    "v5t": "verb",
    "v5n": "verb",
    "v5b": "verb",
    "v5m": "verb",
    "v5r": "verb",
    "v5aru": "verb",
    "vs": "verb",
    "vs-i": "verb",
    "vk": "verb",
    "vz": "verb",
}


def map_pos(tags: list[str]) -> str:
    for tag in tags:
        key = tag.split(" ")[0]
        if key in _POS_MAP:
            return _POS_MAP[key]
    return "word"


def download(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and dest.stat().st_size > 1_000_000:
        print(f"Using cached {dest}")
        return
    print(f"Downloading {url}")
    req = urllib.request.Request(url, headers={"User-Agent": "jojo-dict-builder/1.0"})
    with urllib.request.urlopen(req, timeout=180) as resp, open(dest, "wb") as fh:
        while True:
            chunk = resp.read(1 << 20)
            if not chunk:
                break
            fh.write(chunk)
    print(f"Saved {dest} ({dest.stat().st_size // 1024} KB)")


def ensure_json() -> Path:
    if CACHE.exists() and CACHE.stat().st_size > 1_000_000:
        print(f"Using cached {CACHE}")
        return CACHE
    download(URL, CACHE_ZIP)
    import zipfile
    with zipfile.ZipFile(CACHE_ZIP) as zf:
        name = next(n for n in zf.namelist() if n.endswith(".json"))
        with zf.open(name) as src, open(CACHE, "wb") as dst:
            dst.write(src.read())
    print(f"Extracted {CACHE} ({CACHE.stat().st_size // 1024} KB)")
    return CACHE


def build(limit: int) -> dict:
    path = ensure_json()
    raw = json.loads(path.read_text(encoding="utf-8"))
    words = raw["words"] if isinstance(raw, dict) else raw

    existing: dict = {}
    if OUT.exists():
        existing = json.loads(OUT.read_text(encoding="utf-8"))

    built: dict[str, dict] = {}
    for entry in words:
        kanji_forms = [k.get("text") for k in entry.get("kanji", []) if k.get("text")]
        kana_forms = [k.get("text") for k in entry.get("kana", []) if k.get("text")]
        if not kana_forms and not kanji_forms:
            continue
        senses = entry.get("sense", [])
        defs: list[str] = []
        pos_tags: list[str] = []
        for sense in senses[:3]:
            pos_tags.extend(sense.get("partOfSpeech") or [])
            for gloss in sense.get("gloss") or []:
                text = gloss.get("text") if isinstance(gloss, dict) else str(gloss)
                if text and text not in defs:
                    defs.append(text)
                if len(defs) >= 3:
                    break
            if len(defs) >= 3:
                break
        if not defs:
            continue
        readings = [_kata_to_hira(k) for k in kana_forms[:3]]
        surface = kanji_forms[0] if kanji_forms else kana_forms[0]
        pos = map_pos(pos_tags)
        romaji = to_romaji(readings[0]) if readings else ""
        payload = {
            "surface": surface,
            "readings": readings,
            "romaji": romaji,
            "pos": pos,
            "jlpt": None,
            "definitions": defs,
            "ja_definitions": [],
        }
        # Index by every kanji and kana headword so lookups hit.
        keys = list(dict.fromkeys(kanji_forms + kana_forms))
        for key in keys:
            if key in existing:
                continue  # hand-curated wins
            if key not in built:
                built[key] = {**payload, "surface": key}

        if len(built) >= limit:
            break

    # Hand-curated entries always win.
    merged = {**built, **existing}
    # Cap total size while keeping curated.
    if len(merged) > limit + len(existing):
        curated_keys = set(existing)
        extras = [k for k in merged if k not in curated_keys][:limit]
        merged = {**{k: merged[k] for k in extras}, **existing}

    print(f"Built {len(merged)} entries ({len(existing)} curated kept)")
    return merged


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=20000)
    args = parser.parse_args()
    data = build(args.limit)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"Wrote {OUT} ({OUT.stat().st_size // 1024} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
