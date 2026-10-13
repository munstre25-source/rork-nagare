# explain-word Edge Function

The app never talks to Gemini. It calls this function only:

```
POST {SUPABASE_URL}/functions/v1/explain-word
apikey: <SUPABASE_ANON_KEY>
Authorization: Bearer <SUPABASE_ANON_KEY>
x-app-user-id: <RevenueCat anonymous appUserID>
x-app-language: ja | ko
Content-Type: application/json

{ "kind": "lookup" | "context", "word": "食べる", "sentence": "コンビニでおにぎりを食べました。" }
```

Responses:

- `lookup` → `{ word, readings[], romaji, pos, conjugation_class, definitions[], ja_definitions[], formality_note, audio_hint }`
- `context` → `{ contextual_explanation, examples[], related_words[] }`

The server owns: one Gemini call through `GEMINI_API_KEY` (model from `GEMINI_MODEL_EXPLAIN`, default `google/gemini-2.5-flash`), a shared `word_explanations` cache keyed with `PROMPT_VERSION` (Korean keys are prefixed `ko|`), and a RevenueCat check for `x-app-user-id`. Japanese uses `nagare_learn_japanese_pro`. Korean (`x-app-language: ko`) uses `SORI_ENTITLEMENT_ID` (default `sori_pro`) and, when set, `SORI_REVENUECAT_SECRET_API_KEY`. Positive and negative results are cached a few minutes. Per-IP / per-JWT ingress limits run before any RevenueCat call, then per-user rate limits and the global daily Gemini cap.

When the request uses an authenticated Supabase user JWT, `x-app-user-id` must match `app_metadata.revenuecat_app_user_id`. Requests that still use the shared anon key skip that bind and rely on per-IP ingress limits.

Return 401/403 for no entitlement / bind failure and 429 when rate limited or over the global cap. The app silently falls back to local data on any non-2xx, network failure or its 12 s timeout.

See the main [README](../../../README.md#backend-edge-functions) for secrets and curl examples.
