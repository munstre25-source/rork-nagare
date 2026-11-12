#!/usr/bin/env python3
"""Turn saved YouTube metadata into a balanced, review-gated local queue.

This reads cached metadata only. A metadata candidate is not a transcript,
audio grant, reviewed lesson, or publication approval.
"""

import argparse
import collections
import gzip
import json
import re
from pathlib import Path

def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(path)


def category_map(sources, curated, categorized_reports=(), channel_categories=()):
    categories = {}
    for source in json.loads(sources.read_text(encoding="utf-8"))["sources"]:
        if source.get("status") == "resolved" and source.get("category"):
            categories[source["channel_id"]] = source["category"]
    for path in curated:
        for video in json.loads(path.read_text(encoding="utf-8")):
            channel, category = video.get("channel_id"), video.get("category")
            if not channel or not category:
                continue
            previous = categories.get(channel)
            if previous is not None and previous != category:
                raise ValueError(f"Conflicting category for channel {channel}")
            categories[channel] = category
    for path in categorized_reports:
        report = json.loads(path.read_text(encoding="utf-8"))
        for video in report["newSources"]["candidates"]:
            channel, category = video["channel_id"], video["category"]
            previous = categories.get(channel)
            if previous is not None and previous != category:
                raise ValueError(f"Conflicting category for channel {channel}")
            categories[channel] = category
    for path in channel_categories:
        rows = json.loads(path.read_text(encoding="utf-8"))["channels"]
        for row in rows:
            channel, category = row["channel_id"], row["category"]
            previous = categories.get(channel)
            if previous is not None and previous != category:
                raise ValueError(f"Conflicting category for channel {channel}")
            categories[channel] = category
    return categories


def candidates_from_archives(archives, categories):
    candidates = {}
    uncategorized = collections.Counter()
    for archive in archives:
        with gzip.open(archive, "rt", encoding="utf-8") as stream:
            for line in stream:
                video = json.loads(line)
                video_id = video.get("video_id")
                channel = video.get("channel_id")
                if (
                    not isinstance(video_id, str)
                    or not re.fullmatch(r"[A-Za-z0-9_-]{11}", video_id)
                    or not video.get("metadata_candidate")
                    or not video.get("duration_sec")
                    or not 3 <= video["duration_sec"] <= 180
                    or (video.get("declared_audio_language") or "").split("-")[0] != "ja"
                ):
                    continue
                category = categories.get(channel)
                if category is None:
                    uncategorized[channel] += 1
                    continue
                candidates[video_id] = {
                    "video_id": video_id,
                    "channel_id": channel,
                    "channel_name": video["channel_name"],
                    "title": video["title"],
                    "duration_sec": video["duration_sec"],
                    "category": category,
                    "caption_available": bool(video.get("caption_available")),
                    "published_at": video.get("published_at"),
                }
    return list(candidates.values()), uncategorized


def balanced_queue(candidates, limit, per_channel):
    groups = collections.defaultdict(list)
    for video in candidates:
        groups[(video["category"], video["channel_id"])].append(video)
    for videos in groups.values():
        videos.sort(
            key=lambda v: (
                not v["caption_available"],
                v["duration_sec"] > 60,
                abs(v["duration_sec"] - 35),
                v["video_id"],
            )
        )
        del videos[per_channel:]
    by_category = collections.defaultdict(list)
    for (category, channel), videos in groups.items():
        by_category[category].append((channel, videos))
    for channels in by_category.values():
        channels.sort(key=lambda pair: pair[0])
    rotating = {
        category: collections.deque(channels)
        for category, channels in by_category.items()
    }
    result = []
    while len(result) < limit:
        added = False
        for category in sorted(rotating):
            channels = rotating[category]
            for _ in range(len(channels)):
                channel, videos = channels.popleft()
                if videos:
                    result.append(videos.pop(0))
                    added = True
                    channels.append((channel, videos))
                    break
        if not added:
            break
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, action="append", required=True)
    parser.add_argument("--sources", type=Path, required=True)
    parser.add_argument("--curated", type=Path, action="append", default=[])
    parser.add_argument("--categorized-report", type=Path, action="append", default=[])
    parser.add_argument("--channel-categories", type=Path, action="append", default=[])
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--limit", type=int, default=1000)
    parser.add_argument("--per-channel", type=int, default=30)
    args = parser.parse_args()
    if args.limit < 1 or args.per_channel < 1:
        parser.error("--limit and --per-channel must be positive")
    categories = category_map(
        args.sources, args.curated, args.categorized_report, args.channel_categories
    )
    eligible, uncategorized = candidates_from_archives(args.archive, categories)
    queue = balanced_queue(eligible, args.limit, args.per_channel)
    report = {
        "newSources": {"candidates": queue},
        "pending": [],
        "intake": {
            "eligibleCategorizedVideos": len(eligible),
            "queuedVideos": len(queue),
            "queuedChannels": len({v["channel_id"] for v in queue}),
            "queuedByCategory": dict(collections.Counter(v["category"] for v in queue)),
            "uncategorizedChannels": len(uncategorized),
            "uncategorizedShortJapaneseVideos": sum(uncategorized.values()),
            "paidInferenceCalls": 0,
        },
    }
    write_json(args.output, report)
    print(json.dumps(report["intake"], ensure_ascii=False))


if __name__ == "__main__":
    main()
