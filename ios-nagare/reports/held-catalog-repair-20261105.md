# Free held-catalog repair — 2026-11-05

Published **24 additional source videos**, taking the catalog from **464 to 488 clips** (278 distinct source videos). The local tier now has **37 published clips**; all 37 passed the database’s sealed local-publication proof check. Complete sources include 42, 48, 49, 51 and 56 seconds. No Gemini key, paid inference or new spending allowance was used.

The combined repair inventory still contains **48 timing-passing drafts awaiting language review** and **41 held videos**. These are not live additions. Holds include unclear/non-Japanese speech, unresolved collapsed or implausible intervals, and alignment-context limits. Raw offline English and recognition errors were corrected against source evidence before the 24 publications. Word timing comes from actual audio attention/DTW, not arithmetic sentence subdivision. Passing interval/seal checks does not establish perfect human-audited word boundaries.

Two production migrations admit the pinned free Whisper ASR and its distinct raw attention/DTW provenance. The local ingestion endpoint requires recorded English review. Existing source-channel, embed, duration, duplicate-window and database integrity checks remain active. Scheduled daily publication stays disabled.

Validation: 24 Python tests and 47 Deno tests passed. Both migration SQL guard transactions passed before applying them. Public catalog totals and all local proof checks were re-read after publication. A fresh iOS build is required for the already committed local-tier feed eligibility change; this backend work does not ship an app binary.

| Video | Channel | Duration | Timed words |
| --- | --- | ---: | ---: |
| [L8YzKNYvXeU](https://www.youtube.com/watch?v=L8YzKNYvXeU) | kattyanneru/かっちゃんねる | 49 s | 136 |
| [6NjKw4M14KE](https://www.youtube.com/watch?v=6NjKw4M14KE) | kattyanneru/かっちゃんねる | 42 s | 117 |
| [Lr7aYnodVVg](https://www.youtube.com/watch?v=Lr7aYnodVVg) | Hanaの暮らし | 51 s | 155 |
| [gZULl_R05Cw](https://www.youtube.com/watch?v=gZULl_R05Cw) | トリビアン | 20 s | 61 |
| [6Tg62yO9zTU](https://www.youtube.com/watch?v=6Tg62yO9zTU) | もふもふ事件簿 | 9 s | 14 |
| [ZzqYssLLImo](https://www.youtube.com/watch?v=ZzqYssLLImo) | レッチャンネル | 14 s | 22 |
| [DIlhbsI-9-Q](https://www.youtube.com/watch?v=DIlhbsI-9-Q) | 長野県でラジコンを飛ばそう！ | 16 s | 27 |
| [NSI9hvrVsuw](https://www.youtube.com/watch?v=NSI9hvrVsuw) | はじめしゃちょー（hajime） | 12 s | 48 |
| [X9q4wQng5fk](https://www.youtube.com/watch?v=X9q4wQng5fk) | えり  /  親子で楽しむおうち遊び | 12 s | 38 |
| [uM2I5PeEYWQ](https://www.youtube.com/watch?v=uM2I5PeEYWQ) | あかちゃす丸裸🍎 | 11 s | 33 |
| [cR-8JJ8uvkg](https://www.youtube.com/watch?v=cR-8JJ8uvkg) | ここちゃんねる | 12 s | 40 |
| [KLRtRKxDGa4](https://www.youtube.com/watch?v=KLRtRKxDGa4) | トリビアン | 20 s | 77 |
| [myQhpZOQNkc](https://www.youtube.com/watch?v=myQhpZOQNkc) | もふもふ事件簿 | 11 s | 22 |
| [V4TDB9cZgw0](https://www.youtube.com/watch?v=V4TDB9cZgw0) | 世界をのぞき見! | 25 s | 77 |
| [k_-b76oRa6Q](https://www.youtube.com/watch?v=k_-b76oRa6Q) | 三津家貴也 | 48 s | 133 |
| [_UyPJzP2rzY](https://www.youtube.com/watch?v=_UyPJzP2rzY) | ALLOUTの筋トレHACK【トレーニングギアブランド】 | 31 s | 78 |
| [wkOTMSnJYKw](https://www.youtube.com/watch?v=wkOTMSnJYKw) | erika_kurashi | 13 s | 40 |
| [mPWc3N4rU4Y](https://www.youtube.com/watch?v=mPWc3N4rU4Y) | manaのアイデア料理 | 38 s | 115 |
| [Q-eeYF8zrGY](https://www.youtube.com/watch?v=Q-eeYF8zrGY) | 伊達千春【美容神😇】 | 18 s | 67 |
| [Ukfa2vNxXu4](https://www.youtube.com/watch?v=Ukfa2vNxXu4) | GiftJP | 11 s | 43 |
| [jVyTJZxj_18](https://www.youtube.com/watch?v=jVyTJZxj_18) | manaのアイデア料理 | 49 s | 126 |
| [ePbC3feznrU](https://www.youtube.com/watch?v=ePbC3feznrU) | manaのアイデア料理 | 56 s | 152 |
| [IJKBGKojZXo](https://www.youtube.com/watch?v=IJKBGKojZXo) | えり  /  親子で楽しむおうち遊び | 17 s | 58 |
| [YThIbra3t3w](https://www.youtube.com/watch?v=YThIbra3t3w) | kattyanneru/かっちゃんねる | 49 s | 147 |

Full metadata, individual remaining hold reasons and publication inventory: [JSON](held-catalog-repair-20261105.json). Recording-derived channel labels and filter observations: [Kiku audit](kiku-recordings-20261105.md).
