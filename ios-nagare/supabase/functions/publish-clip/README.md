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
