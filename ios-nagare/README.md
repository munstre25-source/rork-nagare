# Nagare 流れ — Scroll, Listen, Flow into Japanese

Native SwiftUI (iOS 17+), SwiftData, Observation, Swift concurrency. The only third-party package is
RevenueCat (`purchases-ios-spm`). Supabase is called over plain URLSession. Gemini is only reached
through the Supabase Edge Function, so there is no Gemini key in the app.

## Secrets
Copy `Config/Secrets.example.plist` to `Jojo/Config/Secrets.plist` (it's gitignored and picked up by the
synchronized target folder), then fill in:
- `SUPABASE_URL`: e.g. `https://xxxx.supabase.co`
- `SUPABASE_ANON_KEY`
- `REVENUECAT_API_KEY`: the public iOS SDK key (`appl_…`)

Any value still starting with `YOUR_` is treated as not configured, and the app runs fully offline.

## Record marketing videos (screen recording)
DEBUG only. From splash debug buttons, or **Profile → Debug · Marketing**.

**Five scripts** (record each as its own cut):

1. **Sakura dark neon** — core For You story  
2. **Sakura dark** (glow off) — same story  
3. **Amber dark neon** — same story  
4. **Amber dark** (glow off) — same story  
5. **Full app tour** — onboarding → For You → Vocab → Explore → Library → Profile, then every look (Sakura/Amber × dark neon / dark / light)

Core story beats (videos 1–4): For You scrolls **3 clips**, normal→maximum video, word tap → dictionary + paint ladder → save fly animation → flashcard Again/Good.

1. Start Simulator/device screen recording.
2. Open the script and tap **Begin …**.
3. Stop when **Showcase finished** appears. Trim outside the app.

## Adding clips
The study feed only plays clips whose transcript was taken from the video (`id` starts with `immersion-`).
`Tools/generate_seed.py` refreshes the dictionary and debug vocab. It does not rewrite `SeedClips.json`.
New clips come from `fill-catalog`. Gemini selects one complete, self-contained 20–90 second exchange from each eligible source video, returns exact source offsets and the timed transcript, and the pipeline rejects invalid or incomplete excerpts. The app plays only that excerpt in the official YouTube player, with its transcript-relative timestamps, English translation, and tappable vocabulary. It does not download or re-host the video.

## Optional local clip overrides
You can place `Jojo/Resources/Clips/{clip.id}.mp4` to force AVPlayer for a specific clip (useful if
YouTube embeds fail in a given environment). Leave this empty for normal YouTube playback.
`ClipPlayerFactory` order: local file (if present) → YouTube → simulated poster.

Clips with a real ID and no local file use `YouTubeClipPlayer` (WKWebView + official IFrame API).
Everything else uses `SimulatedClipPlayer` (animated gradient poster, karaoke cursor, ja-JP narration).
YouTube video is never re-hosted.

## Supabase
- Clip library: apply migrations from **`ios-nagare/`** (see below). Jojo GETs `/rest/v1/clips?published=eq.true&select=*`. The Korean app reads `/rest/v1/sori_clips` on the same project. Each app syncs in the background at launch and every 30 minutes, then merges rows by `id` into SwiftData. Bundled verified clips stay available offline. A remote row replaces the bundle when the id matches. Rows that are no longer published are dropped on the next sync.
- Word explanations: `POST /functions/v1/explain-word`. See `supabase/functions/explain-word/README.md`.
  Lookup order: seed token → local dictionary → SwiftData cache → Edge Function (12 s timeout) → static fallback.
  Live calls are logged locally (`WordExplainService.stats()`: today/total count, average latency).

## Backend Edge Functions

Run all Supabase CLI commands from the **`ios-nagare/`** directory (not the repo root):

```bash
cd ios-nagare
supabase db push
supabase functions deploy explain-word youtube-search analyze-clip publish-clip fill-catalog
supabase secrets set \
  GEMINI_API_KEY=… \
  YOUTUBE_API_KEY=… \
  ADMIN_TOKEN=… \
  REVENUECAT_SECRET_API_KEY=…
```

### Secrets you must set

| Name | Required | Purpose |
|------|----------|---------|
| `GEMINI_API_KEY` | yes | Only model key. Transcription, translation, dictionary enrichment, and word explanations all use it. An `sk-or-` value calls Gemini through OpenRouter (Google AI Studio only). Any other value calls Gemini directly. |
| `YOUTUBE_API_KEY` | yes | YouTube Data API for `youtube-search` |
| `ADMIN_TOKEN` | yes | Admin functions (`x-admin-token`, compared constant-time) |
| `REVENUECAT_SECRET_API_KEY` | yes | Entitlement checks for `explain-word` |
| `CRON_FILL_TOKEN` | for the timer | Alternate admin header the catalog jobs send. The first successful `fill-catalog` call stores it in Vault. |
| `SORI_REVENUECAT_SECRET_API_KEY` | no | Korean entitlement secret. Falls back to `REVENUECAT_SECRET_API_KEY`. |
| `SORI_ENTITLEMENT_ID` | no | Korean entitlement id. Default `sori_pro`. |

Platform-provided (usually already present in Edge Functions): `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ANON_KEY`.

Optional limit / version envs:

| Name | Default | Purpose |
|------|---------|---------|
| `EXPLAIN_LOOKUP_DAILY_LIMIT` | `80` | Per-user lookup calls / UTC day |
| `EXPLAIN_CONTEXT_DAILY_LIMIT` | `40` | Per-user context calls / UTC day |
| `GEMINI_GLOBAL_DAILY_CAP` | `2000` | Global Gemini calls / UTC day |
| `YOUTUBE_QUOTA_DAILY_CAP` | `8000` | YouTube quota units / UTC day |
| `REVENUECAT_CACHE_TTL_SEC` | `300` | Entitlement cache TTL (positive and negative) |
| `PROMPT_VERSION` | `3` | Bumped into explanation cache keys |
| `GEMINI_MODEL_EXPLAIN` | `google/gemini-2.5-flash` | Model for word explanations and dictionary enrichment |
| `GEMINI_MODEL_ANALYZE` | `google/gemini-2.5-flash` | Model for `analyze-clip` and `fill-catalog` |
| `EXPLAIN_INGRESS_IP_PER_MINUTE` | `60` | Pre-RC per-IP requests / minute |
| `EXPLAIN_INGRESS_JWT_PER_MINUTE` | `30` | Pre-RC per authenticated JWT sub / minute |

Admin functions require the **anon key** (`apikey` + `Authorization: Bearer`) **and** `x-admin-token`. Never log secrets or tokens.

### Curl smoke tests

```bash
# explain-word (needs a RevenueCat app user with nagare_learn_japanese_pro)
curl -sS "$SUPABASE_URL/functions/v1/explain-word" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  -H "x-app-user-id: $RC_APP_USER_ID" \
  -H "Content-Type: application/json" \
  -d '{"kind":"lookup","word":"食べる","sentence":"コンビニでおにぎりを食べました。"}'

# youtube-search (admin)
curl -sS "$SUPABASE_URL/functions/v1/youtube-search" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  -H "x-admin-token: $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query":"日本語 会話","maxResults":5}'

# analyze-clip (admin) — Gemini watches the YouTube window; always published=false.
# Add "language":"ko" to write sori_clips. Anything else writes clips.
curl -sS "$SUPABASE_URL/functions/v1/analyze-clip" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  -H "x-admin-token: $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"videoId":"xxxxxxxxxxx","category":"drama","difficulty":"Beginner","startSec":10,"endSec":28,"title":"Test","channelName":"Test"}'

# publish-clip (admin) — refuses publish if lines fail validation
curl -sS "$SUPABASE_URL/functions/v1/publish-clip" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  -H "x-admin-token: $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"id":"clip-id","action":"publish","language":"ja"}'

# unpublish
curl -sS "$SUPABASE_URL/functions/v1/publish-clip" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  -H "x-admin-token: $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"id":"clip-id","action":"unpublish"}'

# fill-catalog (admin) — publish lesson clips until the time budget or a daily cap.
# {} writes Japanese clips. {"language":"ko"} writes sori_clips.
curl -sS "$SUPABASE_URL/functions/v1/fill-catalog" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  -H "x-admin-token: $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}'
```

## Keeping the feed stocked

`fill-catalog` searches YouTube for a public, embeddable source video up to three minutes long that is not already in the catalog. Gemini selects one coherent 20–90 second exchange, returns its absolute start/end times and a timed transcript, and the function validates the clip boundaries, dialogue, and vocabulary before publishing. Transcript times are stored relative to the excerpt; `source_start_sec` tells the app where to seek in the original YouTube video. Japanese rows go in `clips` with ids `immersion-…`. Korean rows go in `sori_clips` with ids `sori-…` and TOPIK levels `TOPIK1`–`TOPIK6`. Both catalogs share `YOUTUBE_QUOTA_DAILY_CAP` and `GEMINI_GLOBAL_DAILY_CAP`. A run stops on those caps. A Gemini video `402` pauses searching for two hours so the timer does not spend YouTube quota.

Two pg_cron jobs call it: `fill-jojo-catalog` every 10 minutes with `{}`, and `fill-sori-catalog` at minutes 5, 15, 25, 35, 45, and 55 with `{"language":"ko"}`. The first authorized call stores `project_url`, `admin_token` (the `CRON_FILL_TOKEN`), and `catalog_bearer` in Vault. Do not commit those values.

The job prefers the level with the fewest published clips and remembers the YouTube page so the next run walks forward. On the phone, a clip the learner has finished sorts behind clips they have not seen, and new rows show up on the next sync.

## RevenueCat setup
- Entitlement: `nagare_learn_japanese_pro`
- Offering: `default` (current), with `$rc_monthly` → product `monthly` ($9.99/mo) and `$rc_annual` → product `yearly`
  ($59.99/yr). Both products exist in the Test Store and the App Store app and are attached to the entitlement.
  In App Store Connect, create auto-renewable subscriptions `monthly` and `yearly` in one group.
  Yearly intro offer: **3-day free trial**. Monthly: **no free trial**.
- API keys: DEBUG builds use `REVENUECAT_TEST_API_KEY` / `EXPO_PUBLIC_REVENUECAT_TEST_API_KEY` (Test Store);
  release builds use `REVENUECAT_IOS_API_KEY` / `EXPO_PUBLIC_REVENUECAT_IOS_API_KEY`. A single
  `REVENUECAT_API_KEY` in `Secrets.plist` overrides both when set.
- For the App Store app, add RevenueCat's In-App Purchase Key (App Store Connect → Users and Access → Integrations)
  and confirm the dashboard shows Valid credentials.
- Paywall: if a RevenueCat Paywall is published for the `default` offering, the app shows it (RevenueCatUI).
  Otherwise it shows the built-in Nagare paywall. Both have no close button (hard paywall).
- Customer Center: Profile → Manage Subscription opens RevenueCat's Customer Center (cancel, refund, restore).
- The constants are in `StoreConstants` (`Services/PurchaseManager.swift`).
- Identity: anonymous `Purchases.shared.appUserID` only. `logIn` is never called. Purchases and restores attach to
  that anonymous ID; Restore Purchases re-syncs the Apple ID's receipt onto it.

## Meta Ads (RevenueCat Conversions API)
Dashboard: RevenueCat → Integrations → Meta Ads → Conversions API with your Pixel/Dataset ID + access token.
Keep Meta “Log in-app events automatically” **off** (RevenueCat sends purchases).

App-side (`MetaAttribution.swift` + FacebookCore SPM):
1. Add to `Jojo/Config/Secrets.plist`:
   - `META_APP_ID` = Nagare Meta App ID (`1856489205337782`)
   - `META_CLIENT_TOKEN` = Meta Developers → App → Settings → Advanced → **Client Token**
2. After `Purchases.configure`, the app sets `$fbAnonId` + device IDs via `collectDeviceIdentifiers()`.
3. The tracking prompt appears on first launch, before any ad event. Meta auto purchase logging stays disabled.

Test: sandbox purchase → RevenueCat Customer History → Meta Ads delivery row.

## Insights (acquisition + feedback)
- Onboarding asks **How did you find Jojo?** (Instagram / TikTok / web / App Store / …) → `submit-acquisition`
- After ~15 min watched or 4 main-app opens: **Are you enjoying Jojo?** sheet → `submit-feedback`
- Profile → **Give feedback** anytime
- After a **trial auto-renew cancel**: soft reason sheet → `submit-feedback` (`cancel_price`, `cancel_time`, …)
- Local review UI: `tools/insights-dashboard` (`python3 -m http.server 8787`) with URL + anon key + `ADMIN_TOKEN`
- Private HQ: https://socialreporthq.com/hq/jojo-insights

## Testing purchases
`Nagare.storekit` contains both products; yearly uses a **3-day** free trial. In Xcode, go to Scheme → Run → Options →
StoreKit Configuration and select `Nagare.storekit`. For live explanations, use a StoreKit sandbox purchase so the
Edge Function sees a real `pro` entitlement.

**DEBUG bypass:** DEBUG builds show "DEBUG: Skip paywall" on the paywall. This button is compiled out of release builds. With
the bypass on, the Edge Function rejects calls because there is no real entitlement, so the app silently uses local dictionary entries.

## Widgets
Home Screen + Lock Screen widgets surface the retention loop: **due cards** (tap → review) and **streak / daily goal** (tap → feed).

- Extension target: `JojoWidgets` (`com.socialreporthq.jojo.widgets`)
- Shared snapshot: `JojoShared/WidgetSnapshot.swift` via App Group `group.com.socialreporthq.jojo`
- Deep links: `jojo://review`, `jojo://feed`

Enable the App Group on both the app and widget App IDs in the Apple Developer portal (same team as the Xcode signing). After the first study session, long-press the Home Screen → Add Widget → Jojo Progress.

## Assumptions
- The paywall is hard: no free tier. The daily goal timer is motivational only.
- The level badge (N5→N1) is estimated from known and learning word counts.
- The streak counts consecutive days with at least 1 minute watched.
- A streak-at-risk nudge fires at 21:30 and the daily reminder at 19:00. A Day-2 reminder is scheduled after starting a 3-day yearly trial when notifications are allowed.
- Onboarding does not show named testimonials. For You opens on clips ranked from the answers saved during onboarding.
- Noto Sans JP is bundled as static Regular/Bold subsets (Latin + kana + CJK unified). Hiragino Sans is the fallback.
- The SwiftData models are CloudKit-compatible, but CloudKit sync is disabled (`cloudKitDatabase: .none`).
- Terms / Privacy / Support: `https://socialreporthq.com/jojo/{terms,privacy,support}` (`StoreConstants`). Contact: `support@socialreporthq.com`.
