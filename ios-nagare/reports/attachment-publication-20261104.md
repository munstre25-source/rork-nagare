# Screenshot-source publication — 4 November 2026

Reviewed 34 images: 56 readable channel labels, 54 canonical channels resolved and registered. Two labels remain ambiguous; covered rows are documented in [the source inventory](attachment-channels-20261104.md).

Published **13 new videos** from 11 channels. The live catalog increased from **451 to 464 clips**, and from **241 to 254 unique source videos**. Public rows were fetched again after publication. All 13 new records passed the database publication-proof validator; 407 spoken-word intervals passed bounds/order checks.

No Gemini key or paid inference calls were used. Processing used pinned local Qwen ASR/forced alignment, OPUS Japanese-to-English translation, and JMdict vocabulary. Source-caption inspection corrected Japanese homophones where necessary; English meanings were reviewed and corrected before publication. Timestamp validity is not a claim of independently measured perfect alignment across all existing content.

The free local route does not require creator captions and does not reject burned English. Processing windows support 3–300 seconds, with complete short sources up to 180 seconds and coherent excerpts for longer uploads. The selected published Shorts below run 4–32 seconds. Missing/collapsed timing, unclear speech, incomplete audio, and questionable drafts remain held.

Daily GitHub publishing and both catalog-fill database cron jobs are disabled. User-requested immersion processing, analytics retention, and embed auditing remain active. This was a one-off publication, not a new schedule.

A fresh iOS build is required to display local-tier entries and the expanded duration range. The client fix is on main; backend publication does not rebuild the app. Existing clip IDs were retained.

## Live additions

| Channel | Video | Seconds |
|---|---|---:|
| Hanaso Japanese | [NWQ6kBW4g9g](https://www.youtube.com/watch?v=NWQ6kBW4g9g) | 19 |
| GiftJP | [794NbT957JA](https://www.youtube.com/watch?v=794NbT957JA) | 10 |
| まるもももか🐷🍑10万人行きたい | [LGweeRgR91A](https://www.youtube.com/watch?v=LGweeRgR91A) | 17 |
| 伊達千春【美容神😇】 | [W7W5nRO-rCQ](https://www.youtube.com/watch?v=W7W5nRO-rCQ) | 12 |
| Hanaso Japanese | [5JKfKnZ2pFA](https://www.youtube.com/watch?v=5JKfKnZ2pFA) | 25 |
| ハリネズミの茶々丸ファミリー🍼 | [fz968_fhxvg](https://www.youtube.com/watch?v=fz968_fhxvg) | 4 |
| ABEMA 恋する週末ホームステイ【公式】 | [tXwwh5FueIs](https://www.youtube.com/watch?v=tXwwh5FueIs) | 7 |
| 伊達千春【美容神😇】 | [4FIRWjZar80](https://www.youtube.com/watch?v=4FIRWjZar80) | 23 |
| にじドリル | [AytGyyt5JYM](https://www.youtube.com/watch?v=AytGyyt5JYM) | 32 |
| ゆり〻2人目妊娠中の助産師ママ | [UpTmtWfjLQ0](https://www.youtube.com/watch?v=UpTmtWfjLQ0) | 22 |
| 倉嶋里菜 | [3Jb9efU_3d0](https://www.youtube.com/watch?v=3Jb9efU_3d0) | 17 |
| 魚を保護する人 | [W7jwTbVYd6A](https://www.youtube.com/watch?v=W7jwTbVYd6A) | 28 |
| アニメ絵創作室 | [sUEGyzd3M6k](https://www.youtube.com/watch?v=sUEGyzd3M6k) | 20 |

## Validation and held work

The focused backend suite passed 43 tests; the offline Python suite passed 14 tests. The local-publication SQL guard tests passed in a rolled-back transaction. Full iOS/Xcode compilation was unavailable on this Windows host; syntax checks found no new parser errors.

The finite draft scan processed 142 candidates: {'held': 129, 'ready_locally': 13}. These are draft outcomes, separate from the 13 actual live additions (including two pilot videos). Details and held reasons are in [the machine-readable report](attachment-publication-20261104.json). Held drafts were not published.
