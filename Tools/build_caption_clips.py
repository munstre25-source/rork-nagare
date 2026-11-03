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
import os
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DICT_PATH = ROOT / "ios-nagare" / "Jojo" / "Resources" / "Dictionary.json"
OUT_DIR = ROOT / "ios-nagare" / "reports" / "caption-clips"
SUBS_DIR = ROOT / ".tmp_probe" / "subs"

try:
    import fugashi  # type: ignore
    TAGGER = fugashi.Tagger()
except Exception:
    TAGGER = None

try:
    import pykakasi  # type: ignore
    KAKASI = pykakasi.kakasi()
except Exception:
    KAKASI = None

YT_DLP = next((str(p) for p in [ROOT / ".tmp_venv" / "bin" / "yt-dlp"] if p.exists()), "yt-dlp")

POS_MAP = {
    "名詞": "noun", "代名詞": "pronoun", "動詞": "verb", "形容詞": "adjective", "形状詞": "adjective",
    "副詞": "adverb", "助詞": "particle", "助動詞": "auxiliary", "感動詞": "interjection",
    "接続詞": "conjunction", "連体詞": "adjective", "接頭辞": "prefix", "接尾辞": "suffix",
    "補助記号": "punct", "記号": "punct", "空白": "punct",
}
GRAMMAR_POS = {"particle", "auxiliary"}
# Caption annotations that are not speech: [音楽], (笑), ♪, speaker tags like （あいり）.
NOISE_RE = re.compile(r"\[[^\]]*\]|［[^］]*］|[（(][^）)]{0,12}[）)]|[♪♫♬]|^[^\s：:]{1,10}[：:]")
CJK_RE = re.compile(r"[\u3040-\u30ff\u4e00-\u9fff々ー]")

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
    bundle = json.loads(DICT_PATH.read_text(encoding="utf-8")) if DICT_PATH.exists() else {}
    try:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import build_jmdict_bundle as jm  # type: ignore
        if jm.CACHE.exists():
            # Offline builds can afford kana spellings of kanji words (わたし, たべる).
            return {**jm.build(10 ** 6, jm.CURATED, kana_fallback_keys=True), **bundle}
    except Exception as exc:
        print(f"  full JMdict unavailable ({exc}); using app bundle", file=sys.stderr)
    return bundle


def kata_to_hira(text: str) -> str:
    return "".join(chr(ord(c) - 0x60) if 0x30A1 <= ord(c) <= 0x30F6 else c for c in text)


def rough_romaji(kana: str) -> str:
    if KAKASI is not None:
        return "".join(part["hepburn"] for part in KAKASI.convert(kata_to_hira(kana)))
    return "".join(_HIRA.get(c, "") for c in kata_to_hira(kana))


def clean_caption(text: str, japanese: bool) -> str:
    text = NOISE_RE.sub("", text).strip()
    if japanese:
        # Multi-line cues are joined with spaces; Japanese has none between words.
        text = re.sub(r"(?<=[^\x00-\x7f])\s+(?=[^\x00-\x7f])", "", text)
    return re.sub(r"\s+", " ", text).strip()


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


def _cached_subs(video_id: str, dest: Path) -> tuple[Path | None, Path | None]:
    ja = next(iter(sorted(dest.glob(f"{video_id}.ja*.vtt"))), None)
    en = next(iter(sorted(dest.glob(f"{video_id}.en*.vtt"))), None)
    return ja, en


def download_subs(video_id: str, dest: Path, attempts: int = 4, pause: float = 20) -> tuple[Path | None, Path | None]:
    """Fetch manual ja/en tracks into dest, reusing earlier downloads.

    YouTube rate-limits subtitle fetches per IP (HTTP 429 / bot check), so
    failures back off and retry instead of being treated as "no captions".
    """
    dest.mkdir(parents=True, exist_ok=True)
    ja, en = _cached_subs(video_id, dest)
    if ja and en:
        return ja, en
    url = f"https://www.youtube.com/watch?v={video_id}"
    cmd = [
        YT_DLP, "--skip-download", "--write-subs", "--sub-langs", "ja.*,ja,en.*,en",
        "--no-write-auto-subs", "--sub-format", "vtt", "--sleep-subtitles", "2",
        "-o", str(dest / f"{video_id}.%(ext)s"), url,
    ]
    env = {**os.environ, "PATH": f"{Path(YT_DLP).parent}{os.pathsep}{os.environ.get('PATH', '')}"}
    for attempt in range(attempts):
        result = subprocess.run(cmd, check=False, capture_output=True, text=True, timeout=180, env=env)
        ja, en = _cached_subs(video_id, dest)
        if ja and en:
            return ja, en
        blocked = "429" in result.stderr or "not a bot" in result.stderr
        if not blocked:
            break
        time.sleep(pause * (2 ** attempt))
    return ja, en


def _feat(word, name: str) -> str | None:
    value = getattr(word.feature, name, None)
    return None if value in (None, "*", "") else str(value)


def _morphemes(text: str) -> list[dict]:
    out = []
    for word in TAGGER(text):
        surface = word.surface
        if not surface.strip():
            continue
        pos1 = _feat(word, "pos1") or ""
        pos2 = _feat(word, "pos2") or ""
        out.append({
            "surface": surface,
            "pos1": "代名詞" if pos1 == "代名詞" else pos1,
            "pos2": pos2,
            "kana": _feat(word, "kana") or "",
            "lemma": (_feat(word, "lemma") or surface).split("-")[0],
            "base": _feat(word, "orthBase") or surface,
            "base_kana": _feat(word, "kanaBase") or "",
        })
    return out


def _joins(group: list[dict], m: dict) -> bool:
    """Attach conjugation endings and suffixes to the word they belong to."""
    head, last = group[0], group[-1]
    inflecting = head["pos1"] in ("動詞", "形容詞")
    if inflecting and m["pos1"] == "助動詞" and m["surface"] not in ("です", "だ", "でしょう", "だろう"):
        return True
    if inflecting and m["pos1"] == "助詞" and m["pos2"] == "接続助詞" and m["surface"] in ("て", "で"):
        return True
    if inflecting and m["pos1"] == "動詞" and m["pos2"] == "非自立可能" and last["surface"] in ("て", "で"):
        return True
    if head["pos1"] == "名詞" and m["pos1"] == "接尾辞":
        return True
    if head["surface"].isdigit() and m["pos1"] == "名詞" and m["pos2"] == "普通名詞" and len(m["surface"]) == 1:
        return True
    if head["pos1"] == "名詞" and head["pos2"] == "普通名詞" and m["pos1"] == "動詞" and m["base"] == "為る":
        return True
    return False


PARTICLE_ROMAJI = {"は": "wa", "へ": "e", "を": "o"}


def _reading_for(surface: str, kana: str, entry: dict | None) -> str | None:
    if not any("\u4e00" <= c <= "\u9fff" or c == "々" for c in surface):
        return None
    if any(c.isdigit() for c in surface):
        return None
    hira = kata_to_hira(kana) if kana else ""
    readings = (entry or {}).get("readings") or []
    if hira and (hira in readings or not readings):
        return hira
    return readings[0] if readings else (hira or None)


def tokenize(text: str, dictionary: dict) -> list[dict]:
    tokens: list[dict] = []
    if TAGGER is not None:
        groups: list[list[dict]] = []
        for m in _morphemes(text):
            if groups and _joins(groups[-1], m):
                groups[-1].append(m)
            else:
                groups.append([m])
        # Compound particles (における, について, として) are one grammar unit.
        merged: list[list[dict]] = []
        for group in groups:
            prev = merged[-1] if merged else None
            joined = "".join(m["surface"] for m in (prev or []) + group)
            if prev and prev[0]["pos1"] == "助詞" and len(joined) <= 5 \
                    and (dictionary.get(joined) or {}).get("pos") in ("particle", "expression"):
                prev.extend(group)
                prev[0] = {**prev[0], "base": joined, "lemma": joined}
            else:
                merged.append(group)
        groups = merged
        for group in groups:
            head = group[0]
            surface = "".join(m["surface"] for m in group)
            kana = "".join(m["kana"] for m in group)
            pos = POS_MAP.get(head["pos1"], "word")
            punct = pos == "punct" or not CJK_RE.search(surface)
            inflecting = head["pos1"] in ("動詞", "形容詞", "助動詞")
            conjugated = inflecting and (len(group) > 1 or head["base"] != surface)
            base = head["base"] if head["base"] != "為る" else "する"
            base_kana = head["base_kana"]
            suru_noun = head["pos1"] == "名詞" and len(group) > 1 and group[1]["base"] == "為る"
            if suru_noun:
                base, base_kana, pos = head["surface"] + "する", head["kana"] + "スル", "verb"
                conjugated = True
            has_kanji = lambda s: any("\u4e00" <= c <= "\u9fff" for c in s)  # noqa: E731
            lemma = head["lemma"] if has_kanji(head["lemma"]) else None
            if suru_noun:
                keys = [base, head["surface"]]
            elif inflecting:
                # Conjugated surfaces collide with unrelated kana headwords (した → 下), and
                # kana verbs need UniDic's lemma; without it (於く) the kana base (おく → 奥) lies.
                kana_ok = not lemma or lemma == base
                keys = [base if has_kanji(base) else None, lemma, base if kana_ok else None,
                        head["surface"] if kana_ok else None]
            elif has_kanji(surface):
                keys = [surface, base, head["surface"]]
            else:
                # Kana spellings are ambiguous (なん → 難); UniDic's lemma (何) names the word.
                keys = [lemma if len(group) == 1 else None, surface, base]
            entry = next((dictionary[k] for k in keys if k and k in dictionary), None)
            defs = (entry or {}).get("definitions") or []
            reading = _reading_for(surface, kana, dictionary.get(surface))
            if pos == "particle" and surface in PARTICLE_ROMAJI:
                romaji = PARTICLE_ROMAJI[surface]
            elif punct:
                romaji = ""
            else:
                romaji = rough_romaji(reading or kana or surface)
            base_form = base if conjugated and base != surface else None
            base_entry = dictionary.get(base) if base_form else None
            base_reading = None
            if base_form:
                base_reading = _reading_for(base_form, base_kana, base_entry)
            tokens.append({
                "surface": surface,
                "reading": reading,
                "romaji": romaji,
                "start": 0,
                "end": 0,
                "pos": pos,
                "definitions": defs[:3],
                "ja_definitions": (entry or {}).get("ja_definitions") or [],
                "jlpt": (entry or {}).get("jlpt"),
                # Untranslated names stay plain text; grammar words get the app's local notes.
                "tappable": not punct and (bool(defs) or pos in GRAMMAR_POS),
                "baseForm": base_form,
                "baseReading": base_reading,
                "baseRomaji": rough_romaji(base_reading or base_form) if base_form else None,
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


def clean_cues(cues: list[dict], japanese: bool) -> list[dict]:
    out = []
    for cue in cues:
        text = clean_caption(cue["text"], japanese)
        if not text or (japanese and not CJK_RE.search(text)):
            continue
        if out and out[-1]["text"] == text and cue["start"] - out[-1]["end"] < 0.5:
            out[-1]["end"] = cue["end"]
            continue
        out.append({**cue, "text": text})
    return out


CONTENT_POS = {"noun", "verb", "adjective", "adverb", "pronoun"}
_STOP = {"to", "a", "an", "the", "be", "of", "or", "e.g.", "one's", "someone", "something", "etc."}


def _gloss_stems(tokens: list[dict]) -> set[str]:
    stems = set()
    for t in tokens:
        if t.get("pos") not in CONTENT_POS:
            continue
        for d in t.get("definitions") or []:
            for w in re.findall(r"[a-z']+", d.lower()):
                if w not in _STOP and len(w) >= 3:
                    stems.add(w[:5])
    return stems


def _hit_rate(lines: list[dict], translations: list[str]) -> float:
    hits = total = 0
    for line, en in zip(lines, translations):
        stems = _gloss_stems(line["tokens"])
        if not stems or not en:
            continue
        total += 1
        words = {w[:5] for w in re.findall(r"[a-z']+", en.lower()) if len(w) >= 3}
        hits += bool(stems & words)
    return hits / total if total else 0.0


def alignment_ok(lines: list[dict]) -> bool:
    """Reject windows whose creator English track is shifted against the Japanese.

    Compares dictionary-gloss overlap for the paired lines against the same
    lines paired one cue earlier/later; drift makes a shifted pairing win.
    """
    en = [ln["translation"] for ln in lines]
    aligned = _hit_rate(lines, en)
    forward = _hit_rate(lines[:-1], en[1:])
    backward = _hit_rate(lines[1:], en[:-1])
    return aligned >= 0.3 and aligned >= max(forward, backward)


def spread(items: list, cap: int) -> list:
    if cap <= 0 or len(items) <= cap:
        return items
    if cap == 1:
        return [items[len(items) // 2]]
    return [items[round(k * (len(items) - 1) / (cap - 1))] for k in range(cap)]


def windows_from_cues(ja_cues: list[dict], en_cues: list[dict], dictionary: dict,
                      min_dur: float = 20, max_dur: float = 60) -> list[dict]:
    ja_cues = clean_cues(ja_cues, True)
    en_cues = clean_cues(en_cues, False)
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
            if lines and lines[-1]["translation"] == translation and cue["start"] - lines[-1]["end"] < 1.0:
                # One English cue spanning several Japanese cues is one sentence.
                prev = lines[-1]
                prev["tokens"].extend(tokens)
                prev["end"] = cue["end"]
                for t in prev["tokens"]:
                    t["start"], t["end"] = prev["start"], prev["end"]
            else:
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
            if (ja_cues[min(j, len(ja_cues) - 1)]["end"] - start) >= min_dur and len(lines) >= 4:
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
                if tappable >= 4 and alignment_ok(rel):
                    out.append({"source_start_sec": round(start, 3), "duration_sec": round(dur, 3), "lines": rel})
        i = max(j, i + 1)
    return out


DIFFICULTY = {"kids": "Beginner", "learning": "Beginner", "podcast": "Intermediate", "anime": "Intermediate",
              "drama": "Advanced", "variety": "Advanced", "interview": "Intermediate", "gaming": "Advanced",
              "vtuber": "Advanced"}


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
        "difficulty": DIFFICULTY.get(category, "Intermediate"),
        "source_start_sec": start,
        "duration_sec": dur,
        "lines": stamped,
        "published": False,  # ingest function flips this after validation
        "review_tier": "caption",
        "video_orientation": "landscape",
        "channel_avatar_color": "#F97316",
        "thumbnail_gradient": ["#1C1917", "#44403C", "#78716C"],
    }


def build_one(video_id: str, category: str, channel: str, title: str, dictionary: dict,
              max_per_video: int = 0, subs_dir: Path = SUBS_DIR) -> list[dict]:
    ja_path, en_path = download_subs(video_id, subs_dir)
    if not ja_path or not en_path:
        print(f"  skip {video_id}: missing manual ja/en subs (ja={ja_path} en={en_path})")
        return []
    ja_cues = parse_vtt(ja_path)
    en_cues = parse_vtt(en_path)
    windows = windows_from_cues(ja_cues, en_cues, dictionary)
    chosen = spread(windows, max_per_video)
    clips = [make_clip(video_id, title, channel, category, w) for w in chosen]
    print(f"  {video_id}: {len(clips)}/{len(windows)} windows from {len(ja_cues)} ja cues")
    return clips


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--video-id", action="append", default=[])
    parser.add_argument("--category", default="kids")
    parser.add_argument("--channel", default="")
    parser.add_argument("--title", default="")
    parser.add_argument("--from-probe", type=Path)
    parser.add_argument("--jobs", type=Path,
                        help="JSON list of {video_id, category, channel, title, max_clips?}")
    parser.add_argument("--max-per-video", type=int, default=8)
    parser.add_argument("--out", type=Path, default=OUT_DIR / "caption_clips.json")
    parser.add_argument("--subs-dir", type=Path, default=SUBS_DIR)
    parser.add_argument("--delay", type=float, default=12, help="seconds between uncached downloads")
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
    if args.jobs and args.jobs.exists():
        for row in json.loads(args.jobs.read_text(encoding="utf-8")):
            jobs.append({
                "video_id": row["video_id"],
                "category": row.get("category") or args.category,
                "channel": row.get("channel") or args.channel,
                "title": row.get("title") or args.title,
                "max_clips": row.get("max_clips"),
            })
    for vid in args.video_id:
        jobs.append({"video_id": vid, "category": args.category, "channel": args.channel, "title": args.title})

    if not jobs:
        print("No videos. Pass --video-id, --jobs or --from-probe.", file=sys.stderr)
        return 1

    all_clips = []
    for n, job in enumerate(jobs):
        cached = all(_cached_subs(job["video_id"], args.subs_dir))
        if n and not cached:
            time.sleep(args.delay)
        cap = job.get("max_clips") or args.max_per_video
        all_clips.extend(build_one(job["video_id"], job["category"], job["channel"], job["title"], dictionary,
                                   cap, args.subs_dir))

    out = args.out
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(all_clips, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Wrote {len(all_clips)} clips → {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
