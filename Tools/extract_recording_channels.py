#!/usr/bin/env python3
"""Extract visible channel labels from Kiku catalog recordings with verified offline Japanese OCR."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import unicodedata
import av
import numpy as np
import onnxruntime as ort
from PIL import Image

OCR_SHA256="e1075a67dba758ecfc7ebc78a10ae61c95ac8fb66a9c86fab5541e33f085cb7a"

class JapaneseOCR:
    def __init__(self,path):
        if hashlib.sha256(path.read_bytes()).hexdigest()!=OCR_SHA256:raise ValueError("Japanese OCR model checksum mismatch")
        options=ort.SessionOptions();options.intra_op_num_threads=3;options.inter_op_num_threads=1
        self.session=ort.InferenceSession(str(path),sess_options=options,providers=["CPUExecutionProvider"])
        self.characters=[""]+self.session.get_modelmeta().custom_metadata_map["character"].splitlines()+[" "]
    def read(self,image):
        width=max(48,math.ceil(image.width/image.height*48))
        array=np.asarray(image.convert('RGB').resize((width,48))).astype(np.float32)/127.5-1
        probabilities=self.session.run(None,{"x":array.transpose(2,0,1)[None]})[0][0]
        ids=probabilities.argmax(axis=1);scores=probabilities.max(axis=1);chars=[];confidence=[];previous=-1
        for index,value in enumerate(ids):
            if value and value!=previous:chars.append(self.characters[value]);confidence.append(float(scores[index]))
            previous=value
        return "".join(chars).strip(),sum(confidence)/len(confidence) if confidence else 0

def channel_bands(image):
    pixels=np.asarray(image).astype(np.int16);area=pixels[:,330:1030];value=area.mean(2)
    gray=(area.max(2)-area.min(2)<14)&(value>100)&(value<195);white=value>210
    rows=np.flatnonzero(gray.sum(1)>12);groups=[]
    for y in rows:
        if groups and y-groups[-1][-1]<=5:groups[-1].append(int(y))
        else:groups.append([int(y)])
    lines=[]
    for group in groups:
        lo,hi=group[0],group[-1]+1
        if 670<lo<2110 and 12<hi-lo<55 and gray[lo:hi].sum()/max(1,gray[lo:hi].sum()+white[lo:hi].sum())>.75:lines.append((lo,hi))
    profile=np.median(pixels[:,:40].mean(2),axis=1)
    dividers=np.flatnonzero(np.abs(np.diff(profile))>7)+1
    result=[]
    for i,(lo,hi) in enumerate(lines):
        if i+1<len(lines) and lines[i+1][0]-hi<34:continue
        if i==0 or lo-lines[i-1][1]>34:continue
        if not any(25<=y-hi<=60 for y in dividers):continue
        columns=np.flatnonzero(gray[lo:hi].sum(0)>0)
        if not len(columns):continue
        left=max(328,330+int(columns[0])-6);right=min(1040,330+int(columns[-1])+7)
        result.append((left,lo-4,right,hi+4))
    return result

def normalize(text):return re.sub(r"[\W_]","",unicodedata.normalize("NFKC",text).casefold())

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--video",type=Path,required=True)
    parser.add_argument("--model",type=Path,default=Path('/tmp/jojo-japanese-ocr.onnx'))
    parser.add_argument("--output",type=Path,required=True)
    parser.add_argument("--step",type=float,default=.5)
    args=parser.parse_args();root=args.output;root.mkdir(parents=True,exist_ok=True);(root/'crops').mkdir(exist_ok=True)
    ocr=JapaneseOCR(args.model);labels={};observations=0;sampled=0;next_time=0.;previous_crops={}
    log=(root/'observations.jsonl').open('w')
    with av.open(args.video) as container:
        stream=container.streams.video[0];stream.thread_type='AUTO';stream.codec_context.thread_count=2
        duration=container.duration/av.time_base
        for frame in container.decode(stream):
            if frame.time<next_time:continue
            next_time=frame.time+args.step;sampled+=1;image=frame.to_image()
            for box in channel_bands(image):
                crop=image.crop(box);digest=hashlib.sha256(crop.tobytes()).hexdigest()
                if digest in previous_crops:text,score=previous_crops[digest]
                else:text,score=ocr.read(crop);previous_crops[digest]=(text,score)
                key=normalize(text)
                if len(key)<2 or score<.60:continue
                observation={'video':args.video.name,'timeSec':round(frame.time,3),'text':text,'confidence':round(score,4),'box':box};observations+=1;log.write(json.dumps(observation,ensure_ascii=False)+'\n')
                if key not in labels:labels[key]={'label':text,'confidence':score,'observations':0,'evidence':[],'crop':'crops/'+hashlib.sha256(key.encode()).hexdigest()[:16]+'.png'}
                entry=labels[key];entry['observations']+=1
                if len(entry['evidence'])<8:entry['evidence'].append({'video':args.video.name,'timeSec':round(frame.time,3),'box':box})
                if score>=entry['confidence']:entry['label']=text;entry['confidence']=score;crop.save(root/entry['crop'])
            if sampled%30==0:
                (root/'channels-ocr.json').write_text(json.dumps({'video':args.video.name,'durationSec':duration,'sampledFrames':sampled,'observations':observations,'complete':False,'labels':list(labels.values())},ensure_ascii=False,indent=2));log.flush();print(json.dumps({'seconds':round(frame.time),'labels':len(labels),'frames':sampled}),flush=True)
            if len(previous_crops)>5000:previous_crops.clear()
    log.close();(root/'channels-ocr.json').write_text(json.dumps({'video':args.video.name,'durationSec':duration,'sampledFrames':sampled,'observations':observations,'complete':True,'labels':list(labels.values())},ensure_ascii=False,indent=2));print(json.dumps({'complete':True,'labels':len(labels),'frames':sampled,'paidInferenceCalls':0}),flush=True)
if __name__=='__main__':main()
