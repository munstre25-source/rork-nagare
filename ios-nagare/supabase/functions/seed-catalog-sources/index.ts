import { corsPreflight, errorResponse, jsonResponse, readJson } from "../_shared/http.ts";
import { isAdminOrCron } from "../_shared/admin.ts";
import { requireEnv } from "../_shared/env.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { tryConsumeYoutubeQuota } from "../_shared/limits.ts";
import { parseIsoDurationSec } from "../_shared/immersion.ts";

const CHANNELS: Record<string, string> = {
  bachiramylove629: "anime", SpeakJapaneseNaturally: "learning", JSI55: "learning",
  TheNihongoNook: "learning", KanamatopeJapanese: "learning", SayuriSaying: "learning",
  the_bitesize_japanese_podcast: "learning", "tokiwa-japanese": "learning",
  OkkeiJapanese: "learning", TOHOanimation: "anime", PeppaPigJapaneseOfficial: "kids",
  "Bebefinn日本語": "kids", BlippiJapanese: "kids", "Akane-JapaneseClass": "learning",
  "nihongo-no-jikan": "learning", yuyunihongopodcast: "learning", QuizKnock: "variety",
  nihongonomori2013: "learning", japanese_tanakasan: "learning", "moshimoshi.yusuke": "learning",
  kensanokaeri: "learning", withyuki1030: "learning", DailyJapanese: "learning",
};
type Video = {
  id: string;
  snippet?: { title?: string; channelTitle?: string; channelId?: string };
  contentDetails?: { duration?: string };
  status?: { privacyStatus?: string; embeddable?: boolean };
};
export function windowStarts(duration: number): number[] {
  if (!Number.isFinite(duration) || duration < 8 || duration > 240) return [];
  if (duration <= 120) return [0];
  return Array.from({ length: Math.min(20, Math.floor((duration - 8) / 90) + 1) }, (_, i) => i * 90);
}
export async function handler(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") return errorResponse(405, "Method not allowed");
  if (!isAdminOrCron(req)) return errorResponse(401, "Unauthorized");
  try {
    const body = await readJson<{ handles?: string[]; videoIds?: string[]; apply?: boolean; maxVideosPerChannel?: number }>(req);
    const perChannel = body.maxVideosPerChannel ?? 5;
    if (!Number.isInteger(perChannel) || perChannel < 1 || perChannel > 20) {
      return errorResponse(400, "maxVideosPerChannel must be between 1 and 20");
    }
    const handles = [...new Set(body.handles ?? [])];
    const ids = [...new Set(body.videoIds ?? [])];
    if (!Array.isArray(body.handles ?? []) || handles.length > 5 ||
        handles.some((handle) => typeof handle !== "string" || !CHANNELS[handle]) ||
        !Array.isArray(body.videoIds ?? []) || ids.length > 50 ||
        ids.some((id) => typeof id !== "string" || !/^[A-Za-z0-9_-]{11}$/.test(id))) {
      return errorResponse(400, "Provide up to five configured handles and 50 valid video IDs");
    }
    const supabase = serviceClient();
    async function youtube(path: string, params: Record<string, string>): Promise<Record<string, unknown>[]> {
      if (!(await tryConsumeYoutubeQuota(supabase, 1))) throw new Error("youtube_quota");
      const query = new URLSearchParams({ ...params, key: requireEnv("YOUTUBE_API_KEY") });
      const response = await fetch("https://www.googleapis.com/youtube/v3/" + path + "?" + query);
      if (!response.ok) throw new Error("youtube_unavailable");
      const data = await response.json();
      return data.items ?? [];
    }
    const { data: existing, error: readError } = await supabase.from("clips").select("id,video_id,published");
    if (readError) throw new Error("catalog_read_failed");
    const known = new Set((existing ?? []).map((clip) => clip.video_id));
    const liveIds = new Set((existing ?? []).filter((clip) => clip.published).map((clip) => clip.video_id));
    const liveChannels = new Map<string, number>();
    const sourceMetadata: Array<{ video_id: string; channel_id: string; channel_title: string; checked_at: string }> = [];
    const existingIds = [...liveIds];
    for (let i = 0; i < existingIds.length; i += 50) {
      const items = await youtube("videos", { part: "snippet", id: existingIds.slice(i, i + 50).join(",") });
      for (const item of items) {
        const video = item as Video;
        const channelId = video.snippet?.channelId;
        if (channelId) sourceMetadata.push({ video_id: video.id, channel_id: channelId, channel_title: video.snippet?.channelTitle ?? "", checked_at: new Date().toISOString() });
        if (channelId) liveChannels.set(channelId, (liveChannels.get(channelId) ?? 0) +
          (existing ?? []).filter((clip) => clip.published && clip.video_id === video.id).length);
      }
    }
    if (body.apply && sourceMetadata.length) {
      const { error } = await supabase.from("catalog_video_sources").upsert(sourceMetadata);
      if (error) throw new Error("source_metadata_failed");
    }
    const results: Record<string, unknown>[] = [];
    for (const handle of handles) {
      const channels = await youtube("channels", { part: "snippet,contentDetails", forHandle: handle });
      if (!channels.length) { results.push({ handle, status: "channel_not_found", queuedWindows: 0 }); continue; }
      const channel = channels[0] as { id: string; snippet: { title: string }; contentDetails: { relatedPlaylists: { uploads: string } } };
      const uploads = await youtube("playlistItems", { part: "contentDetails", playlistId: channel.contentDetails.relatedPlaylists.uploads, maxResults: "50" });
      const videoIds = uploads.map((item) => (item as { contentDetails: { videoId: string } }).contentDetails.videoId);
      const videos = videoIds.length
        ? await youtube("videos", { part: "snippet,status,contentDetails", id: videoIds.join(",") }) as Video[]
        : [];
      // Discovery must advance past previously screened sources, including rejected
      // ones. Temporary failures already own a queued retry; never seed them again.
      if (videoIds.length) {
        const seen = await Promise.all([
          supabase.from("catalog_video_sources").select("video_id").in("video_id", videoIds),
          supabase.from("catalog_candidate_queue").select("video_id").in("video_id", videoIds),
          supabase.from("catalog_rejections").select("video_id").in("video_id", videoIds),
        ]);
        if (seen.some((result) => result.error)) throw new Error("source_history_read_failed");
        for (const result of seen) for (const row of result.data ?? []) known.add(row.video_id);
      }
      const eligible = videos.filter((video) => video.status?.privacyStatus === "public" && video.status.embeddable === true &&
        windowStarts(parseIsoDurationSec(video.contentDetails?.duration ?? "") ?? 0).length > 0 && !known.has(video.id))
        .sort((a, b) => (parseIsoDurationSec(a.contentDetails?.duration ?? "") ?? 0) - (parseIsoDurationSec(b.contentDetails?.duration ?? "") ?? 0))
        .slice(0, perChannel);
      const rows = eligible.flatMap((video) => {
        const duration = parseIsoDurationSec(video.contentDetails?.duration ?? "") ?? 0;
        return windowStarts(duration).map((start) => ({
          video_id: video.id, window_start_sec: start, duration_sec: duration,
          title: (video.snippet?.title ?? "").slice(0, 140), channel_title: (video.snippet?.channelTitle ?? channel.snippet.title).slice(0, 80),
          category: CHANNELS[handle], difficulty: CHANNELS[handle] === "learning" || CHANNELS[handle] === "kids" ? "Beginner" : "Intermediate",
          added_at: new Date().toISOString(),
        }));
      });
      let queued = 0;
      if (body.apply && rows.length) {
        const { error, count } = await supabase.from("catalog_candidate_queue")
          .upsert(rows, { onConflict: "video_id,window_start_sec", ignoreDuplicates: true, count: "exact" });
        if (error) throw new Error("candidate_seed_failed");
        queued = count ?? 0;
      }
      if (body.apply) {
        const { error } = await supabase.from("catalog_sources").upsert({ handle, channel_id: channel.id, title: channel.snippet.title, discovery_status: rows.length ? "eligible" : "no_new_eligible_uploads", eligible_video_ids: eligible.map((v) => v.id), checked_at: new Date().toISOString() });
        if (error) throw new Error("source_registry_failed");
      }
      results.push({
        handle, channelId: channel.id, title: channel.snippet.title,
        status: rows.length ? (body.apply ? "seeded" : "eligible") : "no_new_eligible_uploads",
        eligibleVideos: eligible.map((v) => v.id), queuedWindows: queued, existingPublishedLessons: liveChannels.get(channel.id) ?? 0,
      });
    }
    const requestedVideos: Record<string, unknown>[] = [];
    if (ids.length) {
      const videos = await youtube("videos", { part: "snippet,status,contentDetails", id: ids.join(",") }) as Video[];
      for (const id of ids) {
        const video = videos.find((v) => v.id === id);
        const duration = parseIsoDurationSec(video?.contentDetails?.duration ?? "") ?? 0;
        requestedVideos.push({
          videoId: id, durationSec: duration, title: video?.snippet?.title ?? "",
          public: video?.status?.privacyStatus === "public", embeddable: video?.status?.embeddable === true,
          status: liveIds.has(id) ? "published" : duration > 240 ? "deferred_source_over_4_minutes" : video ? "not_published" : "unavailable",
        });
      }
    }
    return jsonResponse({ sources: results, requestedVideos, applied: !!body.apply });
  } catch (error) {
    const message = error instanceof Error ? error.message : "seed_failed";
    return errorResponse(message === "youtube_quota" ? 429 : 502, message);
  }
}
if (import.meta.main) Deno.serve(handler);
