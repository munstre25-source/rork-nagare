import { corsPreflight, errorResponse, jsonResponse, readJson } from "../_shared/http.ts";
import { requireEnv } from "../_shared/env.ts";
import { isAdminOrCron } from "../_shared/admin.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { tryConsumeYoutubeQuota } from "../_shared/limits.ts";
import { catalogTable, parseLanguage, type CatalogLanguage } from "../_shared/catalog.ts";
import { analyzeWindow, clipId, clipRow, log } from "../_shared/immersion.ts";

/**
 * One scheduled pass: publish learner clips from the candidate queue, and only when the
 * queue runs low search YouTube for fresh candidates. Each search costs 101 quota units,
 * so results are queued and consumed over many passes instead of being dropped when the
 * analysis budget runs out. Publishing itself uses no YouTube quota.
 *
 * The hearing pass is one AI call per clip (dictionary fields ride along; definitions are
 * fetched on tap through the shared word_explanations cache), which keeps the cost per
 * clip low enough for the library to grow by dozens of clips per day.
 *
 * Body {"language":"ko"} writes sori_clips. Anything else writes clips. Admin only; a
 * pg_cron job calls this with x-admin-token every 10 minutes.
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
  { category: "gaming", difficulty: "Intermediate", query: "日本語 マイクラ 実況 会話 ショート" },
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
    if (!isAdminOrCron(req)) return errorResponse(401, "Unauthorized");

    const body = await readJson<{ language?: string }>(req);
    const language = parseLanguage(body.language);
    const supabase = serviceClient();
    const cronReady = await rememberCronAccess(supabase);
    const published: Array<{ id: string; videoId: string; difficulty: string; category: string }> = [];
    const pause = await fillPause(supabase);
    if (pause) return jsonResponse(summary(published, pause, cronReady));
    const started = Date.now();
    let stopped = "time-budget";
    await pruneQueue(supabase, language);

    // Fill the queue with search results first (quota is spent here, once per candidate),
    // then spend the rest of the pass publishing from it. A quota wall during the search
    // phase must not stop the pass: queued candidates still publish quota-free.
    const queued = await queueCount(supabase, language);
    if (queued < QUEUE_TARGET) {
      const fill = await enqueueFreshCandidates(supabase, language, started, QUEUE_TARGET - queued);
      if (fill.stopped) stopped = fill.stopped;
    }

    const queue = await takeQueue(supabase, language, RUN_CANDIDATE_TARGET);
    for (const candidate of queue) {
      if (Date.now() - started >= RUN_BUDGET_MS) break;
      const result = await analyzeAndPublish(supabase, candidate, language);
      if (!result.ok) {
        const keep = result.reason === "gemini-cap" || result.reason === "model_payment" ||
          result.reason.includes("402");
        if (!keep) await removeQueued(supabase, language, candidate.videoId);
        if (result.reason === "gemini-cap") {
          stopped = "gemini-cap";
          return jsonResponse(summary(published, stopped, cronReady));
        }
        if (result.reason === "model_payment" || result.reason.includes("402")) {
          await pauseFill(supabase, "gemini-payment");
          stopped = "model-payment";
          return jsonResponse(summary(published, stopped, cronReady));
        }
        continue;
      }
      await removeQueued(supabase, language, candidate.videoId);
      published.push({
        id: result.id,
        videoId: candidate.videoId,
        difficulty: result.difficulty,
        category: candidate.category,
      });
    }
    if (published.length === 0 && stopped === "time-budget" && queue.length === 0) {
      stopped = "no-candidate";
    }

    return jsonResponse(summary(published, stopped, cronReady));
  } catch (err) {
    const message = err instanceof Error ? err.message : "";
    log("catalog_fill_error", { message: message.slice(0, 200) });
    if (message.startsWith("Missing required env")) return errorResponse(500, "Server misconfigured");
    return errorResponse(500, "Catalog fill failed");
  }
});

const RUN_BUDGET_MS = 110_000;
/** Candidates pulled from the queue per pass. */
const RUN_CANDIDATE_TARGET = 6;
/** A bad-yield lane must not dump the day's search quota into one pass. */
const MAX_SEARCHES_PER_PASS = 3;
/** Keep at least this many unprocessed candidates queued for the language. */
const QUEUE_TARGET = 15;
const QUERY_VARIANTS: Record<CatalogLanguage, string[]> = {
  ja: ["", "日常会話", "2024", "2025"],
  ko: ["", "일상회화", "2024", "2025"],
};

// MARK: - Candidate queue

type QueuedCandidate = {
  videoId: string;
  title: string;
  channelTitle: string;
  durationSec: number;
  category: string;
  difficulty: string;
};

async function queueCount(
  supabase: ReturnType<typeof serviceClient>,
  language: CatalogLanguage,
): Promise<number> {
  const { count } = await supabase
    .from(queueTable(language))
    .select("video_id", { count: "exact", head: true });
  return count ?? 0;
}

function queueTable(language: CatalogLanguage): string {
  return language === "ko" ? "sori_candidate_queue" : "catalog_candidate_queue";
}

async function pruneQueue(
  supabase: ReturnType<typeof serviceClient>,
  language: CatalogLanguage,
): Promise<void> {
  const cutoff = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
  await supabase.from(queueTable(language)).delete().lt("added_at", cutoff);
}

async function takeQueue(
  supabase: ReturnType<typeof serviceClient>,
  language: CatalogLanguage,
  limit: number,
): Promise<QueuedCandidate[]> {
  const { data } = await supabase
    .from(queueTable(language))
    .select("video_id, title, channel_title, duration_sec, category, difficulty")
    .order("added_at", { ascending: true })
    .limit(limit);
  return ((data ?? []) as Array<Record<string, unknown>>).map((row) => ({
    videoId: String(row.video_id),
    title: String(row.title ?? ""),
    channelTitle: String(row.channel_title ?? ""),
    durationSec: Number(row.duration_sec ?? 0),
    category: String(row.category ?? "interview"),
    difficulty: String(row.difficulty ?? "Beginner"),
  }));
}

async function removeQueued(
  supabase: ReturnType<typeof serviceClient>,
  language: CatalogLanguage,
  videoId: string,
): Promise<void> {
  await supabase.from(queueTable(language)).delete().eq("video_id", videoId);
}

/**
 * Searches the emptiest lanes until at least `target` fresh candidates are queued.
 * A search page's videos are all queued, so one 101-unit search serves many passes.
 */
async function enqueueFreshCandidates(
  supabase: ReturnType<typeof serviceClient>,
  language: CatalogLanguage,
  started: number,
  target: number,
): Promise<{ stopped: string | null }> {
  const lanes = await lanesByEmptiness(supabase, language);
  let queuedNew = 0;
  let searches = 0;
  for (const lane of lanes) {
    if (queuedNew >= target || searches >= MAX_SEARCHES_PER_PASS || Date.now() - started >= RUN_BUDGET_MS) break;
    const laneKey = `${language}|${lane.category}|${lane.difficulty}`;
    const found = await searchFresh(supabase, lane, language, laneKey);
    if (!found.ok) {
      if (found.reason === "youtube-quota") return { stopped: "youtube-quota" };
      continue;
    }
    searches++;
    if (found.videos.length === 0) {
      await advanceCursor(supabase, laneKey, found.nextPageToken);
      continue;
    }
    const rows = found.videos.map((video) => ({
      video_id: video.videoId,
      title: video.title.slice(0, 140),
      channel_title: video.channelTitle.slice(0, 80),
      duration_sec: video.durationSec,
      category: lane.category,
      difficulty: lane.difficulty,
      added_at: new Date().toISOString(),
    }));
    const { error, count } = await supabase
      .from(queueTable(language))
      .upsert(rows, { onConflict: "video_id", count: "exact", ignoreDuplicates: true });
    if (error) {
      log("candidate_queue_upsert_failed", { detail: error.message.slice(0, 120) });
      continue;
    }
    queuedNew += count ?? 0;
    // A page that queues nothing new is exhausted: advance the cursor so the next
    // search moves on. Otherwise keep the page token — those queued videos still get
    // consumed by later passes before this lane is searched again.
  }
  return { stopped: null };
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
    maxResults: "25",
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

  const { data: queued } = await supabase
    .from(queueTable(language))
    .select("video_id")
    .in("video_id", ids);
  for (const row of queued ?? []) existingIds.add((row as { video_id: string }).video_id);

  const videos: FreshVideo[] = [];
  for (const item of videosJson.items ?? []) {
    const videoId = item.id;
    if (!videoId || existingIds.has(videoId)) continue;
    if (item.status?.embeddable !== true || item.status?.privacyStatus !== "public") continue;
    const durationSec = parseDurationSec(item.contentDetails?.duration ?? "");
    // YouTube's "short" search filter means under four minutes, not a learner-sized
    // excerpt. Keep only sources we can inspect in one pass and curate into 20–90s clips.
    if (durationSec === null || durationSec < 20 || durationSec > 180) continue;
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

async function analyzeAndPublish(
  supabase: ReturnType<typeof serviceClient>,
  candidate: QueuedCandidate,
  language: CatalogLanguage,
): Promise<{ ok: true; id: string; difficulty: string } | { ok: false; reason: string }> {
  const outcome = await analyzeWindow(supabase, {
    videoId: candidate.videoId,
    windowStart: 0,
    // A 90s window keeps the heard response small enough for the edge worker's compute
    // limit; longer sources still yield learner-sized clips from their first 90 seconds.
    windowEnd: Math.min(candidate.durationSec, 90),
    language,
    askCategory: false,
    minSpokenSec: 12,
  });
  if (!outcome.ok) {
    log("catalog_candidate_rejected", {
      videoId: candidate.videoId,
      reason: outcome.reason,
      detail: outcome.detail,
    });
    if (outcome.reason === "gemini_cap") return { ok: false, reason: "gemini-cap" };
    if (outcome.reason === "model_payment") return { ok: false, reason: "Gemini HTTP 402" };
    return { ok: false, reason: outcome.reason };
  }
  const prefix = language === "ko" ? "sori" : "immersion";
  const id = clipId(prefix, candidate.videoId, outcome.draft);
  const row = clipRow({
    id,
    video: {
      videoId: candidate.videoId,
      title: candidate.title,
      channelTitle: candidate.channelTitle,
      durationSec: candidate.durationSec,
    },
    draft: outcome.draft,
    category: candidate.category,
    published: true,
    withProvenance: language === "ja",
  });
  const { error } = await supabase.from(catalogTable(language)).upsert(row);
  if (error) return { ok: false, reason: "insert-failed" };
  log("catalog_clip_published", { id, timingMode: outcome.draft.timingMode, model: outcome.draft.model });
  return { ok: true, id, difficulty: outcome.draft.difficulty };
}

function parseDurationSec(iso: string): number | null {
  const match = iso.match(/^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$/);
  if (!match) return null;
  return Number(match[1] ?? 0) * 3600 + Number(match[2] ?? 0) * 60 + Number(match[3] ?? 0);
}
