#!/usr/bin/env python3
"""Repair existing live catalog timing using local compute; zero paid inference calls."""
import argparse
import json
import os
from pathlib import Path
import re
import urllib.error
from local_word_alignment import LocalAligner
from repair_word_timing_catalog import configuration, request_json


def source_audio(clip, directory, sources):
    import hashlib
    import soundfile as sf
    from source_audio import extract_source_window
    video_id = clip["video_id"]
    if not re.fullmatch(r"[A-Za-z0-9_-]{11}", video_id):
        raise ValueError("Invalid source video ID")
    directory.mkdir(parents=True, exist_ok=True)
    identity = {"videoId": video_id, "sourceStartSec": float(clip.get("source_start_sec") or 0),
                "durationSec": float(clip["duration_sec"])}
    key = hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()
    cached = directory / (key + ".wav")
    if cached.exists():
        audio, rate = sf.read(cached, dtype="float32")
        if rate != 16000 or audio.ndim != 1:
            raise ValueError("Cached source audio format mismatch")
        return audio
    if video_id not in sources:
        from yt_dlp import YoutubeDL
        options = {"noplaylist": True, "quiet": True, "no_warnings": True,
                   "retries": 1, "socket_timeout": 30}
        with YoutubeDL(options) as downloader:
            sources[video_id] = downloader.extract_info("https://www.youtube.com/watch?v=" + video_id, download=False)
    audio, byte_count = extract_source_window(sources[video_id], identity["sourceStartSec"], identity["durationSec"])
    # Write only complete, timestamp-checked clip audio. Never cache signed source URLs.
    temporary = cached.with_suffix(".partial.wav")
    sf.write(temporary, audio, 16000, subtype="FLOAT")
    temporary.replace(cached)
    (directory / (key + ".json")).write_text(json.dumps({**identity, "bytesFetched": byte_count}))
    return audio


def maintenance_headers(base, anon, use_vault):
    headers = {"apikey": anon, "Authorization": "Bearer " + anon, "Content-Type": "application/json"}
    admin = os.environ.get("ADMIN_TOKEN")
    if not admin and use_vault:
        project = base.split("//", 1)[1].split(".", 1)[0]
        pat = (Path.home() / ".supabase/access-token").read_text().strip()
        rows = request_json("https://api.supabase.com/v1/projects/" + project + "/database/query",
            {"Authorization": "Bearer " + pat, "Content-Type": "application/json"},
            {"query": "select decrypted_secret from vault.decrypted_secrets where name='admin_token' limit 1"})
        admin = rows[0]["decrypted_secret"] if rows else None
    if not admin:
        raise ValueError("ADMIN_TOKEN or explicitly authorized --use-existing-vault is required for --apply")
    return {**headers, "x-admin-token": admin}


def needs_alignment(clip):
    return not clip["lines"] or any(line.get("timing") != "word" or not (
        line.get("translationReview", {}).get("wordTimingVerified") is True or
        line.get("translationReview", {}).get("localAlignment", {}).get("version") == 1
    ) for line in clip["lines"])


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--apply", action="store_true")
    p.add_argument("--use-existing-vault", action="store_true")
    p.add_argument("--id", action="append", default=[])
    p.add_argument("--limit", type=int, default=3, help="0 processes all remaining live clips")
    p.add_argument("--media-directory", type=Path, required=True)
    p.add_argument("--report-directory", type=Path, required=True)
    p.add_argument("--model-path", default="Qwen/Qwen3-ForcedAligner-0.6B")
    p.add_argument("--device", default="cpu")
    args = p.parse_args()
    base, anon = configuration()
    headers = {"apikey": anon, "Authorization": "Bearer " + anon, "Content-Type": "application/json"}
    clips, offset = [], 0
    while True:
        rows = request_json(base + "/rest/v1/clips?published=eq.true&select=id,video_id,source_start_sec,duration_sec,lines&order=id&limit=500&offset=" + str(offset), headers)
        clips.extend(rows)
        if len(rows) < 500: break
        offset += len(rows)
    pending = [c for c in clips if needs_alignment(c) and (not args.id or c["id"] in args.id)]
    selected = pending if args.limit == 0 else pending[:max(0, args.limit)]
    print(json.dumps({"published": len(clips), "pending": len(pending), "selected": len(selected), "paidApiCalls": 0}), flush=True)
    if not selected: return
    if args.apply: headers = maintenance_headers(base, anon, args.use_existing_vault)
    args.report_directory.mkdir(parents=True, exist_ok=True)
    aligner = LocalAligner(args.model_path, args.device)
    results, sources = [], {}
    for clip in selected:
        result = {"id": clip["id"], "status": "held"}
        stop = False
        try:
            audio = source_audio(clip, args.media_directory, sources)
            alignment = aligner.align(clip, audio)
            # This is subtitle/timestamp data only; credentials never go into reports.
            safe_id = re.sub(r"[^A-Za-z0-9_.-]", "_", clip["id"])
            (args.report_directory / (safe_id + ".json")).write_text(json.dumps(alignment, ensure_ascii=False, indent=2))
            if args.apply:
                response = request_json(base + "/functions/v1/review-catalog", headers,
                    {"id": clip["id"], "apply": True, "expectedLines": clip["lines"], "localAlignment": alignment})
                result.update({k: response[k] for k in ["status", "method", "repairedWordLines", "paidApiCalls"] if k in response})
            else: result["status"] = "aligned_locally"
        except urllib.error.HTTPError as error:
            # Never print request headers, credentials or signed media URLs.
            result.update(http=error.code, reason="remote_request_rejected")
            stop = error.code in (401, 403, 429, 500, 503)
        except ValueError as error:
            result["reason"] = str(error)[:180]
        except Exception as error:
            result["reason"] = type(error).__name__
        results.append(result)
        (args.report_directory / "summary.json").write_text(json.dumps(results, ensure_ascii=False, indent=2))
        print(json.dumps(result), flush=True)
        if stop: break
    print(json.dumps({"processed": len(results), "applied": sum(r["status"] == "applied" for r in results),
                      "held": sum(r["status"] == "held" for r in results), "paidApiCalls": 0}), flush=True)


if __name__ == "__main__":
    main()
