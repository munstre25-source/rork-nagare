/** Read-only, maintenance-authenticated YouTube inventory. No AI and no database writes. */
import { isAdminOrCron } from "../_shared/admin.ts";
import { corsPreflight, errorResponse, jsonResponse } from "../_shared/http.ts";

type Body = {action?: string; ids?: unknown; channelId?: unknown; pageToken?: unknown; query?: unknown};
type Video = {id:string; snippet?:{title?:string;channelId?:string;channelTitle?:string;publishedAt?:string;defaultAudioLanguage?:string;defaultLanguage?:string;liveBroadcastContent?:string}; status?:{privacyStatus?:string;embeddable?:boolean;madeForKids?:boolean}; contentDetails?:{duration?:string;caption?:string;contentRating?:{ytRating?:string};regionRestriction?:{allowed?:string[];blocked?:string[]}}};
class InventoryError extends Error {
  constructor(message:string, public status:number){super(message);}
}
function ids(value:unknown, pattern:RegExp):string[] {
  if(!Array.isArray(value) || !value.length || value.length>50 || value.some(v=>typeof v!=="string" || !pattern.test(v))) throw new InventoryError("Provide 1-50 valid IDs",400);
  return [...new Set(value)] as string[];
}
function cursor(value:unknown):string|undefined {
  if(value===undefined || value==="")return undefined;
  if(typeof value!=="string" || value.length>1024 || /[\u0000-\u001f]/.test(value))throw new InventoryError("Invalid page token",400);
  return value;
}
export function durationSeconds(value:string):number {
  const m=/^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$/.exec(value);
  return m ? Number(m[1]??0)*86400+Number(m[2]??0)*3600+Number(m[3]??0)*60+Number(m[4]??0) : 0;
}
export function videoInventory(v:Video) {
  const s=v.snippet??{},c=v.contentDetails??{},status=v.status??{};
  const durationSec=durationSeconds(c.duration??"");
  const reasons:string[]=[];
  if(status.privacyStatus!=="public")reasons.push("not_public");
  if(status.embeddable!==true)reasons.push("not_embeddable");
  if(s.liveBroadcastContent && s.liveBroadcastContent!=="none")reasons.push("live_or_upcoming");
  if(durationSec<3)reasons.push("under_3_seconds_or_unknown_duration");
  if(c.contentRating?.ytRating==="ytAgeRestricted")reasons.push("age_restricted");
  return {video_id:v.id,title:s.title,channel_id:s.channelId,channel_name:s.channelTitle,published_at:s.publishedAt,
    duration_sec:durationSec,declared_audio_language:s.defaultAudioLanguage??null,declared_text_language:s.defaultLanguage??null,
    caption_available:c.caption==="true",region_restriction:c.regionRestriction??null,made_for_kids:status.madeForKids??null,
    metadata_candidate:reasons.length===0,exclusion_reasons:reasons,transcript_timing_review:"not_reviewed"};
}
async function youtube(path:string,params:Record<string,string>) {
  const key=Deno.env.get("YOUTUBE_API_KEY")?.trim();
  if(!key)throw new InventoryError("YouTube metadata credential unavailable",503);
  const url=new URL("https://www.googleapis.com/youtube/v3/"+path);
  for(const [k,v] of Object.entries({...params,key}))url.searchParams.set(k,v);
  let response:Response;
  try {response=await fetch(url,{signal:AbortSignal.timeout(25000)});}
  catch {throw new InventoryError("YouTube metadata request unavailable",502);}
  const payload=await response.json();
  if(!response.ok){
    const raw=payload.error?.errors?.[0]?.reason;
    const reason=typeof raw==="string" && /^[A-Za-z0-9_-]{1,80}$/.test(raw)?raw:"unknown";
    throw new InventoryError("YouTube metadata request failed: "+reason, /quota|dailyLimit|rateLimit/i.test(reason)?429:502);
  }
  return payload;
}
export async function handler(req:Request):Promise<Response> {
  if(req.method==="OPTIONS")return corsPreflight();
  if(req.method!=="POST")return errorResponse(405,"Method not allowed");
  if(!isAdminOrCron(req))return errorResponse(401,"Unauthorized");
  try {
    const body=await req.json() as Body;
    const common={readOnly:true,paidInferenceCalls:0};
    if(body.action==="channels"){
      const selected=ids(body.ids,/^UC[A-Za-z0-9_-]{22}$/);
      const data=await youtube("channels",{part:"snippet,contentDetails,statistics,status",id:selected.join(","),maxResults:"50"});
      const channels=(data.items??[]).map((c:{id:string;snippet:{title:string;customUrl?:string;description?:string};contentDetails:{relatedPlaylists?:{uploads?:string}};statistics?:{videoCount?:string;subscriberCount?:string}})=>({channel_id:c.id,title:c.snippet.title,handle:c.snippet.customUrl??null,description:c.snippet.description?.slice(0,1200)??"",uploads:c.contentDetails?.relatedPlaylists?.uploads??null,public_upload_count:Number(c.statistics?.videoCount??0),subscribers:Number(c.statistics?.subscriberCount??0)}));
      return jsonResponse({...common,channels,missing:selected.filter(id=>!channels.some((c:{channel_id:string})=>c.channel_id===id))});
    }
    if(body.action==="uploads"){
      if(typeof body.channelId!=="string" || !/^UC[A-Za-z0-9_-]{22}$/.test(body.channelId))throw new InventoryError("Valid channel ID required",400);
      const token=cursor(body.pageToken);
      const data=await youtube("playlistItems",{part:"snippet,contentDetails,status",playlistId:"UU"+body.channelId.slice(2),maxResults:"50",...(token?{pageToken:token}:{})});
      const videos=(data.items??[]).map((v:{contentDetails:{videoId:string};snippet:{title:string;videoOwnerChannelId?:string;publishedAt?:string};status?:{privacyStatus?:string}})=>({video_id:v.contentDetails.videoId,title:v.snippet.title,owner_channel_id:v.snippet.videoOwnerChannelId??null,published_at:v.snippet.publishedAt??null,playlist_privacy:v.status?.privacyStatus??null}));
      return jsonResponse({...common,channel_id:body.channelId,playlist_total:data.pageInfo?.totalResults??null,nextPageToken:data.nextPageToken??null,videos});
    }
    if(body.action==="videos"){
      const selected=ids(body.ids,/^[A-Za-z0-9_-]{11}$/);
      const data=await youtube("videos",{part:"snippet,contentDetails,status",id:selected.join(","),maxResults:"50"});
      const videos=(data.items??[]).map(videoInventory);
      return jsonResponse({...common,videos,missing:selected.filter(id=>!videos.some((v:{video_id:string})=>v.video_id===id))});
    }
    if(body.action==="search_channels"){
      if(typeof body.query!=="string" || !body.query.trim() || body.query.length>1000)throw new InventoryError("Bounded channel query required",400);
      const token=cursor(body.pageToken);
      const data=await youtube("search",{part:"snippet",type:"channel",q:body.query,maxResults:"50",...(token?{pageToken:token}:{})});
      const channels=(data.items??[]).map((c:{id:{channelId:string};snippet:{title:string;description?:string}})=>({channel_id:c.id.channelId,title:c.snippet.title,description:c.snippet.description??""}));
      return jsonResponse({...common,channels,nextPageToken:data.nextPageToken??null});
    }
    throw new InventoryError("Unknown read-only inventory action",400);
  }catch(error){return errorResponse(error instanceof InventoryError?error.status:400,error instanceof InventoryError?error.message:"Invalid inventory request");}
}
if(import.meta.main)Deno.serve(handler);
