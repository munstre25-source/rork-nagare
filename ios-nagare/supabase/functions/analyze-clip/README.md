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

`startSec` and `endSec` are absolute times in the original YouTube video and must span 8–120 seconds. The row stores `startSec` as `source_start_sec`, stores the segment's length as `duration_sec`, and makes transcript/token times relative to that segment so playback and subtitles begin together. `language` is `ja` (default, table `clips`) or `ko` (table `sori_clips`). Does **not** scrape YouTube captions. One Gemini call transcribes and timestamps the words and returns readings, romaji, part of speech, and a level (`N5`–`N1`, or `TOPIK1`–`TOPIK6` for Korean). For Japanese, concise contextual word meanings are included in that same processing pass and stored with the timed tokens. Existing clips and rich explanations retain the cached `explain-word` fallback. A separate preprocessing review compares every English line with the original audio and checks grammar and meaning; unclear or unsupported lines are rejected, not guessed. This is a second metered model call for valid Japanese candidates. Learning modes render the same reviewed stored data on device and do not trigger processing. Japanese text must be mostly Japanese; Korean text must be mostly Hangul. Always inserts with `published=false`.
