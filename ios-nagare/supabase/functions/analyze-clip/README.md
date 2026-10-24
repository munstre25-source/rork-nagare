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
  "channelName": "Test",
  "language": "ja"
}
```

`startSec` and `endSec` are absolute times in the original YouTube video. The row stores `startSec` as `source_start_sec`, stores the selected segment's length as `duration_sec`, and makes transcript/token times relative to that segment so playback and subtitles begin together. `language` is `ja` (default, table `clips`) or `ko` (table `sori_clips`). Does **not** scrape YouTube captions. Gemini watches the YouTube URL and writes the words and timestamps, then the same `GEMINI_API_KEY` adds readings, meanings, and a level (`N5`–`N1`, or `TOPIK1`–`TOPIK6` for Korean). Those fields never replace the heard surfaces or times. Japanese text must be mostly Japanese; Korean text must be mostly Hangul. Always inserts with `published=false`.
