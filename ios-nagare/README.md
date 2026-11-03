# Nagare 流れ — Scroll, Listen, Flow into Japanese

Native SwiftUI (iOS 17+), SwiftData, Observation, Swift concurrency. The third-party packages are
RevenueCat (`purchases-ios-spm`) and Meta FacebookCore. Supabase is called over plain URLSession. Gemini is only reached
through the Supabase Edge Function, so there is no Gemini key in the app.

## Secrets
Copy `Config/Secrets.example.plist` to `Jojo/Config/Secrets.plist` (it's gitignored and picked up by the
synchronized target folder), then fill in:
- `SUPABASE_URL`: e.g. `https://xxxx.supabase.co`
- `SUPABASE_ANON_KEY`
- `REVENUECAT_API_KEY`: the public iOS SDK key (`appl_…`)

Any value still starting with `YOUR_` is treated as not configured. The Meta App ID and client token
are bundled separately in `Jojo/Info.plist`, so Meta attribution works from a clean checkout.

## Record marketing videos (screen recording)
DEBUG only. From splash debug buttons, or **Profile → Debug · Marketing**.

**Five scripts** (record each as its own cut):

1. **Sakura dark neon** — core For You story  
2. **Sakura dark** (glow off) — same story  
3. **Amber dark neon** — same story  
4. **Amber dark** (glow off) — same story  
5. **Full app tour** — onboarding → For You → Vocab → Explore → Search → Library → Profile, then every look (Sakura/Amber × dark neon / dark / light)

Core story beats (videos 1–4): current For You chrome (Library · For You/Explore · Search), scrolls **3 clips**, theater video, word tap → dictionary + paint ladder → save fly animation → flashcard Again/Good.

1. Start Simulator/device screen recording.
2. Open the script and tap **Begin …**.
3. Stop when **Showcase finished** appears. Trim outside the app.

## Adding clips
The study feed only plays clips whose transcript was taken from the video (`id` starts with `immersion-`).
`Tools/generate_seed.py` refreshes the dictionary and debug vocab. It does not rewrite `SeedClips.json`.
New clips come from `fill-catalog`. Source videos up to two minutes can become complete lessons of up to 120 seconds when the spoken scene is coherent. Longer source videos yield self-contained 8–40 second excerpts. Gemini returns exact source offsets and timed transcripts; the pipeline rejects invalid or incomplete lessons. The app plays the selected lesson in the official YouTube player, with its transcript-relative timestamps, English translation, and tappable vocabulary. It does not download or re-host the video.

## Explore, Vocab, Library, and Profile

Explore leads with word/phrase search and opens matching clips at the relevant sentence.
Dictionary results open clip examples; the separate audio button speaks the word.
Grammar requests are cancelled when the selected pattern changes. Search counts and
empty/offline states follow the active scope.

Vocab searches saved words and can open clip examples for the same query. Its flashcards
icon differs from Library's books icon. Reviews and early practice use the same queue
rules as Profile and the dock: due learning cards first; optional early practice is
labeled Practice; Known words are excluded from automatic queues. Vocab's current filters
apply to its main practice session. Known words remain available for deliberate deck
practice. Badges refresh when learning cards become due, including Again cards.

Vocab lists actual familiarity/encounter counts, honors reading settings, supports all
five JLPT decks, and keeps its illustrative timeline collapsed and clearly labeled.
Deck creation avoids duplicate channel/topic filters. Audio controls are separate from
word navigation and Library playback; saved/later shelves can remove their own clips.

Profile shows all five mastery states, describes Known marks accurately, and displays
the chosen feed content level. It links to Clip Library. Speaking Practice describes
recognition comparison rather than promising an AI chat. Explore's daily plan marks
Review after a completed card session, Watch after a finished clip, and Speak after a
recognized attempt; opening and cancelling those screens does not complete the task.

Native regression tests in JojoTests cover queue eligibility, early practice, scoped
search, and calendar-day plan separation. Run them on a Mac with Xcode. Verify the
word-search → clip → saved word → review → Profile flow on a device or simulator,
including audio-only taps, filters, return navigation, and saved-clip removal.

## Shared subtitles and learning modes

Each clip has one canonical enriched transcript in its existing `lines` JSON: Japanese
token surfaces, kana readings (furigana is derived on device), romaji, concise English
word meanings, sentence translations, and validated sentence/word timestamps. The Japanese
hearing prompt (default version 6) produces these together in one model call.
Japanese English translations then receive one separate audio-grounded quality review
during preprocessing, before the shared dataset is stored or published. New Japanese
clips missing meanings, romaji, or kanji readings are rejected before storage; punctuation
does not require these fields. Timing repair retains enrichment and falls back to sentence
highlighting when word timing cannot be trusted.

The player and Profile offer presentation presets, independent of the content level:

| Mode | Furigana | Romaji | English | Word lookup |
| --- | --- | --- | --- | --- |
| Beginner | On | On | Always shown | On |
| Guided Immersion | On | Off | Tap to reveal each sentence | On |
| Full Immersion | Off | Off | Hidden | On |

Each assistance control can be changed independently; combinations outside a preset show
as Custom. English cycles through On, Tap, and Hidden. Guided reveals are temporary and
reset when the sentence, active line, or English setting changes. Full Immersion removes
mastery/POS decoration while retaining the spoken cursor and optional word taps.

Settings are persisted locally in SwiftData and change rendering immediately without
fetching subtitles, restarting playback, or invoking AI. The additive preference fields
preserve existing Japanese-only/English-only settings and reading choices. Previously
processed clips remain usable via the bundled lexicon and existing shared explanation
cache; they are not automatically reprocessed. Catalog deduplication and import reuse
continue sharing previously processed clips across learners.

No database migration or separate subtitle files are needed. To ship, deploy the updated
`analyze-clip`, `fill-catalog`, `immersion-worker`, and `publish-clip` functions (each bundles the shared
enrichment code), then build the iOS app in Xcode. A configured `SUBTITLE_PROMPT_VERSION` overrides
the default. Explanation cache versioning remains separate, so existing word explanations
are retained.

Validation:

```bash
npx --yes deno test --allow-env --allow-read --allow-net supabase/functions/_shared
```

In Xcode, run `JojoTests`, then check the same playing clip across all presets, individual
toggles, sentence advances/replays, relaunch, small/large text sizes, portrait Shorts, and
expanded landscape playback.

## Translation quality

Japanese preprocessing makes one hearing/enrichment call and one separate translation
review call. The reviewer receives the original selected YouTube audio and every indexed
Japanese line with its proposed English. It checks meaning, standard English grammar,
negation, tense/aspect, possibility/obligation, passive/causative forms, questions,
politeness, omitted subjects, and uncertainty. Unsupported dialogue or unclear audio is
rejected rather than filled in. Short natural replies and idioms remain valid.

Review output may replace English only. It cannot replace Japanese, token meanings,
timestamps, or line indexes. Every line must be reviewed with explicit positive checks;
partial, duplicate-index, malformed, or negative reviews block publication. Obvious
placeholder/agreement defects have additional deterministic checks; these checks alone
are not a semantic translation test.

A `translationReview` receipt inside the existing lines JSON records review version,
actual model, and a SHA-256 digest of the source video, excerpt bounds, Japanese tokens,
timings, and final English. Unchanged reviewed data is reused when published again;
editing translation-relevant data requires a new review. Learning-mode changes and
playback make no review calls. No schema migration is needed.

Both passes consume the existing global Gemini usage cap. The review call has a
45-second timeout and can use `GEMINI_MODEL_TRANSLATION_REVIEW` (defaults to the analysis
model). Provider failures use the existing bounded retry handling. An unsupported meaning
is a terminal review failure for that import rather than repeated speculative generation.
The Korean pipeline keeps its existing behavior. Word-explanation cache versioning is
independent and unchanged.

Existing clips are not silently rewritten or retrospectively declared accurate. Run this
read-only audit from `ios-nagare/` against bundled clips or an exported array of catalog
rows; it makes no model or database requests:

```bash
npx --yes deno run --allow-read supabase/functions/_shared/translation-audit.ts Jojo/Resources/SeedClips.json
```

The bundled audit covers 10 clips / 86 lines. All 10 lack the new audio review, and
`immersion-r34OGOpTOs0-5-45` contains an English fragment ending mid-thought. Its
Japanese utterance spans three stored lines; correcting the segmentation needs source
review and care for saved word line indexes. A second flag on
`immersion-pd-5GK2JdQk-5-45` is a sentence-segmentation warning, not proof of a
mistranslation. The audit report is in
`reports/bundled-translation-audit.json`. A successful automated review reduces errors
but is not human certification; assess real outputs against the audio and bilingual
reference translations before claiming catalog-wide accuracy. Unit tests use mocked model
responses to verify the gates, reuse, and failure behavior; they do not measure model
translation accuracy.

## Optional local clip overrides
You can place `Jojo/Resources/Clips/{clip.id}.mp4` to force AVPlayer for a specific clip (useful if
YouTube embeds fail in a given environment). Leave this empty for normal YouTube playback.
`ClipPlayerFactory` order: local file (if present) → YouTube → simulated poster.

Clips with a real ID and no local file use `YouTubeClipPlayer` (WKWebView + official IFrame API).
Everything else uses `SimulatedClipPlayer` (animated gradient poster, karaoke cursor, ja-JP narration).
YouTube video is never re-hosted.

## Supabase
- Clip library: apply migrations from **`ios-nagare/`** (see below). Jojo GETs `/rest/v1/clips?published=eq.true&select=*`. The Korean app reads `/rest/v1/sori_clips` on the same project. Each app syncs at launch and every five minutes, when For You opens, and when the learner reaches the last three queued clips. New published lessons are appended after the current clip; rows that are no longer published are removed from the local remote cache on the next sync. Bundled verified clips stay available offline. A remote row replaces the bundle when the id matches.
- Word explanations: `POST /functions/v1/explain-word`. See `supabase/functions/explain-word/README.md`.
  Lookup order: seed token → local dictionary → SwiftData cache → Edge Function (12 s timeout) → static fallback.
  Live calls are logged locally (`WordExplainService.stats()`: today/total count, average latency).

## Backend Edge Functions

Production analytics require migration `20261101170000_production_analytics.sql` before
deploying `analytics-ingest`, `submit-acquisition`, `submit-feedback`, `direct-messages`,
`report-playback`, `admin-insights`, and `admin-dashboard`. A verified StoreKit app transaction
labels an App Store install as `production`; simulator, debug, TestFlight, and unavailable
verification are `test`. The command
centre counts only production rows. Historical mixed rows remain `legacy` and are excluded
because their origin cannot be recovered reliably. The new iOS build must reach App Store users
before their activity appears in the production dashboard. Older builds lack the environment
header and are classified as test by the server. After deploying, verify the classification and
production dashboard against a real App Store installation:

```sql
select environment, count(*) from public.analytics_sessions group by environment;
select environment, count(*) from public.analytics_events group by environment;
select public.admin_dashboard_metrics_range(now() - interval '7 days', now());
```

Run all Supabase CLI commands from the **`ios-nagare/`** directory (not the repo root):

```bash
cd ios-nagare
supabase db push
supabase functions deploy explain-word youtube-search analyze-clip publish-clip fill-catalog audit-embeds
supabase secrets set \
  GEMINI_API_KEY=… \
  YOUTUBE_API_KEY=… \
  ADMIN_TOKEN=… \
  REVENUECAT_SECRET_API_KEY=…
```

### Secrets you must set

| Name | Required | Purpose |
|------|----------|---------|
| `GEMINI_API_KEY` | yes | Model key. Catalog creation uses one hearing pass for speech, timing, and learner fields, plus one audio-grounded English review for valid Japanese candidates (rejected candidates can still consume calls); word explanations use Gemini only on a cache miss when requested. Normal feed playback does not call AI. An `sk-or-` value calls Gemini through OpenRouter (Google AI Studio only). Any other value calls Gemini directly. |
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
| `PROMPT_VERSION` | `4` | Bumped into explanation cache keys |
| `SUBTITLE_PROMPT_VERSION` | `6` | Subtitle enrichment provenance; independent of explanation caches |
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

`fill-catalog` searches YouTube for a public, embeddable source video 8–180 seconds long that is not already in the catalog. For sources up to two minutes, Gemini can keep the full meaningful spoken scene, up to 120 seconds. Longer sources yield one coherent 8–40 second exchange. The function validates the lesson boundaries, dialogue, and vocabulary before publishing. Transcript times are stored relative to the lesson; `source_start_sec` tells the app where to seek in the original YouTube video. Japanese rows go in `clips` with ids `immersion-…`. Korean rows go in `sori_clips` with ids `sori-…` and TOPIK levels `TOPIK1`–`TOPIK6`. Both catalogs share `YOUTUBE_QUOTA_DAILY_CAP` and `GEMINI_GLOBAL_DAILY_CAP`. A run stops on those caps. A Gemini video `402` pauses searching for two hours so the timer does not spend YouTube quota.

Japanese discovery rotates through the supplied sources: Blue Archive Global, テレ東公式 あにてれちゃんねる, SHONEN JUMP CHANNEL OFFICIAL, Studio Pierrot, avex pictures, TOHO animation, Shochiku anime, 集英社オレンジ文庫, TMS anime, Pony Canyon anime, and とた. Handle-based sources are resolved through `channels.list`; searches use that channel ID, YouTube's embeddable/under-four-minute filters, and a strict 8–180 second metadata check. Channel sources rotate across cron passes so they do not get buried behind general search lanes. `とた` is treated as a variety source only for spoken interview or behind-the-scenes clips; songs are rejected by the speech-only lesson analysis.

For a one-time curator seed, an admin may include `{"videoIds":["…"]}` in a `fill-catalog` request (up to 50 IDs). This only queues public, embeddable 8–180 second videos; every ID still goes through the normal spoken-Japanese transcript, lesson, and vocabulary checks before it can become live. It does not force-publish a video.

Two pg_cron jobs call it: `fill-jojo-catalog` every 10 minutes with `{}`, and `fill-sori-catalog` at minutes 5, 15, 25, 35, 45, and 55 with `{"language":"ko"}`. The first authorized call stores `project_url`, `admin_token` (the `CRON_FILL_TOKEN`), and `catalog_bearer` in Vault. Do not commit those values.

Every 30 minutes, `audit-youtube-embeds` checks published Japanese and Korean catalog videos with YouTube's `videos.list` API in batches of 50. It unpublishes clips when YouTube no longer reports `status.embeddable=true`, including deleted/private videos omitted from a successful API response. YouTube/network/quota errors leave the affected batch untouched. Re-publishing a clip and processing a learner-submitted video also recheck embed availability. Unpublished clips no longer appear in client feeds, while their rows remain available for recovery/history. The job uses the same Vault secrets as the other catalog cron jobs.

The job prefers the level with the fewest published clips and remembers the YouTube page so the next run walks forward. It discovers fresh YouTube sources, verifies their current embed permission, and builds a new timed lesson before publishing. On the phone, a clip the learner has finished sorts behind clips they have not seen, and new lessons are fetched while the learner is approaching the end of the current queue.

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
- Paywall: the annual-first native comparison is canonical. RevenueCat supplies live packages/prices and verified product-specific trial eligibility. A remote template does not automatically replace it; Customer Center remains supported. The paywall remains hard, without a close button.
- Customer Center: Profile → Manage Subscription opens RevenueCat's Customer Center (cancel, refund, restore).
- The constants are in `StoreConstants` (`Services/PurchaseManager.swift`).
- Identity: anonymous `Purchases.shared.appUserID` only. `logIn` is never called. Purchases and restores attach to
  that anonymous ID; Restore Purchases re-syncs the Apple ID's receipt onto it.

## Meta Ads (RevenueCat Conversions API)
Dashboard: RevenueCat → Integrations → Meta Ads → Conversions API with your Pixel/Dataset ID + access token.
Keep Meta “Log in-app events automatically” **off** (RevenueCat sends purchases).

App-side (`MetaAttribution.swift` + FacebookCore SPM):
1. The Meta App ID and **Client Token** are both bundled in `Jojo/Info.plist`, as required by the
   Meta iOS SDK. `Secrets.plist` can override them locally but is no longer required for Meta.
   Do not put the Meta App Secret or RevenueCat Conversions API token in the app bundle.
2. The app checks that its effective Meta App ID matches `Info.plist` before initializing the SDK.
3. After ATT authorization, the app sets `$fbAnonId` + device IDs in RevenueCat via
   `collectDeviceIdentifiers()`. The tracking prompt appears on first launch, before any ad event.
   Meta auto purchase logging stays disabled.

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

## Current release / simulator handoff

See [HANDOFF-SIMULATOR.md](HANDOFF-SIMULATOR.md) for applied migrations, publication policy, annual-first pricing QA and simulator steps. Display presets alone need no SQL migration; the pipeline/dashboard requires the three migrations listed there, already applied. Existing live clips were retained by explicit user instruction. See the [full source report](reports/catalog-release-2026-11-02.md).


## Verified word karaoke

All newly analyzed, explicitly published, and caption-imported clips require complete
word timings. Invalid timing gets one focused pass against the original YouTube audio;
a separate audio/translation review then verifies every onset and offset. Missing,
uniformly interpolated, incomplete, or unsupported timing is held rather than marked
word-synchronized. Existing cached sentence-only clips retain an honest sentence cue
until their source audio has been aligned; the client never fabricates word timestamps.

Deploy `20261103160000_verified_word_timing.sql` and the six changed functions together:
`analyze-clip`, `fill-catalog`, `immersion-worker`, `publish-clip`, `review-catalog`, and
`ingest-caption-clips`. Preserve JWT verification and the existing admin-token gates.
The service-only timing RPC preserves source bounds, Japanese, readings, meanings,
line/token order, and publication state; it checks signed audio evidence and uses a
compare-and-swap to avoid overwriting concurrent edits.

Audit without making AI calls or mutations:

```bash
python3 Tools/repair_word_timing_catalog.py
```

After deployment, use `ADMIN_TOKEN` from the operator's environment for a pilot and then
resume the remaining catalog. No credentials are printed or saved in reports:

```bash
python3 Tools/repair_word_timing_catalog.py --apply --limit 3 --report /tmp/word-timing-pilot.json
python3 Tools/repair_word_timing_catalog.py --apply --limit 0 --workers 2 --report /tmp/word-timing-catalog.json
```

`--use-existing-vault` is an explicit operator authorization to read this project's
existing maintenance credential into process memory. Repairs respect AI quotas/spend
limits, stop on provider/auth/budget failures, and leave unsupported clips unchanged.
Re-running skips clips with current independent word-verification receipts. A final
read-only audit reports the remaining work; a successful request alone is not proof
that every catalog entry has been repaired.
