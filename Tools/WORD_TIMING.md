# Word timing without paid inference

`repair_word_timing_local.py` aligns the existing public catalog against its original source audio with [Qwen3-ForcedAligner-0.6B](https://huggingface.co/Qwen/Qwen3-ForcedAligner-0.6B). Inference runs on this machine. There is no paid AI call, API key, budget reservation or credit requirement. The first run downloads public model weights; later runs can use the cached model. This is a local speech model, not a dictionary or even-duration subtitle animation.

Install a PyTorch wheel matching the machine first (CPU works), then:

```sh
python3 -m venv /tmp/jojo-word-alignment-venv
/tmp/jojo-word-alignment-venv/bin/pip install torch==2.6.0 --index-url https://download.pytorch.org/whl/cpu
/tmp/jojo-word-alignment-venv/bin/pip install -r Tools/requirements-word-alignment.txt
```

Pilot without saving to the catalog:

```sh
/tmp/jojo-word-alignment-venv/bin/python Tools/repair_word_timing_local.py \
  --limit 3 --device cpu --media-directory /tmp/jojo-source-audio \
  --report-directory /tmp/jojo-local-timing-pilot
```

An authorized maintenance operator can add `--apply --use-existing-vault`. The existing project maintenance credential stays in memory and never enters reports. Set `--limit 0` to process all remaining published clips. Model and source windows are read with bounded HTTP Range requests and cached locally; unavailable source audio is held rather than replaced by guessed timestamps. Creator media access controls are not bypassed.

For one already-extracted clip, use `local_word_alignment.py --clip-json ... --audio ... --output ... --device cpu`. A full-source media file also needs `--audio-start SOURCE_START`; an extracted clip starts at zero.

The aligner predicts a real audio interval for each existing app token. It preserves source text, readings, definitions and translations, pins punctuation to zero duration, and rejects missing/collapsed/overlapping/out-of-source intervals. The model has native 80 ms timestamp resolution; collapsed short units are retried on pitch-preserved 2x-slowed audio (40 ms bins in the original time base). Automated alignment is not proof of frame-perfect timing or transcript correctness; uncertain results need source/transcript review. Do not label these results as an independent translation or visual review.

The authenticated `review-catalog` local path takes the exact original subtitle snapshot and source bounds. The database permits only timing changes to already-published content, preserving its category, source, review tier and original review fields. It cannot publish a new or held clip, replace translations/meanings, or pretend local alignment is paid independent verification. Local receipts record the model revision, audio SHA-256, original payload hash and resulting integrity seal. New content still needs the existing content/source publication checks; run local alignment before publishing it through a supported reviewed workflow.

The older `repair_word_timing_catalog.py --apply` operator now requires explicit `--paid-ai`; it cannot accidentally choose paid processing as a fallback.

Verification:

```sh
python3 -m unittest discover -s Tools -p test_local_word_alignment.py
npx deno test --allow-env --allow-read --allow-net ios-nagare/supabase/functions/_shared
```

Run `supabase/tests/local_alignment_guard.sql` inside a rollback-only transaction with the new migration. It checks service-only privileges, source/content preservation, stale-source rejection, invalid timing rejection, and that a local receipt cannot pass independent review checks.
