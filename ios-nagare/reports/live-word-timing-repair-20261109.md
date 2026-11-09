# Live catalog word timing repair

Local audio alignment upgraded **49 of the 211** originally line-timed clips, covering 248 subtitle lines. The public catalog now shows 408 clips with word timing on every line and 162 with at least one line-timed subtitle.

Public verification checked that every repaired clip retained the same source bounds, Japanese, English, dictionary data and original review information. Each repaired line has a sealed local alignment receipt. The batch used zero paid inference calls.

## Remaining clips

- 148 need a complete source-audio window.
- 14 have cached audio but still need transcript or alignment review.

## New channels

The shortlist includes 37 videos from 20 newly verified channels. YouTube requested sign-in for 29 of 29 attempted fresh audio sources. The publication metadata check also returned `quotaExceeded`. New live clips in this run: 0.

## Production repair

The deployed `review-catalog` function now accepts the pinned Whisper timing receipts already supported by the database. The punctuation migration aligns the database with the server’s treatment of the Japanese full-width tilde. The SQL regression verified both zero-duration punctuation and rejection of a zero-duration spoken word.

The [repair manifest](live-word-timing-repair-20261109.json) lists the clip IDs, repaired lines, remaining audio windows and new-channel shortlist.
