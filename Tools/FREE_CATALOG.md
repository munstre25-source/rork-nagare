# One-off catalog expansion without paid inference

The daily publishing schedule is disabled at the user's request. These tools never read a Gemini key or call a paid inference provider. Public YouTube metadata is rechecked by the authenticated `ingest-local-clips` endpoint. Only registered source channels may publish; existing windows are not overwritten.

## Build, review, publish

1. Discover candidates with `free_catalog_pipeline.py`, or reuse its candidates JSON. Creator captions are optional and burned English is allowed. Sources up to three minutes can stay complete; longer uploads use a coherent excerpt. The backend supports 3–300 seconds, including Shorts, without a 40-second ceiling.
2. Run `repair_held_catalog.py` against held results. Supply explicit candidate, audio-cache and report paths; `--device cpu` is the default. GPU runs use `--device cuda`. `--corrections` maps video IDs and recognition-segment indices to source-checked Japanese; original recognition and audio hashes remain separate evidence. The result is a draft, never automatic publication. `--resegment` uses short native-ASR speech windows; those anchors are only coarse search bounds. `--salvage-excerpt` tries a contiguous successfully aligned speech block when the complete window fails; it never stitches around failed phrases.
3. Review Japanese against speech and visible creator captions; fix recognition errors and rerun actual audio alignment. Review **every** English line, including output that passed heuristics. Offline OPUS translations can be seriously wrong. Check context vocabulary and proper names against the offline dictionary.
4. Prepare review JSON: a list of `{id, videoId, japanese: [exact concatenated Japanese per card], english: [reviewed translation per card], notes, dictionary?: [...]}`. Dictionary corrections identify an exact `surface` and may supply definitions/reading/romaji/POS. Consecutive tokens can merge using their existing outer audio boundaries; tokens cannot split into invented times. Single-token corrections retain conjugation bases.
5. Run `publish_reviewed_local.py --draft-directory ... --reviews ...` to produce reviewed artifacts. Add `--apply` for the explicitly authorized publication. Japanese, video ID and clip/window ID must still match the review snapshot. The endpoint requires a recorded English review, source validation, pinned model provenance and database-sealed audio alignment. Credentials come from the environment or an explicitly authorized in-memory Vault read (`--use-existing-vault`); reports never contain credentials.

`free_catalog_pipeline.py --apply` is deliberately rejected: use the explicit reviewed publisher. Use `--help` on each tool for required paths and limits. Ready-for-review counts are not publication counts. English punctuation and whole-word dictionary corrections must pass preflight: a name may include an indivisible honorific token, which must not be split into fabricated intervals.

## Timing evidence

The newer path uses local faster-whisper recognition and **raw attention/DTW jumps at the application's exact dictionary-word boundaries**. It does not call the duration-adjusting word-timestamp helper, distribute a sentence evenly, or invent missing word times. Silero VAD trims only the outside silence of each audio phrase; internal pauses and source offsets remain. Collapsed intervals are re-predicted from real audio neighborhoods, optionally slowed with pitch preserved. Unresolved words, out-of-bounds intervals and overlong DTW contexts stay held. Model alignment is not a claim of a perfect human boundary audit.

When a greedy ASR phrase boundary cuts across a word or repeated phrase, adjacent phrases can be searched jointly (at most 14 seconds, three merges). Every original dictionary word and its order survive. Natural card boundaries are restored afterward from the newly inferred word intervals, rather than showing one oversized merged card.

For a source-checked topic inside an existing cached window, use `curate_local_excerpt.py --spec ... --candidates ... --source-directory ... --audio-cache ... --whisper-model ... --translation-model ... --output ... [--device cuda]`. The spec is a list of `{videoId, lo, hi, segments: [[start, end, correctedJapanese], ...], notes}`. Times are relative to the original cached PCM window, not absolute video time. The tool verifies original audio/model/video identity, requires a single contiguous 3–300 second excerpt, rejects clipped or reordered phrases, and recomputes all final word intervals from the actual excerpt audio. Source-review notes are mandatory; they do not replace checking Japanese and every English line. Publication still uses the separate reviewed publisher.

The Qwen path remains available. Its outlier timestamp interpolation is disabled; the same real-audio refinement and rejection rules apply.

| Purpose | Pinned public model | Revision |
| --- | --- | --- |
| Whisper ASR / raw DTW | dropbox-dash/faster-whisper-large-v3-turbo | 0a363e9161cbc7ed1431c9597a8ceaf0c4f78fcf |
| Qwen ASR | Qwen/Qwen3-ASR-0.6B | 5eb144179a02acc5e5ba31e748d22b0cf3e303b0 |
| Qwen forced alignment | Qwen/Qwen3-ForcedAligner-0.6B | c7cbfc2048c462b0d63a45797104fc9db3ad62b7 |
| Independent transcript comparison only | Systran/faster-whisper-large-v3 | edaa852ec7e145841d8ffdb056a99866b5f0a478 |
| Draft English | Helsinki-NLP/opus-mt-ja-en | 0770961a39ba6bd66305b149c3f4110bcafca2e6 |

Whisper `model.bin` SHA-256: `e76620f83d5f5b69efd3d87e3dc180c1bd21df9fbebacfd4335e5e1efcc018da`. Processing records also bind the actual PCM audio hash. The independent full Whisper model has SHA-256 `69f74147e3334731bc3a76048724833325d2ec74642fb52620eda87352e3d4f1`; it is used only to corroborate Japanese, not to claim a different registered timing provenance. Slowed, overlapping short-chunk recognition can help clarify difficult speech, but any such processed audio is evidence only: final timing always uses the unmodified source PCM. Singing, background vocals, repetitive decoding and unresolved phrases must remain held; written instructions cannot be presented as words spoken over unrelated music.

Install CPU PyTorch, then `pip install -r Tools/requirements-free-catalog.txt`. Optional NVIDIA support used in this repair: `nvidia-cublas-cu12==12.9.1.4`, `nvidia-cudnn-cu12==9.10.2.21`; expose their package `lib` directories in `LD_LIBRARY_PATH`. CPU processing does not need these packages. Downloaded model weights and cached audio remain outside version control.

## Inventories and client

Original screenshot sources: `ios-nagare/reports/attachment-channels-20261104.json`; verified identities: `attachment-channel-resolution-20261104.json`. Recording-derived labels and observed filter taxonomy: `kiku-recordings-20261105.json` and the matching Markdown/CSV. Label-only and truncated names are not canonical channel IDs or approved sources. Offline OCR uses the checksum-verified PP-OCRv4 Japanese mobile model; see `extract_recording_channels.py`.

The iOS feed retains the local server review tier and accepts locally processed lessons and complete Shorts. A fresh app build is required for that previously committed client change; publishing backend clips does not distribute an iOS binary.

## Count source archives

Use the maintenance-authenticated, read-only `catalog-inventory` function to
enumerate full public uploads playlists and check each video’s metadata. The
function uses the configured YouTube key server-side and makes no inference calls.

```bash
python3 Tools/catalog_inventory.py archives \
  --channels /path/to/verified-channels.json \
  --output /path/to/archive-checkpoints \
  --request-limit 2000 --use-existing-vault
```

The channel manifest is a JSON array with `channel_id`, `title`, and
`public_upload_count` for each verified channel. Reuse the same output directory
to resume a bounded scan. Inspect `archive-summary.json` for completeness and
`metadata-candidates.jsonl.gz` for deduplicated video records.

The screen checks public status, embedding, age restrictions, live status and a
three-second minimum. It keeps long videos and videos without captions.
Declared audio language and duration are screening signals. The three-minute
bucket can prioritize short-form review. Portrait format, spoken Japanese,
transcript quality and word alignment each require their own verification.

## Daily local queue

`daily_local_catalog.py` runs the existing local models and drains the eligible queue by default. It sends reviewed lessons in batches of five, stopping at the YouTube quota. Use `--limit` to cap a run. It keeps incomplete work
in a local state directory. Each run records unpublished candidates in `source-queue.json`, including those awaiting authorized audio. An empty intake does not trigger downloads or publication.

```bash
/path/to/local-venv/bin/python Tools/daily_local_catalog.py \
  --state "$HOME/.local/state/jojo-catalog" --publish-reviewed --use-existing-vault
```

Use `--report` to replace the initial manifest of timing holds and new-channel
candidates. The local runtime and pinned model files from the existing free
pipeline must be installed on the machine that runs the job. Pass
`--model-directory` when the model folders are outside `/tmp`. The optional
Vault flag uses the existing maintenance credential in memory when a reviewed
publish batch is ready.

Place original, creator-authorized media next to `authorized-media.json` in the
state directory. Use each YouTube video ID as the key. Record the file’s exact
source offset, covered duration, SHA-256 and permission or license. New drafts
also need the verified channel ID and original video dimensions.

```json
{
  "abcdefghijk": {
    "file": "creator-original.mp4",
    "sourceStartSec": 0,
    "durationSec": 45,
    "sha256": "<SHA-256 of the file>",
    "permission": "<creator permission or applicable license>",
    "channelId": "<verified YouTube channel ID>",
    "width": 1080,
    "height": 1920
  }
}
```

The local audio file must be the same edit and language track as the source
video. Alternate edits need their own source-time verification. The YouTube
metadata quota resets at midnight Pacific Time. Fresh metadata checks can then
resume, and local audio remains a separate input.

Timing proofs land in `timing-proofs` for review. New drafts land in `drafts`.
Use the existing review JSON format in `reviews.json` and include the draft’s
`alignment.audioSha256` as `audioSha256` on each review. The daily runner sends
only those reviewed snapshots for publication. It checks the current live
catalog first to avoid publishing an existing source twice. See `last-run.json`
for the result of each run.
