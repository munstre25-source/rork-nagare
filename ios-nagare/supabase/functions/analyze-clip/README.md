# analyze-clip (admin)

```
POST {SUPABASE_URL}/functions/v1/analyze-clip
apikey: <SUPABASE_ANON_KEY>
Authorization: Bearer <SUPABASE_ANON_KEY>
x-admin-token: <ADMIN_TOKEN>
Content-Type: application/json

{
  "videoId": "xxxxxxxxxxx",
  "category": "drama",
  "difficulty": "Beginner",
  "startSec": 10,
  "endSec": 40,
  "title": "Test",
  "channelName": "Test"
}
```

Does **not** scrape YouTube captions. Sends the YouTube watch URL to Gemini (`GEMINI_MODEL_ANALYZE`) as video input with start/end offsets. Validates timestamps (strictly increasing, clamped), non-empty tokens, mostly-Japanese text, and enums. Always inserts with `published=false`.
