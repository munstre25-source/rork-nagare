# Simulator handoff — 2 November 2026

## Copy this to the simulator agent

Pull the latest main without discarding local work. This release includes the earlier agent’s automatic publisher, shared subtitle modes, Explore/Vocab/Profile fixes, personalized onboarding, Podcast classification, Pipeline analytics, and the annual-first paywall.

Build/run Jojo and run its tests plus the checks below. Native iOS changes have not been compiled on this Windows/WSL host. Backend/web checks passed. **Keep existing publication flags unchanged**: the user explicitly declined the legacy hold. The verified snapshot has **191 live clips**, **50 queued source videos / 51 windows**, **64 live clips passing current policy**, and **127 legacy live clips needing review**. The 127 is a quality status, not removed content. The worker can add more after this snapshot.

The three Supabase migrations below are already applied and recorded on project jacpmygzmsfiyltdsiyu. No database work is needed for a normal simulator build. Do not reset the database, blindly push all historical migrations, publish legacy drafts, or raise the shared USD 5 AI cap.

## Build and test

Preserve simulator-agent changes before pulling; do not use a hard reset or force push.

\~\~\~sh
git switch main
git pull --ff-only
xcodebuild -resolvePackageDependencies -project ios-nagare/Jojo.xcodeproj -scheme Jojo
xcodebuild -showdestinations -project ios-nagare/Jojo.xcodeproj -scheme Jojo
# Choose an available iOS Simulator UDID from the preceding output:
xcodebuild -project ios-nagare/Jojo.xcodeproj -scheme Jojo \\
  -destination 'platform=iOS Simulator,id=<SIMULATOR\_UDID>' test
\~\~\~

The project uses filesystem-synchronized source groups; new Swift files are included automatically. Use the existing public client configuration workflow. Never put service-role/admin tokens or AI provider keys in the app.

## Onboarding and first feed

* Fresh onboarding must persist motivation, liked/passed interests, reading level and goal. Rapid swipes record one answer per card; leaving the level screen cancels delayed continuation.
* Compare beginner Anime with advanced Podcasts. Interest ranking cannot bypass the saved level gate. Missing inventory must not be invented or mislabeled.
* Level selection initializes Beginner / Guided / Full Immersion help for new profiles. Later display changes remain independent of difficulty and invoke no AI.
* The Welcome clip must be first in For You and survive the handoff/relaunch while eligible.
* Normal DEBUG onboarding/bypass uses the personal feed rather than forced showcase clips. No demo vocabulary/watch history is seeded by default; explicit marketing demos remain separate.
* Profile goal/level changes refresh upcoming recommendations while preserving the current watch.
* Exact retired clip IDs leave the local cache on sync even if another excerpt of the same video remains live.
* Podcasts are a separate interest/category. Adult lessons and podcasts must not become Kids for easy vocabulary or slow speech.

## Annual-first paywall

The native annual-first comparison is now canonical; a RevenueCat remote template no longer silently replaces it. RevenueCat still supplies the assigned current offering (default fallback), packages, localized prices, trial eligibility, purchases/restores and entitlement state. Customer Center remains available.

* Annual starts selected and is the primary recommended offer. Explicit monthly selection must survive asynchronous product loading.
* **Annual CTA: Start Free Trial** for verified annual-trial eligibility. **Monthly CTA: Continue**. Unknown/ineligible annual users see Continue rather than an unavailable free-trial promise.
* Full billed annual total is most prominent. Monthly equivalent, percentage and currency savings compare actual same-currency prices over exactly one year versus twelve monthly payments.
* Hide discount claims for missing currencies/periods or annual pricing that is not cheaper. Percentages never round up. No fabricated Most Popular claim or sale price is used.
* CTA stays visible while scrolling. Test small iPhone, iPad, landscape and large Dynamic Type; cards should expand without clipping.
* Test annual-only/monthly-only, delayed/missing products, load failure, eligible/ineligible/unknown trials, purchase cancellation/pending, restore with/without entitlement and a successful sandbox purchase.
* Plan selection is disabled during purchase/restore. Analytics/reminders must use the package actually purchased.
* StoreConstants expects monthly/yearly packages and nagare\_learn\_japanese\_pro entitlement. The local StoreKit annual fixture is documented as a three-day trial; live StoreKit terms are authoritative.
* For paywall QA use a non-subscribed test install with RevenueCat configured. Stored DEBUG bypass or a cached entitlement can skip it. Missing RevenueCat config intentionally enables debug bypass. Do not change release eligibility or hardcode prices to force screenshots.
* New native regression tests cover savings, currencies, periods, no discount, JPY, onboarding and level gating. Run them on macOS.

## Applied Supabase migrations

Already applied and recorded, in dependency order:

1. 20261101170000\_production\_analytics.sql — test/legacy/production separation, production-only KPIs and service-only playback reporting.
2. 20261102000539\_catalog\_pipeline\_quality\_gate.sql — private attempts/history/source registry, paginated metrics, integrity seal and publication guard.
3. 20261102003637\_catalog\_content\_classification.sql — Podcast category, policy 3 content/audience proof, authoritative channel metadata and guarded category updates.

Older schema features were bootstrapped with incomplete migration-history bookkeeping. An old version missing from history does not prove its schema is missing. Do not replay all older migrations to reconcile that history.

Deployed paths: admin-dashboard, admin-insights, admin-pipeline, analytics-ingest, direct-messages, report-playback, submit-acquisition, submit-feedback, analyze-clip, fill-catalog, immersion-worker, publish-clip, review-catalog, seed-catalog-sources, audit-embeds. Shared helpers were shipped with their consumers.

Publisher: ten-minute schedule, one candidate/pass, original growth target and four-minute source ceiling preserved. Temporary audit pause cleared. Shared AI cap remains USD 5; snapshot spend is about USD 4.716. Budget/quota holds appear in Pipeline and do not mean playback is broken. Avoid bulk AI jobs during simulator QA.

## Catalog / dashboard

Open /hq/jojo-insights?view=pipeline in the existing private HQ. It shows live inventory, policy-approved versus legacy review-needed clips, queue videos/windows, processing/stalled attempts, actual publication transitions, held/rejected/failed outcomes/reasons, channels and budget, with pagination/search and automatic refresh. History starts at this deployment; old creation dates are not fabricated as publish events.

Future publication requires original-audio translation/grammar and timing checks, visual burned-in English inspection, content/audience classification and a database seal. Uncertain evidence does not pass. Podcasts are distinct; Kids requires child-directed content. YouTube CC remains off; the app retains adjustable English assistance.

**The user chose to keep all existing live clips unchanged.** Some legacy clips have English-subtitle or transcript/segmentation findings. Keep them live and display their review status; do not call every live clip verified.

Complete requested channel/video states: reports/catalog-release-2026-11-02.md and .json. All 23 unique channel handles resolved. The eleven long Minecraft IDs remain blocked by the four-minute source policy; queued sources still need approval.

## Validation completed here

* 44 shared backend tests passed; all Edge Function entrypoints type-check.
* Next production build and Pipeline browser checks: navigation, metrics, filtering/search, pagination, refresh errors, light theme and mobile overflow.
* Rolled-back service-role tests rejected missing approval, edited translations, shifted bounds, wrong categories and burned-in English; history transitions worked.
* Rolled-back analytics fixtures proved test activity is excluded and production activity counts.
* Exact comparison of 193 existing clips / 1,209 lines preserved Japanese tokens/readings/meanings, indexes, line/token times, offsets, durations and existing publication flags.
* Security advisors ran. Existing project warnings remain; new pipeline tables have RLS and service-only access.

Native compilation, real StoreKit UI/purchase flows and device playback require the macOS simulator agent. Do not claim those passed until run.

