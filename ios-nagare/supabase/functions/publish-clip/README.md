# publish-clip (admin)

```
POST {SUPABASE_URL}/functions/v1/publish-clip
apikey: <SUPABASE_ANON_KEY>
Authorization: Bearer <SUPABASE_ANON_KEY>
x-admin-token: <ADMIN_TOKEN>
Content-Type: application/json

{ "id": "clip-id", "action": "publish" | "unpublish", "language": "ja" | "ko" }
```

`language` selects `clips` or `sori_clips`. `publish` refuses (422) if `lines` fail validation for that language. `unpublish` sets `published=false`.

## English word definitions

Japanese catalog publication checks every dictionary token. Upload tools fill gaps
from Jojo's offline dictionaries and preserve existing meanings, readings, sentence
translations and timing. The shared server publication step can make one bounded
gloss request under the existing model budget for words still missing from a clip.
Any unresolved tokens produce an actionable review result with line and token
positions. The local publishing route uses offline lookup and reviewed corrections.

To check a catalog export or prepare enriched drafts locally, run
`python3 Tools/catalog_word_definitions.py clips.json --output enriched-clips.json`.
The command runs locally and reports held clips. It exits with status 1 when
any definitions remain unresolved.
