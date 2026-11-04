#!/usr/bin/env python3
"""Align an existing Japanese clip on this machine. No paid API or time interpolation."""
import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import subprocess
import unicodedata

MODEL = "Qwen/Qwen3-ForcedAligner-0.6B"
REVISION = "c7cbfc2048c462b0d63a45797104fc9db3ad62b7"


def spoken_text(text):
    return "".join(c for c in unicodedata.normalize("NFKC", text)
                   if unicodedata.category(c)[0] in ("L", "N") or c == "'")


def token_units(line):
    return [(i, spoken_text(t["surface"])) for i, t in enumerate(line["tokens"])
            if spoken_text(t["surface"]) and t["surface"] not in ("ー", "〜")]


def map_alignment(line, items, offset, duration):
    """One real model interval per app word. Never split an interval arithmetically."""
    units = token_units(line)
    if len(items) != len(units):
        raise ValueError("Aligner did not return every requested word")
    tokens = copy.deepcopy(line["tokens"])
    cursor = offset
    spans = {}
    # Tiny float/stretch slop only — never invent a missing boundary.
    edge = 0.03
    for (index, text), item in zip(units, items):
        if spoken_text(item["text"]) != text:
            raise ValueError("Aligner changed the requested transcript")
        start = round(offset + float(item["start_time"]), 3)
        end = round(offset + float(item["end_time"]), 3)
        if not all(math.isfinite(t) for t in (start, end)):
            raise ValueError("Word lies outside its actual audio")
        if start < offset - edge or end > duration + edge:
            raise ValueError("Word lies outside its actual audio")
        start = min(max(start, offset), duration)
        end = min(max(end, start), duration)
        if end <= start or start < cursor - .001:
            raise ValueError("Collapsed or overlapping word timing needs review")
        if end - start > max(2.5, len(text) * .7):
            raise ValueError("Word spans implausibly long audio")
        spans[index] = (start, end)
        cursor = end
    if not spans:
        raise ValueError("No spoken words")
    cursor = min(s[0] for s in spans.values())
    for i, token in enumerate(tokens):
        start, end = spans.get(i, (cursor, cursor))
        token.update(start=start, end=end)
        cursor = end
    return {**copy.deepcopy(line), "start": min(s[0] for s in spans.values()),
            "end": max(s[1] for s in spans.values()), "tokens": tokens, "timing": "word"}



def invalid_items(items, duration):
    """Locate unusable model predictions without repairing them arithmetically."""
    bad = set()
    for i, item in enumerate(items):
        start, end = item["start_time"], item["end_time"]
        if not all(math.isfinite(x) for x in (start, end)) or start < -.03 or end > duration + .03 or end <= start or end-start > max(2.5, len(item["text"])*.7):
            bad.add(i)
        if i and start < items[i-1]["end_time"]-.001:
            bad.update((i-1, i))
    return bad


def refine_items(items, audio, infer):
    """Re-predict failed words in short anchored audio, retaining real model boundaries."""
    import copy
    current, evidence = copy.deepcopy(items), []
    duration = len(audio)/16000
    for _ in range(2):
        bad = invalid_items(current, duration)
        if not bad: break
        groups = []
        for index in sorted(bad):
            lo, hi = max(0,index-2), min(len(current),index+3)
            if groups and lo <= groups[-1][1]: groups[-1][1] = max(groups[-1][1],hi)
            else: groups.append([lo,hi])
        changed = False
        for first, last in groups:
            lo = max(0.,current[first-1]["end_time"]) if first else 0.
            hi = min(duration,current[last]["start_time"]) if last<len(current) else duration
            if not math.isfinite(lo+hi) or hi-lo < .1: continue
            units = [x["text"] for x in current[first:last]]
            window = audio[round(lo*16000):round(hi*16000)]
            for factor in (2,4):
                try:
                    predicted = infer(window,units,factor)
                except ValueError:
                    continue
                evidence.append({"firstWord":first,"lastWordExclusive":last,"audioStartSec":lo,"audioEndSec":hi,"audioTimeScale":factor,"items":predicted})
                if len(predicted)!=len(units) or any(x["text"]!=u for x,u in zip(predicted,units)) or invalid_items(predicted,len(window)/16000): continue
                replacement = [{**x,"start_time":round(x["start_time"]+lo,3),"end_time":round(x["end_time"]+lo,3)} for x in predicted]
                candidate = current[:first]+replacement+current[last:]
                if len(invalid_items(candidate,duration)) < len(invalid_items(current,duration)):
                    current = candidate;changed = True;break
        if not changed: break
    return current,evidence


def extract_audio(path, start, duration):
    import imageio_ffmpeg
    import numpy as np
    cmd = [imageio_ffmpeg.get_ffmpeg_exe(), "-v", "error", "-ss", str(start), "-i", str(path),
           "-t", str(duration), "-vn", "-ac", "1", "-ar", "16000", "-f", "f32le", "pipe:1"]
    pcm = subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout
    audio = np.frombuffer(pcm, dtype="<f4").copy()
    if len(audio) < 1600 or not np.isfinite(audio).all() or float(np.max(np.abs(audio))) < .001:
        raise ValueError("Source has no usable audio")
    return audio


class LocalAligner:
    def __init__(self, model_path=MODEL, device="cuda:0"):
        import torch
        if device == "cpu":
            torch.set_num_threads(min(8, max(1, __import__("os").cpu_count() or 1)))
        from qwen_asr import Qwen3ForcedAligner
        self.model = Qwen3ForcedAligner.from_pretrained(model_path,
            **({"revision": REVISION} if model_path == MODEL else {}),
            dtype=torch.bfloat16 if device.startswith("cuda") else torch.float32,
            device_map=device, attn_implementation="sdpa")

    def _infer(self, window, units, factor):
        if factor != 1:
            import librosa
            window = librosa.effects.time_stretch(window, rate=1/factor)
        processor = self.model.aligner_processor
        tokenize, fix = processor.tokenize_japanese, processor.fix_timestamp
        processor.tokenize_japanese = lambda text: units
        # The upstream postprocessor interpolates some non-monotonic outliers.
        # Keep raw predictions here so refinement must use the actual sound.
        processor.fix_timestamp = lambda data: [int(x) for x in data.tolist()]
        try:
            result = self.model.align(audio=(window,16000),text=" ".join(units),language="Japanese")[0]
        finally:
            processor.tokenize_japanese, processor.fix_timestamp = tokenize, fix
        return [dict(text=t.text,start_time=round(t.start_time/factor,3),end_time=round(t.end_time/factor,3)) for t in result]

    def align(self, clip, audio):
        import numpy as np
        duration = len(audio) / 16000
        if abs(duration - float(clip["duration_sec"])) > .25:
            raise ValueError("Extracted audio does not match clip duration")
        lines, evidence = [], []
        previous_end = 0.0
        for index, line in enumerate(clip["lines"]):
            # Sentence bounds restrict the search, but do not manufacture word boundaries.
            # Floor at the previous aligned end so padded windows cannot overlap sentences.
            lo = max(0.0, previous_end, float(line["start"]) - .35)
            hi = min(duration, max(lo + 0.08, float(line["end"]) + .35))
            if hi <= lo:
                raise ValueError("Invalid original sentence bounds")
            units = [text for _, text in token_units(line)]
            if not units:
                raise ValueError("Sentence has no spoken words")
            aligned, attempts, failure = None, [], None
            window = audio[round(lo*16000):round(hi*16000)]
            for factor in (1,2,4):
                if len(window) < 1600:
                    failure = "Sentence audio window is empty"
                    continue
                if getattr(self,"max_audio_seconds",None) and len(window)*factor/16000 > self.max_audio_seconds:
                    failure = "Phrase exceeds aligner audio context"
                    continue
                try:
                    items = self._infer(window,units,factor)
                except ValueError as error:
                    failure = str(error)
                    continue
                attempts.append({"audioTimeScale":factor,"rawPredictions":True,"items":items})
                if invalid_items(items,len(window)/16000):
                    items,refinements = refine_items(items,window,self._infer)
                    attempts[-1]["refinements"] = refinements
                try:
                    aligned = map_alignment(line, items, lo, duration)
                    break
                except ValueError as error:
                    failure = str(error)
            if aligned is None:
                raise ValueError(f"line[{index}]: {failure}")
            if lines and aligned["start"] < lines[-1]["end"] - 0.001:
                raise ValueError(f"line[{index}]: aligned sentences overlap; transcript check required")
            lines.append(aligned)
            previous_end = float(aligned["end"])
            evidence.append({"lineIndex": index, "audioStartSec": lo, "audioEndSec": hi, "attempts": attempts})
        return {"version": 1, "method": "local-forced-alignment", "model": MODEL, "revision": REVISION,
                "audioSha256": hashlib.sha256(np.asarray(audio, dtype="<f4").tobytes()).hexdigest(),
                "sampleRate": 16000, "audioDurationSec": duration, "videoId": clip["video_id"],
                "sourceStartSec": float(clip.get("source_start_sec", 0)),
                "durationSec": float(clip["duration_sec"]), "lines": lines, "evidence": evidence}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--clip-json", type=Path, required=True)
    p.add_argument("--audio", type=Path, required=True)
    p.add_argument("--audio-start", type=float, default=0, help="Offset into provided media; local clip starts at zero")
    p.add_argument("--model-path", default=MODEL)
    p.add_argument("--device", default="cuda:0")
    p.add_argument("--output", type=Path, required=True)
    args = p.parse_args()
    clip = json.loads(args.clip_json.read_text())
    audio = extract_audio(args.audio, args.audio_start, float(clip["duration_sec"]))
    result = LocalAligner(args.model_path, args.device).align(clip, audio)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2))
    print(json.dumps({"id": clip["id"], "status": "aligned_locally", "lines": len(result["lines"]),
                      "paidApiCalls": 0, "output": str(args.output)}), flush=True)


if __name__ == "__main__":
    main()
