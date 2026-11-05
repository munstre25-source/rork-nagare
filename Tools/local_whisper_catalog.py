"""Free local Whisper transcription, raw attention/DTW, and offline dictionary/English."""
import re
import hashlib
from pathlib import Path
from types import SimpleNamespace

from free_catalog_pipeline import display_groups
from local_word_alignment import LocalAligner
from translation_quality import translation_issues

ASR_MODEL = "dropbox-dash/faster-whisper-large-v3-turbo"
ASR_REVISION = "0a363e9161cbc7ed1431c9597a8ceaf0c4f78fcf"
ASR_SHA256 = "e76620f83d5f5b69efd3d87e3dc180c1bd21df9fbebacfd4335e5e1efcc018da"
TRANSLATION_MODEL = "Helsinki-NLP/opus-mt-ja-en"
TRANSLATION_REVISION = "0770961a39ba6bd66305b149c3f4110bcafca2e6"

def verify_whisper_weights(model_path):
    digest=hashlib.sha256()
    with (Path(model_path)/"model.bin").open("rb") as weights:
        for block in iter(lambda:weights.read(8*1024*1024),b""):digest.update(block)
    if digest.hexdigest()!=ASR_SHA256:raise ValueError("Whisper model checksum mismatch")

def align_phrase_context(aligner,clip,audio):
    """Retry adjacent phrases jointly when a greedy ASR boundary misplaces words."""
    import copy
    draft=copy.deepcopy(clip);merges=[]
    for attempt in range(4):
        try:return aligner.align(draft,audio),merges
        except ValueError as error:
            match=re.search(r"line\[(\d+)\]",str(error))
            if not match or attempt==3:raise
            index=int(match.group(1));first=max(0,index-1);last=min(len(draft["lines"]),index+2)
            group=draft["lines"][first:last]
            if len(group)<2 or group[-1]["end"]-group[0]["start"]>14:raise
            # Every dictionary token and its order survives. Only the coarse ASR
            # search window changes; all final times are inferred again from audio.
            combined={**group[0],"end":group[-1]["end"],"tokens":[token for line in group for token in line["tokens"]]}
            draft["lines"][first:last]=[combined]
            merges.append({"firstPhrase":first,"lastPhraseExclusive":last,"reason":str(error)})

def restore_phrase_groups(original_lines, aligned_lines):
    """Restore natural card boundaries after joint acoustic search, keeping every word time."""
    original = [t for line in original_lines for t in line["tokens"]]
    aligned = [t for line in aligned_lines for t in line["tokens"]]
    if [t["surface"] for t in original] != [t["surface"] for t in aligned]:
        raise ValueError("Joint alignment changed transcript word identity/order")
    restored, offset = [], 0
    for line in original_lines:
        tokens = aligned[offset:offset + len(line["tokens"])]; offset += len(tokens)
        spoken = [t for t in tokens if t["end"] > t["start"]]
        if spoken:
            restored.append({"start":spoken[0]["start"], "end":spoken[-1]["end"],
                "timing":"word", "tokens":tokens})
    return restored

class LocalWhisperAligner(LocalAligner):
    """Raw attention/DTW jumps at exact app-word token boundaries; no duration hacks."""
    max_audio_seconds=None
    context_seconds=29.8
    def __init__(self,model):
        from faster_whisper.tokenizer import Tokenizer
        self.model=model
        self.tokenizer=Tokenizer(model.hf_tokenizer,model.model.is_multilingual,task="transcribe",language="ja")

    def _infer(self,window,units,factor):
        from faster_whisper.audio import pad_or_trim
        from faster_whisper.vad import get_speech_timestamps,VadOptions
        speech=get_speech_timestamps(window,VadOptions(threshold=.35,min_speech_duration_ms=80,min_silence_duration_ms=200,speech_pad_ms=160))
        if not speech:raise ValueError("No speech in alignment phrase")
        head,tail=speech[0]["start"],speech[-1]["end"]
        window=window[head:tail]
        if len(window)*factor/16000>self.context_seconds:raise ValueError("DTW audio context exceeded")
        if factor!=1:
            import librosa
            window=librosa.effects.time_stretch(window,rate=1/factor)
        parts=[self.tokenizer.encode(unit) for unit in units]
        target=[token for part in parts for token in part]
        if len(target)>440:raise ValueError("DTW text context exceeded")
        proxy=SimpleNamespace(sot_sequence=self.tokenizer.sot_sequence,eot=self.tokenizer.eot,
            split_to_word_tokens=lambda ids:(units+["<|endoftext|>"],parts+[[self.tokenizer.eot]]))
        features=self.model.feature_extractor(window)
        encoded=self.model.encode(pad_or_trim(features))
        aligned=self.model.find_alignment(proxy,[target],encoded,round(len(window)/160))[0]
        return [dict(text=x["word"],start_time=round(head/16000+float(x["start"])/factor,3),end_time=round(head/16000+float(x["end"])/factor,3),probability=float(x["probability"]),speechStartSec=head/16000,speechEndSec=tail/16000) for x in aligned]

    def align(self,clip,audio):
        proof=super().align(clip,audio)
        return {**proof,"method":"local-attention-dtw","model":ASR_MODEL,"revision":ASR_REVISION}

class LocalWhisperProcessor:
    def __init__(self, model_path, translator_path, device="cuda"):
        verify_whisper_weights(model_path)
        import torch
        from faster_whisper import WhisperModel
        from transformers import AutoTokenizer, AutoModelForSeq2SeqLM
        import build_caption_clips as dictionary
        torch.set_num_threads(8)
        self.asr = WhisperModel(model_path, device=device, compute_type="int8_float16" if device=="cuda" else "int8", cpu_threads=8)
        self.aligner = LocalWhisperAligner(self.asr)
        self.dictionary_module, self.dictionary = dictionary, dictionary.load_dictionary()
        self.tokenizer = AutoTokenizer.from_pretrained(translator_path)
        self.translator = AutoModelForSeq2SeqLM.from_pretrained(translator_path).eval()

    def recognize(self,audio):
        segments,info=self.asr.transcribe(audio,beam_size=5,condition_on_previous_text=False,temperature=0,word_timestamps=False,vad_filter=True)
        heard=[dict(start=s.start,end=s.end,text=s.text,avgLogProbability=s.avg_logprob,noSpeechProbability=s.no_speech_prob) for s in segments]
        return {"language":info.language,"languageProbability":info.language_probability,"segments":heard}

    def recognize_phrases(self,audio):
        # Native ASR word times provide coarse search windows only. Final word
        # intervals are always re-predicted by raw attention/DTW below.
        segments,info=self.asr.transcribe(audio,beam_size=5,condition_on_previous_text=False,temperature=0,word_timestamps=True,vad_filter=True)
        heard=[]
        for segment in segments:
            group=[]
            for word in segment.words or []:
                group.append(word)
                if word.end-group[0].start>=6 or sum(len(w.word) for w in group)>=50 or (word.word.rstrip().endswith(("。","!","?","！","？")) and word.end-group[0].start>=1):
                    heard.append(dict(start=group[0].start,end=group[-1].end,text="".join(w.word for w in group),avgLogProbability=segment.avg_logprob,noSpeechProbability=segment.no_speech_prob));group=[]
            if group:heard.append(dict(start=group[0].start,end=group[-1].end,text="".join(w.word for w in group),avgLogProbability=segment.avg_logprob,noSpeechProbability=segment.no_speech_prob))
        return {"language":info.language,"languageProbability":info.language_probability,"segmentation":"native-asr-coarse-windows-v1","segments":heard}

    def salvage_excerpt(self,video,info,audio,source_start,heard):
        """Choose a contiguous real-audio region; never fill a missing word interval."""
        if heard["language"]!="ja":raise ValueError("Source has no recognized Japanese speech")
        import copy
        groups=[];group=[]
        for segment in heard["segments"]:
            text=segment["text"].strip()
            try:
                if not text or not re.search(r"[\u3040-\u30ff\u3400-\u9fff]",text) or segment["avgLogProbability"] < -1.25:raise ValueError("Unusable speech")
                line={"start":max(0.,segment["start"]),"end":min(len(audio)/16000,segment["end"]),"tokens":self.dictionary_module.tokenize(text,self.dictionary)}
                proof=self.aligner.align({"video_id":video["video_id"],"duration_sec":len(audio)/16000,"source_start_sec":source_start,"lines":[line]},audio)
                group.append((segment,proof["lines"][0]))
            except ValueError:
                if group:groups.append(group);group=[]
        if group:groups.append(group)
        groups.sort(key=lambda g:g[-1][1]["end"]-g[0][1]["start"],reverse=True)
        for group in groups:
            lo=max(0.,group[0][1]["start"]-.2);hi=min(len(audio)/16000,group[-1][1]["end"]+.2)
            first,last=round(lo*16000),round(hi*16000);lo=first/16000;duration=(last-first)/16000
            if duration<3:continue
            excerpt=copy.deepcopy(heard);excerpt["segments"]=[{**segment,"start":max(0.,segment["start"]-lo),"end":min(duration,segment["end"]-lo)} for segment,_ in group]
            try:
                clip,evidence=self.process(video,info,audio[first:last],source_start+lo,excerpt)
                clip["processing"]["sourceWindowSelection"]="Contiguous speech excerpt after full-window timing failure; actual audio re-aligned; requires language review"
                return clip,evidence
            except ValueError:continue
        raise ValueError("No contiguous Japanese speech excerpt passed raw timing checks")

    def process(self,video,info,audio,source_start,heard):
        import torch
        if heard["language"]!="ja":raise ValueError("No Japanese speech: "+heard["language"])
        duration=round(len(audio)/16000,3)
        lines=[]
        for segment in heard["segments"]:
            text=segment["text"].strip()
            if not text or not re.search(r"[\u3040-\u30ff\u3400-\u9fff]",text):continue
            if segment["avgLogProbability"] < -1.25:raise ValueError("Low-confidence speech requires source review")
            lines.append({"start":max(0.,segment["start"]),"end":min(duration,segment["end"]),"timing":"line","translation":"Local translation pending.","tokens":self.dictionary_module.tokenize(text,self.dictionary)})
        if not lines:raise ValueError("No Japanese learning transcript")
        clip={"id":f"local-{video['video_id']}-{round(source_start*1000)}-{round(duration*1000)}","video_id":video["video_id"],"title":video["title"],"channel_name":video["channel_name"],"category":video["category"],"difficulty":"Intermediate","source_start_sec":source_start,"duration_sec":duration,"video_orientation":"portrait" if (info.get("height") or 0)>(info.get("width") or 1) else "landscape","lines":lines,"processing":{"language":"Japanese","asrModel":ASR_MODEL,"asrRevision":ASR_REVISION,"asrSha256":ASR_SHA256,"translationModel":TRANSLATION_MODEL,"translationRevision":TRANSLATION_REVISION}}
        alignment,merges=align_phrase_context(self.aligner,clip,audio)
        if merges:clip["processing"]["alignmentPhraseMerges"]=merges
        out=[]
        for line in restore_phrase_groups(lines, alignment["lines"]):
            for group in display_groups(line["tokens"],max_chars=60):
                spoken=[t for t in group if t["end"]>t["start"]]
                if spoken:out.append({"start":spoken[0]["start"],"end":spoken[-1]["end"],"timing":"word","tokens":group})
        texts=["".join(t["surface"] for t in line["tokens"]) for line in out]
        with torch.inference_mode():
            for i in range(0,len(texts),12):
                inputs=self.tokenizer(texts[i:i+12],return_tensors="pt",padding=True,truncation=True,max_length=256)
                generated=self.translator.generate(**inputs,max_new_tokens=140,num_beams=3)
                for line,english in zip(out[i:i+12],self.tokenizer.batch_decode(generated,skip_special_tokens=True)):line["translation"]=english.strip()
        clip["lines"]=out
        clip["alignment"]={**alignment,"lines":out}
        clip["translationIssues"]=translation_issues(out)
        return clip,alignment["evidence"]
