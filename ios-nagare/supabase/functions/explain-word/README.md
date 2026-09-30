# explain-word Edge Function (contract)

The app never talks to Gemini. It calls this function only:

```
POST {SUPABASE_URL}/functions/v1/explain-word
apikey: <SUPABASE_ANON_KEY>
Authorization: Bearer <SUPABASE_ANON_KEY>
x-app-user-id: <RevenueCat anonymous appUserID>
Content-Type: application/json

{ "kind": "lookup" | "context", "word": "食べる", "sentence": "コンビニでおにぎりを食べました。" }
```

Responses:

- `lookup` → `{ word, readings[], romaji, pos, conjugation_class, definitions[], formality_note, audio_hint }`
- `context` → `{ contextual_explanation, examples[], related_words[] }`

The server owns: the Gemini 2.5 Flash Lite call and key, a shared cache, verifying the
`pro` entitlement for `x-app-user-id` via the RevenueCat REST API, and per-user rate limiting.
Return 401/403 for no entitlement and 429 when rate limited. The app silently falls back to local data
on any non-2xx, network failure or its 2.5 s timeout.
