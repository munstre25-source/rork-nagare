#!/usr/bin/env python3
"""POST caption-tier clips to the ingest-caption-clips Edge Function in batches.

Env (never hard-coded, never printed):
  SUPABASE_URL       https://<ref>.supabase.co
  SUPABASE_ANON_KEY  public anon key (functions require a JWT)
  ADMIN_TOKEN        must equal the function's ADMIN_TOKEN secret

Usage:
  python3 Tools/ingest_caption_clips.py ios-nagare/reports/caption-clips/caption_clips.json
  python3 Tools/ingest_caption_clips.py clips.json --limit 2 --dry-run
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path


def env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        sys.exit(f"Missing env {name}")
    return value


def post(url: str, anon: str, admin: str, clips: list[dict]) -> dict:
    req = urllib.request.Request(
        url,
        data=json.dumps({"publish": True, "clips": clips}, ensure_ascii=False).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {anon}",
            "apikey": anon,
            "x-admin-token": admin,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as err:
        return {"error": f"HTTP {err.code}: {err.read().decode('utf-8', 'replace')[:300]}"}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("clips", type=Path)
    parser.add_argument("--batch", type=int, default=20)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    clips = json.loads(args.clips.read_text(encoding="utf-8"))
    if args.limit:
        clips = clips[: args.limit]
    print(f"{len(clips)} clips from {args.clips}")
    if args.dry_run:
        return 0

    url = env("SUPABASE_URL").rstrip("/") + "/functions/v1/ingest-caption-clips"
    anon, admin = env("SUPABASE_ANON_KEY"), env("ADMIN_TOKEN")
    accepted = 0
    errors: list[dict] = []
    for i in range(0, len(clips), args.batch):
        result = post(url, anon, admin, clips[i : i + args.batch])
        if "error" in result:
            print(f"  batch {i // args.batch}: {result['error']}")
            errors.append({"batch": i // args.batch, "reason": result["error"]})
            continue
        accepted += result.get("accepted", 0)
        errors.extend(result.get("errors") or [])
        print(f"  batch {i // args.batch}: accepted {result.get('accepted')} rejected {result.get('rejected')}")
    print(f"Accepted {accepted}/{len(clips)}")
    for e in errors[:15]:
        print("  ", e)
    return 0 if accepted else 1


if __name__ == "__main__":
    sys.exit(main())
