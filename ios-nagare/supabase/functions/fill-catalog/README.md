# fill-catalog (admin)

```
POST {SUPABASE_URL}/functions/v1/fill-catalog
apikey: <SUPABASE_ANON_KEY>
Authorization: Bearer <SUPABASE_ANON_KEY>
x-admin-token: <ADMIN_TOKEN or CRON_FILL_TOKEN>
Content-Type: application/json

{}
```

`{}` publishes Japanese lessons into `clips`. `{"language":"ko"}` publishes Korean lessons into `sori_clips`.

An administrator can also pass `{"videoIds":["YouTubeID", ...]}` to seed up to 50 exact source videos into the Japanese candidate queue. The function checks that they are public, embeddable, and 20–180 seconds, then applies the regular Japanese speech, excerpt, transcript, and vocabulary checks before publication. This is a candidate seed, not a force-publish path.

Example request for the supplied Black Clover IDs:

```sh
curl -sS "$SUPABASE_URL/functions/v1/fill-catalog" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  -H "x-admin-token: $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"videoIds":["NmtDYd40i-Q","PtBmc0oFIx4","umzOm3846cA","4MYo8FfiXMA","VRDalljTlmA"]}'
```

The response's `queuedCandidates` reports how many passed the metadata gate and entered the queue; `clips` / `count` reports only lessons that passed the analysis and were published.

One call keeps going until its time budget, the YouTube daily quota, or the Gemini daily cap. It prefers the thinnest level and searches embeddable public source videos 12–180 seconds long. Gemini inspects each source and selects one self-contained exchange of 8–40 seconds, including absolute start/end offsets, and produces its transcript. The pipeline validates boundaries, requires 2–24 spoken lines and at least four tappable words, then stores transcript timestamps relative to the excerpt and the original YouTube start offset. The app seeks to that offset and plays the excerpt in the official YouTube player; no video file is downloaded or re-hosted. Difficulty is the model's Beginner / Intermediate / Advanced grade, or the average JLPT or TOPIK level of the words. A video `402` pauses both catalogs for two hours.

`fill-jojo-catalog` runs every 10 minutes. `fill-sori-catalog` runs at minutes 5, 15, 25, 35, 45, and 55. See the main README for secrets.

The Japanese job also rotates through the configured official anime channels by YouTube channel ID (resolving handles with `channels.list` where needed). Search results are still filtered to embeddable videos under four minutes and then checked to be 12–180 seconds before entering the queue.
