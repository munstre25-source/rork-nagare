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
        alignment=self.aligner.align(clip,audio)
        out=[]
        for line in alignment["lines"]:
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
