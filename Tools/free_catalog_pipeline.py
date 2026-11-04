#!/usr/bin/env python3
"""Discover selected channels and publish locally transcribed/aligned/translated lessons.
No Gemini key, paid inference API, creator-caption requirement, or 40-second clip limit.
"""
import argparse
import collections
import hashlib
import json
import re
import sys
import time
import urllib.error
from pathlib import Path

from local_word_alignment import LocalAligner, MODEL as ALIGNER_MODEL, REVISION as ALIGNER_REVISION
from repair_word_timing_catalog import configuration, request_json
from repair_word_timing_local import maintenance_headers
from translation_quality import translation_issues

ROOT = Path(__file__).resolve().parents[1]
ASR_MODEL, ASR_REVISION = "Qwen/Qwen3-ASR-0.6B", "5eb144179a02acc5e5ba31e748d22b0cf3e303b0"
TRANSLATION_MODEL, TRANSLATION_REVISION = "Helsinki-NLP/opus-mt-ja-en", "0770961a39ba6bd66305b149c3f4110bcafca2e6"


def natural_windows(audio, sample_rate=16000):
    """Split recognition work near low-energy boundaries; retain the entire selected clip."""
    import numpy as np
    total, cursor, out = len(audio), 0, []
    while total - cursor > 26 * sample_rate:
        lo, hi = cursor + 14 * sample_rate, min(total - 4 * sample_rate, cursor + 24 * sample_rate)
        candidates = range(lo, hi, sample_rate // 10)
        end = min(candidates, key=lambda p: float(np.mean(audio[p:p+sample_rate//10] ** 2))) + sample_rate // 20
        out.append((cursor, end)); cursor = end
    if total > cursor: out.append((cursor, total))
    return out


def display_groups(tokens, max_chars=36):
    """Stable display lines end on punctuation or a word boundary, never inside a word."""
    groups, current, chars = [], [], 0
    for token in tokens:
        length = len(token["surface"])
        if current and (chars + length > max_chars or token["end"] - current[0]["start"] > 8):
            groups.append(current); current, chars = [], 0
        current.append(token); chars += length
        if token["surface"] in ("。", "！", "？", "!", "?"):
            groups.append(current); current, chars = [], 0
    if current: groups.append(current)
    # A punctuation-only fragment belongs to its preceding spoken line.
    out = []
    for group in groups:
        if all(t["end"] <= t["start"] for t in group) and out: out[-1].extend(group)
        else: out.append(group)
    return out


class FreeProcessor:
    def __init__(self, asr_path, aligner_path, translator_path):
        import torch
        torch.set_num_threads(min(8, max(1, __import__("os").cpu_count() or 1)))
        from qwen_asr import Qwen3ASRModel
        from transformers import AutoTokenizer, AutoModelForSeq2SeqLM
        import build_caption_clips as dictionary
        if dictionary.TAGGER is None: raise ValueError("Offline Japanese tokenizer is required")
        self.dictionary_module = dictionary
        self.dictionary = dictionary.load_dictionary()
        self.asr = Qwen3ASRModel.from_pretrained(asr_path, dtype=torch.float32, device_map="cpu",
            attn_implementation="sdpa", max_new_tokens=768, max_inference_batch_size=1)
        self.aligner = LocalAligner(aligner_path, "cpu")
        self.tokenizer = AutoTokenizer.from_pretrained(translator_path)
        self.translator = AutoModelForSeq2SeqLM.from_pretrained(translator_path).eval()

    def process(self, video, info, audio, source_start):
        import torch
        import numpy as np
        duration = round(len(audio) / 16000, 3)
        lines, diagnostics = [], []
        for lo, hi in natural_windows(audio):
            window = audio[lo:hi]
            if float(np.sqrt(np.mean(window ** 2))) < .002: continue
            heard = self.asr.transcribe(audio=(window, 16000))[0]
            if heard.language != "Japanese" or not heard.text.strip():
                diagnostics.append({"start":lo/16000,"end":hi/16000,"status":"non_japanese_or_no_speech","language":heard.language})
                continue
            japanese = re.sub(r"\s+", " ", heard.text).strip()
            if len(re.findall(r"[\u3040-\u30ff\u3400-\u9fff]",japanese)) < 2: continue
            tokens = self.dictionary_module.tokenize(japanese, self.dictionary)
            # Timestamp every app word from this same audio. Temporary English is never published.
            raw_line = {"start":0,"end":len(window)/16000,"timing":"line","translation":"Local transcription pending translation.","tokens":tokens}
            segment = {"id":"segment","video_id":video["video_id"],"source_start_sec":source_start+lo/16000,
                       "duration_sec":len(window)/16000,"lines":[raw_line]}
            aligned = self.aligner.align(segment, window)
            for token in aligned["lines"][0]["tokens"]:
                token["start"] = round(token["start"] + lo/16000, 3)
                token["end"] = round(token["end"] + lo/16000, 3)
            for group in display_groups(aligned["lines"][0]["tokens"]):
                spoken = [t for t in group if t["end"] > t["start"]]
                if not spoken: continue
                lines.append({"start":spoken[0]["start"],"end":spoken[-1]["end"],"timing":"word","tokens":group})
            diagnostics.append({"start":lo/16000,"end":hi/16000,"text":heard.text,"alignment":aligned["evidence"]})
        if not lines or not any(t.get("tappable") for line in lines for t in line["tokens"]):
            raise ValueError("No Japanese speech with usable offline vocabulary")
        texts = ["".join(t["surface"] for t in line["tokens"]) for line in lines]
        english = []
        with torch.inference_mode():
            for i in range(0,len(texts),12):
                inputs = self.tokenizer(texts[i:i+12],return_tensors="pt",padding=True,truncation=True,max_length=256)
                generated = self.translator.generate(**inputs,max_new_tokens=120,num_beams=3)
                english.extend(self.tokenizer.batch_decode(generated,skip_special_tokens=True))
        for line, translation in zip(lines,english):
            translation = translation.strip()
            if not re.search(r"[A-Za-z]{2}",translation): raise ValueError("Offline translation is incomplete")
            line["translation"] = translation
        orientation = "portrait" if (info.get("height") or 0) > (info.get("width") or 1) else "landscape"
        identifier = f"local-{video['video_id']}-{round(source_start*1000)}-{round(duration*1000)}"
        clip = {"id":identifier,"video_id":video["video_id"],"title":video["title"],"channel_name":video["channel_name"],
                "category":video["category"],"difficulty":"Intermediate","source_start_sec":source_start,
                "duration_sec":duration,"video_orientation":orientation,"lines":lines,
                "processing":{"language":"Japanese","asrModel":ASR_MODEL,"asrRevision":ASR_REVISION,
                    "translationModel":TRANSLATION_MODEL,"translationRevision":TRANSLATION_REVISION}}
        clip["alignment"] = {"version":1,"method":"local-forced-alignment","model":ALIGNER_MODEL,"revision":ALIGNER_REVISION,
            "audioSha256":hashlib.sha256(np.asarray(audio,dtype="<f4").tobytes()).hexdigest(),"sampleRate":16000,
            "audioDurationSec":len(audio)/16000,"videoId":clip["video_id"],"sourceStartSec":source_start,
            "durationSec":duration,"lines":lines}
        clip["translationIssues"] = translation_issues(lines)
        return clip, diagnostics


def source_window(video, info, directory):
    import soundfile as sf
    from source_audio import extract_source_window
    source_duration = float(info.get("duration") or video["duration_sec"])
    # Keep complete Shorts and other short uploads. Long videos receive a useful
    # continuous excerpt; no 40-second filter or caption/English-overlay filter.
    start, duration = (0., source_duration) if source_duration <= 180 else (min(30.,source_duration*.05),120.)
    duration = min(duration, source_duration-start,300.)
    identity = json.dumps([video["video_id"],start,duration],separators=(",",":"))
    key = hashlib.sha256(identity.encode()).hexdigest()
    path = directory/(key+".wav");directory.mkdir(parents=True,exist_ok=True)
    if path.exists():
        audio, rate = sf.read(path,dtype="float32")
        if rate != 16000 or audio.ndim != 1: raise ValueError("Invalid cached source audio")
    else:
        audio, byte_count = extract_source_window(info,start,duration)
        temporary = path.with_suffix(".partial.wav");sf.write(temporary,audio,16000,subtype="FLOAT");temporary.replace(path)
        (directory/(key+".json")).write_text(json.dumps({"videoId":video["video_id"],"sourceStartSec":start,"requestedDurationSec":duration,"bytesFetched":byte_count}))
    return audio,start


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--sources",type=Path,required=True,help="Resolved channel report")
    p.add_argument("--report-directory",type=Path,required=True)
    p.add_argument("--media-directory",type=Path,required=True)
    p.add_argument("--per-channel",type=int,default=1)
    p.add_argument("--attempts-per-channel",type=int,default=3)
    p.add_argument("--limit",type=int,default=0)
    p.add_argument("--candidates-file",type=Path,help="Reuse discovered public candidates; publication still rechecks metadata")
    p.add_argument("--apply",action="store_true")
    p.add_argument("--use-existing-vault",action="store_true")
    p.add_argument("--asr-model",default="/tmp/jojo-qwen-asr-model")
    p.add_argument("--aligner-model",default="/tmp/jojo-qwen-aligner-model")
    p.add_argument("--translation-model",default="/tmp/jojo-ja-en-model")
    args=p.parse_args();args.report_directory.mkdir(parents=True,exist_ok=True)
    base,anon=configuration();headers=maintenance_headers(base,anon,args.use_existing_vault)
    sources=json.loads(args.sources.read_text())["sources"]
    sources=list({s["channel_id"]:s for s in sources if s["status"]=="resolved"}.values())
    candidates=[]
    if args.candidates_file:
        candidates=json.loads(args.candidates_file.read_text())
    else:
        for i in range(0,len(sources),8):
            result=request_json(base+"/functions/v1/ingest-local-clips",headers,
                {"action":"candidates","channels":[s["channel_id"] for s in sources[i:i+8]],"perChannel":20},timeout=180)
            candidates.extend(result["videos"])
    (args.report_directory/"candidates.json").write_text(json.dumps(candidates,ensure_ascii=False,indent=2))
    # Existing published source IDs are omitted to expand variety without duplicates.
    existing=set();offset=0
    while True:
        rows=request_json(base+"/rest/v1/clips?published=eq.true&select=video_id&limit=500&offset="+str(offset),headers)
        existing.update(r["video_id"] for r in rows)
        if len(rows)<500:break
        offset+=len(rows)
    queues=collections.defaultdict(list)
    for video in candidates:
        if video["video_id"] not in existing:queues[video["channel_id"]].append(video)
    for queue in queues.values():queue.sort(key=lambda v:(v["duration_sec"]>180,v["duration_sec"]>75,v["duration_sec"]))
    ordered=[]
    for n in range(args.attempts_per_channel):
        for source in sources:
            queue=queues.get(source["channel_id"],[])
            if len(queue)>n:ordered.append(queue[n])
    if args.limit:ordered=ordered[:args.limit]
    print(json.dumps({"resolvedChannels":len(sources),"candidates":len(candidates),"newSourceVideos":sum(map(len,queues.values())),"selectedAttempts":len(ordered),"paidApiCalls":0}),flush=True)
    processor=FreeProcessor(args.asr_model,args.aligner_model,args.translation_model)
    from yt_dlp import YoutubeDL
    summary=[];accepted=collections.Counter()
    for video in ordered:
        if accepted[video["channel_id"]]>=args.per_channel:continue
        result={"video_id":video["video_id"],"channel":video["channel_name"],"status":"held"}
        started=time.monotonic()
        try:
            with YoutubeDL({"quiet":True,"no_warnings":True,"noplaylist":True,"retries":1,"socket_timeout":30}) as downloader:
                info=downloader.extract_info("https://www.youtube.com/watch?v="+video["video_id"],download=False)
            if info.get("channel_id")!=video["channel_id"]:raise ValueError("Source identity changed")
            audio,start=source_window(video,info,args.media_directory)
            clip,evidence=processor.process(video,info,audio,start)
            (args.report_directory/(clip["id"]+".json")).write_text(json.dumps(clip,ensure_ascii=False,indent=2))
            (args.report_directory/(clip["id"]+"-evidence.json")).write_text(json.dumps(evidence,ensure_ascii=False))
            if args.apply and clip["translationIssues"]:
                raise ValueError("Offline English requires review: " + ",".join(str(x["lineIndex"]) for x in clip["translationIssues"]))
            if args.apply:
                response=request_json(base+"/functions/v1/ingest-local-clips",headers,{"clips":[clip]},timeout=180)
                if not response.get("accepted"):raise ValueError((response.get("rejected") or [{"reason":"Publication not accepted"}])[0]["reason"])
                result["status"]="published"
            else:result["status"]="ready_locally"
            result.update(id=clip["id"],duration_sec=clip["duration_sec"],orientation=clip["video_orientation"],lines=len(clip["lines"]))
            accepted[video["channel_id"]]+=1
        except urllib.error.HTTPError as error:
            result.update(reason="remote_request_rejected",http=error.code)
            if error.code in (401,403,429,500,503):
                summary.append(result);print(json.dumps(result),flush=True);break
        except ValueError as error:result["reason"]=str(error)[:220]
        except Exception as error:result["reason"]=type(error).__name__
        result["seconds"]=round(time.monotonic()-started,1)
        summary.append(result);(args.report_directory/"summary.json").write_text(json.dumps(summary,ensure_ascii=False,indent=2))
        print(json.dumps(result,ensure_ascii=False),flush=True)
    (args.report_directory/"summary.json").write_text(json.dumps(summary,ensure_ascii=False,indent=2))
    print(json.dumps({"processed":len(summary),"published":sum(s["status"]=="published" for s in summary),"channelsAdded":len(accepted),"paidApiCalls":0}),flush=True)


if __name__=="__main__":main()
