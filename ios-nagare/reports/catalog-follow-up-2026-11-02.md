# Catalog follow-up snapshot

As of 2026-11-02T10:43:27.86556+00:00 UTC. Counts continue to change as the budgeted publisher runs.

**205 live clips; 52 queued source videos / 54 windows.** Queue inventory includes in-flight sources until completion. Current technical failures: 0; unresolved publishing holds: 0; stalled workers: 0. Excluded source windows: 83. Historical failed, held and rejected attempts remain in audit views.

This follow-up started at 191 live clips and has added 14. No existing clip was unpublished. 92 live clips pass policy 3; 113 legacy live clips lack current approval and remain live under the explicit keep-live instruction.

Additional ledger spend so far: **USD 0.8689 of the USD 4 processing allowance**. Estimated account balance from the user's USD 5.79 baseline: USD 4.9211. The **USD 1.79 user-definition allowance** is separate and cannot be reserved by video calls. Outstanding reservations are visible in the dashboard; unused allowance is not a charge.

## Requested channels

All 23 unique requested handles are registered and resolved. Queued sources have not yet passed publication checks. Exclusions describe current candidates, not a permanent channel ban.

| Handle | Live | Queued videos | Status |
|---|---:|---:|---|
| @japanese_tanakasan | 3 | 0 | Live |
| @OkkeiJapanese | 2 | 0 | Live |
| @JSI55 | 2 | 4 | Live + queued |
| @Akane-JapaneseClass | 1 | 1 | Live + queued |
| @yuyunihongopodcast | 1 | 0 | Live |
| @bachiramylove629 | 0 | 0 | Current candidates excluded |
| @QuizKnock | 0 | 18 | Queued |
| @TOHOanimation | 4 | 1 | Live + queued |
| @tokiwa-japanese | 0 | 0 | Current candidates excluded |
| @KanamatopeJapanese | 0 | 0 | Current candidates excluded |
| @BlippiJapanese | 4 | 14 | Live + queued |
| @PeppaPigJapaneseOfficial | 2 | 13 | Live + queued |
| @Bebefinn日本語 | 0 | 0 | Current candidates excluded |
| @SpeakJapaneseNaturally | 0 | 0 | Current candidates excluded |
| @DailyJapanese | 1 | 0 | Live |
| @TheNihongoNook | 0 | 0 | Current candidates excluded |
| @the_bitesize_japanese_podcast | 0 | 0 | No eligible recent upload under source policy |
| @SayuriSaying | 0 | 0 | No eligible recent upload under source policy |
| @kensanokaeri | 0 | 0 | No eligible recent upload under source policy |
| @nihongo-no-jikan | 0 | 0 | No eligible recent upload under source policy |
| @moshimoshi.yusuke | 1 | 0 | Live |
| @withyuki1030 | 0 | 0 | No eligible recent upload under source policy |
| @nihongonomori2013 | 0 | 1 | Queued |

## Requested video IDs

All 11 were rechecked public and embeddable, but exceed the four-minute source policy. They remain blocked from this bounded publisher.

| Video | Source seconds | State |
|---|---:|---|
| [scLWToOqXzA](https://www.youtube.com/watch?v=scLWToOqXzA) | 3604 | blocked source over 4 minutes |
| [Hd6gAtt5BOU](https://www.youtube.com/watch?v=Hd6gAtt5BOU) | 3646 | blocked source over 4 minutes |
| [TA-tUGtjils](https://www.youtube.com/watch?v=TA-tUGtjils) | 3768 | blocked source over 4 minutes |
| [ijzd6W09uB8](https://www.youtube.com/watch?v=ijzd6W09uB8) | 3751 | blocked source over 4 minutes |
| [RIKmx-R987A](https://www.youtube.com/watch?v=RIKmx-R987A) | 3745 | blocked source over 4 minutes |
| [e0acNvVwkWI](https://www.youtube.com/watch?v=e0acNvVwkWI) | 3863 | blocked source over 4 minutes |
| [W3Rw3GsVjpo](https://www.youtube.com/watch?v=W3Rw3GsVjpo) | 3848 | blocked source over 4 minutes |
| [nX8gk8OLb0U](https://www.youtube.com/watch?v=nX8gk8OLb0U) | 3780 | blocked source over 4 minutes |
| [NhJJcAiZvFY](https://www.youtube.com/watch?v=NhJJcAiZvFY) | 7712 | blocked source over 4 minutes |
| [FZUIZYEwHp4](https://www.youtube.com/watch?v=FZUIZYEwHp4) | 3652 | blocked source over 4 minutes |
| [a9SBvpregYU](https://www.youtube.com/watch?v=a9SBvpregYU) | 5214 | blocked source over 4 minutes |

## Repairs, validation, and handoff

Fourteen existing clips passed fresh full reviews; five English lines were corrected and seven categories were corrected. Exact before/after comparison confirmed Japanese, readings/meanings, token and line timing, source offsets, durations, line slots and publication flags were unchanged. Unsupported legacy segmentation/audio findings remain review-needed; they were not guessed into approval.

Candidate leases prevent scheduled and manual workers from paying for the same source window concurrently. Both original publisher jobs are active with their original schedules. Curated discovery now skips already screened/queued uploads and can enqueue up to 20 new uploads per requested channel without expensive search queries. Further search discovery respects the daily YouTube quota reserve.

New publication still requires audio-grounded transcription, English meaning and grammar, timing, content/audience categorization, source visual inspection, and a valid database seal. Burned-in English is excluded; optional YouTube CC remains off.

50 backend tests pass; all Edge entrypoints type-check; the Next production build passes. The dashboard deployment for implementation commit dff13a6 succeeded on Vercel. Additional discovery/lease changes are included in the follow-up commit. Native Xcode compilation, iOS tests and actual latency measurements require the simulator agent.

See [feed performance and migration handoff](feed-performance-and-pipeline-handoff-2026-11-02.md). The adjacent JSON includes exact queued and excluded IDs and reasons.
