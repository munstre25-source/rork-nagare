#!/bin/bash
# Collect Japanese-learning YouTube candidates for the catalog queue (no API quota:
# scrapes public search-result pages with the consent bypass cookie).
set -u
OUT=/tmp/candidates.jsonl
: > $OUT

declare -a LANES=(
  "interview|Beginner|日本語 街頭インタビュー ショート"
  "interview|Beginner|日本語 街頭インタビュー 会話"
  "interview|Advanced|日本語 インタビュー 会話 ショート"
  "drama|Beginner|コンビニ カフェ 注文 日本語 会話 ショート"
  "drama|Beginner|日本語 会話 スキット ショート"
  "drama|Advanced|日本語 ドラマ セリフ ショート"
  "variety|Intermediate|日本語 あるある トーク ショート"
  "variety|Intermediate|バラエティ 日本語 トーク 切り抜き ショート"
  "kids|Beginner|子供向け 日本語 あいさつ 会話 ショート"
  "kids|Beginner|こども 日本語 ひらがな 会話"
  "anime|Beginner|日本語 アニメ 日常会話 ショート"
  "anime|Intermediate|アニメ セリフ 日本語 ショート"
  "anime|Beginner|アニメ 切り抜き 日本語 会話"
  "vtuber|Intermediate|日本語 VTuber 雑談 ショート"
  "vtuber|Intermediate|VTuber 切り抜き 雑談 日本語"
  "gaming|Intermediate|日本語 マイクラ 実況 会話 ショート"
  "gaming|Intermediate|ゲーム実況 日本語 会話 ショート"
  "food|Beginner|日本語 ラーメン 屋台 会話 ショート"
  "travel|Beginner|日本語 旅行 会話 ショート 観光"
)

for lane in "${LANES[@]}"; do
  IFS='|' read -r category difficulty query <<< "$lane"
  eq=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$query")
  curl -s "https://www.youtube.com/results?search_query=$eq&sp=CAMSAhAB" \
    -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15" \
    -H "Cookie: SOCS=CAI; CONSENT=YES+cb.20210328-17-p0.en+FX+419; PREF=hl=ja" \
    --max-time 30 > /tmp/lane.html
  python3 - "$category" "$difficulty" "$query" <<'PY' >> $OUT
import json, re, sys
category, difficulty, query = sys.argv[1:4]
html = open('/tmp/lane.html', encoding='utf-8', errors='replace').read()
# Each video renderer block carries id, title, length
blocks = re.split(r'"videoRenderer":', html)
seen = set()
for b in blocks[1:]:
    m = re.search(r'"videoId":"([A-Za-z0-9_-]{11})"', b)
    if not m: continue
    vid = m.group(1)
    t = re.search(r'"title":\{"runs":\[\{"text":"(.*?)"\}', b)
    title = t.group(1) if t else ''
    dur = None
    d = re.search(r'"lengthText":\{[^}]*"simpleText":"(\d+):(\d+)"', b)
    if d:
        dur = int(d.group(1)) * 60 + int(d.group(2))
    else:
        d = re.search(r'"thumbnailOverlayTimeStatusRenderer":\{"text":\{"simpleText":"(\d+):(\d+)"', b)
        if d: dur = int(d.group(1)) * 60 + int(d.group(2))
    if vid in seen: continue
    seen.add(vid)
    print(json.dumps({
        "video_id": vid, "title": title[:140], "duration_sec": dur,
        "category": category, "difficulty": difficulty, "query": query,
    }, ensure_ascii=False))
PY
  sleep 2
done

python3 - <<'PY'
import json
existing = set(open('/tmp/existing.txt').read().split())
rows = [json.loads(l) for l in open('/tmp/candidates.jsonl')]
seen, fresh = set(), []
for r in rows:
    v = r['video_id']
    if v in existing or v in seen: continue
    seen.add(v)
    fresh.append(r)
json.dump(fresh, open('/tmp/fresh.json','w'), ensure_ascii=False, indent=1)
print(len(fresh), 'fresh candidates of', len(rows), 'scraped')
from collections import Counter
print(Counter((r['category'], r['difficulty']) for r in fresh))
PY
