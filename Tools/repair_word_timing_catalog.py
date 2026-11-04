#!/usr/bin/env python3
"""Audit, or explicitly repair, existing published word timing. Never print/store credentials."""
import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import plistlib
import threading
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]

def request_json(url, headers, body=None, timeout=240):
    request = urllib.request.Request(url, headers=headers,
        data=None if body is None else json.dumps(body).encode())
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.load(response)

def configuration():
    base, anon = os.environ.get("SUPABASE_URL"), os.environ.get("SUPABASE_ANON_KEY")
    if base and anon:
        return base.rstrip("/"), anon
    config = plistlib.loads((ROOT / "ios-nagare/Config/Secrets.plist").read_bytes())
    return (base or config["SUPABASE_URL"]).rstrip("/"), anon or config["SUPABASE_ANON_KEY"]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Run paid audio repair only with explicit --paid-ai")
    parser.add_argument("--paid-ai", action="store_true", help="Explicitly opt into paid inference; free processing uses repair_word_timing_local.py")
    parser.add_argument("--use-existing-vault", action="store_true", help="Explicitly authorize reading this project's maintenance credential into memory")
    parser.add_argument("--limit", type=int, default=3, help="Pilot size; 0 means all remaining clips")
    parser.add_argument("--workers", type=int, default=2)
    parser.add_argument("--id", action="append", default=[])
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if args.apply and not args.paid_ai:
        parser.error("--apply requires explicit --paid-ai; use Tools/repair_word_timing_local.py for zero-credit processing")
    base, anon = configuration()
    headers = {"apikey": anon, "Authorization": "Bearer " + anon, "Content-Type": "application/json"}
    clips = []
    offset = 0
    while True:
        page = request_json(base + "/rest/v1/clips?published=eq.true&select=id,video_id,lines&order=id&limit=500&offset=" + str(offset), headers)
        clips.extend(page)
        if len(page) < 500:
            break
        offset += len(page)
    pending = [clip for clip in clips if not clip["lines"] or any(
        line.get("timing") != "word" or line.get("translationReview", {}).get("wordTimingVerified") is not True
        for line in clip["lines"])]
    print(json.dumps({"published": len(clips), "independently_word_verified": len(clips) - len(pending), "needs_word_verification": len(pending)}), flush=True)
    if args.id:
        pending = [clip for clip in pending if clip["id"] in args.id]
    if not args.apply:
        return
    admin = os.environ.get("ADMIN_TOKEN")
    if not admin and args.use_existing_vault:
        project = base.split("//", 1)[1].split(".", 1)[0]
        pat = (Path.home() / ".supabase/access-token").read_text().strip()
        rows = request_json("https://api.supabase.com/v1/projects/" + project + "/database/query",
            {"Authorization": "Bearer " + pat, "Content-Type": "application/json"},
            {"query": "select decrypted_secret from vault.decrypted_secrets where name='admin_token' limit 1"})
        admin = rows[0]["decrypted_secret"] if rows else None
    if not admin:
        raise SystemExit("ADMIN_TOKEN or explicitly authorized --use-existing-vault is required")
    headers = {**headers, "x-admin-token": admin}
    selected = pending if args.limit == 0 else pending[:max(0, args.limit)]
    stopped = threading.Event()
    results = []
    def repair(clip):
        if stopped.is_set():
            return {"id": clip["id"], "status": "not_attempted"}
        try:
            response = request_json(base + "/functions/v1/review-catalog", headers,
                {"id": clip["id"], "apply": True, "repairTiming": True})
            return {"id": clip["id"], **{key: response[key] for key in ["status", "reason", "detail", "repairedWordLines"] if key in response}}
        except urllib.error.HTTPError as error:
            try:
                payload = json.loads(error.read())
            except (ValueError, UnicodeError):
                payload = {}
            if error.code in [401, 402, 403, 429, 500, 503]:
                stopped.set()
            return {"id": clip["id"], "status": "held", "http": error.code,
                "detail": str(payload.get("detail") or payload.get("error") or payload.get("message") or "Repair not approved")[:300]}
        except Exception as error:
            stopped.set()
            return {"id": clip["id"], "status": "held", "detail": type(error).__name__}
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, min(4, args.workers))) as executor:
        for result in executor.map(repair, selected):
            results.append(result)
            print(json.dumps(result), flush=True)
            if args.report:
                args.report.write_text(json.dumps(results, ensure_ascii=False, indent=2))
    print(json.dumps({"attempted": sum(row["status"] != "not_attempted" for row in results),
        "applied": sum(row["status"] == "applied" for row in results), "stopped": stopped.is_set()}), flush=True)

if __name__ == "__main__":
    main()
