import { corsPreflight, errorResponse, jsonResponse, readJson } from "../_shared/http.ts";
import { isAdminOrCron } from "../_shared/admin.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { requireEnv } from "../_shared/env.ts";
import { LOCAL_CATEGORIES, normalizeChannel, seconds, validateLocalCatalogClip, type LocalCatalogClip } from "../_shared/local-catalog.ts";

type Source = {name: string; handle?: string; category: string; channel_id?: string};
async function youtube(path: string, params: Record<string, string>) {
  const url = new URL("https://www.googleapis.com/youtube/v3/" + path);
  for (const [key, value] of Object.entries({...params, key: requireEnv("YOUTUBE_API_KEY")})) url.searchParams.set(key,value);
  const response = await fetch(url, {signal: AbortSignal.timeout(20000)});
  const payload = await response.json();
  if (!response.ok) throw new Error("YouTube metadata request failed: " + response.status + ":" + (payload.error?.errors?.[0]?.reason ?? "unknown"));
  return payload;
}
async function mapLimit<T, U>(values: T[], run: (item: T) => Promise<U>): Promise<U[]> {
  const result: U[] = new Array(values.length); let next = 0;
  await Promise.all(Array.from({length: Math.min(4,values.length)}, async () => {
    while (next < values.length) {const i=next++; result[i] = await run(values[i]);}
  }));
  return result;
}
async function discover(source: Source) {
  if (!source.name || !LOCAL_CATEGORIES.has(source.category)) return {...source, status:"invalid"};
  let items;
  if (source.handle || source.channel_id) {
    items = (await youtube("channels",{part:"snippet,contentDetails,statistics", ...(source.channel_id ? {id:source.channel_id} : {forHandle:source.handle!.replace(/^@/,"")})})).items ?? [];
  } else {
    const candidates = (await youtube("search",{part:"snippet",type:"channel",q:source.name,maxResults:"5"})).items ?? [];
    const ids = candidates.map((c: {id:{channelId:string}}) => c.id.channelId).join(",");
    items = ids ? (await youtube("channels",{part:"snippet,contentDetails,statistics",id:ids})).items ?? [] : [];
    const exact = items.filter((c: {snippet:{title:string}}) => normalizeChannel(c.snippet.title) === normalizeChannel(source.name));
    if (exact.length !== 1) return {...source,status:"needs_identity_check",candidates:items.map((c: {id:string;snippet:{title:string;customUrl:string};statistics:{subscriberCount:string}}) => ({channel_id:c.id,title:c.snippet.title,handle:c.snippet.customUrl,subscribers:c.statistics?.subscriberCount}))};
    items = exact;
  }
  const channel = items[0];
  if (!channel) return {...source,status:"not_found"};
  return {...source,status:"resolved",channel_id:channel.id,title:channel.snippet.title,handle:channel.snippet.customUrl ?? source.handle ?? channel.id,
    uploads:channel.contentDetails.relatedPlaylists.uploads,subscribers:channel.statistics?.subscriberCount};
}
export async function handler(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") return errorResponse(405,"Method not allowed");
  if (!isAdminOrCron(req)) return errorResponse(401,"Unauthorized");
  try {
    const body = await readJson<{action?:string;sources?:Source[];channels?:string[];clips?:LocalCatalogClip[];perChannel?:number}>(req);
    const sb=serviceClient();
    if (body.action === "discover" || body.action === "register") {
      if (!Array.isArray(body.sources) || body.sources.length>12 || !body.sources.length) return errorResponse(400,"Provide 1–12 sources");
      const sources = await mapLimit(body.sources, async (source) => {
        try { return await discover(source); }
        catch (error) { return {...source,status:"lookup_failed",detail:error instanceof Error?error.message:"Source lookup failed"}; }
      });
      if (body.action === "register") {
        for (const source of sources) {
          if (source.status !== "resolved" || !("channel_id" in source) || !("title" in source)) continue;
          const {error}=await sb.from("catalog_sources").upsert({handle:source.handle,channel_id:source.channel_id,title:source.title,
            discovery_status:"user_selected",local_pipeline_ok:true,local_category:source.category,checked_at:new Date().toISOString()},{onConflict:"handle"});
          if (error) throw new Error("Channel registration failed");
        }
      }
      return jsonResponse({sources,paidApiCalls:0});
    }
    if (body.action === "candidates") {
      if (!Array.isArray(body.channels) || !body.channels.length || body.channels.length>12) return errorResponse(400,"Provide 1–12 channel IDs");
      const {data: sources,error}=await sb.from("catalog_sources").select("channel_id,title,local_category").in("channel_id",body.channels).eq("local_pipeline_ok",true);
      if (error) throw new Error("Source state unavailable");
      const byId=new Map((sources ?? []).map((s) => [s.channel_id,s]));
      const channels=(await youtube("channels",{part:"contentDetails",id:[...byId.keys()].join(",")})).items ?? [];
      const count=Math.min(50,Math.max(1,body.perChannel ?? 10));
      const lists=await mapLimit(channels,async (c: {contentDetails:{relatedPlaylists:{uploads:string}}}) => (await youtube("playlistItems",{part:"contentDetails",playlistId:c.contentDetails.relatedPlaylists.uploads,maxResults:String(count)})).items ?? []);
      const ids=[...new Set(lists.flat().map((v: {contentDetails:{videoId:string}}) => v.contentDetails.videoId))];
      const videos=[];
      for (let i=0;i<ids.length;i+=50) {
        const data=await youtube("videos",{part:"snippet,contentDetails,status",id:ids.slice(i,i+50).join(",")});
        for (const v of data.items ?? []) {
          if (!v.status.embeddable || v.status.privacyStatus!=="public" || v.snippet.liveBroadcastContent!=="none" || seconds(v.contentDetails.duration)<3 || v.contentDetails.contentRating?.ytRating) continue;
          const source=byId.get(v.snippet.channelId); if(!source) continue;
          videos.push({video_id:v.id,title:v.snippet.title,channel_id:v.snippet.channelId,channel_name:v.snippet.channelTitle,
            duration_sec:seconds(v.contentDetails.duration),category:source.local_category,caption_available:v.contentDetails.caption==="true",language:v.snippet.defaultAudioLanguage ?? null});
        }
      }
      return jsonResponse({videos,paidApiCalls:0});
    }
    const clips=body.clips;
    if (!Array.isArray(clips) || !clips.length || clips.length>20) return errorResponse(400,"Provide 1–20 locally processed clips");
    const metadata=await youtube("videos",{part:"snippet,contentDetails,status",id:clips.map(c=>c.video_id).join(",")});
    const videos=new Map((metadata.items ?? []).map((v: {id:string})=>[v.id,v]));
    const accepted:string[]=[],rejected:Array<{id:string;reason:string}>=[];
    for (const clip of clips) {
      try {
        const lines=validateLocalCatalogClip(clip);
        // Public metadata is fetched at publication, never accepted from the operator.
        const video=videos.get(clip.video_id) as {snippet:{title:string;channelId:string;channelTitle:string;liveBroadcastContent:string};status:{embeddable:boolean;privacyStatus:string};contentDetails:{duration:string;contentRating?:{ytRating?:string}}} | undefined;
        if (!video || !video.status.embeddable || video.status.privacyStatus!=="public" || video.snippet.liveBroadcastContent!=="none" || video.contentDetails.contentRating?.ytRating || clip.source_start_sec+clip.duration_sec>seconds(video.contentDetails.duration)+.1) throw new Error("Source is unavailable, unembeddable or outside its real duration");
        const {data:source,error:sourceError}=await sb.from("catalog_sources").select("local_category").eq("channel_id",video.snippet.channelId).eq("local_pipeline_ok",true).limit(1).maybeSingle();
        if (sourceError || !source || source.local_category!==clip.category) throw new Error("Source channel/category is not approved for local publishing");
        const {data:existing,error:existsError}=await sb.from("clips").select("id").eq("video_id",clip.video_id).eq("source_start_sec",clip.source_start_sec).eq("duration_sec",clip.duration_sec).limit(1);
        if (existsError) throw new Error("Duplicate check unavailable");
        if(existing?.length) {rejected.push({id:clip.id,reason:"already_catalogued"});continue;}
        const {error:videoError}=await sb.from("catalog_video_sources").upsert({video_id:clip.video_id,channel_id:video.snippet.channelId,channel_title:video.snippet.channelTitle,checked_at:new Date().toISOString()});
        if(videoError) throw new Error("Source provenance unavailable");
        const hashArgs={p_video_id:clip.video_id,p_start:clip.source_start_sec,p_duration:clip.duration_sec,p_lines:lines};
        const {data:baseHash,error:baseError}=await sb.rpc("catalog_review_hash",hashArgs);
        if(baseError || typeof baseHash!=="string") throw new Error("Source integrity check unavailable");
        const alignment={version:1,method:clip.alignment.method,model:clip.alignment.model,revision:clip.alignment.revision,
          audioSha256:clip.alignment.audioSha256,videoId:clip.video_id,sourceStartSec:clip.source_start_sec,durationSec:clip.duration_sec,sourceLinesHash:baseHash,databaseHash:baseHash};
        const publication={version:1,method:"local-asr-translation",...clip.processing,channelId:video.snippet.channelId,category:clip.category,
          videoId:clip.video_id,sourceStartSec:clip.source_start_sec,durationSec:clip.duration_sec,databaseHash:baseHash};
        const sealed=lines.map(line=>({...line,translationReview:{version:"local-1",localAlignment:alignment,localPublication:publication}}));
        // Integrity hashes exclude receipt fields, so baseHash seals these same exact lines.
        const {error:insertError}=await sb.from("clips").insert({id:clip.id,video_id:clip.video_id,title:video.snippet.title,channel_name:video.snippet.channelTitle,
          category:clip.category,difficulty:["Intermediate","Advanced"].includes(clip.difficulty ?? "")?clip.difficulty:"Beginner",
          source_start_sec:clip.source_start_sec,duration_sec:clip.duration_sec,lines:sealed,published:true,review_tier:"local",timing_mode:"word",
          channel_avatar_color:"#F97316",thumbnail_gradient:["#1C1917","#44403C","#78716C"],video_orientation:clip.video_orientation==="portrait"?"portrait":"landscape",
          model:"local-qwen-opus",prompt_version:"local-catalog-1"});
        if(insertError) throw new Error(insertError.code==="23505"?"already_catalogued":insertError.message.slice(0,200));
        accepted.push(clip.id);
      } catch(error) {rejected.push({id:clip?.id ?? "?",reason:error instanceof Error?error.message:"Local ingest failed"});}
    }
    return jsonResponse({accepted:accepted.length,ids:accepted,rejected,paidApiCalls:0});
  } catch(error) {return errorResponse(500,error instanceof Error?error.message:"Local catalog operation failed");}
}
if(import.meta.main) Deno.serve(handler);
