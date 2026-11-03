#!/usr/bin/env python3
"""Apply current policy-v3 translation review to live clips missing a valid receipt.

Calls review-catalog with apply=true. Uses whatever AI_PROVIDER_ORDER the project
has configured (prefer google,openrouter so reviews stay on the free Gemini key).

Env: SUPABASE_URL, SUPABASE_ANON_KEY, ADMIN_TOKEN

Usage:
  python3 Tools/batch_review_catalog.py --limit 5
  python3 Tools/batch_review_catalog.py --dry-run
  python3 Tools/batch_review_catalog.py --quarantine   # unpublish on unsupported
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request


def env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        sys.exit(f"Missing env {name}")
    return value


def post(url: str, anon: str, admin: str, body: dict) -> tuple[int, dict]:
    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode(),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {anon}",
            "apikey": anon,
            "x-admin-token": admin,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            return resp.status, json.load(resp)
    except urllib.error.HTTPError as err:
        try:
            payload = json.loads(err.read().decode("utf-8", "replace") or "{}")
        except Exception:
            payload = {"error": f"HTTP {err.code}"}
        return err.code, payload if isinstance(payload, dict) else {"error": str(payload)}


def list_needing_review(base: str, anon: str, admin: str) -> list[str]:
    """Use admin-pipeline live inventory filtered to needs_review."""
    ids: list[str] = []
    page = 0
    while True:
        url = (
            f"{base}/functions/v1/admin-pipeline"
            f"?view=live&status=needs_review&page={page}"
        )
        req = urllib.request.Request(
            url,
            headers={
                "Authorization": f"Bearer {anon}",
                "apikey": anon,
                "x-admin-token": admin,
            },
        )
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.load(resp)
        items = data.get("items") or []
        ids.extend(item["id"] for item in items if item.get("id"))
        total = int(data.get("total") or 0)
        page_size = int(data.get("page_size") or 50)
        if (page + 1) * page_size >= total or not items:
            break
        page += 1
    return ids


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=0, help="Max clips to review (0 = all)")
    parser.add_argument("--delay", type=float, default=2.0, help="Seconds between reviews")
    parser.add_argument("--quarantine", action="store_true",
                        help="Unpublish clips the review rejects as unsupported")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--id", action="append", default=[], help="Review only these clip ids")
    args = parser.parse_args()

    base = env("SUPABASE_URL").rstrip("/")
    anon, admin = env("SUPABASE_ANON_KEY"), env("ADMIN_TOKEN")
    ids = args.id or list_needing_review(base, anon, admin)
    if args.limit:
        ids = ids[: args.limit]
    print(f"{len(ids)} clips to review")
    if args.dry_run:
        for clip_id in ids[:20]:
            print(" ", clip_id)
        if len(ids) > 20:
            print(f"  … and {len(ids) - 20} more")
        return 0

    url = base + "/functions/v1/review-catalog"
    ok = fail = held = 0
    for i, clip_id in enumerate(ids):
        if i:
            time.sleep(args.delay)
        status, result = post(url, anon, admin, {
            "id": clip_id,
            "apply": True,
            "quarantine": args.quarantine,
        })
        state = result.get("status") or result.get("error") or f"HTTP {status}"
        reason = result.get("reason") or ""
        detail = (result.get("detail") or "")[:120]
        if status == 200 and state in {"applied", "reviewed"}:
            ok += 1
            mark = "ok"
        elif status in {402, 429}:
            print(f"  STOP {clip_id}: {state} {reason} {detail}".strip())
            break
        elif state in {"needs_review", "reviewed_pending_apply"} or status >= 400:
            fail += 1
            mark = "fail"
        else:
            held += 1
            mark = "held"
        print(f"  [{i + 1}/{len(ids)}] {mark} {clip_id}: {state}"
              + (f" · {reason}" if reason else "")
              + (f" · {detail}" if detail else ""))
    print(f"Done: applied {ok}, failed {fail}, other {held}")
    return 0 if fail == 0 or ok > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
