# ingest-caption-clips

Admin Edge Function that publishes **caption-tier** clips built offline by
`Tools/build_caption_clips.py` (creator YouTube captions + local tokenization +
JMdict). No Gemini / OpenRouter spend.

## Auth

```
x-admin-token: <ADMIN_TOKEN>
```

## Body

```json
{
  "publish": true,
  "clips": [ /* objects from reports/caption-clips/caption_clips.json */ ]
}
```

Max 50 clips per request. The function re-stamps `translationReview` with
`version: "caption-1"` and a `databaseHash` from `catalog_review_hash`, then
upserts into `clips`. Publication requires the channel to be flagged
`catalog_sources.caption_tier_ok = true`.

## Run end to end

```
# 1. Which videos have creator ja+en tracks (YouTube Data API: videos.list caption flag,
#    then captions.list trackKind=standard). Costs ~1 unit / 50 videos + 50 units / video.
# 2. Build clips (yt-dlp subtitles, fugashi/UniDic, JMdict, alignment check):
python3 Tools/build_caption_clips.py --jobs jobs.json --max-per-video 8
# 3. Publish (reads SUPABASE_URL, SUPABASE_ANON_KEY, ADMIN_TOKEN from the environment):
python3 Tools/ingest_caption_clips.py ios-nagare/reports/caption-clips/caption_clips.json
```

`jobs.json` is a list of `{video_id, category, channel, title}`; `channel` must equal
the YouTube channel title stored in `catalog_sources.title`.

YouTube rate-limits subtitle downloads per IP (HTTP 429 / "confirm you're not a bot");
the builder caches tracks under `.tmp_probe/subs`, waits between videos and backs off.

## Mark a channel eligible

```sql
update public.catalog_sources
set caption_tier_ok = true
where handle in ('@SomeKidsChannel');
```
