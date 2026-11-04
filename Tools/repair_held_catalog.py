#!/usr/bin/env python3
"""Build reviewable repairs for held catalog videos with free local models. Never auto-publish."""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import time
from free_catalog_pipeline import source_window
from local_whisper_catalog import LocalWhisperProcessor,ASR_MODEL,ASR_REVISION
from repair_word_timing_catalog import configuration,request_json

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--held-report",type=Path,required=True)
    parser.add_argument("--candidates",type=Path,required=True)
    parser.add_argument("--media-directory",type=Path,required=True)
    parser.add_argument("--report-directory",type=Path,required=True)
    parser.add_argument("--device",choices=["cpu","cuda"],default="cpu")
    parser.add_argument("--limit",type=int,default=0)
    parser.add_argument("--max-source-seconds",type=float,default=0)
    parser.add_argument("--per-channel",type=int,default=2)
    parser.add_argument("--id",action="append",default=[])
    parser.add_argument("--corrections",type=Path)
    args=parser.parse_args();root=args.report_directory;root.mkdir(parents=True,exist_ok=True)
    candidates={v["video_id"]:v for v in json.loads(args.candidates.read_text())}
    held=json.loads(args.held_report.read_text());held=[x for x in held if x["status"]=="held" and x["video_id"] in candidates]
    base,anon=configuration();headers={"apikey":anon,"Authorization":"Bearer "+anon}
    live=request_json(base+"/rest/v1/clips?published=eq.true&select=video_id,channel_name&limit=1000",headers)
    existing={r["video_id"] for r in live};known_channels={r["channel_name"] for r in live}
    queues=collections.defaultdict(list)
    for item in held:
        v=candidates[item["video_id"]]
        if v["video_id"] not in existing and (not args.max_source_seconds or v["duration_sec"]<=args.max_source_seconds) and (not args.id or v["video_id"] in args.id):queues[v["channel_id"]].append(v)
    for queue in queues.values():queue.sort(key=lambda v:(v["duration_sec"]<12,v["duration_sec"]))
    channel_order=sorted(queues,key=lambda c:(queues[c][0]["channel_name"] in known_channels,min(v["duration_sec"] for v in queues[c])))
    ordered=[queues[c][n] for n in range(args.per_channel) for c in channel_order if len(queues[c])>n]
    if args.limit:ordered=ordered[:args.limit]
    processor=LocalWhisperProcessor('/tmp/jojo-whisper-turbo-model','/tmp/jojo-ja-en-model',args.device)
    corrections=json.loads(args.corrections.read_text()) if args.corrections else {}
    from yt_dlp import YoutubeDL
    import soundfile as sf
    summary=json.loads((root/"summary.json").read_text()) if (root/"summary.json").exists() else [];accepted=collections.Counter();prior={r["video_id"]:r for r in summary}
    for video in ordered:
        vid=video["video_id"];result={"video_id":vid,"channel":video["channel_name"],"status":"held"};started=time.monotonic()
        if accepted[video["channel_id"]]>=args.per_channel:continue
        previous=prior.get(vid)
        if previous and previous['status']=='ready_for_review' and vid not in corrections:
            accepted[video['channel_id']]+=1;continue
        try:
            metadata=root/(vid+'-metadata.json')
            if metadata.exists():info=json.loads(metadata.read_text())
            else:
                with YoutubeDL({"quiet":True,"no_warnings":True,"noplaylist":True,"socket_timeout":30}) as y:info=y.extract_info('https://www.youtube.com/watch?v='+vid,download=False)
                if info.get('channel_id')!=video['channel_id']:raise ValueError('Source channel changed')
                metadata.write_text(json.dumps({k:info.get(k) for k in ['id','channel_id','width','height','duration']}))
            cached=next((x for x in args.media_directory.glob('*.json') if json.loads(x.read_text()).get('videoId')==vid),None)
            if cached:
                identity=json.loads(cached.read_text());audio,rate=sf.read(cached.with_suffix('.wav'),dtype='float32');start=identity['sourceStartSec']
                if rate!=16000 or audio.ndim!=1:raise ValueError('Invalid cached audio')
            else:
                if 'formats' not in info:
                    with YoutubeDL({"quiet":True,"no_warnings":True}) as y:info=y.extract_info('https://www.youtube.com/watch?v='+vid,download=False)
                audio,start=source_window(video,info,args.media_directory)
            digest=hashlib.sha256(audio.tobytes()).hexdigest();heard_path=root/(vid+'-whisper.json')
            if heard_path.exists():heard=json.loads(heard_path.read_text())
            else:heard={**processor.recognize(audio),'audioSha256':digest,'asrModel':ASR_MODEL,'asrRevision':ASR_REVISION};heard_path.write_text(json.dumps(heard,ensure_ascii=False,indent=2))
            if heard.get('audioSha256')!=digest or heard.get('asrModel')!=ASR_MODEL or heard.get('asrRevision')!=ASR_REVISION:raise ValueError('Recognition cache identity mismatch')
            if vid in corrections:
                heard=json.loads(json.dumps(heard))
                for index,text in corrections[vid].items():heard['segments'][int(index)]['text']=text
            clip,evidence=processor.process(video,info,audio,start,heard)
            if vid in corrections:clip['processing'].update(operatorTranscriptCorrections=list(corrections[vid]),operatorTranscriptEvidence='Operator corrected recognizer wording against source evidence')
            (root/(clip['id']+'.json')).write_text(json.dumps(clip,ensure_ascii=False,indent=2))
            (root/(clip['id']+'-evidence.json')).write_text(json.dumps(evidence,ensure_ascii=False))
            result.update(status='ready_for_review',id=clip['id'],duration_sec=clip['duration_sec'],lines=[{'ja':''.join(t['surface'] for t in l['tokens']),'en':l['translation']} for l in clip['lines']]);accepted[video['channel_id']]+=1
        except Exception as error:result['reason']=str(error)[:220]
        result['seconds']=round(time.monotonic()-started,1);summary=[r for r in summary if r['video_id']!=vid];summary.append(result)
        (root/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2));print(json.dumps(result,ensure_ascii=False),flush=True)
        if (root/'STOP_AFTER_CURRENT').exists():break
    print(json.dumps({'processed':len(summary),'ready':sum(s['status']=='ready_for_review' for s in summary),'paidInferenceCalls':0}),flush=True)
if __name__=='__main__':main()
