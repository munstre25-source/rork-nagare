import { corsPreflight, errorResponse, jsonResponse } from "../_shared/http.ts";
import { geminiModelAnalyze, requireEnv } from "../_shared/env.ts";
import { requireAdmin } from "../_shared/admin.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { tryConsumeYoutubeQuota, tryIncrementGeminiUsage } from "../_shared/limits.ts";
import { geminiAnalyzeYouTubeSegment, parseJsonObject } from "../_shared/gemini.ts";
import {
  durationFromLines,
  LineLike,
  validateEnums,
  validateLines,
} from "../_shared/validate.ts";

/**
 * One scheduled pass: search YouTube for a short public Japanese video the catalog
 * does not have yet, ask Gemini for a learner transcript, and publish it when the
 * lines validate. The phone never downloads the file. It plays the YouTube id.
 *
 * Admin only. A pg_cron job calls this with x-admin-token.
 */

type Lane = { category: string; difficulty: string; query: string };

const LANES: Lane[] = [
  { category: "anime", difficulty: "Beginner", query: "日本語 アニメ 会話 初心者" },
  { category: "anime", difficulty: "Intermediate", query: "アニメ セリフ 日本語" },
  { category: "drama", difficulty: "Beginner", query: "日本語 日常会話 ショート" },
  { category: "drama", difficulty: "Advanced", query: "日本語 ドラマ セリフ" },
  { category: "variety", difficulty: "Intermediate", query: "日本語 バラエティ トーク ショート" },
  { category: "vtuber", difficulty: "Intermediate", query: "日本語 VTuber 雑談 ショート" },
  { category: "interview", difficulty: "Beginner", query: "日本語 街頭インタビュー" },
  { category: "interview", difficulty: "Advanced", query: "日本語 インタビュー" },
  { category: "kids", difficulty: "Beginner", query: "子供向け 日本語 アニメ ショート" },
  { category: "gaming", difficulty: "Intermediate", query: "日本語 ゲーム実況 ショート" },
];

const GRADIENTS = [
  ["#0B1030", "#2B2F7A", "#F29E4C"],
  ["#10261A", "#2E7D4F", "#F6E27F"],
  ["#2B1405", "#9C3D10", "#F2B134"],
];

const SYSTEM = `You analyze a short Japanese YouTube video segment for language learners.
Return a single JSON object: { "lines": [ { "translation": string (English), "start": number, "end": number, "tokens": [ Token ] } ] }.
Each Token: surface (required), reading (kana if kanji), altReadings (string[]), romaji, start, end, pos, conjugationClass (optional), jlpt (optional N5-N1), definitions (English string[]), formality (optional), tappable (bool), baseForm/baseReading/baseRomaji (optional for conjugated stems).
Rules:
- Timestamps are absolute seconds within the given segment window; strictly increasing; each token within its line; each line within [startSec, endSec].
- Tokenize into learner-friendly units (particles separate). Punctuation may be tokens with pos "punctuation" and tappable false.
- definitions required for tappable tokens.
- Japanese dialogue only; no English in surface.
- No markdown.`;

type SearchItem = { id?: { videoId?: string } };
type VideoItem = {
  id?: string;
  status?: { embeddable?: boolean; privacyStatus?: string };
  contentDetails?: { duration?: string };
  snippet?: { title?: string; channelTitle?: string };
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") return errorResponse(405, "Method not allowed");

  try {
    const adminToken = requireEnv("ADMIN_TOKEN");
    if (!requireAdmin(req, adminToken)) return errorResponse(401, "Unauthorized");

    const supabase = serviceClient();
    const lane = await leastFilledLane(supabase);
    const enums = validateEnums(lane.category, lane.difficulty);
    if (!enums.ok) return errorResponse(500, "Server misconfigured");

    const found = await searchFresh(supabase, lane.query);
    if (!found.ok) return jsonResponse({ published: false, reason: found.reason, lane });
    if (found.videos.length === 0) {
      return jsonResponse({ published: false, reason: "no-new-videos", lane });
    }

    let attempts = 0;
    let lastError = "no-candidate";
    for (const video of found.videos) {
      if (attempts >= 2) break;
      const window = clipWindow(video.durationSec);
      if (!window) continue;
      attempts += 1;
      const published = await analyzeAndPublish(supabase, video, lane, window);
      if (published.ok) {
        return jsonResponse({
          published: true,
          id: published.id,
          videoId: video.videoId,
          lane,
          startSec: window.start,
          endSec: window.end,
        });
      }
      lastError = published.reason;
    }

    return jsonResponse({ published: false, reason: lastError, lane, attempts });
  } catch (err) {
    const message = err instanceof Error ? err.message : "";
    if (message.startsWith("Missing required env")) return errorResponse(500, "Server misconfigured");
    return errorResponse(500, "Catalog fill failed");
  }
});

async function leastFilledLane(
  supabase: ReturnType<typeof serviceClient>,
): Promise<Lane> {
  const { data } = await supabase.from("clips").select("category, difficulty").eq("published", true);
  const counts = new Map<string, number>();
  for (const row of data ?? []) {
    const key = `${row.category}|${row.difficulty}`;
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  return LANES.reduce((best, lane) => {
    const bestCount = counts.get(`${best.category}|${best.difficulty}`) ?? 0;
    const laneCount = counts.get(`${lane.category}|${lane.difficulty}`) ?? 0;
    return laneCount < bestCount ? lane : best;
  });
}

type FreshVideo = { videoId: string; title: string; channelTitle: string; durationSec: number };

async function searchFresh(
  supabase: ReturnType<typeof serviceClient>,
  query: string,
): Promise<{ ok: true; videos: FreshVideo[] } | { ok: false; reason: string }> {
  if (!(await tryConsumeYoutubeQuota(supabase, 100))) {
    return { ok: false, reason: "youtube-quota" };
  }
  const ytKey = requireEnv("YOUTUBE_API_KEY");
  const searchParams = new URLSearchParams({
    part: "snippet",
    type: "video",
    q: query,
    maxResults: "8",
    videoEmbeddable: "true",
    videoDuration: "short",
    regionCode: "JP",
    relevanceLanguage: "ja",
    key: ytKey,
  });
  const searchRes = await fetch(`https://www.googleapis.com/youtube/v3/search?${searchParams}`);
  if (!searchRes.ok) return { ok: false, reason: "youtube-search-failed" };
  const searchJson = await searchRes.json() as { items?: SearchItem[] };
  const ids = (searchJson.items ?? [])
    .map((item) => item.id?.videoId)
    .filter((id): id is string => typeof id === "string" && id.length === 11);
  if (ids.length === 0) return { ok: true, videos: [] };

  if (!(await tryConsumeYoutubeQuota(supabase, 1))) {
    return { ok: false, reason: "youtube-quota" };
  }
  const videosParams = new URLSearchParams({
    part: "snippet,status,contentDetails",
    id: ids.join(","),
    key: ytKey,
  });
  const videosRes = await fetch(`https://www.googleapis.com/youtube/v3/videos?${videosParams}`);
  if (!videosRes.ok) return { ok: false, reason: "youtube-videos-failed" };
  const videosJson = await videosRes.json() as { items?: VideoItem[] };

  const { data: existing } = await supabase.from("clips").select("video_id");
  const existingIds = new Set((existing ?? []).map((row: { video_id: string }) => row.video_id));

  const videos: FreshVideo[] = [];
  for (const item of videosJson.items ?? []) {
    const videoId = item.id;
    if (!videoId || existingIds.has(videoId)) continue;
    if (item.status?.embeddable !== true || item.status?.privacyStatus !== "public") continue;
    const durationSec = parseDurationSec(item.contentDetails?.duration ?? "");
    if (durationSec === null || durationSec < 12 || durationSec > 240) continue;
    videos.push({
      videoId,
      title: item.snippet?.title?.trim() || `Clip ${videoId}`,
      channelTitle: item.snippet?.channelTitle?.trim() || "Unknown",
      durationSec,
    });
  }
  return { ok: true, videos };
}

function clipWindow(durationSec: number): { start: number; end: number } | null {
  const start = durationSec > 30 ? 5 : 0;
  const end = Math.min(durationSec, start + 40);
  if (end - start < 12 || end - start > 180) return null;
  return { start, end };
}

async function analyzeAndPublish(
  supabase: ReturnType<typeof serviceClient>,
  video: FreshVideo,
  lane: Lane,
  window: { start: number; end: number },
): Promise<{ ok: true; id: string } | { ok: false; reason: string }> {
  if (!(await tryIncrementGeminiUsage(supabase))) {
    return { ok: false, reason: "gemini-cap" };
  }
  const id = `immersion-${video.videoId}-${Math.floor(window.start)}-${Math.floor(window.end)}`;
  const model = geminiModelAnalyze();
  let text = "";
  try {
    const result = await geminiAnalyzeYouTubeSegment({
      model,
      system: SYSTEM,
      user: `Segment window: startSec=${window.start}, endSec=${window.end}. Produce lines JSON for this Japanese clip.`,
      youtubeUrl: `https://www.youtube.com/watch?v=${video.videoId}`,
      startSec: window.start,
      endSec: window.end,
    });
    text = result.text;
  } catch {
    return { ok: false, reason: "gemini-failed" };
  }

  let raw: Record<string, unknown>;
  try {
    raw = parseJsonObject(text);
  } catch {
    return { ok: false, reason: "invalid-transcript" };
  }
  const validated = validateLines(raw.lines, window.start, window.end);
  if (!validated.ok) return { ok: false, reason: "invalid-transcript" };

  const lines = raw.lines as LineLike[];
  const row = {
    id,
    video_id: video.videoId,
    title: video.title.slice(0, 140),
    channel_name: video.channelTitle.slice(0, 80),
    category: lane.category,
    difficulty: lane.difficulty,
    duration_sec: durationFromLines(lines, window.end - window.start),
    lines,
    published: true,
    channel_avatar_color: "#FF6B00",
    thumbnail_gradient: GRADIENTS[Math.abs(hashCode(id)) % GRADIENTS.length],
  };
  const { error } = await supabase.from("clips").upsert(row);
  if (error) return { ok: false, reason: "insert-failed" };
  return { ok: true, id };
}

function parseDurationSec(iso: string): number | null {
  const match = iso.match(/^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$/);
  if (!match) return null;
  return Number(match[1] ?? 0) * 3600 + Number(match[2] ?? 0) * 60 + Number(match[3] ?? 0);
}

function hashCode(value: string): number {
  let hash = 0;
  for (let i = 0; i < value.length; i++) hash = (Math.imul(31, hash) + value.charCodeAt(i)) | 0;
  return hash;
}
