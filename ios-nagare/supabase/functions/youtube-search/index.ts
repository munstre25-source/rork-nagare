import { corsPreflight, errorResponse, jsonResponse, readJson } from "../_shared/http.ts";
import { requireEnv } from "../_shared/env.ts";
import { requireAdmin } from "../_shared/admin.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { tryConsumeYoutubeQuota } from "../_shared/limits.ts";

type Body = { query?: string; maxResults?: number };

type SearchItem = {
  id?: { videoId?: string };
  snippet?: {
    title?: string;
    channelTitle?: string;
    publishedAt?: string;
    thumbnails?: { medium?: { url?: string }; default?: { url?: string } };
  };
};

type VideoItem = {
  id?: string;
  status?: { embeddable?: boolean; privacyStatus?: string };
  contentDetails?: { duration?: string };
  snippet?: {
    title?: string;
    channelTitle?: string;
    publishedAt?: string;
    thumbnails?: { medium?: { url?: string }; default?: { url?: string } };
  };
};

/** Parse ISO-8601 duration like PT1M30S → seconds. */
function parseDurationSec(iso: string): number | null {
  const m = iso.match(/^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$/);
  if (!m) return null;
  const h = Number(m[1] ?? 0);
  const min = Number(m[2] ?? 0);
  const s = Number(m[3] ?? 0);
  return h * 3600 + min * 60 + s;
}

const SEARCH_QUOTA = 100;
const VIDEOS_QUOTA = 1;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") return errorResponse(405, "Method not allowed");

  try {
    const adminToken = requireEnv("ADMIN_TOKEN");
    if (!requireAdmin(req, adminToken)) return errorResponse(401, "Unauthorized");

    const body = await readJson<Body>(req);
    const query = typeof body.query === "string" ? body.query.trim() : "";
    if (!query) return errorResponse(400, "query is required");
    const maxResults = Math.min(
      25,
      Math.max(1, Number.isFinite(body.maxResults) ? Number(body.maxResults) : 10),
    );

    const supabase = serviceClient();

    // Reserve search.list quota first (100 units).
    if (!(await tryConsumeYoutubeQuota(supabase, SEARCH_QUOTA))) {
      return errorResponse(429, "YouTube daily quota exceeded");
    }

    const ytKey = requireEnv("YOUTUBE_API_KEY");
    const searchParams = new URLSearchParams({
      part: "snippet",
      type: "video",
      q: query,
      maxResults: String(maxResults),
      videoEmbeddable: "true",
      videoDuration: "short",
      regionCode: "JP",
      relevanceLanguage: "ja",
      key: ytKey,
    });

    const searchRes = await fetch(
      `https://www.googleapis.com/youtube/v3/search?${searchParams}`,
    );
    if (!searchRes.ok) return errorResponse(502, "YouTube search failed");
    const searchJson = await searchRes.json() as { items?: SearchItem[] };
    const ids = (searchJson.items ?? [])
      .map((i) => i.id?.videoId)
      .filter((id): id is string => typeof id === "string" && id.length > 0);

    if (ids.length === 0) return jsonResponse({ results: [] });

    // videos.list ≈ 1 unit
    if (!(await tryConsumeYoutubeQuota(supabase, VIDEOS_QUOTA))) {
      return errorResponse(429, "YouTube daily quota exceeded");
    }

    const videosParams = new URLSearchParams({
      part: "snippet,status,contentDetails",
      id: ids.join(","),
      key: ytKey,
    });
    const videosRes = await fetch(
      `https://www.googleapis.com/youtube/v3/videos?${videosParams}`,
    );
    if (!videosRes.ok) return errorResponse(502, "YouTube videos.list failed");
    const videosJson = await videosRes.json() as { items?: VideoItem[] };

    const { data: existing } = await supabase.from("clips").select("video_id");
    const existingIds = new Set(
      (existing ?? []).map((r: { video_id: string }) => r.video_id),
    );

    const results = [];
    for (const v of videosJson.items ?? []) {
      const videoId = v.id;
      if (!videoId || existingIds.has(videoId)) continue;
      if (v.status?.embeddable !== true) continue;
      if (v.status?.privacyStatus !== "public") continue;
      const durationSec = parseDurationSec(v.contentDetails?.duration ?? "");
      if (durationSec === null || durationSec <= 0 || durationSec > 180) continue;

      const thumb =
        v.snippet?.thumbnails?.medium?.url ??
        v.snippet?.thumbnails?.default?.url ??
        null;

      results.push({
        videoId,
        title: v.snippet?.title ?? "",
        channelTitle: v.snippet?.channelTitle ?? "",
        thumbnailUrl: thumb,
        publishedAt: v.snippet?.publishedAt ?? null,
        durationSec,
      });
    }

    return jsonResponse({ results });
  } catch (err) {
    const message = err instanceof Error ? err.message : "";
    if (message.startsWith("Missing required env")) {
      return errorResponse(500, "Server misconfigured");
    }
    return errorResponse(500, "Search failed");
  }
});
