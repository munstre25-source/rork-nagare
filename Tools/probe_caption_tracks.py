#!/usr/bin/env python3
"""Probe which catalog / channel videos have creator-uploaded (non-ASR) captions.

Uses yt-dlp metadata only — no download, no YouTube Data API quota, no AI credits.

Writes:
  ios-nagare/reports/caption-track-probe-YYYY-MM-DD.md
  ios-nagare/reports/caption-track-probe-YYYY-MM-DD.json

Usage:
  python3 Tools/probe_caption_tracks.py
  python3 Tools/probe_caption_tracks.py --limit 40
  python3 Tools/probe_caption_tracks.py --video-id dQw4w9WgXcQ
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FILES = ROOT / "files"
REPORTS = ROOT / "ios-nagare" / "reports"


def have_ytdlp() -> str | None:
    root = Path(__file__).resolve().parents[1]
    candidates = [
        root / ".tmp_venv" / "bin" / "yt-dlp",
        Path(shutil.which("yt-dlp") or ""),
        Path(shutil.which("youtube-dl") or ""),
    ]
    for path in candidates:
        if path and path.exists():
            return str(path)
    return None


def load_video_ids(limit: int | None) -> list[dict]:
    rows: list[dict] = []
    videos_json = FILES / "videos.json"
    if videos_json.exists():
        raw = json.loads(videos_json.read_text(encoding="utf-8"))
        items = raw if isinstance(raw, list) else raw.get("videos") or raw.get("items") or []
        for item in items:
            vid = item.get("id") or item.get("video_id") or item.get("videoId")
            if not vid:
                continue
            rows.append({
                "video_id": vid,
                "title": item.get("title") or "",
                "channel": item.get("channel") or item.get("channel_title") or item.get("channelTitle") or "",
                "duration_sec": item.get("duration_sec") or item.get("duration") or 0,
            })
    tsv = FILES / "video_ids.tsv"
    if tsv.exists() and not rows:
        for line in tsv.read_text(encoding="utf-8").splitlines():
            parts = line.strip().split("\t")
            if parts and parts[0] and not parts[0].startswith("#"):
                rows.append({"video_id": parts[0], "title": parts[1] if len(parts) > 1 else "", "channel": "", "duration_sec": 0})
    # Prefer shorter clips first — caption windows are more useful there.
    rows.sort(key=lambda r: (float(r.get("duration_sec") or 99999), r["video_id"]))
    if limit:
        rows = rows[:limit]
    return rows


def probe(video_id: str, ytdlp: str) -> dict:
    url = f"https://www.youtube.com/watch?v={video_id}"
    cmd = [
        ytdlp, "--skip-download", "--quiet", "--no-warnings",
        "--print", "%(.{id,title,channel,duration,subtitles,automatic_captions})j",
        url,
    ]
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.STDOUT, timeout=60, text=True)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        return {"video_id": video_id, "ok": False, "error": str(exc)[:200]}

    try:
        data = json.loads(out.strip().splitlines()[-1])
    except json.JSONDecodeError:
        return {"video_id": video_id, "ok": False, "error": "bad_json"}

    manual = data.get("subtitles") or {}
    auto = data.get("automatic_captions") or {}
    # Creator-uploaded tracks (never auto).
    ja_manual = [k for k in manual if k.lower().startswith("ja")]
    en_manual = [k for k in manual if k.lower().startswith("en")]
    return {
        "video_id": video_id,
        "ok": True,
        "title": data.get("title") or "",
        "channel": data.get("channel") or "",
        "duration": data.get("duration") or 0,
        "ja_manual": ja_manual,
        "en_manual": en_manual,
        "has_ja_manual": bool(ja_manual),
        "has_en_manual": bool(en_manual),
        "eligible": bool(ja_manual) and bool(en_manual),
        "auto_langs": sorted(list(auto.keys()))[:12],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=60)
    parser.add_argument("--video-id", action="append", default=[])
    args = parser.parse_args()

    ytdlp = have_ytdlp()
    if not ytdlp:
        print("yt-dlp not found. Install with: pip install yt-dlp", file=sys.stderr)
        # Still write an empty report so the pipeline has a place to land.
        REPORTS.mkdir(parents=True, exist_ok=True)
        day = date.today().isoformat()
        stub = {"generated_at": day, "error": "yt-dlp_missing", "eligible": [], "summary": {}}
        (REPORTS / f"caption-track-probe-{day}.json").write_text(json.dumps(stub, indent=2), encoding="utf-8")
        (REPORTS / f"caption-track-probe-{day}.md").write_text(
            f"# Caption track probe ({day})\n\n`yt-dlp` is not installed. Run `pip install yt-dlp` and re-run.\n",
            encoding="utf-8",
        )
        return 1

    if args.video_id:
        rows = [{"video_id": v, "title": "", "channel": "", "duration_sec": 0} for v in args.video_id]
    else:
        rows = load_video_ids(args.limit)

    print(f"Probing {len(rows)} videos with {ytdlp}")
    results = []
    for i, row in enumerate(rows, 1):
        print(f"[{i}/{len(rows)}] {row['video_id']}")
        result = probe(row["video_id"], ytdlp)
        result.setdefault("title", row.get("title") or "")
        result.setdefault("channel", row.get("channel") or "")
        results.append(result)

    eligible = [r for r in results if r.get("eligible")]
    ja_only = [r for r in results if r.get("has_ja_manual") and not r.get("has_en_manual")]
    summary = {
        "probed": len(results),
        "ok": sum(1 for r in results if r.get("ok")),
        "ja_manual": sum(1 for r in results if r.get("has_ja_manual")),
        "en_manual": sum(1 for r in results if r.get("has_en_manual")),
        "eligible_ja_and_en": len(eligible),
        "ja_only": len(ja_only),
    }

    day = date.today().isoformat()
    REPORTS.mkdir(parents=True, exist_ok=True)
    payload = {"generated_at": day, "summary": summary, "eligible": eligible, "results": results}
    (REPORTS / f"caption-track-probe-{day}.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    lines = [
        f"# Caption track probe ({day})",
        "",
        f"- Probed: **{summary['probed']}**",
        f"- OK: **{summary['ok']}**",
        f"- Creator JA captions: **{summary['ja_manual']}**",
        f"- Creator EN captions: **{summary['en_manual']}**",
        f"- Eligible (JA + EN manual): **{summary['eligible_ja_and_en']}**",
        f"- JA only: **{summary['ja_only']}**",
        "",
        "## Eligible videos",
        "",
    ]
    for r in eligible:
        lines.append(f"- `{r['video_id']}` — {r.get('title','')} ({r.get('channel','')})")
    if not eligible:
        lines.append("_None in this sample._")
    lines.append("")
    (REPORTS / f"caption-track-probe-{day}.md").write_text("\n".join(lines), encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
