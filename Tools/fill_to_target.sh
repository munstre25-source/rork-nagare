#!/bin/bash
# Run fill-catalog passes until the Japanese catalog reaches the target count.
# Publishing costs no YouTube search quota (1 unit per candidate check).
set -u
ANON=$(python3 -c "import json; print(json.load(open('/tmp/anon.json'))[0]['decrypted_secret'])")
ADMIN=$(python3 -c "import json; print(json.load(open('/tmp/admin.json'))[0]['decrypted_secret'])")
TARGET=${1:-100}
for i in $(seq 1 20); do
  COUNT=$(/tmp/q.sh <<'SQL' | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['count'])" 2>/dev/null
select count(*) from clips where published = true;
SQL
)
  echo "=== pass $i: published=$COUNT target=$TARGET"
  if [ "${COUNT:-0}" -ge "$TARGET" ]; then echo "target reached"; break; fi
  curl -s -X POST "https://jacpmygzmsfiyltdsiyu.supabase.co/functions/v1/fill-catalog" \
    -H "Authorization: Bearer $ANON" -H "x-admin-token: $ADMIN" \
    -H "Content-Type: application/json" -d '{}' --max-time 150 | head -c 400
  echo
  sleep 5
done
