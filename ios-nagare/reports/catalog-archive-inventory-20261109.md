# YouTube catalog inventory

Inventory closed November 9, 2026. Counts combine channel statistics and uploads-playlist snapshots collected during the audit.

| Measure | Original sources | Expanded verified sources |
| --- | ---: | ---: |
| Distinct channel IDs | 54 | 537 |
| Public uploads reported by YouTube | 41,789 | 297,472 |
| Archives paged through to the end | 54 | 435 |
| Unique video IDs enumerated | 41,618 | 233,446 |
| Videos passing the metadata screen | 41,551 | 233,218 |
| Candidates with Japanese audio declared | 23,798 | 117,795 |
| Candidates up to three minutes | 24,520 | 179,421 |

The public catalog contains **570 clips from 360 videos**. Of the enumerated metadata candidates, 129 already appear in the live catalog. The scan identified 117,714 unused candidates with declared Japanese audio, including 81,257 up to three minutes.

## Coverage

Of 1,343 recording-label groups, 523 matched a verified channel ID and 820 still need identity checks. Resolution used previously verified IDs, exact normalized titles and observed handles. Guessed handles were used to discover channels. A title or an observed handle still had to match the recording evidence. Duplicate exact matches and truncated or possible video titles stayed out of the resolved set.

The expanded totals include 27 partially scanned channels, 9 unscanned channels, and 66 channels that reported zero public uploads and had unavailable playlists. The archives without a complete scan account for 92,888 reported uploads. The expanded scan prioritized smaller archives for complete coverage and saved page checkpoints when YouTube returned quotaExceeded.

The metadata screen uses public status, embedding eligibility, live status, age restrictions and a three-second minimum. It includes uncaptioned and long videos. Language declarations and the three-minute duration bucket help prioritize review. Japanese speech, portrait format, transcripts and word timing require separate verification.

The audit used zero Gemini or paid inference calls. It published zero clips.

See the [channel and label manifest](catalog-archive-inventory-20261109.json) for per-channel coverage and recording-label decisions.

YouTube exposes the public upload count and paginated upload IDs through separate API resources. [Channel statistics](https://developers.google.com/youtube/v3/docs/channels#statistics.videoCount), [Playlist pagination](https://developers.google.com/youtube/v3/docs/playlistItems/list).
