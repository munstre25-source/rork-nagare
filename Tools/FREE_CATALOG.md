# One-off catalog expansion without Gemini

The daily publishing schedule is disabled at the user's request. Use `free_catalog_pipeline.py` for manual one-off runs. It uses public YouTube metadata through the authenticated `ingest-local-clips` endpoint; it never reads a Gemini key or calls a paid inference provider.

Source inventory: `ios-nagare/reports/attachment-channels-20261104.json`. Verified channel identities: `attachment-channel-resolution-20261104.json`. Every readable label is tied to its screenshot; names covered by navigation are explicitly marked as obscured.

The local tier accepts uncaptained videos and burned English. Short sources up to three minutes can stay complete. Longer uploads receive a coherent longer excerpt rather than a fixed 40-second maximum. The database accepts bounded processing windows up to five minutes and at least one valid subtitle line, including Shorts shorter than eight seconds. Only explicitly registered source channels may publish; live metadata is rechecked and existing source windows are not overwritten.

Offline processing uses Qwen speech recognition/alignment and OPUS Japanese-to-English translation, with pinned public model revisions. Word timings come from actual audio; collapsed or missing intervals are held. Offline English can contain errors: compare the Japanese and English before publishing and correct errors through the authenticated operator path. The operator records corrections separately from local model provenance. Do not invent independent paid-review flags.

Install a CPU PyTorch wheel, then `pip install -r Tools/requirements-free-catalog.txt`. The `--asr-model`, `--aligner-model`, and `--translation-model` arguments select downloaded local model directories. Run `free_catalog_pipeline.py --help` for the explicit source/report/cache paths. The default builds artifacts without publishing. `--apply` publishes only through the local endpoint and holds flagged English for review. Credentials are supplied by environment or an explicitly authorized in-memory Vault read, never reports.

The iOS feed now retains the server review tier and accepts these locally processed lessons and complete Shorts. A fresh app build is required for that client change. Backend publication itself does not rebuild or distribute the iOS binary.
