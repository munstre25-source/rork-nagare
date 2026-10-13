# youtube-search (admin)

```
POST {SUPABASE_URL}/functions/v1/youtube-search
apikey: <SUPABASE_ANON_KEY>
Authorization: Bearer <SUPABASE_ANON_KEY>
x-admin-token: <ADMIN_TOKEN>
Content-Type: application/json

{ "query": "日本語 会話", "maxResults": 5, "language": "ja" }
```

`language` `ko` searches with `regionCode=KR` and skips ids already in `sori_clips`. The default `ja` uses `regionCode=JP` and `clips`. Uses YouTube Data API `search.list` with `videoEmbeddable=true` and `videoDuration=short`, then verifies via `videos.list` (embeddable, public, duration ≤ 180s). Refuses above `YOUTUBE_QUOTA_DAILY_CAP` (default 8000), shared with the Korean catalog.
