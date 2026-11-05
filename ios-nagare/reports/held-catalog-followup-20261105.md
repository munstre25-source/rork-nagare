# Catalog follow-up review — 2026-11-05

**82 more lessons are live: 45 of 48 drafts and 37 of 41 held sources.** All 89 requested sources have a recorded outcome. The catalog grew from 488 to 570 published clips (360 distinct videos). All 119 local publication proofs validate. Paid inference calls: **0**. Scheduled catalog filling remains disabled.

New lessons include 21 complete source videos and 61 contiguous reviewed excerpts, lasting 6.42–120 seconds; 24 exceed 40 seconds. A short recovered excerpt does not mean the rest of its source video was repaired.

## Repairs and checks

- Short speech windows and bounded joint phrase searches recover words misplaced by greedy recognition boundaries. Natural card boundaries are restored after alignment; every inferred word interval is retained.
- Corrected Japanese includes names, technical terms and homophones. Complete English was reviewed; raw offline machine translation was never treated as final.
- All final timings come from actual original PCM through raw attention/DTW, without even subdivision, gap stitching or fabricated missing-word timestamps. Independent full-model and slowed-audio recognition corroborate transcript wording only.
- Publication rechecks source channel, public/embed status and source duration, then seals exact subtitles and audio provenance in the database.
- 33 Python regression tests passed; 43 focused Deno tests also passed. The integrity query confirms 119/119 local proofs. Model-derived timing is not a perfect human boundary audit.
- Source videos retain their speakers' claims and jokes; this is language review, not independent factual verification of those claims.

## Remaining seven performances

| Video | Original queue | Channel | Reason |
| --- | --- | --- | --- |
| [F6TTFSBI11o](https://www.youtube.com/watch?v=F6TTFSBI11o) | held | よへ 僕がいい旦那になるまで | Music/vocal-led cooking video. Available recognition does not establish a trustworthy matching Japanese recipe narration; written recipe steps cannot be forced onto unrelated audio. |
| [FRml1nnawSU](https://www.youtube.com/watch?v=FRml1nnawSU) | held | 伊豆のぬし釣り | The cached source window contains singing/music. Forced-Japanese slowed decoding yields lyric-like material rather than reliable conversational speech; speech alignment is insufficient for verified lyrics. |
| [ZP20NwTBT00](https://www.youtube.com/watch?v=ZP20NwTBT00) | draft | よへ 僕がいい旦那になるまで | Music/vocal-led cooking video. Japanese on-screen cooking steps are not a verified matching spoken transcript; no fabricated timing was published. |
| [xIUYjjHMESg](https://www.youtube.com/watch?v=xIUYjjHMESg) | draft | 田舎民カイジ【shorts】 | Rhythmic vocal/jingle performance. Repeated local decodes still disagree on words and existing intervals collapse; retained for a music/rhythm-specific review. |
| [VrzsTij2gkA](https://www.youtube.com/watch?v=VrzsTij2gkA) | held | あーずかい | Explicit song-cover performance. Sustained singing needs a separate lyric transcription/alignment review; the speech decoder did not substantiate reliable words. |
| [RRGebB-JBD8](https://www.youtube.com/watch?v=RRGebB-JBD8) | draft | よへ 僕がいい旦那になるまで | Music/vocal-led cooking video. Japanese on-screen cooking steps are not a verified matching spoken transcript; no fabricated timing was published. |
| [j5ar9MRTc68](https://www.youtube.com/watch?v=j5ar9MRTc68) | held | 田舎民カイジ【shorts】 | Rhythmic vocal/jingle performance. Multiple local decodes still disagree on words and existing timing collapses; retained for a music/rhythm-specific review. |

These need reliable music/rhythm transcription and timing, rather than forcing a spoken-dialogue transcript onto singing or background vocals. No lyrics are reproduced here.

## Published repairs

| Video | Original queue | Channel | Source start | Length | Selection |
| --- | --- | --- | ---: | ---: | --- |
| [yT12afxLAnc](https://www.youtube.com/watch?v=yT12afxLAnc) | draft | 毎日しんちゃん | 0s | 15.35s | contiguous excerpt |
| [AabYgeRFp-g](https://www.youtube.com/watch?v=AabYgeRFp-g) | draft | アニまち | 0s | 11.52s | contiguous excerpt |
| [hmGy6-jpASs](https://www.youtube.com/watch?v=hmGy6-jpASs) | draft | 田舎民カイジ【shorts】 | 0s | 27s | complete source |
| [W5-jF4cNi2c](https://www.youtube.com/watch?v=W5-jF4cNi2c) | draft | 極悪特区 | 0s | 30s | complete source |
| [fsFrcj8N1QI](https://www.youtube.com/watch?v=fsFrcj8N1QI) | draft | ひみつ基地。 | 0s | 31.9s | contiguous excerpt |
| [8hGepBfxC1Q](https://www.youtube.com/watch?v=8hGepBfxC1Q) | draft | ヘビさんのアウトドア日誌 | 0s | 22.84s | contiguous excerpt |
| [SwiQky3hUrI](https://www.youtube.com/watch?v=SwiQky3hUrI) | draft | あーずかい | 0s | 22.04s | contiguous excerpt |
| [oEnaPwvWfQI](https://www.youtube.com/watch?v=oEnaPwvWfQI) | draft | 錬磨 | 0s | 21.98s | contiguous excerpt |
| [k3cd46BDKdw](https://www.youtube.com/watch?v=k3cd46BDKdw) | draft | 日本の紫陽花 | 0s | 58s | complete source |
| [NC7MzVbCZ4U](https://www.youtube.com/watch?v=NC7MzVbCZ4U) | draft | のすけぼっち飯 | 0s | 55.03s | contiguous excerpt |
| [ytzSJAw96sk](https://www.youtube.com/watch?v=ytzSJAw96sk) | draft | ふじやま家族 | 0s | 8.08s | contiguous excerpt |
| [rjr9uxcSn0A](https://www.youtube.com/watch?v=rjr9uxcSn0A) | held | 世界をのぞき見! | 0s | 10.804s | contiguous excerpt |
| [bfOUPCtkwPU](https://www.youtube.com/watch?v=bfOUPCtkwPU) | held | あおぎり高校 - Aogiri Vtuber High School | 9.27s | 8.492s | contiguous excerpt |
| [51JVRnuOYC4](https://www.youtube.com/watch?v=51JVRnuOYC4) | held | はるひなちゃんねる | 0s | 38s | complete source |
| [jJ8HCKE4h6A](https://www.youtube.com/watch?v=jJ8HCKE4h6A) | held | りくらぼ / RikuLab | 0s | 45s | contiguous excerpt |
| [cvIULMseJDM](https://www.youtube.com/watch?v=cvIULMseJDM) | held | たろたん | 0s | 29.54s | contiguous excerpt |
| [Ze7q-vso82s](https://www.youtube.com/watch?v=Ze7q-vso82s) | held | 東出昌大 | 0s | 23.07s | contiguous excerpt |
| [x88uCTmH31Q](https://www.youtube.com/watch?v=x88uCTmH31Q) | held | マイ | 55s | 6.42s | contiguous excerpt |
| [AVZIkKg70oU](https://www.youtube.com/watch?v=AVZIkKg70oU) | draft | 小物ロマン | 0s | 64s | complete source |
| [kJylcRMFtd4](https://www.youtube.com/watch?v=kJylcRMFtd4) | held | ともき | 31.74s | 13.87s | contiguous excerpt |
| [SJKqmPmjIDU](https://www.youtube.com/watch?v=SJKqmPmjIDU) | draft | やまかわてるき | 0s | 37.36s | contiguous excerpt |
| [NI6wF7kIXxg](https://www.youtube.com/watch?v=NI6wF7kIXxg) | held | いい声ボイトレ研究所 | 27.48s | 100.426s | contiguous excerpt |
| [Q6_ZQaD2VVM](https://www.youtube.com/watch?v=Q6_ZQaD2VVM) | draft | 青ヶ島ちゃんねる AOGASHIMA Channel | 25.4s | 120s | contiguous excerpt |
| [qV56C_BrPsM](https://www.youtube.com/watch?v=qV56C_BrPsM) | draft | カズチャンネル/Kazu Channel | 59.72s | 40.98s | contiguous excerpt |
| [42KzsSzAtnM](https://www.youtube.com/watch?v=42KzsSzAtnM) | draft | はじめしゃちょー（hajime） | 0s | 13s | contiguous excerpt |
| [059UtxcQTlI](https://www.youtube.com/watch?v=059UtxcQTlI) | held | アニメ絵創作室 | 0s | 19s | complete source |
| [0jOYJLHhrjk](https://www.youtube.com/watch?v=0jOYJLHhrjk) | draft | 長野県でラジコンを飛ばそう！ | 0s | 19s | complete source |
| [Tb_ItgrQlNU](https://www.youtube.com/watch?v=Tb_ItgrQlNU) | held | ここちゃんねる | 0s | 21s | complete source |
| [0S34ZgqRQHs](https://www.youtube.com/watch?v=0S34ZgqRQHs) | draft | にじドリル | 0s | 29s | contiguous excerpt |
| [ykw6STTksAM](https://www.youtube.com/watch?v=ykw6STTksAM) | held | ちゃまはし【アニメ・声優】 | 19.9s | 16.01s | contiguous excerpt |
| [zBn_Ok9bwQY](https://www.youtube.com/watch?v=zBn_Ok9bwQY) | draft | erika_kurashi | 0s | 15s | complete source |
| [RHotkJktt5Q](https://www.youtube.com/watch?v=RHotkJktt5Q) | draft | 毎日しんちゃん | 0.34s | 21.86s | contiguous excerpt |
| [KBl7i8slgb0](https://www.youtube.com/watch?v=KBl7i8slgb0) | draft | アニまち | 0s | 26s | contiguous excerpt |
| [bGYpSxCJY1A](https://www.youtube.com/watch?v=bGYpSxCJY1A) | held | 極悪特区 | 0s | 30s | contiguous excerpt |
| [RZzkmN9ODvo](https://www.youtube.com/watch?v=RZzkmN9ODvo) | held | あおぎり高校 - Aogiri Vtuber High School | 11.486s | 18.074s | contiguous excerpt |
| [r5Xnazbf1Go](https://www.youtube.com/watch?v=r5Xnazbf1Go) | held | ひみつ基地。 | 0s | 13.36s | contiguous excerpt |
| [Jq_UVLhV9SE](https://www.youtube.com/watch?v=Jq_UVLhV9SE) | held | りくらぼ / RikuLab | 0s | 50s | complete source |
| [OqoZYpSQiMc](https://www.youtube.com/watch?v=OqoZYpSQiMc) | held | たろたん | 6s | 21.28s | contiguous excerpt |
| [yXW4ynIhRBA](https://www.youtube.com/watch?v=yXW4ynIhRBA) | draft | 三津家貴也 | 0s | 50s | complete source |
| [SxeH6D7Bcj8](https://www.youtube.com/watch?v=SxeH6D7Bcj8) | held | ヘビさんのアウトドア日誌 | 50.318s | 8.56s | contiguous excerpt |
| [Ju6K6demcuU](https://www.youtube.com/watch?v=Ju6K6demcuU) | draft | 東出昌大 | 0s | 29.2s | contiguous excerpt |
| [hCCPJ-etKNg](https://www.youtube.com/watch?v=hCCPJ-etKNg) | draft | Hanaの暮らし | 0s | 51s | contiguous excerpt |
| [tBcIjdnzDcs](https://www.youtube.com/watch?v=tBcIjdnzDcs) | draft | 錬磨 | 0s | 56s | complete source |
| [7zQRoqD4d1k](https://www.youtube.com/watch?v=7zQRoqD4d1k) | draft | 日本の紫陽花 | 0s | 57s | contiguous excerpt |
| [69Z6XYoYNpA](https://www.youtube.com/watch?v=69Z6XYoYNpA) | held | のすけぼっち飯 | 0s | 50.85s | contiguous excerpt |
| [vGdVLHOQvO4](https://www.youtube.com/watch?v=vGdVLHOQvO4) | held | マイ | 19.22s | 8.13s | contiguous excerpt |
| [6uXEoiEuc1E](https://www.youtube.com/watch?v=6uXEoiEuc1E) | draft | 小物ロマン | 0s | 66s | complete source |
| [sDfaEpM9LIk](https://www.youtube.com/watch?v=sDfaEpM9LIk) | held | ともき | 2.702s | 11.918s | contiguous excerpt |
| [eXb0s-kVuC8](https://www.youtube.com/watch?v=eXb0s-kVuC8) | draft | やまかわてるき | 0s | 81s | contiguous excerpt |
| [faoboC067GE](https://www.youtube.com/watch?v=faoboC067GE) | held | いい声ボイトレ研究所 | 78.53s | 57.744s | contiguous excerpt |
| [LUmrgB1XnSo](https://www.youtube.com/watch?v=LUmrgB1XnSo) | held | 青ヶ島ちゃんねる AOGASHIMA Channel | 54.296s | 77.644s | contiguous excerpt |
| [K-2CVUw-xAg](https://www.youtube.com/watch?v=K-2CVUw-xAg) | draft | カズチャンネル/Kazu Channel | 30s | 79.44s | contiguous excerpt |
| [kcfeaejvzy8](https://www.youtube.com/watch?v=kcfeaejvzy8) | held | はじめしゃちょー（hajime） | 10.95s | 41.526s | contiguous excerpt |
| [phGyfevu_o0](https://www.youtube.com/watch?v=phGyfevu_o0) | draft | えり / 親子で楽しむおうち遊び | 0s | 17s | complete source |
| [xUd33Baf_yI](https://www.youtube.com/watch?v=xUd33Baf_yI) | held | アニメ絵創作室 | 0s | 20s | complete source |
| [b6Frd92ucpI](https://www.youtube.com/watch?v=b6Frd92ucpI) | draft | 長野県でラジコンを飛ばそう！ | 0s | 22s | complete source |
| [tRt0vQzCUYo](https://www.youtube.com/watch?v=tRt0vQzCUYo) | draft | トリビアン | 0s | 20s | contiguous excerpt |
| [nOCiMBsGNao](https://www.youtube.com/watch?v=nOCiMBsGNao) | held | ここちゃんねる | 13.86s | 11.54s | contiguous excerpt |
| [cNOAFv80RLk](https://www.youtube.com/watch?v=cNOAFv80RLk) | held | ちゃまはし【アニメ・声優】 | 35.15s | 11.89s | contiguous excerpt |
| [lG26PCAT5z4](https://www.youtube.com/watch?v=lG26PCAT5z4) | draft | 毎日しんちゃん | 13s | 11.85s | contiguous excerpt |
| [NSqs3cajFzg](https://www.youtube.com/watch?v=NSqs3cajFzg) | held | 世界をのぞき見! | 0s | 31s | contiguous excerpt |
| [EHo-WpfQksY](https://www.youtube.com/watch?v=EHo-WpfQksY) | draft | アニまち | 0s | 29s | complete source |
| [ffChOg3t0FE](https://www.youtube.com/watch?v=ffChOg3t0FE) | draft | 極悪特区 | 0s | 36s | complete source |
| [LoBDOW2-AJg](https://www.youtube.com/watch?v=LoBDOW2-AJg) | draft | あおぎり高校 - Aogiri Vtuber High School | 0s | 70s | complete source |
| [8gVuJ9aZBZI](https://www.youtube.com/watch?v=8gVuJ9aZBZI) | held | ひみつ基地。 | 0s | 18.84s | contiguous excerpt |
| [TyS8SeJNfeI](https://www.youtube.com/watch?v=TyS8SeJNfeI) | draft | りくらぼ / RikuLab | 0s | 52s | complete source |
| [mhBbYPeTZ9o](https://www.youtube.com/watch?v=mhBbYPeTZ9o) | held | たろたん | 66.704s | 14.96s | contiguous excerpt |
| [jcpJaSK0oDM](https://www.youtube.com/watch?v=jcpJaSK0oDM) | held | ヘビさんのアウトドア日誌 | 14.518s | 22.896s | contiguous excerpt |
| [-h2btPiOxlk](https://www.youtube.com/watch?v=-h2btPiOxlk) | draft | 東出昌大 | 8.62s | 23.96s | contiguous excerpt |
| [AhCds2EUG24](https://www.youtube.com/watch?v=AhCds2EUG24) | draft | あーずかい | 30.41s | 38.44s | contiguous excerpt |
| [ph3ZEzGZnVg](https://www.youtube.com/watch?v=ph3ZEzGZnVg) | draft | Hanaの暮らし | 0s | 30.62s | contiguous excerpt |
| [c74g0BarqBE](https://www.youtube.com/watch?v=c74g0BarqBE) | draft | 錬磨 | 0s | 26.46s | contiguous excerpt |
| [UwEHgaS-ihY](https://www.youtube.com/watch?v=UwEHgaS-ihY) | draft | 日本の紫陽花 | 0s | 19.14s | contiguous excerpt |
| [iURMTVKNCbk](https://www.youtube.com/watch?v=iURMTVKNCbk) | draft | のすけぼっち飯 | 0s | 61s | complete source |
| [XsFd2f2w0vU](https://www.youtube.com/watch?v=XsFd2f2w0vU) | held | マイ | 3.71s | 13.29s | contiguous excerpt |
| [TWrHhgP7FD4](https://www.youtube.com/watch?v=TWrHhgP7FD4) | draft | 小物ロマン | 0s | 36.76s | contiguous excerpt |
| [CzbzzIrgQ3o](https://www.youtube.com/watch?v=CzbzzIrgQ3o) | held | ともき | 78.652s | 7.48s | contiguous excerpt |
| [63p0o7t3HMU](https://www.youtube.com/watch?v=63p0o7t3HMU) | held | やまかわてるき | 8.966s | 11.1s | contiguous excerpt |
| [q2a02nfgfZE](https://www.youtube.com/watch?v=q2a02nfgfZE) | held | いい声ボイトレ研究所 | 24.79s | 73.284s | contiguous excerpt |
| [yU2tLkfS7j8](https://www.youtube.com/watch?v=yU2tLkfS7j8) | held | 青ヶ島ちゃんねる AOGASHIMA Channel | 90.8s | 25.5s | contiguous excerpt |
| [LhkJVdi8CcM](https://www.youtube.com/watch?v=LhkJVdi8CcM) | draft | カズチャンネル/Kazu Channel | 30s | 105.24s | contiguous excerpt |
| [G4EkX9MraGk](https://www.youtube.com/watch?v=G4EkX9MraGk) | held | ちゃまはし【アニメ・声優】 | 0s | 14.6s | contiguous excerpt |

Exact IDs, source windows, proof hashes, correction counts and review notes are in [the JSON audit](held-catalog-followup-20261105.json). Cached media, model weights and credentials are not committed.
