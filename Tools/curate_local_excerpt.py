#!/usr/bin/env python3
"""Build source-checked, contiguous local lesson drafts. Never publish automatically."""
import argparse
import copy
import hashlib
import json
import math
import re
from pathlib import Path

from local_whisper_catalog import LocalWhisperProcessor, ASR_MODEL, ASR_REVISION


def prepare_excerpt(audio, rate, identity, original, selection):
    """Bind an operator transcript to the exact original PCM and a real source window."""
    if rate != 16000 or audio.ndim != 1:
        raise ValueError("Expected mono 16 kHz source audio")
    digest = hashlib.sha256(audio.tobytes()).hexdigest()
    if original.get("audioSha256") != digest:
        raise ValueError("Recognition/audio identity mismatch")
    if original.get("asrModel") != ASR_MODEL or original.get("asrRevision") != ASR_REVISION:
        raise ValueError("Original pinned ASR provenance required")
    vid = selection["videoId"]
    if not re.fullmatch(r"[A-Za-z0-9_-]{11}", vid) or identity.get("videoId") != vid:
        raise ValueError("Source video identity mismatch")
    lo, hi = selection["lo"], selection["hi"]
    offset = identity["sourceStartSec"]
    if any(isinstance(x, bool) or not isinstance(x, (int, float)) or not math.isfinite(x) for x in (lo, hi, offset)):
        raise ValueError("Finite source bounds required")
    first, last = round(lo * rate), round(hi * rate)
    if offset < 0 or first < 0 or last > len(audio) or not 3 * rate <= last - first <= 300 * rate:
        raise ValueError("Excerpt outside actual audio or 3-300 second bounds")
    notes = selection.get("notes")
    segments = selection.get("segments")
    if not isinstance(notes, str) or not notes.strip() or not isinstance(segments, list) or not segments:
        raise ValueError("Source-review notes and corrected speech phrases required")
    lo, duration = first / rate, (last - first) / rate
    phrases, previous = [], lo
    for start, end, text in segments:
        if any(isinstance(x, bool) or not isinstance(x, (int, float)) or not math.isfinite(x) for x in (start, end)):
            raise ValueError("Finite phrase bounds required")
        if start < lo - .001 or end > last / rate + .001 or end <= start or start < previous - .001:
            raise ValueError("Corrected phrases must remain ordered inside one contiguous source window")
        if not isinstance(text, str) or not text.strip():
            raise ValueError("Corrected Japanese phrase required")
        phrases.append(dict(start=max(0., start-lo), end=min(duration, end-lo), text=text))
        previous = end
    # Confidence remains original model evidence, never an invented operator score.
    confidence = min(s["avgLogProbability"] for s in original["segments"])
    silence = max(s["noSpeechProbability"] for s in original["segments"])
    for phrase in phrases:
        phrase.update(avgLogProbability=confidence, noSpeechProbability=silence)
    excerpt = audio[first:last]
    heard = {**copy.deepcopy(original), "segments": phrases,
             "audioSha256": hashlib.sha256(excerpt.tobytes()).hexdigest()}
    return excerpt, offset + lo, heard, digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("spec", "candidates", "source-directory", "audio-cache", "whisper-model", "translation-model", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--device", choices=["cpu", "cuda"], default="cpu")
    args = parser.parse_args()
    import soundfile as sf
    candidates = {r["video_id"]: r for r in json.loads(args.candidates.read_text())}
    identities = {}
    for path in args.audio_cache.glob("*.json"):
        identity = json.loads(path.read_text())
        if identity.get("videoId"):
            identities.setdefault(identity["videoId"], []).append((path, identity))
    args.output.mkdir(parents=True, exist_ok=True)
    processor = LocalWhisperProcessor(str(args.whisper_model), str(args.translation_model), args.device)
    summary = []
    for selection in json.loads(args.spec.read_text()):
        vid = selection["videoId"]
        result = dict(video_id=vid, status="held")
        try:
            video = candidates[vid]
            result["channel"] = video["channel_name"]
            matches = identities.get(vid, [])
            if len(matches) != 1:
                raise ValueError("Require exactly one identified source audio window")
            path, identity = matches[0]
            original = json.loads((args.source_directory / (vid + "-whisper.json")).read_text())
            info = json.loads((args.source_directory / (vid + "-metadata.json")).read_text())
            if info.get("id") != vid or info.get("channel_id") != video["channel_id"]:
                raise ValueError("Cached metadata/candidate identity mismatch")
            audio, rate = sf.read(path.with_suffix(".wav"), dtype="float32")
            excerpt, start, heard, digest = prepare_excerpt(audio, rate, identity, original, selection)
            clip, evidence = processor.process(video, info, excerpt, start, heard)
            clip["processing"].update(operatorTranscriptCorrections=list(range(len(heard["segments"]))),
                operatorTranscriptEvidence=selection["notes"], originalAudioSha256=digest,
                sourceWindowSelection="Source-checked contiguous excerpt; final word intervals recomputed from original audio")
            (args.output / (clip["id"] + ".json")).write_text(json.dumps(clip, ensure_ascii=False, indent=2))
            (args.output / (clip["id"] + "-evidence.json")).write_text(json.dumps(evidence, ensure_ascii=False))
            result.update(status="ready_for_review", id=clip["id"], duration_sec=clip["duration_sec"],
                lines=[dict(ja="".join(t["surface"] for t in line["tokens"]), en=line["translation"]) for line in clip["lines"]])
        except Exception as error:
            result["reason"] = str(error)
        summary.append(result)
        (args.output / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2))
        print(json.dumps({k:v for k,v in result.items() if k != "lines"}, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
