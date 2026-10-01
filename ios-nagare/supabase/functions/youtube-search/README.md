# youtube-search (admin)

```
POST {SUPABASE_URL}/functions/v1/youtube-search
apikey: <SUPABASE_ANON_KEY>
Authorization: Bearer <SUPABASE_ANON_KEY>
x-admin-token: <ADMIN_TOKEN>
Content-Type: application/json

{ "query": "日本語 会話", "maxResults": 5 }
```

Uses YouTube Data API `search.list` with `videoEmbeddable=true`, `videoDuration=short`, `regionCode=JP`, then verifies via `videos.list` (embeddable, public, duration ≤ 180s). Skips `video_id`s already in `clips`. Logs quota units and refuses above `YOUTUBE_QUOTA_DAILY_CAP` (default 8000).
