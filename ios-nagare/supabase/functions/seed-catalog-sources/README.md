# Verify and seed requested sources

Admin/cron-only maintenance endpoint; gateway JWT verification stays enabled.
POST handles (up to five from the configured allowlist), videoIds (up to 50), and apply.
The endpoint resolves actual YouTube channel ids, inspects the latest 50 uploads per channel,
and selects up to five new public embeddable sources between 8 and 240 seconds.
The four-minute source ceiling matches the automatic publisher.
Long sources are deferred; this endpoint does not expand the media ingestion limits.

Apply true deduplicates candidate windows by video_id and window_start_sec.
queuedWindows is the number newly inserted, so zero can mean these eligible sources are already queued.
existingPublishedLessons counts published lessons by resolved channel id, not an unreliable title match.
Requested video metadata is verified, but a video longer than four minutes is explicitly deferred.
Queued sources still need transcription, enrichment, translation/audio review, and publication.
Seeding is not a promise of publication. No eligible recent uploads refers to the scanned latest 50,
not an exhaustive historical scan or a finding that the channel is unavailable.
The normal publisher schedule and consumption of this queue remain unchanged.
