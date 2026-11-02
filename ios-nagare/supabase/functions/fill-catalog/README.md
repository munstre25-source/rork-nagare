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

An administrator can also pass `{"videoIds":["YouTubeID", ...]}` to seed up to 50 exact source videos into the Japanese candidate queue. The function checks that they are public, embeddable, and 8–1800 seconds, then applies the regular Japanese speech, excerpt, transcript, and vocabulary checks before publication. This is a candidate seed, not a force-publish path.

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

One call keeps going until its time budget, the YouTube daily quota, or the Gemini daily cap. It prefers the thinnest level and searches short uploads on configured channels and other lanes, then checks public status, embedding and an 8–240 second source duration. For sources up to 120 seconds, Gemini prefers the whole meaningful spoken scene, up to 120 seconds; for longer sources it selects an 8–40 second exchange from each nonoverlapping 90-second window, up to 20 windows per source. Each window is queued and quality checked independently. The pipeline validates boundaries, speech density on long lessons, 2–80 spoken lines for short sources (2–24 for excerpts), and at least four tappable words. Transcript timestamps are stored relative to the lesson, with the original YouTube start offset. The app seeks to that offset and plays the lesson in the official YouTube player; no video file is downloaded or re-hosted. Difficulty is the model's Beginner / Intermediate / Advanced grade, or the average JLPT or TOPIK level of the words. A video `402` pauses both catalogs for two hours.

`fill-jojo-catalog` runs every 10 minutes. `fill-sori-catalog` runs at minutes 5, 15, 25, 35, 45, and 55. See the main README for secrets.

The Japanese job rotates through the configured anime, kids, variety, and learner channels by YouTube channel ID (resolving handles with `channels.list` where needed). Eleven hour-long playlist IDs are documented in `DEFERRED_SOURCES.md` and are not scheduled; short uploads from the supplied channels are the active priority. Before deployment, verify the candidate queue has `window_start_sec` in its primary key and `clips.category` accepts `learning` and `podcast`. The linked production schema already has both, although its migration history differs from the repository; do not run all pending migrations just to reconcile that history. A source being configured or queued does not mean any lesson is live; verify `published = true` clips and playback after the run.

For a live rollout, apply only explicitly reviewed migrations listed in ../../../HANDOFF-SIMULATOR.md (the current three are already applied; do not blindly push all historical pending migrations), deploy `fill-catalog` and `admin-dashboard`, then invoke `fill-catalog` with `{}` using the admin headers above. The scheduled job continues through the queued windows. In the SQL editor, check progress with:

```sql
select video_id, count(*) as live_lessons
from public.clips
where published = true and video_id in (
  'scLWToOqXzA', 'Hd6gAtt5BOU', 'TA-tUGtjils', 'ijzd6W09uB8',
  'RIKmx-R987A', 'e0acNvVwkWI', 'W3Rw3GsVjpo', 'nX8gk8OLb0U',
  'NhJJcAiZvFY', 'FZUIZYEwHp4', 'a9SBvpregYU'
)
group by video_id order by video_id;

select video_id, window_start_sec, category from public.catalog_candidate_queue
where video_id in ('scLWToOqXzA', 'Hd6gAtt5BOU', 'TA-tUGtjils')
order by video_id, window_start_sec;

select video_id, reason, detail from public.catalog_rejections
where video_id in ('scLWToOqXzA', 'Hd6gAtt5BOU', 'TA-tUGtjils')
order by rejected_at desc limit 30;
```

Also check `public.clips` for `channel_name ilike '%definitive%'` and play a published clip in the iOS simulator. A source over 30 minutes, a blocked embed, or a window without clear Japanese speech will not publish. The 2,000-lesson target is a growth goal, not a guaranteed yield from these sources.

Current Japanese publication uses policy 3: original-audio English/timing verification, burned-in English rejection, observed content/audience classification and a database seal. Discovery categories are hints; the reviewed category is stored. Kids requires child-directed content; podcasts have their own category. Pipeline history is visible in HQ. Legacy publication flags remain unchanged by explicit user instruction. Simulator/test playback evidence is excluded from production source-blocking decisions.
