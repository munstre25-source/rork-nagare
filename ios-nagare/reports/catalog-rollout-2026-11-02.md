# Catalog review and deployment — 2 November 2026

As of 2026-11-02T00:01:25.450035+00:00. This is a snapshot; the automatic publisher remains active.

Published: 190 lessons (193 total rows). Whole-clip audio review passed: 100; still blocked for quality/technical review: 93.
Changed English: 47 clips / 126 lines, plus saved review receipts. All 193 pre-repair clips / 1209 lines retained exact source bounds, Japanese tokens/readings/meanings, line indexes, line/token times, and publication state.
AI spending recorded: USD 3.027093 of the unchanged USD 5 cap. Future background publisher activity shares this same hard cap.

The other agent’s committed publisher entrypoint (e3f83c0), four-minute source ceiling, one candidate per run, growth target, and ten-minute schedule were preserved. Only its shared helpers were updated to include the translation gate. No broad migration push, git reset, or deployment of unrelated functions was performed.

## Requested channels

Live counts are published lessons. Queued counts are distinct source videos, with candidate-window counts in parentheses. Queued means awaiting ingestion and quality approval, not already live.

| Handle | Live lessons | Queued videos (windows) | Status |
|---|---:|---:|---|
| @bachiramylove629 | 0 | 5 (5) | Queued |
| @SpeakJapaneseNaturally | 0 | 5 (5) | Queued |
| @JSI55 | 2 | 5 (5) | Live + queued |
| @TheNihongoNook | 0 | 3 (3) | Queued |
| @KanamatopeJapanese | 0 | 5 (5) | Queued |
| @SayuriSaying | 0 | 0 (0) | Blocked: no eligible new uploads among latest 50 under 4-minute policy |
| @the_bitesize_japanese_podcast | 0 | 0 (0) | Blocked: no eligible new uploads among latest 50 under 4-minute policy |
| @tokiwa-japanese | 0 | 5 (5) | Queued |
| @OkkeiJapanese | 2 | 5 (5) | Live + queued |
| @TOHOanimation | 0 | 5 (5) | Queued |
| @PeppaPigJapaneseOfficial | 0 | 5 (5) | Queued |
| @Bebefinn日本語 | 0 | 5 (5) | Queued |
| @BlippiJapanese | 0 | 5 (5) | Queued |
| @Akane-JapaneseClass | 0 | 5 (5) | Queued |
| @nihongo-no-jikan | 0 | 0 (0) | Blocked: no eligible new uploads among latest 50 under 4-minute policy |
| @yuyunihongopodcast | 1 | 0 (0) | Live |
| @QuizKnock | 0 | 5 (5) | Queued |
| @nihongonomori2013 | 0 | 5 (5) | Queued |
| @japanese_tanakasan | 2 | 5 (5) | Live + queued |
| @moshimoshi.yusuke | 0 | 4 (4) | Queued |
| @kensanokaeri | 0 | 0 (0) | Blocked: no eligible new uploads among latest 50 under 4-minute policy |
| @withyuki1030 | 0 | 0 (0) | Blocked: no eligible new uploads among latest 50 under 4-minute policy |
| @DailyJapanese | 0 | 1 (2) | Queued |

All 23 unique handles resolved to channel ids. Repeated handles in the request were deduplicated. Queued ids and resolved channel ids are recorded in the adjacent JSON report.

## Requested video ids

All eleven are public and embeddable, but exceed the automatic publisher’s four-minute source ceiling. None are live or queued. Supporting them requires bounded extraction for long source media; extending a duration limit alone would be insufficient.

| Video id | Source seconds | Status |
|---|---:|---|
| [scLWToOqXzA](https://www.youtube.com/watch?v=scLWToOqXzA) | 3604 | Blocked: source over 4 minutes |
| [Hd6gAtt5BOU](https://www.youtube.com/watch?v=Hd6gAtt5BOU) | 3646 | Blocked: source over 4 minutes |
| [TA-tUGtjils](https://www.youtube.com/watch?v=TA-tUGtjils) | 3768 | Blocked: source over 4 minutes |
| [ijzd6W09uB8](https://www.youtube.com/watch?v=ijzd6W09uB8) | 3751 | Blocked: source over 4 minutes |
| [RIKmx-R987A](https://www.youtube.com/watch?v=RIKmx-R987A) | 3745 | Blocked: source over 4 minutes |
| [e0acNvVwkWI](https://www.youtube.com/watch?v=e0acNvVwkWI) | 3863 | Blocked: source over 4 minutes |
| [W3Rw3GsVjpo](https://www.youtube.com/watch?v=W3Rw3GsVjpo) | 3848 | Blocked: source over 4 minutes |
| [nX8gk8OLb0U](https://www.youtube.com/watch?v=nX8gk8OLb0U) | 3780 | Blocked: source over 4 minutes |
| [NhJJcAiZvFY](https://www.youtube.com/watch?v=NhJJcAiZvFY) | 7712 | Blocked: source over 4 minutes |
| [FZUIZYEwHp4](https://www.youtube.com/watch?v=FZUIZYEwHp4) | 3652 | Blocked: source over 4 minutes |
| [a9SBvpregYU](https://www.youtube.com/watch?v=a9SBvpregYU) | 5214 | Blocked: source over 4 minutes |

## Review blockers

Clips marked below did not receive whole-clip approval. Existing publication flags are unchanged. Do not describe these legacy live clips as audio verified. Transcript/audio mismatches need a new hearing/segmentation pass; multiple sentence cards require a coordinated index/segmentation repair. Translation-only fixes preserve existing saved-word and subtitle references. Provider/JSON failures remain technical blockers, not successful reviews.

| Clip id | Review status | Reason |
|---|---|---|
| boss-rush-live-09 | needs_review | line[0] failed sourceMatchesAudio, meaningAccurate |
| counting-kuma-03 | needs_review | line[0] failed audioClear, sourceMatchesAudio, meaningAccurate |
| harajuku-street-02 | needs_review | line[0] failed sourceMatchesAudio, meaningAccurate |
| hoshizora-academy-07 | needs_review | line[0] failed sourceMatchesAudio, meaningAccurate |
| immersion--trocZ1u204-14-35 | needs_review | line[7] multiple translated sentences must be separate lines |
| immersion-5kXOkOpkYJ8-78-90 | needs_review | line[2] multiple translated sentences must be separate lines |
| immersion-5U8vAa94rFo-28-49 | needs_review | line[3] multiple translated sentences must be separate lines |
| immersion-5Vz_nVN1PrM-75-90 | needs_review | line[3] failed sourceMatchesAudio |
| immersion-67G_CfyZHp0-102-116 | needs_review | line[1] multiple translated sentences must be separate lines |
| immersion-6bAtb5gwX1Y-5-45 | needs_review | line[3] failed sourceMatchesAudio, meaningAccurate |
| immersion-7dbIWMbxDfg-12-41 | needs_review | line[0] failed meaningAccurate |
| immersion-7kk3VajdeaM-0-13 | needs_review | line[3] multiple translated sentences must be separate lines |
| immersion-8miK-6nV7Gw-0-32 | needs_review | line[5] multiple translated sentences must be separate lines |
| immersion-9OYewGtGVQw-0-23 | needs_review | line[0] multiple translated sentences must be separate lines |
| immersion-aglOdAXsKEQ-6-30 | needs_review | line[3] multiple translated sentences must be separate lines |
| immersion-AoZugwG4meE-0-17 | needs_review | line[1] failed sourceMatchesAudio, meaningAccurate |
| immersion-aqjddUenT8A-0-26 | needs_review | line[0] failed meaningAccurate |
| immersion-au2w4AeWyd8-80-99 | needs_review | line[6] multiple translated sentences must be separate lines |
| immersion-AUrfD-1sqM8-33-50 | needs_review | line[1] translation ends mid-thought |
| immersion-butabara-steam | needs_review | line[3] translation ends mid-thought |
| immersion-COb5aAy5CJ0-28-41 | needs_review | line[0] multiple translated sentences must be separate lines |
| immersion-COb5aAy5CJ0-28-42 | needs_review | line[0] failed sourceMatchesAudio |
| immersion-cT-o8IXg6CI-0-15 | needs_review | line[1] failed sourceMatchesAudio |
| immersion-CW0juiwikkQ-43-63 | needs_review | line[3] multiple translated sentences must be separate lines |
| immersion-dcxmIs4colE-0-13 | needs_review | line[2] multiple translated sentences must be separate lines |
| immersion-Dmi0T9qyPJA-30-55 | needs_review | line[5] failed sourceMatchesAudio, meaningAccurate |
| immersion-eihkCy4rlg4-26-41 | needs_review | line[0] failed sourceMatchesAudio |
| immersion-fOfIHF2JjI8-18-30 | needs_review | line[2] multiple translated sentences must be separate lines |
| immersion-gFLvb0SIIn0-39-121 | needs_review | line[1] multiple translated sentences must be separate lines |
| immersion-gyPaUw_5BLc-50-63 | needs_review | line[2] multiple translated sentences must be separate lines |
| immersion-h1XUU_Wq9ks-1-21 | needs_review | line[1] translation is a single letter |
| immersion-h6ObOK-Xwmc-0-18 | needs_review | line[4] failed sourceMatchesAudio |
| immersion-hDfAn3KfBjk-13-30 | needs_review | line[0] translation ends mid-thought |
| immersion-HJdyF2rcZb0-0-21 | needs_review | line[7] translation ends mid-thought |
| immersion-hYLf9yxkDBE-4-28 | needs_review | line[3] multiple translated sentences must be separate lines |
| immersion-Ir35SAOZ5nY-0-30 | needs_review | line[0] failed sourceMatchesAudio |
| immersion-iUyX27UkWDs-23-55 | needs_review | line[1] multiple translated sentences must be separate lines |
| immersion-iYjjpFZTAZA-0-32 | needs_review | line[1] multiple translated sentences must be separate lines |
| immersion-J3XHFIJafkM-81-89 | needs_review | line[2] failed sourceMatchesAudio, meaningAccurate |
| immersion-jJrWJqUJ-NM-21-29 | needs_review | line[1] failed sourceMatchesAudio |
| immersion-KDfG1K1IgZc-18-37 | needs_review | line[0] failed meaningAccurate |
| immersion-kh_PnQ5mY2Y-0-11 | needs_review | line[0] failed sourceMatchesAudio |
| immersion-Ki8uOm2QNOk-2-26 | needs_review | line[7] translation ends mid-thought |
| immersion-komeda-order | needs_review | line[0] failed audioClear, sourceMatchesAudio, meaningAccurate |
| immersion-lnd2SjFMJXI-51-76 | needs_review | line[0] multiple translated sentences must be separate lines |
| immersion-LuADPqD93nM-0-14 | needs_review | line[0] multiple translated sentences must be separate lines |
| immersion-MDtiDGr_-GY-3-17 | needs_review | line[0] multiple translated sentences must be separate lines |
| immersion-mSycuOff7YQ-70-84 | needs_review | line[0] translation ends mid-thought |
| immersion-n9jnD_8JeLc-28-49 | needs_review | line[0] translation ends mid-thought |
| immersion-nfmMuGsqK8Q-14-34 | needs_review | line[0] failed sourceMatchesAudio |
| immersion-Njk2kfY4irI-40-54 | needs_review | line[1] multiple translated sentences must be separate lines |
| immersion-Ovl6nYvihh8-18-36 | needs_review | line[4] multiple translated sentences must be separate lines |
| immersion-pd-5GK2JdQk-5-45 | needs_review | line[0] failed sourceMatchesAudio |
| immersion-pI6TGEHnKo4-3-23 | needs_review | line[0] multiple translated sentences must be separate lines |
| immersion-q89xqLs-eNY-30-50 | needs_review | line[2] multiple translated sentences must be separate lines |
| immersion-QDGzU8DZjkc-21-34 | needs_review | line[3] multiple translated sentences must be separate lines |
| immersion-QgQ8_7zSv7s-26-41 | needs_review | line[1] multiple translated sentences must be separate lines |
| immersion-QThN_GUATTY-19-34 | needs_review | line[2] multiple translated sentences must be separate lines |
| immersion-QyXHpGahA1I-12-24 | needs_review | line[0] translation ends mid-thought |
| immersion-r7ytNplrDCA-0-17 | needs_review | line[0] multiple translated sentences must be separate lines |
| immersion-R9NwPxYOxSw-7-35 | needs_review | line[6] multiple translated sentences must be separate lines |
| immersion-roZJa9Z6S1I-31-43 | needs_review | line[3] multiple translated sentences must be separate lines |
| immersion-rXF2YFvMxKY-32-58 | needs_review | line[4] multiple translated sentences must be separate lines |
| immersion-sapLlgWryNI-0-25 | needs_review | line[2] failed sourceMatchesAudio |
| immersion-SF-EoJkMhBc-0-16 | needs_review | line[0] translation ends mid-thought |
| immersion-swE3eLyJXOM-132-164 | needs_review | line[8] failed sourceMatchesAudio |
| immersion-uL2ABO6yMwM-8-26 | needs_review | line[0] multiple translated sentences must be separate lines |
| immersion-VBd50awmtxg-59-89 | needs_review | line[0] failed audioClear, sourceMatchesAudio, meaningAccurate |
| immersion-VFMFI1yj2wY-0-10 | needs_review | line[4] multiple translated sentences must be separate lines |
| immersion-VFX9q3P6cw0-0-16 | needs_review | line[0] failed sourceMatchesAudio, meaningAccurate |
| immersion-VI44EvFkQ7w-18-35 | needs_review | line[0] multiple translated sentences must be separate lines |
| immersion-VJyFtWJ_36k-61-73 | needs_review | line[2] translation ends mid-thought |
| immersion-Wdw_HjSp7GQ-19-38 | needs_review | line[4] multiple translated sentences must be separate lines |
| immersion-WkJcGj9R7Fk-38-54 | needs_review | line[0] multiple translated sentences must be separate lines |
| immersion-WNQCXxF4uFM-11-33 | needs_review | line[7] failed sourceMatchesAudio, meaningAccurate |
| immersion-Y7kYPuCduwk-0-21 | needs_review | line[7] failed sourceMatchesAudio, meaningAccurate |
| immersion-yGOkIy78MRM-63-87 | needs_review | line[0] translation ends mid-thought |
| immersion-ykw9D1hq1hc-5-23 | needs_review | line[2] multiple translated sentences must be separate lines |
| immersion-yLB0JwdA_ek-0-10 | needs_review | line[0] translation ends mid-thought |
| immersion-yU72X91jPMI-0-16 | needs_review | line[2] failed sourceMatchesAudio |
| immersion-yWy6wBKTicc-8-22 | needs_review | line[1] failed sourceMatchesAudio |
| immersion-Z_leh6MUPHI-72-86 | needs_review | line[0] translation ends mid-thought |
| immersion-ZXeSXMqsSBQ-24-42 | needs_review | line[0] multiple translated sentences must be separate lines |
| kissa-stories-01 | needs_review | line[0] failed audioClear, sourceMatchesAudio, meaningAccurate |
| kitsune-yuki-stream-01 | needs_review | line[0] failed audioClear, sourceMatchesAudio, meaningAccurate |
| konbini-diaries-01 | needs_review | line[0] failed sourceMatchesAudio, meaningAccurate |
| neko-cafe-02 | needs_review | line[0] failed audioClear, sourceMatchesAudio, meaningAccurate |
| piyo-picnic-01 | needs_review | line[0] failed sourceMatchesAudio, meaningAccurate |
| quiz-showdown-11 | needs_review | line[0] failed audioClear, sourceMatchesAudio, meaningAccurate |
| ramen-road-trip-03 | needs_review | line[0] failed sourceMatchesAudio, meaningAccurate |
| speedrun-commentary-02 | needs_review | line[0] failed sourceMatchesAudio, meaningAccurate |
| tsukimi-rin-zatsudan-05 | needs_review | line[0] failed sourceMatchesAudio, meaningAccurate |
| words-that-matter-04 | needs_review | line[0] failed sourceMatchesAudio, meaningAccurate |

## Deployment and verification

34 passed, 0 failed; all six deployed function entrypoints pass deno check.

Live endpoints: analyze-clip v56 (ACTIVE), publish-clip v46 (ACTIVE), fill-catalog v68 (ACTIVE), immersion-worker v24 (ACTIVE), review-catalog v4 (ACTIVE), seed-catalog-sources v2 (ACTIVE).

The timing comparison is structural and exact; it verifies no subtitle timing changed during this work. It does not prove that every legacy timestamp originally aligned with speech. Cached receipts invalidate when audio bounds, Japanese timing/text, or English changes. Learning-mode changes remain local and do not invoke AI.

Automated original-audio review is not human certification. Legacy blocked reviews remain published where they were published before; this maintenance did not unpublish catalog rows. Segmentation/transcript changes requiring new indexes or timing were not forced into translation-only repairs.
