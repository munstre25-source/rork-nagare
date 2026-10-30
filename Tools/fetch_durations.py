#!/usr/bin/env python3
"""Fetch real durations for queued candidates by scraping watch pages (no API quota)."""
import json, re, subprocess, sys

rows = json.load(open('/tmp/queue_rows.json'))
COOKIES = "SOCS=CAI; CONSENT=YES+cb.20210328-17-p0.en+FX+419; PREF=hl=ja"
out = {}
for i, r in enumerate(rows):
    vid = r['video_id']
    try:
        html = subprocess.run(
            ["curl", "-s", f"https://www.youtube.com/watch?v={vid}&hl=ja",
             "-H", "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
             "-H", f"Cookie: {COOKIES}", "--max-time", "20"],
            capture_output=True, text=True, timeout=30).stdout
    except Exception:
        continue
    m = re.search(r'"lengthSeconds":"(\d+)"', html)
    if not m:
        m = re.search(r'"approxDurationMs":"(\d+)"', html)
        if m: out[vid] = int(m.group(1)) // 1000
        continue
    out[vid] = int(m.group(1))
    if (i + 1) % 10 == 0: print(f"{i+1} done", flush=True)

json.dump(out, open('/tmp/durations.json', 'w'))
print(len(out), 'durations fetched of', len(rows))
