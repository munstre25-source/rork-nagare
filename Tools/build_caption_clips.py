#!/usr/bin/env python3
"""Build caption-tier Jojo clips from creator-uploaded YouTube subtitles.

Pipeline (all free / local):
  1. yt-dlp --write-subs --skip-download  (manual tracks only)
  2. Parse VTT/SRT cues, cut 30–90s windows on cue boundaries
  3. Tokenize with fugashi+UniDic when available (else whitespace/punctuation split)
  4. Look up readings/definitions in Dictionary.json (JMdict bundle)
  5. Match English cues by time overlap
  6. Emit clip JSON in the existing lines format with timing: "line"

Usage:
  python3 Tools/build_caption_clips.py --video-id XXX --category kids --channel "Peppa"
  python3 Tools/build_caption_clips.py --from-probe ios-nagare/reports/caption-track-probe-….json
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DICT_PATH = ROOT / "ios-nagare" / "Jojo" / "Resources" / "Dictionary.json"
OUT_DIR = ROOT / "ios-nagare" / "reports" / "caption-clips"

try:
    import fugashi  # type: ignore
    TAGGER = fugashi.Tagger()
except Exception:
    TAGGER = None

# Minimal romaji for when Dictionary has no entry.
_HIRA = {
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
    "だ": "da", "で": "de", "ど": "do",
    "ば": "ba", "び": "bi", "ぶ": "bu", "べ": "be", "ぼ": "bo",
    "ぱ": "pa", "ぴ": "pi", "ぷ": "pu", "ぺ": "pe", "ぽ": "po",
}


def load_dictionary() -> dict:
    if not DICT_PATH.exists():
        return {}
    return json.loads(DICT_PATH.read_text(encoding="utf-8"))


def kata_to_hira(text: str) -> str:
    return "".join(chr(ord(c) - 0x60) if 0x30A1 <= ord(c) <= 0x30F6 else c for c in text)


def rough_romaji(kana: str) -> str:
    return "".join(_HIRA.get(c, "") for c in kata_to_hira(kana))


def parse_vtt(path: Path) -> list[dict]:
    text = path.read_text(encoding="utf-8", errors="replace")
    # Strip header / NOTE / STYLE blocks roughly.
    cues = []
    blocks = re.split(r"\n\s*\n", text)
    ts_re = re.compile(
        r"(?:(\d{2}):)?(\d{2}):(\d{2})[\.,](\d{3})\s-->\s(?:(\d{2}):)?(\d{2}):(\d{2})[\.,](\d{3})"
    )

    def to_sec(h, m, s, ms) -> float:
        return int(h or 0) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000.0

    for block in blocks:
        lines = [ln for ln in block.splitlines() if ln.strip() and not ln.strip().startswith("WEBVTT")
                 and not ln.strip().startswith("NOTE") and not ln.strip().startswith("STYLE")
                 and not ln.strip().startswith("Kind:") and not ln.strip().startswith("Language:")]
        if not lines:
            continue
        m = None
        body_start = 0
        for i, ln in enumerate(lines):
            m = ts_re.search(ln)
            if m:
                body_start = i + 1
                break
        if not m:
            continue
        start = to_sec(m.group(1), m.group(2), m.group(3), m.group(4))
        end = to_sec(m.group(5), m.group(6), m.group(7), m.group(8))
        body = " ".join(lines[body_start:])
        body = re.sub(r"<[^>]+>", "", body).strip()
        body = re.sub(r"\s+", " ", body)
        if body:
            cues.append({"start": start, "end": end, "text": body})
    return cues


def download_subs(video_id: str, dest: Path) -> tuple[Path | None, Path | None]:
    dest.mkdir(parents=True, exist_ok=True)
    url = f"https://www.youtube.com/watch?v={video_id}"
    cmd = [
        "yt-dlp", "--skip-download", "--write-subs", "--sub-langs", "ja*,en*",
        "--no-write-auto-subs", "--convert-subs", "vtt",
        "-o", str(dest / f"{video_id}.%(ext)s"), url,
    ]
    subprocess.run(cmd, check=False, capture_output=True, text=True, timeout=120)
    ja = next(iter(sorted(dest.glob(f"{video_id}*.ja*.vtt"))), None)
    if ja is None:
        ja = next(iter(sorted(dest.glob(f"{video_id}*.jp*.vtt"))), None)
    en = next(iter(sorted(dest.glob(f"{video_id}*.en*.vtt"))), None)
    return ja, en


def tokenize(text: str, dictionary: dict) -> list[dict]:
    tokens: list[dict] = []
    if TAGGER is not None:
        for word in TAGGER(text):
            surface = str(word)
            if not surface.strip():
                continue
            features = getattr(word, "feature", None)
            lemma = getattr(features, "lemma", None) or surface
            reading = getattr(features, "kana", None) or getattr(features, "pron", None) or ""
            pos_raw = getattr(features, "pos1", None) or "word"
            pos = "particle" if "助詞" in str(pos_raw) else (
                "verb" if "動詞" in str(pos_raw) else (
                    "noun" if "名詞" in str(pos_raw) else (
                        "adjective" if "形容" in str(pos_raw) else "word"
                    )
                )
            )
            punct = all(ord(c) < 128 or c in "、。！？…「」『』（）" for c in surface) and not any(
                "\u3040" <= c <= "\u30ff" or "\u4e00" <= c <= "\u9fff" for c in surface
            )
            entry = dictionary.get(surface) or dictionary.get(lemma)
            reading_h = kata_to_hira(reading) if reading else (entry or {}).get("readings", [None])[0]
            has_kanji = any("\u4e00" <= c <= "\u9fff" or c == "々" for c in surface)
            defs = (entry or {}).get("definitions") or []
            tappable = not punct and (bool(defs) or (not punct and len(surface) > 0))
            # Unknown names/slang: keep tappable false so the clip still publishes.
            if not defs and has_kanji is False and pos == "noun":
                tappable = False
            tokens.append({
                "surface": surface,
                "reading": reading_h if has_kanji and reading_h else None,
                "romaji": (entry or {}).get("romaji") or rough_romaji(reading_h or surface),
                "start": 0,
                "end": 0,
                "pos": pos if not punct else "punct",
                "definitions": defs[:3],
                "ja_definitions": (entry or {}).get("ja_definitions") or [],
                "jlpt": (entry or {}).get("jlpt"),
                "tappable": tappable and not punct,
                "baseForm": lemma if lemma != surface else None,
                "baseReading": None,
                "baseRomaji": None,
            })
        return tokens

    # Fallback: split on punctuation / particles-ish boundaries.
    parts = re.findall(r"[\u3040-\u30ff\u4e00-\u9fff々ー]+|[^\s]", text)
    for surface in parts:
        punct = not any("\u3040" <= c <= "\u30ff" or "\u4e00" <= c <= "\u9fff" for c in surface)
        entry = dictionary.get(surface)
        has_kanji = any("\u4e00" <= c <= "\u9fff" or c == "々" for c in surface)
        reading = ((entry or {}).get("readings") or [None])[0]
        defs = (entry or {}).get("definitions") or []
        tokens.append({
            "surface": surface,
            "reading": reading if has_kanji else None,
            "romaji": (entry or {}).get("romaji") or "",
            "start": 0,
            "end": 0,
            "pos": "punct" if punct else ((entry or {}).get("pos") or "word"),
            "definitions": defs[:3],
            "ja_definitions": (entry or {}).get("ja_definitions") or [],
            "jlpt": (entry or {}).get("jlpt"),
            "tappable": bool(defs) and not punct,
            "baseForm": None,
            "baseReading": None,
            "baseRomaji": None,
        })
    return tokens


def match_english(ja_cue: dict, en_cues: list[dict]) -> str:
    best = ""
    best_overlap = 0.0
    for en in en_cues:
        overlap = min(ja_cue["end"], en["end"]) - max(ja_cue["start"], en["start"])
        if overlap > best_overlap:
            best_overlap = overlap
            best = en["text"]
    return best


def windows_from_cues(ja_cues: list[dict], en_cues: list[dict], dictionary: dict,
                      min_dur: float = 30, max_dur: float = 90) -> list[dict]:
    if not ja_cues:
        return []
    out = []
    i = 0
    while i < len(ja_cues):
        start = ja_cues[i]["start"]
        j = i
        lines = []
        while j < len(ja_cues) and (ja_cues[j]["end"] - start) <= max_dur:
            cue = ja_cues[j]
            translation = match_english(cue, en_cues)
            if not translation:
                # Skip cues with no English — empty translation is not allowed.
                j += 1
                continue
            tokens = tokenize(cue["text"], dictionary)
            # Relativize later; store absolute for now.
            for t in tokens:
                t["start"] = cue["start"]
                t["end"] = cue["end"]
            lines.append({
                "tokens": tokens,
                "translation": translation,
                "start": cue["start"],
                "end": cue["end"],
                "timing": "line",
            })
            j += 1
            if (ja_cues[min(j, len(ja_cues) - 1)]["end"] - start) >= min_dur and j - i >= 4:
                break
        if len(lines) >= 4:
            end = lines[-1]["end"]
            dur = end - start
            if dur >= 6:
                # Relativize to window start.
                rel = []
                for line in lines:
                    rel_tokens = []
                    for t in line["tokens"]:
                        tt = dict(t)
                        tt["start"] = round(t["start"] - start, 3)
                        tt["end"] = round(t["end"] - start, 3)
                        rel_tokens.append(tt)
                    rel.append({
                        "tokens": rel_tokens,
                        "translation": line["translation"],
                        "start": round(line["start"] - start, 3),
                        "end": round(line["end"] - start, 3),
                        "timing": "line",
                    })
                tappable = sum(1 for ln in rel for t in ln["tokens"] if t.get("tappable"))
                if tappable >= 4:
                    out.append({"source_start_sec": round(start, 3), "duration_sec": round(dur, 3), "lines": rel})
        i = max(j, i + 1)
    return out


def make_clip(video_id: str, title: str, channel: str, category: str, window: dict) -> dict:
    start = window["source_start_sec"]
    dur = window["duration_sec"]
    clip_id = f"cap-{video_id}-{int(start)}"
    lines = window["lines"]
    # Caption-tier receipt stamped on every line.
    source_blob = json.dumps(
        [{"t": ln["translation"], "s": ln["start"], "e": ln["end"], "x": "".join(t["surface"] for t in ln["tokens"])}
         for ln in lines],
        ensure_ascii=False, separators=(",", ":"),
    )
    source_hash = hashlib.sha256(source_blob.encode("utf-8")).hexdigest()
    db_material = f"{video_id}|{start}|{dur}|{source_hash}"
    database_hash = hashlib.sha256(db_material.encode("utf-8")).hexdigest()
    stamped = []
    for ln in lines:
        stamped.append({
            **ln,
            "translationReview": {
                "version": "caption-1",
                "sourceTrack": "creator-manual",
                "sourceHash": source_hash,
                "databaseHash": database_hash,
                "category": category,
                "videoId": video_id,
                "sourceStartSec": start,
                "durationSec": dur,
            },
        })
    return {
        "id": clip_id,
        "video_id": video_id,
        "title": title or clip_id,
        "channel_name": channel or "Unknown",
        "category": category,
        "difficulty": "Beginner",
        "source_start_sec": start,
        "duration_sec": dur,
        "lines": stamped,
        "published": False,  # ingest function flips this after validation
        "review_tier": "caption",
        "channel_avatar_color": "#F97316",
        "thumbnail_gradient": ["#1C1917", "#44403C", "#78716C"],
    }


def build_one(video_id: str, category: str, channel: str, title: str, dictionary: dict) -> list[dict]:
    with tempfile.TemporaryDirectory() as tmp:
        ja_path, en_path = download_subs(video_id, Path(tmp))
        if not ja_path or not en_path:
            print(f"  skip {video_id}: missing manual ja/en subs (ja={ja_path} en={en_path})")
            return []
        ja_cues = parse_vtt(ja_path)
        en_cues = parse_vtt(en_path)
        windows = windows_from_cues(ja_cues, en_cues, dictionary)
        clips = [make_clip(video_id, title, channel, category, w) for w in windows]
        print(f"  {video_id}: {len(clips)} windows from {len(ja_cues)} ja cues")
        return clips


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--video-id", action="append", default=[])
    parser.add_argument("--category", default="kids")
    parser.add_argument("--channel", default="")
    parser.add_argument("--title", default="")
    parser.add_argument("--from-probe", type=Path)
    args = parser.parse_args()

    dictionary = load_dictionary()
    print(f"Dictionary entries: {len(dictionary)}; fugashi={'yes' if TAGGER else 'no'}")

    jobs = []
    if args.from_probe and args.from_probe.exists():
        probe = json.loads(args.from_probe.read_text(encoding="utf-8"))
        for row in probe.get("eligible") or []:
            jobs.append({
                "video_id": row["video_id"],
                "category": args.category,
                "channel": row.get("channel") or args.channel,
                "title": row.get("title") or args.title,
            })
    for vid in args.video_id:
        jobs.append({"video_id": vid, "category": args.category, "channel": args.channel, "title": args.title})

    if not jobs:
        print("No videos. Pass --video-id or --from-probe.", file=sys.stderr)
        return 1

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    all_clips = []
    for job in jobs:
        all_clips.extend(build_one(job["video_id"], job["category"], job["channel"], job["title"], dictionary))

    out = OUT_DIR / "caption_clips.json"
    out.write_text(json.dumps(all_clips, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Wrote {len(all_clips)} clips → {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
