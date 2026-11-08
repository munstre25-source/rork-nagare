#!/usr/bin/env python3
"""Read-only, resumable full-channel inventory and recording-label resolution. No inference."""
import argparse
import collections
import concurrent.futures
import difflib
import hashlib
import html
import json
import re
import threading
import time
import unicodedata
import urllib.error
from pathlib import Path


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2))
    temporary.replace(path)


def normalize(value):
    return "".join(
        c
        for c in unicodedata.normalize("NFKC", html.unescape(value)).casefold()
        if c.isalnum()
    )


class InventoryClient:
    def __init__(self, output, use_vault, request_limit):
        from repair_word_timing_catalog import configuration
        from repair_word_timing_local import maintenance_headers

        self.base, anon = configuration()
        self.headers = maintenance_headers(self.base, anon, use_vault)
        self.output, self.limit = output, request_limit
        self.lock = threading.Lock()
        self.counts = collections.Counter()
        self.blocked = None
        self.search_blocked = None

    def call(self, body):
        from repair_word_timing_catalog import request_json

        action = body["action"]
        for attempt in range(2):
            with self.lock:
                if self.blocked:
                    raise RuntimeError(self.blocked)
                if action == "search_channels" and self.search_blocked:
                    raise RuntimeError(self.search_blocked)
                if sum(self.counts.values()) >= self.limit:
                    self.blocked = "Configured free metadata request budget reached; checkpoint retained"
                    raise RuntimeError(self.blocked)
                self.counts[action] += 1
                write_json(self.output / "request-counts.json", dict(self.counts))
            try:
                return request_json(
                    self.base + "/functions/v1/catalog-inventory",
                    self.headers,
                    body,
                    timeout=90,
                )
            except urllib.error.HTTPError as error:
                try:
                    detail = json.loads(error.read()).get(
                        "error", "Metadata request failed"
                    )
                except (ValueError, AttributeError):
                    detail = "Metadata request failed: HTTP " + str(error.code)
                if error.code == 429 and re.search(r"quota|dailyLimit", detail, re.I):
                    with self.lock:
                        if action == "search_channels":
                            self.search_blocked = detail
                        else:
                            self.blocked = detail
                    raise RuntimeError(detail) from None
                if (
                    attempt
                    or error.code not in (429, 502, 503, 504)
                    or detail.endswith("playlistNotFound")
                ):
                    raise RuntimeError(detail) from None
                time.sleep(2)


def scan_channel(channel, root, call):
    """Checkpoint whole pages after metadata validation; resume from exact cursors."""
    cid = channel["channel_id"]
    if not re.fullmatch(r"UC[A-Za-z0-9_-]{22}", cid):
        raise ValueError("Invalid canonical channel ID")
    page_token, index, seen_tokens = None, 0, set()
    records, listed_ids, missing_ids = {}, set(), set()
    status_path = root / "status" / (cid + ".json")
    try:
        while True:
            if page_token in seen_tokens:
                raise ValueError(
                    "Repeated uploads cursor; archive completeness cannot be claimed"
                )
            seen_tokens.add(page_token)
            path = root / "pages" / cid / (str(index).zfill(5) + ".json")
            if path.exists():
                page = json.loads(path.read_text())
                if (
                    page["channel_id"] != cid
                    or page["request_page_token"] != page_token
                ):
                    raise ValueError("Cached archive page identity/cursor mismatch")
            else:
                listed = call(
                    dict(
                        action="uploads",
                        channelId=cid,
                        **({"pageToken": page_token} if page_token else {})
                    )
                )
                ids = list(dict.fromkeys(r["video_id"] for r in listed["videos"]))
                metadata = (
                    call(dict(action="videos", ids=ids))
                    if ids
                    else dict(videos=[], missing=[])
                )
                for video in metadata["videos"]:
                    if video.get("channel_id") != cid:
                        video["metadata_candidate"] = False
                        video["exclusion_reasons"] = video.get(
                            "exclusion_reasons", []
                        ) + ["owner_channel_mismatch"]
                page = dict(
                    channel_id=cid,
                    request_page_token=page_token,
                    next_page_token=listed["nextPageToken"],
                    playlist_total=listed["playlist_total"],
                    listed_video_ids=ids,
                    missing_video_ids=metadata["missing"],
                    videos=metadata["videos"],
                )
                write_json(path, page)
            listed_ids.update(page["listed_video_ids"])
            missing_ids.update(page["missing_video_ids"])
            records.update((v["video_id"], v) for v in page["videos"])
            status = dict(
                channel_id=cid,
                title=channel["title"],
                public_upload_count=channel.get("public_upload_count"),
                pages=index + 1,
                listed_ids=len(listed_ids),
                metadata_returned=len(records),
                metadata_candidates=sum(
                    v["metadata_candidate"] for v in records.values()
                ),
                missing_ids=len(missing_ids - records.keys()),
                next_page_token=page["next_page_token"],
                complete=not bool(page["next_page_token"]),
            )
            write_json(status_path, status)
            if not page["next_page_token"]:
                return status
            page_token, index = page["next_page_token"], index + 1
    except Exception as error:
        status = (
            json.loads(status_path.read_text())
            if status_path.exists()
            else dict(channel_id=cid, title=channel["title"], pages=0)
        )
        status.update(complete=False, error=str(error))
        write_json(status_path, status)
        return status


def declared_japanese(video):
    language = video.get("declared_audio_language") or ""
    return re.split(r"[-_]", language.lower(), maxsplit=1)[0] == "ja"


def archive_summary(root, channels):
    selected = {c["channel_id"] for c in channels}
    records, listed, missing, states = {}, set(), set(), []
    for cid in sorted(selected):
        status = root / "status" / (cid + ".json")
        if status.exists():
            states.append(json.loads(status.read_text()))
        for p in sorted((root / "pages" / cid).glob("*.json")):
            page = json.loads(p.read_text())
            listed.update(page["listed_video_ids"])
            missing.update(page["missing_video_ids"])
            for video in page["videos"]:
                vid = video["video_id"]
                if vid not in records or video["channel_id"] == cid:
                    records[vid] = video
    candidates = [v for v in records.values() if v["metadata_candidate"]]
    counts = dict(
        channels_requested=len(selected),
        channels_completed=sum(s.get("complete", False) for s in states),
        reported_public_uploads=sum(c.get("public_upload_count", 0) for c in channels),
        unique_listed_videos=len(listed),
        metadata_returned=len(records),
        missing_video_ids=len(missing - records.keys()),
        metadata_candidates=len(candidates),
        declared_japanese_candidates=sum(declared_japanese(v) for v in candidates),
        unknown_audio_language_candidates=sum(
            not v.get("declared_audio_language") for v in candidates
        ),
        region_restricted_candidates=sum(
            bool(v.get("region_restriction")) for v in candidates
        ),
        candidates_at_most_180_seconds=sum(
            v["duration_sec"] <= 180 for v in candidates
        ),
        review_approved_lessons=0,
        paid_inference_calls=0,
        channels=states,
    )
    write_json(root / "archive-summary.json", counts)
    import gzip

    with gzip.open(
        root / "metadata-candidates.jsonl.gz", "wt", encoding="utf-8"
    ) as output:
        for row in sorted(
            candidates,
            key=lambda v: (v["channel_id"], v.get("published_at") or "", v["video_id"]),
        ):
            output.write(json.dumps(row, ensure_ascii=False) + "\n")
    return counts


def search_groups(rows, size=16, max_chars=950):
    group = []
    for row in rows:
        proposed = group + [row]
        query = "|".join('"' + r["label"].replace('"', "") + '"' for r in proposed)
        if group and (len(proposed) > size or len(query) > max_chars):
            yield group
            group = [row]
        else:
            group = proposed
    if group:
        yield group


def resolve_rows(rows, channels, include_suggestions=True):
    """Exact canonical name/observed alias matching only; fuzzy suggestions never auto-resolve."""
    by_id = {c["channel_id"]: c for c in channels}
    names = collections.defaultdict(set)
    handles = collections.defaultdict(set)
    normalized_titles = []
    for c in channels:
        title = normalize(c["title"])
        names[title].add(c["channel_id"])
        normalized_titles.append((title, c))
        if c.get("handle"):
            handles[normalize(c["handle"])].add(c["channel_id"])
    out = []
    for row in rows:
        result = {
            k: row[k]
            for k in [
                "id",
                "label",
                "observations",
                "confidence",
                "partial",
                "possibleTitle",
            ]
            if k in row
        }
        explicit = row.get("channelId")
        labels = {row["label"]} | {v["label"] for v in row.get("variants", [])}
        matches = set()
        for label in labels:
            key = normalize(label)
            if key:
                index = (
                    handles
                    if unicodedata.normalize("NFKC", label).lstrip().startswith("@")
                    else names
                )
                matches.update(index.get(key, ()))
        if explicit in by_id:
            result.update(
                status="resolved_previous_identity",
                channel_id=explicit,
                canonical_title=by_id[explicit]["title"],
            )
        elif row.get("partial") or row.get("possibleTitle"):
            result.update(
                status="needs_source_label_check", candidate_ids=sorted(matches)
            )
        elif len(matches) == 1:
            cid = next(iter(matches))
            result.update(
                status="resolved_exact_name",
                channel_id=cid,
                canonical_title=by_id[cid]["title"],
            )
        elif len(matches) > 1:
            result.update(status="ambiguous_exact_name", candidate_ids=sorted(matches))
        else:
            key = normalize(row["label"])
            suggestions = []
            if include_suggestions:
                suggestions = sorted(
                    (
                        (difflib.SequenceMatcher(None, key, title).ratio(), c)
                        for title, c in normalized_titles
                    ),
                    key=lambda x: -x[0],
                )[:3]
            result.update(
                status="unresolved_name",
                suggestions=[
                    dict(
                        channel_id=c["channel_id"],
                        title=c["title"],
                        similarity=round(score, 3),
                    )
                    for score, c in suggestions
                    if score >= 0.65
                ],
            )
        out.append(result)
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["archives", "resolve"])
    parser.add_argument("--channels", type=Path, required=True)
    parser.add_argument("--labels", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--use-existing-vault", action="store_true")
    parser.add_argument("--workers", type=int, default=6)
    parser.add_argument("--request-limit", type=int, default=9000)
    parser.add_argument("--search-limit", type=int, default=90)
    args = parser.parse_args()
    root = args.output
    root.mkdir(parents=True, exist_ok=True)
    channels = list(
        {c["channel_id"]: c for c in json.loads(args.channels.read_text())}.values()
    )
    client = InventoryClient(root, args.use_existing_vault, args.request_limit)
    if args.action == "archives":
        with concurrent.futures.ThreadPoolExecutor(
            max_workers=max(1, min(24, args.workers))
        ) as pool:
            futures = [
                pool.submit(scan_channel, c, root, client.call) for c in channels
            ]
            for future in concurrent.futures.as_completed(futures):
                status = future.result()
                print(json.dumps(status, ensure_ascii=False), flush=True)
        result = archive_summary(root, channels)
        print(
            json.dumps(
                {k: v for k, v in result.items() if k != "channels"}, ensure_ascii=False
            ),
            flush=True,
        )
        return
    if not args.labels:
        parser.error("--labels is required for resolution")
    rows = json.loads(args.labels.read_text())["channels"]
    known = {
        r["id"]
        for r in resolve_rows(rows, channels, include_suggestions=False)
        if r["status"].startswith("resolved")
    }
    pending = [r for r in rows if r["id"] not in known]
    groups = list(search_groups(pending))
    pool = {c["channel_id"]: c for c in channels}
    requests = 0
    for i, group in enumerate(groups):
        query = "|".join('"' + r["label"].replace('"', "") + '"' for r in group)
        target = (
            root / "search" / (hashlib.sha256(query.encode()).hexdigest() + ".json")
        )
        if target.exists():
            result = json.loads(target.read_text())
        else:
            if requests >= args.search_limit:
                break
            try:
                result = client.call(dict(action="search_channels", query=query))
            except RuntimeError as error:
                write_json(root / "search-block.json", dict(reason=str(error), group=i))
                break
            requests += 1
            write_json(target, result)
        for c in result["channels"]:
            pool.setdefault(c["channel_id"], c)
        print(
            json.dumps(
                dict(
                    search_group=i + 1,
                    groups=len(groups),
                    candidate_channels=len(pool),
                    paidInferenceCalls=0,
                )
            ),
            flush=True,
        )
    details = {c["channel_id"]: c for c in channels}
    ids = [cid for cid in pool if cid not in details]
    for i in range(0, len(ids), 50):
        selected = ids[i : i + 50]
        path = (
            root
            / "channel-details"
            / (
                hashlib.sha256(",".join(sorted(selected)).encode()).hexdigest()
                + ".json"
            )
        )
        try:
            result = (
                json.loads(path.read_text())
                if path.exists()
                else client.call(dict(action="channels", ids=selected))
            )
        except RuntimeError as error:
            write_json(root / "details-block.json", dict(reason=str(error)))
            break
        write_json(path, result)
        for c in result["channels"]:
            details[c["channel_id"]] = c
    resolved = resolve_rows(rows, list(details.values()))
    selected = {r["channel_id"] for r in resolved if r["status"].startswith("resolved")}
    canonical = [c for cid, c in details.items() if cid in selected]
    write_json(
        root / "label-resolution.json",
        dict(
            labels=resolved,
            status_counts=dict(collections.Counter(r["status"] for r in resolved)),
            distinct_resolved_channels=len(canonical),
            paidInferenceCalls=0,
        ),
    )
    write_json(root / "resolved-channels.json", canonical)
    write_json(root / "candidate-channel-details.json", list(details.values()))
    print(
        json.dumps(
            dict(
                distinct_resolved_channels=len(canonical),
                labels=len(resolved),
                public_uploads=sum(c.get("public_upload_count", 0) for c in canonical),
                status_counts=dict(collections.Counter(r["status"] for r in resolved)),
                paidInferenceCalls=0,
            )
        ),
        flush=True,
    )


if __name__ == "__main__":
    main()
