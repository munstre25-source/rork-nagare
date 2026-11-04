#!/usr/bin/env python3
"""Publish an operator-reviewed local draft only when its Japanese still matches review."""
import argparse
import json
from pathlib import Path
from repair_word_timing_catalog import configuration,request_json
from repair_word_timing_local import maintenance_headers

def reviewed_clip(clip,review):
    actual=["".join(t["surface"] for t in line["tokens"]) for line in clip["lines"]]
    if review["id"]!=clip["id"] or review["videoId"]!=clip["video_id"] or review["japanese"]!=actual:raise ValueError("Japanese changed after language review")
    english=review["english"]
    if len(english)!=len(actual) or any(not isinstance(text,str) or not text.strip() for text in english):raise ValueError("Every reviewed line needs English")
    for term in review.get("dictionary",[]):
        found=0
        for line in clip["lines"]:
            tokens=line["tokens"];out=[];i=0
            while i<len(tokens):
                joined="";end=i
                while end<len(tokens) and len(joined)<len(term["surface"]):
                    joined+=tokens[end]["surface"];end+=1
                if joined==term["surface"]:
                    # Merge only existing consecutive word boundaries. Never subdivide audio.
                    token={**tokens[i],"surface":joined,"start":tokens[i]["start"],"end":tokens[end-1]["end"]}
                    for key in ["definitions","ja_definitions","reading","romaji","pos"]:
                        if key in term:token[key]=term[key]
                    token["tappable"]=bool(token.get("definitions"))
                    if end-i>1:token.update(baseForm=None,baseReading=None,baseRomaji=None)
                    for key in ["baseForm","baseReading","baseRomaji"]:
                        if key in term:token[key]=term[key]
                    out.append(token);i=end;found+=1
                else:out.append(tokens[i]);i+=1
            line["tokens"]=out
        if not found:raise ValueError("Reviewed dictionary term missing: "+term["surface"])
    if review.get("dictionary"):
        clip["processing"]["operatorDictionaryCorrections"]=[t["surface"] for t in review["dictionary"]]
        clip["alignment"]["lines"]=clip["lines"]
    for line,text in zip(clip["lines"],english):line["translation"]=text.strip()
    clip["processing"].update(operatorReview="english-checked",operatorCorrections=list(range(len(english))),operatorReviewNotes=review.get("notes","Japanese and English checked by operator"))
    clip["translationIssues"]=[]
    return clip

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--draft-directory",type=Path,required=True)
    parser.add_argument("--reviews",type=Path,required=True)
    parser.add_argument("--apply",action="store_true")
    parser.add_argument("--use-existing-vault",action="store_true")
    args=parser.parse_args();clips=[]
    for review in json.loads(args.reviews.read_text()):
        draft=args.draft_directory/(review["id"]+".json");clip=reviewed_clip(json.loads(draft.read_text()),review)
        (args.draft_directory/(clip["id"]+"-reviewed.json")).write_text(json.dumps(clip,ensure_ascii=False,indent=2));clips.append(clip)
    if not args.apply:print(json.dumps({"reviewed":len(clips),"published":0}));return
    base,anon=configuration();headers=maintenance_headers(base,anon,args.use_existing_vault);receipts=[]
    for i in range(0,len(clips),5):
        receipt=request_json(base+"/functions/v1/ingest-local-clips",headers,{"clips":clips[i:i+5]},timeout=180);receipts.append(receipt);print(json.dumps(receipt),flush=True)
    args.reviews.with_suffix('.receipts.json').write_text(json.dumps(receipts,ensure_ascii=False,indent=2))
if __name__=="__main__":main()
