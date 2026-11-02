# Learning UI handoff — 2 November 2026

These changes are native iOS only. No Supabase migration or AI processing is needed. The separately edited HANDOFF-SIMULATOR.md has been left untouched.

## Playback layout and paging — updated after screenshot review

- Shorts always show a dedicated playback row immediately below the full video, in normal and maximized modes. Play/pause, speed, save/like, subtitle help, options, size control and the playback clock stay reachable before karaoke. Their colors follow the page appearance, with dark ink on the light surface.
- Landscape-video theater keeps controls hidden until a downward swipe, then auto-hides them after four seconds of idle playback. Pausing, open dialogs and VoiceOver keep revealed controls available.
- A landscape picture is centered near the safe viewport's vertical midpoint, with a bounded karaoke panel below. It shifts only as needed to fit visible controls and larger text. The picture never extends underneath the status bar.
- Rotated wide screens center the complete picture beside the bounded sentence panel.
- Shorts reserve explicit height for video, the measured playback row, and scrollable karaoke; none overlaps the others.
- Explore queues are preserved. Opening a selected clip starts that clip within its queue. For You, Explore queues and onboarding use the same snapping rule and exact viewport-sized, clipped pages, re-anchored after rotation/maximize/minimize. One complete clip occupies each settled page; the next appears after a swipe.
- Back/navigation in Explore occupies a real row above the pager and uses appearance-aware colors.
- No subtitle times, translations, catalog publication flags or AI processing changed.

## Vocabulary progress

- The top card shows current Known words, labeled words learned, with the definition visible.
- Daily practice counts distinct saved-word keys reviewed or rated on the local calendar day. Repeat ratings of one word count once; merely saving/tapping a word does not count as practiced or learned.
- Target starts at ten words and can be changed in Vocab or Profile. It is independent of the existing watch-minute target.
- UserProfile adds defaulted dailyVocabularyGoal. Verify an existing local SwiftData store upgrades without losing preferences; do not erase it to make the build work.
- Progress uses saved review timestamps, works offline and refreshes across midnight.

## Karaoke coverage

A read-only live snapshot found 191 published clips and 1,195 subtitle lines; none lacked Japanese tokens or valid sentence bounds. 1,130 lines have usable word timing. 65 lines across ten clips deliberately use sentence timing.

- Shared playback rendering keeps the moving word cursor for usable word timings.
- Empty, zero-duration, out-of-order, out-of-bounds or repeated whole-sentence token times cannot claim word sync.
- Legacy punctuation tags such as punct are recognized, so punctuation with zero duration does not disable valid word alignment.
- Sentence-timed lines use a visible, gently pulsing sentence cursor while their actual sentence is playing. Reduce Motion uses a steady cursor. Pausing or leaving the sentence stops it.
- No word timings were fabricated, subtitles rewritten, clips unpublished or AI jobs invoked.

Sentence-only clips need proper audio alignment before claiming word-level karaoke; the renderer does not guess:

- immersion-0FJvvV6uGJ0-33-59 — 〔Mondo切り抜き〕韓国語勉強方法のおすすめは？本？アニメ？会話？〔雑談〕
- immersion-0qITlsOy4LU-0-12 — 【60歳から話せる韓国語】韓国の幼稚園児が覚える挨拶と基本表現50選｜初心者・独学・聞き流し・超入門におすすめ
- immersion-fOfIHF2JjI8-18-30 — 【超面白まとめ】\"あの不破湊\"を凌駕するレベルの意味不明さを持つ大型新人登場に脳が破壊されるローレンwwww【ローレン・イロアス/切り抜き/不破湊/叢雲カゲツ/にじさんじ/Fall guys】
- immersion-hDfAn3KfBjk-0-13 — 香港＆台湾人の中国人に対する本音を街頭インタビューしたら驚きの結果に、、！
- immersion-hDfAn3KfBjk-13-30 — 香港＆台湾人の中国人に対する本音を街頭インタビューしたら驚きの結果に、、！
- immersion-MDtiDGr_-GY-3-17 — バラエティ能力が高い声優3選#shorts #アニメ #声優
- immersion-Njk2kfY4irI-40-54 — 日本語NG縛りでエクスが喋る適当すぎる英語に大爆笑する葛葉たち【にじさんじ/切り抜き/まとめ】
- immersion-oN4DNLhbzUE-32-42 — 【ULTIMATE CHICKEN HORSE】回転タレット怖すぎだって！ -切り抜き- #Shorts
- immersion-rXF2YFvMxKY-32-58 — パパ活④こんな女子ってどう？ #ショートドラマ　#ショートムービー#ショートフィルム #longervideos #感動 #感動ドラマ  #演じてみた #shortstory
- immersion-Z_leh6MUPHI-72-86 — 【日本語吹き替え】3年間見下した無能な婿を捨てた元妻。離婚直後、彼が総資産100億の超大物だと判明！エリート美女と再婚し大逆転ｗｗ

## Daily goal completion

For You replaces the persistent completed-goal meter with a brief celebration and an optional review shortcut for up to ten genuinely due words. It collapses after six seconds, can be dismissed immediately, and stays out of the feed on later visits that day. VoiceOver users dismiss it themselves. Explore/Profile retain goal history/status. Completion never forces a review or changes playback.

## Verification and simulator work

Swift syntax was checked with a temporary parser; AppModel has the same existing parser limitation as before. This is not an Xcode type-check. Native regression cases cover vocabulary deduplication/local day boundaries/target persistence and legacy timing/punctuation/fallback behavior.

On macOS, pull main safely and run Jojo's Xcode build and test target. Verify:

1. Both video orientations in light and dark modes, small/large phones, tablet and rotation. Maximize/minimize repeatedly without player restart, seek, status-bar cropping or karaoke overlap. Shorts controls must remain visible in every state, ahead of karaoke.
2. For landscape theater, swipe down/up; pause and wait; play and wait four seconds; open More and Subtitle help and wait longer than four seconds. Controls must remain while a dialog is open. Repeat in Explore queue/single playback and onboarding. VoiceOver must have Show playback controls.
3. Open a clip from the middle of an Explore list or from Vocab. Preserve the selected clip/sentence and any queue. At rest show exactly one clip per screen; swipe once for the next. Rotate and maximize/minimize at the first, middle and last pages without a neighboring clip peeking into the same frame.
4. A word-timed clip moves the word cursor; a sentence-only clip highlights the sentence, not an invented word. Seek/pause/resume and change subtitle modes without resetting playback. Test Reduce Motion.
5. Review the same word twice and mark another Known: daily practice counts distinct words; learned count follows Known state. Adjust target, relaunch, change filters and cross local midnight. Filters do not alter overall progress.
6. Reach the watch goal with/without due words: celebrate once, optional review opens the real queue, close/timeout removes it, and a later visit does not restore the completed meter.

Native regression cases now also cover centered full-video containment and shared pager snapping. These require the macOS test target; geometry and Swift syntax checks on Windows are not a native UI build.
