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

One call keeps going until its time budget, the YouTube daily quota, or the Gemini daily cap. It prefers the thinnest level, walks YouTube pages it has not published, and keeps a clip only when Gemini returns one everyday exchange (2–4 lines, about 6–24 seconds) with definitions. Difficulty is the model's Beginner / Intermediate / Advanced grade, or the average JLPT or TOPIK level of the words. A video `402` pauses both catalogs for two hours.

`fill-jojo-catalog` runs every 10 minutes. `fill-sori-catalog` runs at minutes 5, 15, 25, 35, 45, and 55. See the main README for secrets.
