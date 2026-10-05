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

Does **not** scrape YouTube captions. Gemini watches the YouTube URL and writes the words and timestamps. OpenRouter then adds readings, meanings, and JLPT. Those fields never replace the heard surfaces or times. Always inserts with `published=false`.
