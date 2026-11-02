# Feed performance, offline meanings, and pipeline handoff

## Implementation

- Catalog pages decode and serialize in a utility task, away from the UI actor.
- Canonical sorted JSON avoids rewriting unchanged cached clips on every refresh.
- A successful refresh reuses decoded clips instead of decoding persisted JSON again.
- Catalog merging and membership checks use indexes/sets rather than repeated array scans.
- Overlapping catalog refreshes are coalesced. Cached content stays visible during refresh or network failure.
- Local posters and generated local-video stills share an evictable cache, limited to 24 images / 32 MB.
- Existing single-active-player and next-clip prewarming behavior is preserved. No additional autoplaying embeds or video downloads.
- Word taps synchronously consult token meanings, the bundled dictionary, persisted explanation cache, and saved vocabulary. A missing meaning is UI status, never a stored definition.
- Bundled dictionary now includes ですね. Missing offline context no longer invents a meaning. Empty remote responses cannot erase saved definitions.

Cold YouTube playback still depends on YouTube and the connection. No zero-latency or measured startup claim has been made without an iOS device profile.

## Pipeline and spending

The initial follow-up ledger baseline was $4.994361125. The catalog/video ceiling is $8.994361125, allowing at most $4 additional processing. Unknown costs retain their full reservation; concurrent calls reserve atomically. Production uses OpenRouter directly to avoid the old primary-provider timeout.

The user-definition allowance is separately limited to **$1.79**. Only text lookups can reserve it; video processing cannot use its RPC. Both kinds settle actual provider charges exactly once. The global ledger also includes lookup spending, so the video ceiling is conservative if users spend lookup funds during the catalog run.

Candidate windows have five-minute ownership leases; stale owners cannot release a newer claim. Scheduled and bounded manual runs can safely overlap. Temporary errors and incomplete evidence remain queued with a 20-minute retry delay. Actual source/quality exclusions leave the candidate queue and retain their audit history. The dashboard separates latest publishing work from historical review attempts. Existing live clips remain published under the owner's explicit instruction, including legacy clips still needing policy review.

Approved repairs use a body-based atomic compare-and-swap RPC. It preserves Japanese, tokens, times, line order and publication state. New publication still requires the policy-3 audio/translation/timing/visual/classification seal.

See the companion catalog follow-up snapshot for final counts, requested channels, individual requested videos, exclusions, and spend.

## Supabase migration handoff

The following migrations were applied to project jacpmygzmsfiyltdsiyu and recorded in migration history during this rollout:

| Version | Purpose |
|---|---|
| 20261102085801 | Atomic shared budget reservations and idempotent settlement |
| 20261102094400 | Safe approved-review application and current pipeline reporting |
| 20261102100036 | Scheduled transient retries |
| 20261102101303 | Separate lookup-only launch allowance |
| 20261102103001 | Atomic candidate leases for overlapping scheduled/manual workers |

**Do not run a broad db push or replay these against production.** Older migration history predates this rollout and is not fully aligned. Another environment needs the matching existing base schema and ordered migration chain. No new SwiftData store schema migration is required by this follow-up.

Affected Edge Functions are deployed with JWT verification enabled. Original automatic publisher schedules are preserved; review and publication remain budget gated. No production secret belongs in the iOS bundle.

## Validation and simulator handoff

- 50 shared backend tests pass; all 22 Edge Function entrypoints type-check.
- Database rollback fixtures verify review timing/Japanese preservation, stale-data rejection, approval seals, lookup-only funds, allowance exhaustion and idempotent settlement.
- Next production build passes.
- Edited Swift files pass syntax checks relative to the existing parser baseline. Native compilation and iOS tests could not run on this Windows host.
- Seven native regression tests were added for offline definitions, stable subtitle cache bytes, and malformed-page protection.
- Existing project security advisor finding: public.grammar_patterns lacks RLS. It predates this work; private budget/review RPC permissions were checked separately. Do not silently alter another agent's grammar feature.

On macOS, pull main, build Jojo, and run JojoTests. Profile cold and warm feed entry plus rapid swipes with Instruments. Verify For You, Explore and Vocab playback queues still settle on one complete clip; Shorts controls remain visible; landscape framing and karaoke work in both themes. Test cached meanings in Airplane Mode, unknown words without invented definitions, and ですね from the bundle. Confirm the next prewarmed clip remains silent until activated and artwork memory stays bounded.

A bounded manual follow-up may continue alongside cron until its pass or spending limit. Every attempt is recorded in the same dashboard, uses the same queue leases, and respects the catalog cap. Do not start a separate unguarded publisher.

The separately edited ios-nagare/HANDOFF-SIMULATOR.md was left untouched.
