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

## Mark a channel eligible

```sql
update public.catalog_sources
set caption_tier_ok = true
where handle in ('@SomeKidsChannel');
```
