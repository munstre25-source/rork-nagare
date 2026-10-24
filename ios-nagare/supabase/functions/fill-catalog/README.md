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

One call keeps going until its time budget, the YouTube daily quota, or the Gemini daily cap. It prefers the thinnest level and searches embeddable public source videos up to three minutes long. Gemini inspects each source and selects one self-contained exchange of 20–90 seconds, including absolute start/end offsets, and produces its transcript. The pipeline validates boundaries, requires 2–20 spoken lines and at least two defined words, then stores transcript timestamps relative to the excerpt and the original YouTube start offset. The app seeks to that offset and plays the excerpt in the official YouTube player; no video file is downloaded or re-hosted. Difficulty is the model's Beginner / Intermediate / Advanced grade, or the average JLPT or TOPIK level of the words. A video `402` pauses both catalogs for two hours.

`fill-jojo-catalog` runs every 10 minutes. `fill-sori-catalog` runs at minutes 5, 15, 25, 35, 45, and 55. See the main README for secrets.
