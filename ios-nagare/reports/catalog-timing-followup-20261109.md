# Catalog timing follow-up

Two local speech models reviewed all 14 cached clips. Language detection was run without forcing Japanese.

| Finding | Clips | Next step |
| --- | ---: | --- |
| Portuguese dub | 8 | Obtain the original Japanese track for the same episode. |
| English speech | 1 | Verify a Japanese track or use a Japanese-language window. |
| Speech cut off by the clip boundary | 3 | Revise the subtitle or use an authorized longer window. |
| On-screen text displayed as dialogue | 1 | Separate the written notice from the spoken exchange. |
| Gloss included in timed text | 1 | Move the explanatory gloss into a vocabulary note. |

The public-source selector now rejects explicitly labelled foreign audio tracks. These are editorial or audio-source issues. The live timing-only repair preserves published Japanese and English, so none of the 14 received a timing-only update.

The other 148 windows span 55 source videos. The earlier repair manifest records their exact starts and durations.

Miku publishes related episodes as downloadable podcasts. Their published durations differ from the YouTube cuts, and an audio comparison could not be completed because the podcast enclosure returned HTTP 403. Okkei’s episode 72 sample supplies a transcript. These sources do not yet provide verified source-time audio for the held windows. [Miku’s official podcast](https://themikurealjapanesepodcast.buzzsprout.com/) · [Okkei’s episode 72](https://www.okkeijapanese.com/childhood-home-listening-okkei-japanese-72/).

Windows Task Scheduler runs the local queue at 11:15 a.m. Nairobi time while the account is signed in. It prepares local timing proofs and sends up to five approved new drafts for fresh YouTube metadata validation and publication. Creator-authorized source files and reviewed draft snapshots go into the local state directory. The initial run found an empty inbox.

Zero new clips were published during this review. The local review and daily job used zero hosted inference.

See the [clip review manifest](catalog-timing-followup-20261109.json), [audio window backlog](live-word-timing-repair-20261109.json), and [daily intake instructions](../../Tools/FREE_CATALOG.md).
