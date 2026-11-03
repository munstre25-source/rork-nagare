#!/usr/bin/env python3
"""Daily free content enrichment: new caption-tier clips from approved channels.

No AI calls. Uses only YouTube Data API quota, yt-dlp subtitle downloads, the
local tokenizer and the JMdict bundle, then publishes through ingest-caption-clips.

  1. Ask ingest-caption-clips for approved channels and videos already captioned
  2. List recent uploads per channel (playlistItems, 1 unit per 50 videos)
  3. Keep public, embeddable videos with creator captions (videos.list, 1 unit per 50)
  4. Confirm ja + en standard tracks (captions.list, 50 units per video) until the budget is spent
  5. Download subs, build clips, publish

Env (never hard-coded, never printed):
  YOUTUBE_API_KEY, SUPABASE_URL, SUPABASE_ANON_KEY, ADMIN_TOKEN

Usage:
  python3 Tools/daily_caption_pipeline.py --max-videos 25 --quota-budget 2500
  python3 Tools/daily_caption_pipeline.py --dry-run
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_caption_clips as builder  # noqa: E402
from ingest_caption_clips import post as ingest_post  # noqa: E402

YT = "https://www.googleapis.com/youtube/v3/"
# Base caps before watch-demand boosts. Podcasts stay short; learning is already over-supplied.
CLIPS_PER_VIDEO = {"podcast": 3, "learning": 4}
DEFAULT_CLIPS_PER_VIDEO = 6


def env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        sys.exit(f"Missing env {name}")
    return value


class Quota:
    def __init__(self, budget: int):
        self.budget = budget
        self.used = 0

    def take(self, units: int) -> bool:
        if self.used + units > self.budget:
            return False
        self.used += units
        return True


def yt_get(key: str, quota: Quota, units: int, path: str, **params) -> dict | None:
    if not quota.take(units):
        return None
    url = YT + path + "?" + urllib.parse.urlencode({**params, "key": key})
    try:
        with urllib.request.urlopen(url, timeout=30) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as err:
        body = json.loads(err.read() or b"{}")
        reason = (body.get("error", {}).get("errors") or [{}])[0].get("reason", "")
        print(f"  YouTube {path} HTTP {err.code} {reason}")
        if reason in {"quotaExceeded", "dailyLimitExceeded"}:
            quota.used = quota.budget
        return None


def iso_seconds(duration: str) -> int:
    m = re.match(r"P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?", duration or "")
    if not m:
        return 0
    d, h, mi, s = (int(x or 0) for x in m.groups())
    return d * 86400 + h * 3600 + mi * 60 + s


def edge_state(base: str, anon: str, admin: str) -> dict:
    req = urllib.request.Request(
        base + "/functions/v1/ingest-caption-clips",
        data=json.dumps({"action": "state"}).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {anon}",
                 "apikey": anon, "x-admin-token": admin},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.load(resp)


def channel_category(channel: dict) -> str:
    if re.search(r"podcast|ポッドキャスト", channel["title"], re.I):
        return "podcast"
    return channel["category"]


def clips_for(category: str, demand_priority: int) -> int:
    """More clips from under-watched categories; fewer from over-supplied ones."""
    base = CLIPS_PER_VIDEO.get(category, DEFAULT_CLIPS_PER_VIDEO)
    return min(10, max(2, base + max(0, demand_priority - 2)))


def candidate_videos(key: str, quota: Quota, channels: list[dict], done: set[str], pages: int) -> list[dict]:
    uploads: dict[str, str] = {}
    for i in range(0, len(channels), 50):
        ids = ",".join(c["channel_id"] for c in channels[i:i + 50])
        data = yt_get(key, quota, 1, "channels", part="contentDetails", id=ids, maxResults=50) or {}
        for item in data.get("items", []):
            uploads[item["id"]] = item["contentDetails"]["relatedPlaylists"]["uploads"]

    per_channel: dict[str, list[str]] = {}
    for channel in channels:
        playlist = uploads.get(channel["channel_id"])
        token = None
        for _ in range(pages):
            if not playlist:
                break
            params = {"part": "contentDetails", "playlistId": playlist, "maxResults": 50}
            if token:
                params["pageToken"] = token
            data = yt_get(key, quota, 1, "playlistItems", **params)
            if not data:
                break
            ids = [it["contentDetails"]["videoId"] for it in data.get("items", [])]
            per_channel.setdefault(channel["channel_id"], []).extend(v for v in ids if v not in done)
            token = data.get("nextPageToken")
            if not token:
                break

    by_id = {c["channel_id"]: c for c in channels}
    # Queue by category so high-demand lanes get more slots in the round-robin.
    by_category: dict[str, list[dict]] = {}
    all_ids = [v for ids in per_channel.values() for v in ids]
    for i in range(0, len(all_ids), 50):
        data = yt_get(key, quota, 1, "videos", part="snippet,contentDetails,status",
                      id=",".join(all_ids[i:i + 50]), maxResults=50) or {}
        for item in data.get("items", []):
            cd, sn, st = item["contentDetails"], item["snippet"], item["status"]
            audio = sn.get("defaultAudioLanguage") or sn.get("defaultLanguage") or "ja"
            if cd.get("caption") != "true" or not st.get("embeddable") or st.get("privacyStatus") != "public":
                continue
            if not audio.startswith("ja") or cd.get("contentRating", {}).get("ytRating"):
                continue
            if not 60 <= iso_seconds(cd.get("duration", "")) <= 3600:
                continue
            channel = by_id.get(sn["channelId"])
            if not channel:
                continue
            category = channel_category(channel)
            priority = int(channel.get("demand_priority") or 2)
            by_category.setdefault(category, []).append({
                "video_id": item["id"],
                "title": sn["title"],
                "channel": channel["title"],
                "category": category,
                "demand_priority": priority,
            })

    # Weighted round-robin: a category with priority 4 is offered 4 times per cycle.
    queues = {
        cat: sorted(videos, key=lambda v: (-v["demand_priority"], v["channel"], v["title"]))
        for cat, videos in by_category.items()
    }
    weights = {cat: max(1, videos[0]["demand_priority"] if videos else 1) for cat, videos in queues.items()}
    order = sorted(queues, key=lambda c: (-weights[c], c))
    ordered: list[dict] = []
    while any(queues.values()):
        for cat in order:
            for _ in range(weights.get(cat, 1)):
                if queues.get(cat):
                    ordered.append(queues[cat].pop(0))
    return ordered


def has_bilingual_tracks(key: str, quota: Quota, video_id: str) -> bool | None:
    data = yt_get(key, quota, 50, "captions", part="snippet", videoId=video_id)
    if data is None:
        return None
    langs = {c["snippet"]["language"] for c in data.get("items", [])
             if c["snippet"].get("trackKind") == "standard" and c["snippet"].get("status") == "serving"}
    return any(l.startswith("ja") for l in langs) and any(l.startswith("en") for l in langs)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--max-videos", type=int, default=25)
    parser.add_argument("--quota-budget", type=int, default=2500)
    parser.add_argument("--pages", type=int, default=3, help="upload pages (50 videos each) per channel")
    parser.add_argument("--delay", type=float, default=15, help="seconds between subtitle downloads")
    parser.add_argument("--subs-dir", type=Path, default=builder.SUBS_DIR)
    parser.add_argument("--out", type=Path, default=builder.OUT_DIR / "daily_caption_clips.json")
    parser.add_argument("--dry-run", action="store_true", help="discover and build, do not publish")
    args = parser.parse_args()

    key = env("YOUTUBE_API_KEY")
    base, anon, admin = env("SUPABASE_URL").rstrip("/"), env("SUPABASE_ANON_KEY"), env("ADMIN_TOKEN")
    quota = Quota(args.quota_budget)

    state = edge_state(base, anon, admin)
    channels = state.get("channels") or []
    done = set(state.get("captioned_video_ids") or [])
    demand = state.get("category_demand") or []
    print(f"{len(channels)} approved channels, {len(done)} videos already captioned")
    if demand:
        print("Watch demand (last 90d, high → publish more):")
        for row in demand:
            print(f"  {row['category']}: demand {row['demand_index']} · "
                  f"{row['views']} views / {row['live_clips']} live · priority {row['priority']}")
    else:
        print("No category demand yet; using even priorities")

    candidates = candidate_videos(key, quota, channels, done, args.pages)
    print(f"{len(candidates)} new videos with creator captions (quota used {quota.used})")

    jobs: list[dict] = []
    for video in candidates:
        if len(jobs) >= args.max_videos:
            break
        ok = has_bilingual_tracks(key, quota, video["video_id"])
        if ok is None:
            print(f"  quota budget reached after {len(jobs)} confirmed videos")
            break
        if ok:
            jobs.append(video)
    print(f"{len(jobs)} videos with ja + en creator tracks (quota used {quota.used}/{quota.budget})")
    if jobs:
        by_cat: dict[str, int] = {}
        for j in jobs:
            by_cat[j["category"]] = by_cat.get(j["category"], 0) + 1
        print("Selected:", ", ".join(f"{c}×{n}" for c, n in sorted(by_cat.items(), key=lambda x: -x[1])))
    if not jobs:
        return 0

    dictionary = builder.load_dictionary()
    clips: list[dict] = []
    skipped = 0
    for n, job in enumerate(jobs):
        if n and not all(builder._cached_subs(job["video_id"], args.subs_dir)):
            time.sleep(args.delay)
        cap = clips_for(job["category"], int(job.get("demand_priority") or 2))
        built = builder.build_one(job["video_id"], job["category"], job["channel"], job["title"],
                                  dictionary, cap, args.subs_dir)
        skipped += not built
        clips.extend(built)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(clips, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Built {len(clips)} clips from {len(jobs) - skipped}/{len(jobs)} videos → {args.out}")
    if args.dry_run or not clips:
        return 0

    url = base + "/functions/v1/ingest-caption-clips"
    accepted = 0
    for i in range(0, len(clips), 20):
        result = ingest_post(url, anon, admin, clips[i:i + 20])
        if "error" in result:
            print(f"  batch {i // 20}: {result['error']}")
            continue
        accepted += result.get("accepted", 0)
        for err in (result.get("errors") or [])[:5]:
            print("   rejected", err)
    print(f"Published {accepted}/{len(clips)} clips")
    return 0 if accepted or not clips else 1


if __name__ == "__main__":
    sys.exit(main())
