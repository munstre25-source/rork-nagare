# Review existing Japanese subtitles

Admin/cron-only maintenance endpoint; gateway JWT verification stays enabled.
POST a catalog id with apply false to review against the original audio without writing.
Optional lineIndexes selects existing slots; translations supplies candidate English by original index.
Every selected line must pass the audio, Japanese transcript, meaning, grammar, and structural checks.
A full review receives a receipt bound to its video, source bounds, Japanese tokens/times, and final English.
A partial review does not certify the full clip.

Apply true uses a compare-and-swap against the original lines JSON.
If a legacy row exceeds the REST filter URL limit, reviewed_pending_apply returns the approved
lines and expectedLines for an authenticated operator to compare-and-swap through SQL.
Only apply when the stored JSON still equals expectedLines; never overwrite a concurrent subtitle edit.
Verify all fields other than translation and translationReview are identical before applying.

Unsupported audio/transcripts remain needs_review. Do not invent missing dialogue or shift timing to
force approval. A card containing separate sentences can require a separate transcription/segmentation
repair; this endpoint preserves existing line indexes and all Japanese/token timing.
Review results are metered by the existing global budget and daily usage gates.
Do not expose model or service credentials to clients.

Policy 3 adds visual inspection, timestamped quotes for positive English-subtitle findings, timing review and content/audience classification. Full reviews store the reviewed category and database integrity seal. Partial results cannot certify a live clip. Publication state is preserved by default. The legacy hold proposal was declined: do not quarantine/unpublish without a new explicit instruction. Large-row compare-and-swap proposals include category and expectedCategory; apply the approved category and sealed lines while comparing both originals.
