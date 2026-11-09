#!/usr/bin/env python3
"""Prepare and publish explicitly reviewed local catalog work without hosted inference."""

import argparse
import fcntl
import hashlib
import json
import re
import subprocess
import sys
import urllib.error
from pathlib import Path

from authorized_media import AuthorizedMedia
from catalog_inventory import write_json
from publish_reviewed_local import reviewed_clip
from repair_word_timing_catalog import ROOT, configuration, request_json
from repair_word_timing_local import maintenance_headers

DEFAULT_REPORT = ROOT / "ios-nagare/reports/live-word-timing-repair-20261109.json"
QUOTA_REASONS = ("quotaExceeded", "dailyLimitExceeded")


def public_catalog(base, anon):
    rows = []
    headers = {"apikey": anon, "Authorization": "Bearer " + anon}
    for offset in range(0, 1_000_000, 500):
        page = request_json(
            base
            + "/rest/v1/clips?published=eq.true&select=id,video_id,timing_mode&order=id&limit=500&offset="
            + str(offset),
            headers,
        )
        rows.extend(page)
        if len(page) < 500:
            return rows
    raise ValueError("Public catalog pagination exceeded its safety bound")


def publish_batch(base, headers, clips, candidates):
    """Only called after the existing operator-review checks."""
    videos = sorted({c["video_id"] for c in clips})
    metadata = request_json(
        base + "/functions/v1/catalog-inventory",
        headers,
        {"action": "videos", "ids": videos},
    )
    verified = {v["video_id"]: v for v in metadata["videos"] if v["metadata_candidate"]}
    approved = {}
    for video_id in videos:
        candidate = candidates[video_id]
        if verified.get(video_id, {}).get("channel_id") == candidate["channel_id"]:
            approved[candidate["channel_id"]] = candidate
    if not approved:
        return dict(
            accepted=0, ids=[], rejected=[dict(reason="source_metadata_unavailable")]
        )
    endpoint = base + "/functions/v1/ingest-local-clips"
    response = request_json(
        endpoint,
        headers,
        {
            "action": "register",
            "sources": [
                dict(
                    channel_id=channel_id,
                    name=v["channel_name"],
                    category=v["category"],
                )
                for channel_id, v in approved.items()
            ],
        },
    )
    if any(
        any(reason in r.get("detail", "") for reason in QUOTA_REASONS)
        for r in response["sources"]
    ):
        raise RuntimeError("youtube_quota_exhausted")
    registered = {
        x["channel_id"] for x in response["sources"] if x["status"] == "resolved"
    }
    publishable = [
        c
        for c in clips
        if c["video_id"] in verified
        and candidates[c["video_id"]]["channel_id"]
        == verified[c["video_id"]]["channel_id"]
        and candidates[c["video_id"]]["channel_id"] in registered
    ]
    if not publishable:
        return dict(
            accepted=0, ids=[], rejected=[dict(reason="source_registration_incomplete")]
        )
    return request_json(endpoint, headers, {"clips": publishable}, timeout=180)


def run(args):
    root = args.state
    media_path = root / "authorized-media.json"
    reviews_path = root / "reviews.json"
    report = json.loads(args.report.read_text())
    candidates = {v["video_id"]: v for v in report["newSources"]["candidates"]}
    result = dict(
        paidInferenceCalls=0, timingProofsPrepared=0, newDraftsReady=0, published=0
    )
    media = AuthorizedMedia(media_path) if media_path.exists() else None
    reviews = json.loads(reviews_path.read_text()) if reviews_path.exists() else []
    if (media is None or not media.entries) and not reviews:
        return dict(result, status="waiting_for_authorized_media_or_review")

    base, anon = configuration()
    live = public_catalog(base, anon)
    live_ids = {c["id"] for c in live}
    live_videos = {c["video_id"] for c in live}
    live_line_ids = {c["id"] for c in live if c["timing_mode"] != "word"}
    proofs = root / "timing-proofs"
    drafts = root / "drafts"
    attempts_path = root / "attempted-media.json"
    attempts = json.loads(attempts_path.read_text()) if attempts_path.exists() else {}

    def unattempted(key, vid):
        try:
            file_stat = media.file_path(vid).stat()
        except FileNotFoundError:
            return None
        stamp = hashlib.sha256(
            json.dumps(
                (
                    media.entries[vid],
                    file_stat.st_size,
                    file_stat.st_mtime_ns,
                    file_stat.st_ino,
                ),
                sort_keys=True,
            ).encode()
        ).hexdigest()
        return stamp if attempts.get(key) != stamp else None

    if media is not None:
        targets = {
            c["id"]: stamp
            for c in report["pending"]
            if c["id"] in live_line_ids
            and c["videoId"] in media
            and (stamp := unattempted("timing:" + c["id"], c["videoId"]))
        }
        if targets:
            batch = list(targets)[: args.limit]
            cmd = [
                sys.executable,
                str(ROOT / "Tools/repair_word_timing_local.py"),
                "--authorized-media",
                str(media_path),
                "--media-directory",
                str(root / "audio"),
                "--report-directory",
                str(proofs),
                "--model-path",
                str(args.model_directory / "jojo-qwen-aligner-model"),
                "--device",
                "cpu",
                "--limit",
                str(args.limit),
            ]
            for cid in batch:
                cmd.extend(("--id", cid))
            subprocess.run(cmd, check=True)
            summary = (
                json.loads((proofs / "summary.json").read_text())
                if (proofs / "summary.json").exists()
                else []
            )
            for row in summary:
                if row["id"] in batch:
                    attempts["timing:" + row["id"]] = targets[row["id"]]
                    result["timingProofsPrepared"] += row["status"] == "aligned_locally"
            write_json(attempts_path, attempts)

        selected = {
            vid: stamp
            for vid in candidates
            if vid in media
            and vid not in live_videos
            and (stamp := unattempted("draft:" + vid, vid))
        }
        if selected:
            draft_batch = dict(list(selected.items())[: args.limit])
            write_json(root / "candidates.json", list(candidates.values()))
            write_json(
                root / "draft-queue.json",
                [dict(video_id=vid, status="held") for vid in draft_batch],
            )
            subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "Tools/repair_held_catalog.py"),
                    "--whisper-model",
                    str(args.model_directory / "jojo-whisper-turbo-model"),
                    "--translation-model",
                    str(args.model_directory / "jojo-ja-en-model"),
                    "--authorized-media",
                    str(media_path),
                    "--candidates",
                    str(root / "candidates.json"),
                    "--held-report",
                    str(root / "draft-queue.json"),
                    "--media-directory",
                    str(root / "audio"),
                    "--report-directory",
                    str(drafts),
                    "--device",
                    args.device,
                    "--resegment",
                    "--salvage-excerpt",
                ],
                check=True,
            )
            summary = (
                json.loads((drafts / "summary.json").read_text())
                if (drafts / "summary.json").exists()
                else []
            )
            for row in summary:
                if row["video_id"] in draft_batch:
                    attempts["draft:" + row["video_id"]] = draft_batch[row["video_id"]]
                    result["newDraftsReady"] += row["status"] == "ready_for_review"
            write_json(attempts_path, attempts)

    if not args.publish_reviewed:
        return dict(result, status="prepared")
    clips = []
    for review in reviews:
        cid, vid = review["id"], review["videoId"]
        if cid in live_ids or vid in live_videos or vid not in candidates:
            continue
        if not re.fullmatch(r"[A-Za-z0-9_-]+", cid) or (
            not isinstance(review.get("notes"), str) or not review["notes"].strip()
        ):
            raise ValueError(
                "Reviewed drafts require a valid clip ID and explicit review notes"
            )
        draft = json.loads((drafts / (cid + ".json")).read_text())
        if review.get("audioSha256") != draft["alignment"]["audioSha256"]:
            raise ValueError("The reviewed audio no longer matches the draft")
        if draft["category"] != candidates[vid]["category"]:
            raise ValueError("Reviewed draft category differs from the selected source")
        clips.append(reviewed_clip(draft, review))
        live_videos.add(vid)
        if len(clips) >= args.limit:
            break
    if not clips:
        return dict(result, status="waiting_for_review")
    headers = maintenance_headers(base, anon, args.use_existing_vault)
    try:
        receipt = publish_batch(base, headers, clips, candidates)
    except (urllib.error.HTTPError, RuntimeError) as exc:
        if isinstance(exc, urllib.error.HTTPError):
            try:
                reason = json.loads(exc.read()).get("error", "")
            except ValueError:
                reason = ""
            if not any(q in reason for q in QUOTA_REASONS):
                raise
        elif str(exc) != "youtube_quota_exhausted":
            raise
        return dict(result, status="youtube_quota_exhausted")
    write_json(root / "last-publication-receipt.json", receipt)
    return dict(result, status="publication_checked", published=receipt["accepted"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--device", choices=("cpu", "cuda"), default="cpu")
    parser.add_argument("--model-directory", type=Path, default=Path("/tmp"))
    parser.add_argument("--limit", type=int, choices=range(1, 6), default=5)
    parser.add_argument("--publish-reviewed", action="store_true")
    parser.add_argument("--use-existing-vault", action="store_true")
    args = parser.parse_args()
    args.state.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (args.state / "run.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print(json.dumps(dict(status="already_running", paidInferenceCalls=0)))
            return
        try:
            result = run(args)
        except Exception as exc:
            result = dict(
                status="failed", error=type(exc).__name__, paidInferenceCalls=0
            )
            write_json(args.state / "last-run.json", result)
            print(json.dumps(result), flush=True)
            raise SystemExit(1) from None
        write_json(args.state / "last-run.json", result)
        print(json.dumps(result), flush=True)


if __name__ == "__main__":
    main()
