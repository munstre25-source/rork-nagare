import { assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handler } from "../ingest-local-clips/index.ts";
import { LOCAL_ASR_MODEL, LOCAL_ASR_REVISION, LOCAL_WHISPER_MODEL, LOCAL_WHISPER_REVISION, LOCAL_TRANSLATION_MODEL, LOCAL_TRANSLATION_REVISION, normalizeChannel, seconds, validateLocalCatalogClip, type LocalCatalogClip } from "./local-catalog.ts";
import { LOCAL_ALIGNMENT_MODEL, LOCAL_ALIGNMENT_REVISION } from "./local-alignment.ts";
function clip(duration=124): LocalCatalogClip {
 const lines=[{start:.1,end:1,timing:"word" as const,translation:"Thank you!",tokens:[{surface:"ありがとう",start:.1,end:1,tappable:true,definitions:["thank you"]}]}];
 return {id:"local-test",video_id:"abcdefghijk",title:"Test",channel_name:"Selected",category:"variety",source_start_sec:0,duration_sec:duration,video_orientation:"portrait",lines,
  processing:{operatorReview:"english-checked",language:"Japanese",asrModel:LOCAL_ASR_MODEL,asrRevision:LOCAL_ASR_REVISION,translationModel:LOCAL_TRANSLATION_MODEL,translationRevision:LOCAL_TRANSLATION_REVISION},
  alignment:{version:1,method:"local-forced-alignment",model:LOCAL_ALIGNMENT_MODEL,revision:LOCAL_ALIGNMENT_REVISION,videoId:"abcdefghijk",sourceStartSec:0,durationSec:duration,audioSha256:"a".repeat(64),sampleRate:16000,audioDurationSec:duration,lines}};
}
Deno.test("local pipeline accepts one-line Shorts and full videos past forty seconds",()=>{
 for(const duration of [3,41,124,180,300]) assertEquals(validateLocalCatalogClip(clip(duration))[0].tokens[0].surface,"ありがとう");
 assertEquals(seconds("PT3M"),180);assertEquals(seconds("PT2M4S"),124);
 assertEquals(normalizeChannel("ＡＯＧＡＳＨＩＭＡ Channel!"),"aogashimachannel");
});
Deno.test("local publishing requires Japanese audio provenance and bounded real word intervals",()=>{
 const wrong=clip();wrong.processing.language="English";assertThrows(()=>validateLocalCatalogClip(wrong));
 const missing=clip();missing.alignment.lines=[];assertThrows(()=>validateLocalCatalogClip(missing));
 const bad=clip();bad.lines[0].translation="";assertThrows(()=>validateLocalCatalogClip(bad));
 const collapse=clip();collapse.alignment.lines[0].tokens[0].end=.1;assertThrows(()=>validateLocalCatalogClip(collapse));
});
Deno.test("local publishing discards supplied independent-review claims",()=>{
 const input=clip();input.lines[0].translationReview={version:3,wordTimingVerified:true};
 assertEquals(validateLocalCatalogClip(input)[0].translationReview,undefined);
});
Deno.test("local endpoint rejects unauthenticated callers before any source request",async()=>{
 assertEquals((await handler(new Request("https://example.test",{method:"POST",body:"{}"}))).status,401);
});
Deno.test("free discovery accepts uncaptained short videos and performs no inference requests",async()=>{
 const names=["SUPABASE_URL","SUPABASE_SERVICE_ROLE_KEY","ADMIN_TOKEN","YOUTUBE_API_KEY"];
 const saved=names.map(n=>Deno.env.get(n)), old=globalThis.fetch, calls:string[]=[];
 try {
  for(const [i,n] of names.entries()) Deno.env.set(n,i===0?"https://catalog.example.test":"test-secret");
  globalThis.fetch=async(input)=>{
   const url=new URL(input instanceof Request?input.url:String(input));calls.push(url.hostname+url.pathname);
   if(url.hostname==="catalog.example.test") return Response.json([{channel_id:"UC"+"a".repeat(22),title:"Selected",local_category:"variety"}]);
   if(url.hostname!=="www.googleapis.com") throw new Error("Paid provider request");
   if(url.pathname.endsWith("/channels"))return Response.json({items:[{contentDetails:{relatedPlaylists:{uploads:"uploads"}}}]});
   if(url.pathname.endsWith("/playlistItems"))return Response.json({items:[{contentDetails:{videoId:"abcdefghijk"}}]});
   if(url.pathname.endsWith("/videos"))return Response.json({items:[{id:"abcdefghijk",status:{embeddable:true,privacyStatus:"public"},snippet:{channelId:"UC"+"a".repeat(22),channelTitle:"Selected",title:"Uncaptioned Short",liveBroadcastContent:"none"},contentDetails:{duration:"PT12S",caption:"false"}}]});
   throw new Error("Unexpected request");
  };
  const response=await handler(new Request("https://example.test",{method:"POST",headers:{"x-admin-token":"test-secret"},body:JSON.stringify({action:"candidates",channels:["UC"+"a".repeat(22)]})}));
  assertEquals(response.status,200);const result=await response.json();assertEquals(result.paidApiCalls,0);
  assertEquals(result.videos.length,1);assertEquals(result.videos[0].caption_available,false);assertEquals(result.videos[0].duration_sec,12);
  assertEquals(calls.length,4);
 }finally {globalThis.fetch=old;names.forEach((n,i)=>saved[i]===undefined?Deno.env.delete(n):Deno.env.set(n,saved[i]!));}
});

Deno.test("flagged offline English stays held until the operator reviews it",()=>{
 const candidate=clip();
 candidate.translationIssues=[{lineIndex:0,reason:"missing source meaning"}];
 delete candidate.processing.operatorReview;
 assertThrows(()=>validateLocalCatalogClip(candidate),Error,"Offline English requires operator review");
 candidate.processing.operatorReview="english-checked";
 assertEquals(validateLocalCatalogClip(candidate)[0].translation,"Thank you!");
});

Deno.test("free Whisper uses its own pinned provenance and cannot mix model revisions",()=>{
 const candidate=clip();
 candidate.processing.asrModel=LOCAL_WHISPER_MODEL;
 candidate.processing.asrRevision=LOCAL_WHISPER_REVISION;
 assertEquals(validateLocalCatalogClip(candidate).length,1);
 candidate.processing.asrRevision=LOCAL_ASR_REVISION;
 assertThrows(()=>validateLocalCatalogClip(candidate),Error,"provenance required");
});

Deno.test("missing local ASR provenance never matches an absent map entry",()=>{
 const candidate=clip();
 delete (candidate.processing as Partial<typeof candidate.processing>).asrModel;
 delete (candidate.processing as Partial<typeof candidate.processing>).asrRevision;
 assertThrows(()=>validateLocalCatalogClip(candidate),Error,"provenance required");
});

Deno.test("native attention timing has distinct provenance and keeps word checks",()=>{
 const candidate=clip();
 candidate.alignment.method="local-attention-dtw";
 candidate.alignment.model=LOCAL_WHISPER_MODEL;
 candidate.alignment.revision=LOCAL_WHISPER_REVISION;
 assertEquals(validateLocalCatalogClip(candidate).length,1);
 candidate.alignment.lines[0].tokens[0].end=.1;
 assertThrows(()=>validateLocalCatalogClip(candidate),Error,"missing or implausible");
 candidate.alignment.lines[0].tokens[0].end=1;
 candidate.alignment.method="local-forced-alignment";
 assertThrows(()=>validateLocalCatalogClip(candidate),Error,"provenance");
});

Deno.test("unflagged machine English also requires a recorded operator review",()=>{
 const candidate=clip();
 delete candidate.processing.operatorReview;
 assertThrows(()=>validateLocalCatalogClip(candidate),Error,"English requires operator review");
});
