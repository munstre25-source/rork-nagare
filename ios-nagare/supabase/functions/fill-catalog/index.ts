import { corsPreflight, errorResponse, jsonResponse, readJson } from "../_shared/http.ts";
import { geminiModelAnalyze, requireEnv } from "../_shared/env.ts";
import { requireAdmin, timingSafeEqualString } from "../_shared/admin.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { tryConsumeYoutubeQuota, tryIncrementGeminiUsage } from "../_shared/limits.ts";
import { geminiAnalyzeYouTubeSegment, parseJsonObject } from "../_shared/gemini.ts";
import { catalogTable, languageName, parseLanguage, type CatalogLanguage } from "../_shared/catalog.ts";
import { enrichHeardLines, hearSystemCatalog } from "../_shared/enrich.ts";
import {
  durationFromLines,
  LineLike,
  validateEnums,
  validateLines,
} from "../_shared/validate.ts";

/**
 * One scheduled pass: search YouTube for a short public video the catalog
 * does not have yet, ask Gemini for a learner transcript, and publish it when the
 * lines validate. Body {"language":"ko"} writes sori_clips. Anything else writes
 * clips. The phone never downloads the file. It plays the YouTube id.
 *
 * Admin only. A pg_cron job calls this with x-admin-token.
 */

type Lane = { category: string; difficulty: string; query: string };

const JAPANESE_LANES: Lane[] = [
  { category: "interview", difficulty: "Beginner", query: "日本語 街頭インタビュー ショート" },
  { category: "interview", difficulty: "Advanced", query: "日本語 インタビュー 会話 ショート" },
  { category: "drama", difficulty: "Beginner", query: "コンビニ カフェ 注文 日本語 会話 ショート" },
  { category: "drama", difficulty: "Advanced", query: "日本語 ドラマ セリフ ショート" },
  { category: "variety", difficulty: "Intermediate", query: "日本語 あるある トーク ショート" },
  { category: "kids", difficulty: "Beginner", query: "子供向け 日本語 あいさつ 会話 ショート" },
  { category: "anime", difficulty: "Beginner", query: "日本語 アニメ 日常会話 ショート" },
  { category: "anime", difficulty: "Intermediate", query: "アニメ セリフ 日本語 ショート" },
  { category: "vtuber", difficulty: "Intermediate", query: "日本語 VTuber 雑談 ショート" },
  { category: "gaming", difficulty: "Intermediate", query: "日本語 ゲーム実況 会話 ショート" },
];

const KOREAN_LANES: Lane[] = [
  { category: "interview", difficulty: "Beginner", query: "한국어 길거리 인터뷰 쇼츠" },
  { category: "interview", difficulty: "Advanced", query: "한국어 인터뷰 대화 쇼츠" },
  { category: "drama", difficulty: "Beginner", query: "편의점 카페 주문 한국어 회화 쇼츠" },
  { category: "drama", difficulty: "Advanced", query: "한국어 드라마 대사 쇼츠" },
  { category: "variety", difficulty: "Intermediate", query: "한국어 예능 토크 쇼츠" },
  { category: "kids", difficulty: "Beginner", query: "어린이 한국어 인사 회화 쇼츠" },
  { category: "anime", difficulty: "Beginner", query: "한국어 애니메이션 일상 회화 쇼츠" },
  { category: "anime", difficulty: "Intermediate", query: "한국 애니 대사 쇼츠" },
  { category: "vtuber", difficulty: "Intermediate", query: "한국어 버튜버 잡담 쇼츠" },
  { category: "gaming", difficulty: "Intermediate", query: "한국어 게임 실황 대화 쇼츠" },
];

function lanesFor(language: CatalogLanguage): Lane[] {
  return language === "ko" ? KOREAN_LANES : JAPANESE_LANES;
}

const GRADIENTS = [
  ["#0B1030", "#2B2F7A", "#F29E4C"],
  ["#10261A", "#2E7D4F", "#F6E27F"],
  ["#2B1405", "#9C3D10", "#F2B134"],
];

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
    if (!isCatalogAdmin(req)) return errorResponse(401, "Unauthorized");

    const body = await readJson<{ language?: string }>(req);
    const language = parseLanguage(body.language);
    const supabase = serviceClient();
    const cronReady = await rememberCronAccess(supabase);
    const published: Array<{ id: string; videoId: string; difficulty: string; category: string }> = [];
    const pause = await fillPause(supabase);
    if (pause) return jsonResponse(summary(published, pause, cronReady));
    const started = Date.now();
    const seenVideos = new Set<string>();
    let stopped = "time-budget";

    while (Date.now() - started < RUN_BUDGET_MS) {
      const lanes = await lanesByEmptiness(supabase, language);
      let moved = false;
      for (const lane of lanes) {
        if (Date.now() - started >= RUN_BUDGET_MS) break;
        const laneKey = `${language}|${lane.category}|${lane.difficulty}`;
        const found = await searchFresh(supabase, lane, language, laneKey);
        if (!found.ok) {
          stopped = found.reason;
          if (found.reason === "youtube-quota") {
            return jsonResponse(summary(published, stopped, cronReady));
          }
          continue;
        }
        if (found.videos.length === 0) {
          await advanceCursor(supabase, laneKey, found.nextPageToken);
          moved = true;
          continue;
        }
        let pagePublished = false;
        for (const video of found.videos) {
          if (seenVideos.has(video.videoId) || Date.now() - started >= RUN_BUDGET_MS) continue;
          seenVideos.add(video.videoId);
          for (const window of lessonWindows(video.durationSec)) {
            const result = await analyzeAndPublish(supabase, video, lane, window, language);
            if (result.ok) {
              published.push({
                id: result.id,
                videoId: video.videoId,
                difficulty: result.difficulty,
                category: lane.category,
              });
              pagePublished = true;
              moved = true;
              break;
            }
            if (result.reason === "gemini-cap" || result.reason === "youtube-quota" || result.reason.includes("402")) {
              if (result.reason.includes("402")) await pauseFill(supabase, "gemini-payment");
              return jsonResponse(summary(published, result.reason, cronReady));
            }
          }
        }
        if (!pagePublished) {
          await advanceCursor(supabase, laneKey, found.nextPageToken);
          moved = true;
        }
      }
      if (!moved) {
        stopped = "no-candidate";
        break;
      }
    }

    return jsonResponse(summary(published, stopped, cronReady));
  } catch (err) {
    const message = err instanceof Error ? err.message : "";
    if (message.startsWith("Missing required env")) return errorResponse(500, "Server misconfigured");
    return errorResponse(500, "Catalog fill failed");
  }
});

const RUN_BUDGET_MS = 40_000;
const QUERY_VARIANTS: Record<CatalogLanguage, string[]> = {
  ja: ["", "日常会話", "2024", "2025"],
  ko: ["", "일상회화", "2024", "2025"],
};

function isCatalogAdmin(req: Request): boolean {
  const adminToken = requireEnv("ADMIN_TOKEN");
  if (requireAdmin(req, adminToken)) return true;
  const cronToken = Deno.env.get("CRON_FILL_TOKEN")?.trim() ?? "";
  if (cronToken.length < 16) return false;
  const provided = req.headers.get("x-admin-token") ?? "";
  return timingSafeEqualString(provided, cronToken);
}

async function rememberCronAccess(
  supabase: ReturnType<typeof serviceClient>,
): Promise<boolean> {
  const cronToken = Deno.env.get("CRON_FILL_TOKEN")?.trim() ?? "";
  const projectUrl = (Deno.env.get("SUPABASE_URL") ?? "").trim().replace(/\/$/, "");
  const bearer = (Deno.env.get("SUPABASE_ANON_KEY") ?? "").trim();
  if (cronToken.length < 16 || projectUrl.length < 12 || bearer.length < 16) return false;
  const names = [
    ["project_url", projectUrl],
    ["admin_token", cronToken],
    ["catalog_bearer", bearer],
  ] as const;
  for (const [secretName, secretValue] of names) {
    const { error } = await supabase.rpc("upsert_vault_secret", {
      secret_name: secretName,
      secret_value: secretValue,
    });
    if (error) return false;
  }
  return true;
}

async function fillPause(supabase: ReturnType<typeof serviceClient>): Promise<string | null> {
  const { data } = await supabase
    .from("catalog_fill_state")
    .select("paused_until, pause_reason")
    .eq("id", 1)
    .maybeSingle();
  const row = data as { paused_until?: string | null; pause_reason?: string | null } | null;
  if (!row?.paused_until) return null;
  if (Date.parse(row.paused_until) <= Date.now()) return null;
  return row.pause_reason || "paused";
}

async function pauseFill(supabase: ReturnType<typeof serviceClient>, reason: string): Promise<void> {
  const until = new Date(Date.now() + 2 * 60 * 60 * 1000).toISOString();
  await supabase.from("catalog_fill_state").upsert({
    id: 1,
    paused_until: until,
    pause_reason: reason,
    updated_at: new Date().toISOString(),
  });
}

function summary(
  published: Array<{ id: string; videoId: string; difficulty: string; category: string }>,
  stopped: string,
  cronReady: boolean,
) {
  return {
    published: published.length > 0,
    count: published.length,
    stopped,
    cronReady,
    clips: published,
  };
}

async function lanesByEmptiness(
  supabase: ReturnType<typeof serviceClient>,
  language: CatalogLanguage,
): Promise<Lane[]> {
  const { data } = await supabase.from(catalogTable(language)).select("category, difficulty").eq("published", true);
  const counts = new Map<string, number>();
  for (const row of data ?? []) {
    const key = `${row.category}|${row.difficulty}`;
    counts.set(key, (counts.get(key) ?? 0) + 1);
    const levelKey = `level|${row.difficulty}`;
    counts.set(levelKey, (counts.get(levelKey) ?? 0) + 1);
  }
  return [...lanesFor(language)].sort((a, b) => laneRank(a, counts) - laneRank(b, counts));
}

function laneRank(lane: Lane, counts: Map<string, number>): number {
  const level = counts.get(`level|${lane.difficulty}`) ?? 0;
  const cell = counts.get(`${lane.category}|${lane.difficulty}`) ?? 0;
  return level * 100 + cell;
}

type FreshVideo = { videoId: string; title: string; channelTitle: string; durationSec: number };

async function searchFresh(
  supabase: ReturnType<typeof serviceClient>,
  lane: Lane,
  language: CatalogLanguage,
  laneKey: string,
): Promise<
  | { ok: true; videos: FreshVideo[]; nextPageToken: string | null }
  | { ok: false; reason: string }
> {
  if (!(await tryConsumeYoutubeQuota(supabase, 100))) {
    return { ok: false, reason: "youtube-quota" };
  }
  const cursor = await loadCursor(supabase, laneKey);
  const variants = QUERY_VARIANTS[language];
  const variant = variants[cursor.variant % variants.length] ?? "";
  const ytKey = requireEnv("YOUTUBE_API_KEY");
  const searchParams = new URLSearchParams({
    part: "snippet",
    type: "video",
    q: `${lane.query} ${variant}`.trim(),
    maxResults: "8",
    videoEmbeddable: "true",
    videoDuration: "short",
    order: "date",
    relevanceLanguage: language,
    regionCode: language === "ko" ? "KR" : "JP",
    key: ytKey,
  });
  if (cursor.pageToken) searchParams.set("pageToken", cursor.pageToken);
  const searchRes = await fetch(`https://www.googleapis.com/youtube/v3/search?${searchParams}`);
  if (!searchRes.ok) return { ok: false, reason: "youtube-search-failed" };
  const searchJson = await searchRes.json() as { items?: SearchItem[]; nextPageToken?: string };
  const ids = (searchJson.items ?? [])
    .map((item) => item.id?.videoId)
    .filter((id): id is string => typeof id === "string" && id.length === 11);
  const nextPageToken = searchJson.nextPageToken ?? null;
  if (ids.length === 0) return { ok: true, videos: [], nextPageToken };

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

  const { data: existing } = await supabase
    .from(catalogTable(language))
    .select("video_id")
    .in("video_id", ids);
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
  return { ok: true, videos, nextPageToken };
}

type SearchCursor = { pageToken: string | null; variant: number };

async function loadCursor(
  supabase: ReturnType<typeof serviceClient>,
  laneKey: string,
): Promise<SearchCursor> {
  const { data } = await supabase
    .from("catalog_search_cursors")
    .select("page_token, variant")
    .eq("lane_key", laneKey)
    .maybeSingle();
  const row = data as { page_token?: string | null; variant?: number } | null;
  return {
    pageToken: row?.page_token ?? null,
    variant: typeof row?.variant === "number" ? row.variant : 0,
  };
}

async function advanceCursor(
  supabase: ReturnType<typeof serviceClient>,
  laneKey: string,
  nextPageToken: string | null,
): Promise<void> {
  const current = await loadCursor(supabase, laneKey);
  const variant = nextPageToken ? current.variant : current.variant + 1;
  await supabase.from("catalog_search_cursors").upsert({
    lane_key: laneKey,
    page_token: nextPageToken,
    variant,
    updated_at: new Date().toISOString(),
  });
}

function lessonWindows(durationSec: number): Array<{ start: number; end: number }> {
  const windows: Array<{ start: number; end: number }> = [];
  let start = durationSec > 25 ? 4 : 0;
  while (windows.length < 3 && start + 8 < durationSec) {
    const end = Math.min(durationSec, start + 18);
    if (end - start >= 8 && end - start <= 22) windows.push({ start, end });
    start += 14;
  }
  return windows;
}

function isLesson(lines: LineLike[]): boolean {
  if (lines.length < 2 || lines.length > 5) return false;
  const start = Number(lines[0]?.start);
  const end = Number(lines[lines.length - 1]?.end);
  const span = end - start;
  if (!Number.isFinite(span) || span < 6 || span > 24) return false;
  let defined = 0;
  for (const line of lines) {
    const tokens = Array.isArray(line.tokens) ? line.tokens : [];
    for (const token of tokens) {
      const definitions = (token as { definitions?: unknown }).definitions;
      if (Array.isArray(definitions) && definitions.length > 0) defined += 1;
    }
  }
  return defined >= 2;
}

function gradeDifficulty(modelValue: unknown, lines: LineLike[]): string {
  if (typeof modelValue === "string" && validateEnums("drama", modelValue).ok) return modelValue;
  const rank: Record<string, number> = { N5: 1, N4: 2, N3: 3, N2: 4, N1: 5 };
  let score = 0;
  let counted = 0;
  for (const line of lines) {
    const tokens = Array.isArray(line.tokens) ? line.tokens : [];
    for (const token of tokens) {
      const jlpt = (token as { jlpt?: unknown }).jlpt;
      if (typeof jlpt === "string" && rank[jlpt]) {
        score += rank[jlpt];
        counted += 1;
      }
    }
  }
  if (counted === 0) return "Intermediate";
  const average = score / counted;
  if (average < 2.2) return "Beginner";
  if (average < 3.4) return "Intermediate";
  return "Advanced";
}

async function analyzeAndPublish(
  supabase: ReturnType<typeof serviceClient>,
  video: FreshVideo,
  lane: Lane,
  window: { start: number; end: number },
  language: CatalogLanguage,
): Promise<{ ok: true; id: string; difficulty: string } | { ok: false; reason: string }> {
  if (!(await tryIncrementGeminiUsage(supabase))) {
    return { ok: false, reason: "gemini-cap" };
  }
  const prefix = language === "ko" ? "sori" : "immersion";
  const id = `${prefix}-${video.videoId}-${Math.floor(window.start)}-${Math.floor(window.end)}`;
  const model = geminiModelAnalyze();
  let text = "";
  try {
    const result = await geminiAnalyzeYouTubeSegment({
      model,
      system: hearSystemCatalog(language),
      user: `Segment window: startSec=${window.start}, endSec=${window.end}. Produce lines JSON for this ${languageName(language)} clip.`,
      youtubeUrl: `https://www.youtube.com/watch?v=${video.videoId}`,
      startSec: window.start,
      endSec: window.end,
    });
    text = result.text;
  } catch (err) {
    const message = err instanceof Error ? err.message : "";
    if (message.startsWith("Gemini HTTP")) {
      return { ok: false, reason: message.slice(0, 96) };
    }
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
  const lines = await enrichHeardLines(raw.lines, supabase, language) as LineLike[];
  if (!isLesson(lines)) return { ok: false, reason: "not-a-lesson" };
  const difficulty = gradeDifficulty(raw.difficulty, lines);
  const row = {
    id,
    video_id: video.videoId,
    title: video.title.slice(0, 140),
    channel_name: video.channelTitle.slice(0, 80),
    category: lane.category,
    difficulty,
    duration_sec: durationFromLines(lines, window.end - window.start),
    lines,
    published: true,
    channel_avatar_color: "#FF6B00",
    thumbnail_gradient: GRADIENTS[Math.abs(hashCode(id)) % GRADIENTS.length],
  };
  const { error } = await supabase.from(catalogTable(language)).upsert(row);
  if (error) return { ok: false, reason: "insert-failed" };
  return { ok: true, id, difficulty };
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
