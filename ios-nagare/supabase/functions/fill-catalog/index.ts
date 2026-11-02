import { startPipeline, updatePipeline, failureStatus } from "../_shared/pipeline.ts";
import { corsPreflight, errorResponse, jsonResponse, readJson } from "../_shared/http.ts";
import { requireEnv } from "../_shared/env.ts";
import { isAdminOrCron } from "../_shared/admin.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { tryConsumeYoutubeQuota } from "../_shared/limits.ts";
import { catalogTable, parseLanguage, type CatalogLanguage } from "../_shared/catalog.ts";
import { analyzeWindow, checkYouTubeVideo, clipId, clipRow, log } from "../_shared/immersion.ts";

/**
 * One scheduled pass: publish learner clips from the candidate queue, and only when the
 * queue runs low search YouTube for fresh candidates. Each search costs 101 quota units,
 * so results are queued and consumed over many passes instead of being dropped when the
 * analysis budget runs out. Publishing itself uses no YouTube quota.
 *
 * Hearing and learner enrichment share one model call. Valid Japanese candidates then
 * get one audio-grounded English review before publication; both calls use the global
 * cap. Reviewed data is shared across learners and modes; rich lookups keep their cache.
 *
 * Body {"language":"ko"} writes sori_clips. Anything else writes clips. Admin only; a
 * pg_cron job calls this with x-admin-token every 10 minutes.
 */

type Lane = {
  category: string;
  difficulty: string;
  query: string;
  tag?: string;
  channelId?: string;
  channelHandle?: string;
};

const JAPANESE_LANES: Lane[] = [
  { category: "interview", difficulty: "Beginner", query: "日本語 街頭インタビュー ショート" },
  { category: "interview", difficulty: "Advanced", query: "日本語 インタビュー 会話 ショート" },
  { category: "interview", difficulty: "Advanced", query: "ニュース 解説 日本語 ショート", tag: "news" },
  { category: "drama", difficulty: "Beginner", query: "コンビニ カフェ 注文 日本語 会話 ショート" },
  { category: "drama", difficulty: "Advanced", query: "日本語 ドラマ セリフ ショート" },
  { category: "drama", difficulty: "Intermediate", query: "ショートドラマ 日本語 会話" },
  { category: "variety", difficulty: "Intermediate", query: "日本語 あるある トーク ショート" },
  { category: "variety", difficulty: "Advanced", query: "お笑い 漫才 コント ショート" },
  { category: "variety", difficulty: "Beginner", query: "バラエティ 日本語 リアクション ショート" },
  { category: "kids", difficulty: "Beginner", query: "子供向け 日本語 あいさつ 会話 ショート" },
  { category: "kids", difficulty: "Beginner", query: "こどもちゃれんじ 絵本 読み聞かせ ショート", tag: "books" },
  { category: "anime", difficulty: "Beginner", query: "日本語 アニメ 日常会話 ショート" },
  { category: "anime", difficulty: "Intermediate", query: "アニメ セリフ 日本語 ショート" },
  // Official channels requested for curated anime Japanese. Channel-only searches still
  // pass through the same duration, embed, speech, and transcript validation gates.
  { category: "anime", difficulty: "Intermediate", query: "", channelHandle: "bluearchive_Global", tag: "bluearchive-global" },
  { category: "anime", difficulty: "Intermediate", query: "", channelId: "UC0OXPEQRKArB_EVyFMwDbAQ", tag: "tv-tokyo-anitere" },
  { category: "anime", difficulty: "Intermediate", query: "", channelId: "UC47AYUs8AVU1QsT5LhpXjaw", tag: "shonen-jump" },
  { category: "anime", difficulty: "Intermediate", query: "", channelHandle: "studio_pierrot", tag: "studio-pierrot" },
  { category: "anime", difficulty: "Intermediate", query: "", channelHandle: "avexpictures", tag: "avex-pictures" },
  { category: "anime", difficulty: "Intermediate", query: "", channelHandle: "TOHOanimation", tag: "toho-animation" },
  { category: "anime", difficulty: "Intermediate", query: "", channelHandle: "ShochikuAnimeOfficial", tag: "shochiku-anime" },
  { category: "anime", difficulty: "Intermediate", query: "", channelHandle: "集英社オレンジ文庫", tag: "shueisha-orange-bunko" },
  { category: "anime", difficulty: "Intermediate", query: "", channelHandle: "TMSAnimeJP", tag: "tms-anime" },
  { category: "anime", difficulty: "Intermediate", query: "", channelHandle: "PONYCANYON_anime", tag: "pony-canyon-anime" },
  { category: "learning", difficulty: "Intermediate", query: "", channelHandle: "japanesethedefinitiveguide2337", tag: "japanese-definitive-guide" },
  { category: "anime", difficulty: "Intermediate", query: "", channelHandle: "bachiramylove629", tag: "bachira-my-love" },
  { category: "kids", difficulty: "Beginner", query: "", channelHandle: "PeppaPigJapaneseOfficial", tag: "peppa-japanese" },
  { category: "kids", difficulty: "Beginner", query: "", channelHandle: "Bebefinn日本語", tag: "bebefinn-japanese" },
  { category: "kids", difficulty: "Beginner", query: "", channelHandle: "BlippiJapanese", tag: "blippi-japanese" },
  { category: "variety", difficulty: "Intermediate", query: "", channelHandle: "QuizKnock", tag: "quizknock" },
  { category: "learning", difficulty: "Beginner", query: "", channelHandle: "japanese_tanakasan", tag: "tanaka-japanese" },
  { category: "learning", difficulty: "Intermediate", query: "", channelHandle: "moshimoshi.yusuke", tag: "moshimoshi-yusuke" },
  { category: "learning", difficulty: "Intermediate", query: "", channelHandle: "kensanokaeri", tag: "ken-san-okaeri" },
  { category: "learning", difficulty: "Beginner", query: "", channelHandle: "withyuki1030", tag: "with-yuki" },
  { category: "learning", difficulty: "Beginner", query: "", channelHandle: "DailyJapanese", tag: "daily-japanese" },
  { category: "learning", difficulty: "Beginner", query: "", channelHandle: "SpeakJapaneseNaturally", tag: "speak-japanese-naturally" },
  { category: "learning", difficulty: "Intermediate", query: "", channelHandle: "JSI55", tag: "jsi55" },
  { category: "learning", difficulty: "Beginner", query: "", channelHandle: "TheNihongoNook", tag: "nihongo-nook" },
  { category: "learning", difficulty: "Beginner", query: "", channelHandle: "KanamatopeJapanese", tag: "kanamatope" },
  { category: "learning", difficulty: "Beginner", query: "", channelHandle: "SayuriSaying", tag: "sayuri-saying" },
  { category: "learning", difficulty: "Beginner", query: "", channelHandle: "the_bitesize_japanese_podcast", tag: "bitesize-japanese" },
  { category: "learning", difficulty: "Beginner", query: "", channelHandle: "tokiwa-japanese", tag: "tokiwa-japanese" },
  { category: "learning", difficulty: "Beginner", query: "", channelHandle: "OkkeiJapanese", tag: "okkei-japanese" },
  { category: "learning", difficulty: "Beginner", query: "", channelHandle: "Akane-JapaneseClass", tag: "akane-japanese" },
  { category: "learning", difficulty: "Beginner", query: "", channelHandle: "nihongo-no-jikan", tag: "nihongo-no-jikan" },
  { category: "learning", difficulty: "Intermediate", query: "", channelHandle: "yuyunihongopodcast", tag: "yuyu-japanese-podcast" },
  { category: "learning", difficulty: "Intermediate", query: "", channelHandle: "nihongonomori2013", tag: "nihongo-no-mori" },
  // とた is an artist channel; variety is reserved for any spoken interview/behind-the-scenes material.
  { category: "variety", difficulty: "Intermediate", query: "", channelHandle: "tota_3470", tag: "tota-artist" },
  { category: "vtuber", difficulty: "Intermediate", query: "日本語 VTuber 雑談 ショート" },
  { category: "gaming", difficulty: "Intermediate", query: "日本語 マイクラ 実況 会話 ショート" },
  { category: "gaming", difficulty: "Intermediate", query: "ゲーム実況 切り抜き 日本語 ショート", tag: "clips" },
  { category: "gaming", difficulty: "Beginner", query: "ポケモン ゲーム 実況 日本語 ショート" },
];

/**
 * "Enough content" per language. Below the target (or with any category under its floor)
 * the cron runs in growth mode: every pass searches/publishes at full speed, always
 * favouring the most underfilled categories. At target it drops to freshness mode: a
 * small daily trickle of new clips so the feed never feels stale, and retirements are
 * replaced automatically because the count falls back under target.
 */
const CATALOG_GOALS: Record<CatalogLanguage, { total: number; categoryFloor: number; freshPerDay: number }> = {
  ja: { total: 2000, categoryFloor: 100, freshPerDay: 24 },
  ko: { total: 300, categoryFloor: 30, freshPerDay: 6 },
};
const CATEGORIES = ["anime", "drama", "variety", "vtuber", "interview", "kids", "gaming", "learning", "podcast"];
/**
 * Catalog searches stop once the shared daily YouTube quota passes this mark, keeping
 * the rest for per-candidate checks (1 unit each), the embed audit and in-app search.
 * 2026-10-30: unbounded searches hit the 10000 cap and blocked publishing for the day.
 */
const SEARCH_QUOTA_CEILING = 7000;

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
type ChannelItem = { id?: string };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") return errorResponse(405, "Method not allowed");

  try {
    if (!isAdminOrCron(req)) return errorResponse(401, "Unauthorized");

    const body = await readJson<{ language?: string; videoIds?: unknown }>(req);
    const language = parseLanguage(body.language);
    const requestedVideoIds = Array.isArray(body.videoIds)
      ? [...new Set(body.videoIds.filter((id): id is string => typeof id === "string").map((id) => id.trim()))]
      : [];
    if (body.videoIds !== undefined && (
      !Array.isArray(body.videoIds) ||
      body.videoIds.length > 50 ||
      body.videoIds.some((id) => typeof id !== "string" || !/^[A-Za-z0-9_-]{11}$/.test(id.trim()))
    )) {
      return errorResponse(400, "videoIds must contain at most 50 valid YouTube IDs");
    }
    if (requestedVideoIds.length > 0 && language !== "ja") {
      return errorResponse(400, "videoIds can only be added to the Japanese catalog");
    }
    const supabase = serviceClient();
    const cronReady = await rememberCronAccess(supabase);
    const published: Array<{ id: string; videoId: string; difficulty: string; category: string }> = [];
    const pause = await fillPause(supabase);
    if (pause) return jsonResponse(summary(published, pause, cronReady));
    const started = Date.now();
    let stopped = "time-budget";
    await pruneQueue(supabase, language);

    const stats = await catalogStats(supabase, language);
    const goal = CATALOG_GOALS[language];
    const growth = stats.total < goal.total ||
      CATEGORIES.filter((c) => language === "ja" || !["learning", "podcast"].includes(c))
        .some((c) => (stats.byCategory.get(c) ?? 0) < goal.categoryFloor);
    let queuedExplicitly = 0;
    let passLimit = RUN_CANDIDATE_TARGET;
    if (requestedVideoIds.length > 0) {
      const seeded = await enqueueExplicitVideos(supabase, language, requestedVideoIds);
      if (!seeded.ok) return jsonResponse(summary(published, seeded.reason, cronReady, queuedExplicitly));
      queuedExplicitly = seeded.count;
      log("catalog_explicit_candidates_queued", { count: queuedExplicitly });
    }
    if (!growth) {
      const freshLeft = goal.freshPerDay - stats.last24h;
      if (freshLeft <= 0) return jsonResponse(summary(published, "target-reached", cronReady, queuedExplicitly));
      // One candidate per pass spreads the daily trickle across the day.
      passLimit = 1;
    }

    // Fill the queue with search results first (quota is spent here, once per candidate),
    // then spend the rest of the pass publishing from it. A quota wall during the search
    // phase must not stop the pass: queued candidates still publish quota-free.
    const queued = await queueCount(supabase, language);
    const queueTarget = growth ? QUEUE_TARGET : 3;
    if (queued < queueTarget) {
      if (await youtubeQuotaUsedToday(supabase) >= SEARCH_QUOTA_CEILING) {
        stopped = "search-quota-reserve";
      } else {
        const fill = await enqueueFreshCandidates(supabase, language, started, queueTarget - queued, stats);
        if (fill.stopped) stopped = fill.stopped;
      }
    }

    const queue = await takeQueue(supabase, language, language === "ja" ? passLimit * 5 : passLimit, stats, goal.categoryFloor);
    let processed = 0;
    for (const candidate of queue) {
      if (Date.now() - started >= RUN_BUDGET_MS || processed >= passLimit) break;
      let lease: string | null = null;
      if (language === "ja") {
        const claim = await supabase.rpc("claim_catalog_candidate", {
          p_video_id: candidate.videoId, p_window_start_sec: candidate.windowStartSec,
        });
        if (claim.error || typeof claim.data !== "string") continue;
        lease = claim.data;
      }
      processed += 1;
      try {
        const result = await analyzeAndPublish(supabase, candidate, language);
        if (!result.ok) {
          const keep = failureStatus(result.reason, result.detail ?? "") !== "rejected";
          if (!keep) await removeQueued(supabase, language, candidate.videoId, candidate.windowStartSec);
          else {
            // Rotate transient failures behind other candidates instead of repeatedly
            // charging for the same empty response while ready sources wait.
            const retryAt = new Date(Date.now() + 20 * 60_000).toISOString();
            await supabase.from(queueTable(language)).update(language === "ja"
              ? { next_attempt_at: retryAt } : { added_at: new Date().toISOString() })
              .eq("video_id", candidate.videoId).eq("window_start_sec", candidate.windowStartSec);
          }
          if (result.reason === "gemini-cap") {
            stopped = "gemini-cap";
            return jsonResponse(summary(published, stopped, cronReady, queuedExplicitly));
          }
          if (result.reason === "model_payment" || result.reason.includes("402")) {
            await pauseFill(supabase, "gemini-payment");
            stopped = "model-payment";
            return jsonResponse(summary(published, stopped, cronReady, queuedExplicitly));
          }
          continue;
        }
        await removeQueued(supabase, language, candidate.videoId, candidate.windowStartSec);
        published.push({
          id: result.id,
          videoId: candidate.videoId,
          difficulty: result.difficulty,
          category: result.category,
        });
      } finally {
        if (lease) await supabase.rpc("release_catalog_candidate", {
          p_video_id: candidate.videoId, p_window_start_sec: candidate.windowStartSec, p_lease_token: lease,
        });
      }
    }
    if (published.length === 0 && stopped === "time-budget" && queue.length === 0) {
      stopped = "no-candidate";
    }

    return jsonResponse(summary(published, stopped, cronReady, queuedExplicitly));
  } catch (err) {
    const message = err instanceof Error ? err.message : "";
    log("catalog_fill_error", { message: message.slice(0, 200) });
    if (message.startsWith("Missing required env")) return errorResponse(500, "Server misconfigured");
    return errorResponse(500, "Catalog fill failed");
  }
});

const RUN_BUDGET_MS = 110_000;
/** One analysis fits the 150-second pg_net deadline, even at the 120-second model timeout. */
const RUN_CANDIDATE_TARGET = 1;
/** A bad-yield lane must not dump the day's search quota into one pass. */
const MAX_SEARCHES_PER_PASS = 3;
const MAX_SOURCE_DURATION_SEC = 240;
const SOURCE_WINDOW_SEC = 90;
const MAX_WINDOWS_PER_VIDEO = 20;
/** Keep at least this many unprocessed candidates queued for the language. */
const QUEUE_TARGET = 15;
const QUERY_VARIANTS: Record<CatalogLanguage, string[]> = {
  ja: ["", "日常会話", "2024", "2025"],
  ko: ["", "일상회화", "2024", "2025"],
};

// MARK: - Candidate queue

type QueuedCandidate = {
  videoId: string;
  windowStartSec: number;
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
  if (language === "ja") {
    // Older searches admitted long sources; clear those pending windows so they
    // cannot crowd out quick lessons or keep the queue above its refill target.
    await supabase.from(queueTable(language)).delete().gt("duration_sec", MAX_SOURCE_DURATION_SEC);
  }
}

type CatalogStats = { total: number; last24h: number; byCategory: Map<string, number>; byCell: Map<string, number> };

async function catalogStats(
  supabase: ReturnType<typeof serviceClient>,
  language: CatalogLanguage,
): Promise<CatalogStats> {
  const rows: Array<{ category: string; difficulty: string; created_at?: string }> = [];
  for (let offset = 0; offset < 10_000; offset += 500) {
    const { data, error } = await supabase.from(catalogTable(language))
      .select("id, category, difficulty, created_at")
      .eq("published", true).order("id", { ascending: true })
      .range(offset, offset + 499);
    if (error) throw new Error(`catalog-stats: ${error.message}`);
    rows.push(...((data ?? []) as Array<{ category: string; difficulty: string; created_at?: string }>));
    if ((data ?? []).length < 500) break;
  }
  const dayAgo = Date.now() - 24 * 60 * 60 * 1000;
  const stats: CatalogStats = { total: 0, last24h: 0, byCategory: new Map(), byCell: new Map() };
  for (const row of rows) {
    stats.total++;
    if (row.created_at && Date.parse(row.created_at) >= dayAgo) stats.last24h++;
    stats.byCategory.set(row.category, (stats.byCategory.get(row.category) ?? 0) + 1);
    const cell = `${row.category}|${row.difficulty}`;
    stats.byCell.set(cell, (stats.byCell.get(cell) ?? 0) + 1);
    const level = `level|${row.difficulty}`;
    stats.byCell.set(level, (stats.byCell.get(level) ?? 0) + 1);
  }
  return stats;
}

async function youtubeQuotaUsedToday(supabase: ReturnType<typeof serviceClient>): Promise<number> {
  const { data } = await supabase
    .from("youtube_quota_usage")
    .select("units")
    .eq("day_utc", new Date().toISOString().slice(0, 10))
    .maybeSingle();
  return Number((data as { units?: number } | null)?.units ?? 0);
}

/**
 * Pulls candidates for the most underfilled categories first (oldest first within a
 * category), so a queue full of one lane can't starve kids/variety/gaming.
 */
async function takeQueue(
  supabase: ReturnType<typeof serviceClient>,
  language: CatalogLanguage,
  limit: number,
  stats: CatalogStats,
  categoryFloor: number,
): Promise<QueuedCandidate[]> {
  let ready = supabase.from(queueTable(language))
    .select("video_id, window_start_sec, title, channel_title, duration_sec, category, difficulty, added_at")
    .order("added_at", { ascending: true }).limit(500);
  if (language === "ja") ready = ready.lte("next_attempt_at", new Date().toISOString());
  const { data } = await ready;
  const rows = ((data ?? []) as Array<Record<string, unknown>>).slice();
  const fill = (category: string) => (stats.byCategory.get(category) ?? 0) / Math.max(1, categoryFloor);
  // Round-robin across categories ordered by fill ratio, so one pass mixes categories.
  const buckets = new Map<string, Array<Record<string, unknown>>>();
  for (const row of rows) {
    const category = String(row.category ?? "interview");
    if (!buckets.has(category)) buckets.set(category, []);
    buckets.get(category)!.push(row);
  }
  // Favor short, complete lessons within each category. Older long sources must
  // not hide newer 20–120 second candidates behind the queue's page limit.
  const lessonRank = (row: Record<string, unknown>) => {
    const duration = Number(row.duration_sec ?? 0);
    const durationRank = duration >= 20 && duration <= 120 ? 0 : duration < 20 ? 1 : 2;
    if (language !== "ja" || String(row.category) !== "learning") return durationRank * 3;
    const title = String(row.title ?? "");
    // Listening and conversation uploads are more likely to contain full Japanese
    // exchanges than isolated word-pronunciation or vocabulary Shorts.
    const dialogueRank = /会話|対話|conversation|dialogue|listening/i.test(title) ? 0
      : /pronunciation|pitch accent|vocabulary|how to say|単語|発音/i.test(title) ? 2 : 1;
    return durationRank * 3 + dialogueRank;
  };
  for (const bucket of buckets.values()) bucket.sort((a, b) => lessonRank(a) - lessonRank(b));
  const order = [...buckets.keys()].sort((a, b) => fill(a) - fill(b));
  const picked: Array<Record<string, unknown>> = [];
  while (picked.length < limit && order.some((c) => (buckets.get(c)?.length ?? 0) > 0)) {
    for (const category of order) {
      const next = buckets.get(category)?.shift();
      if (next) picked.push(next);
      if (picked.length >= limit) break;
    }
  }
  return picked.map((row) => ({
    videoId: String(row.video_id),
    windowStartSec: Number(row.window_start_sec ?? 0),
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
  windowStartSec: number,
): Promise<void> {
  await supabase.from(queueTable(language)).delete()
    .eq("video_id", videoId).eq("window_start_sec", windowStartSec);
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
  stats: CatalogStats,
): Promise<{ stopped: string | null }> {
  const rankedLanes = lanesByEmptiness(language, stats);
  const sourceLanes = rankedLanes.filter((lane) => !!lane.channelId || !!lane.channelHandle);
  const sourceIndex = sourceLanes.length > 0
    ? Math.floor(Date.now() / (10 * 60 * 1000)) % sourceLanes.length
    : -1;
  const featuredSource = sourceIndex >= 0 ? sourceLanes[sourceIndex] : undefined;
  // Rotate configured source channels to the front on each cron interval, while the
  // remaining slots continue to favor whichever catalog categories are underfilled.
  const lanes = featuredSource
    ? [featuredSource, ...rankedLanes.filter((lane) => lane !== featuredSource)]
    : rankedLanes;
  let queuedNew = 0;
  let searches = 0;
  for (const lane of lanes) {
    if (queuedNew >= target || searches >= MAX_SEARCHES_PER_PASS || Date.now() - started >= RUN_BUDGET_MS) break;
    const laneKey = `${language}|${lane.category}|${lane.difficulty}${lane.tag ? `|${lane.tag}` : ""}`;
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
    const rows = found.videos.slice(0, 3).flatMap((video) => candidateWindows(video.durationSec).map((windowStartSec) => ({
      video_id: video.videoId,
      window_start_sec: windowStartSec,
      title: video.title.slice(0, 140),
      channel_title: video.channelTitle.slice(0, 80),
      duration_sec: video.durationSec,
      category: lane.category,
      difficulty: lane.difficulty,
      added_at: new Date().toISOString(),
    })));
    const { error, count } = await supabase
      .from(queueTable(language))
      .upsert(rows, { onConflict: "video_id,window_start_sec", count: "exact", ignoreDuplicates: true });
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
  queuedCandidates = 0,
) {
  return {
    published: published.length > 0,
    count: published.length,
    queuedCandidates,
    stopped,
    cronReady,
    clips: published,
  };
}

/** Emptiest category first, then the scarcest level, then the emptiest cell. */
function lanesByEmptiness(language: CatalogLanguage, stats: CatalogStats): Lane[] {
  const floor = CATALOG_GOALS[language].categoryFloor;
  const rank = (lane: Lane) => {
    const categoryFill = Math.min(1, (stats.byCategory.get(lane.category) ?? 0) / floor);
    const level = stats.byCell.get(`level|${lane.difficulty}`) ?? 0;
    const cell = stats.byCell.get(`${lane.category}|${lane.difficulty}`) ?? 0;
    return categoryFill * 1_000_000 + level * 100 + cell;
  };
  return [...lanesFor(language)].sort((a, b) => rank(a) - rank(b));
}

type FreshVideo = { videoId: string; title: string; channelTitle: string; durationSec: number };

function candidateWindows(durationSec: number): number[] {
  if (durationSec <= 120) return [0];
  const starts: number[] = [];
  for (let start = 0; start + 8 <= durationSec && starts.length < MAX_WINDOWS_PER_VIDEO; start += SOURCE_WINDOW_SEC) {
    starts.push(start);
  }
  return starts;
}

async function enqueueExplicitVideos(
  supabase: ReturnType<typeof serviceClient>,
  language: CatalogLanguage,
  videoIds: string[],
  skipRejected = false,
  category = "anime",
): Promise<{ ok: true; count: number } | { ok: false; reason: string }> {
  if (!(await tryConsumeYoutubeQuota(supabase, 1))) {
    return { ok: false, reason: "youtube-quota" };
  }
  const params = new URLSearchParams({
    part: "snippet,status,contentDetails",
    id: videoIds.join(","),
    key: requireEnv("YOUTUBE_API_KEY"),
  });
  const response = await fetch(`https://www.googleapis.com/youtube/v3/videos?${params}`);
  if (!response.ok) return { ok: false, reason: "youtube-videos-failed" };
  const json = await response.json() as { items?: VideoItem[] };
  const ids = (json.items ?? []).map((item) => item.id).filter((id): id is string => !!id);
  if (ids.length === 0) return { ok: true, count: 0 };

  const { data: catalogRows } = await supabase
    .from(catalogTable(language))
    .select("video_id")
    .in("video_id", ids);
  const knownIds = new Set((catalogRows ?? []).map((row: { video_id: string }) => row.video_id));
  if (skipRejected) {
    const { data: rejected } = await supabase.from("catalog_rejections")
      .select("video_id").in("video_id", ids);
    for (const row of rejected ?? []) knownIds.add((row as { video_id: string }).video_id);
  }
  const now = new Date().toISOString();
  const rows = (json.items ?? []).flatMap((item) => {
    const id = item.id;
    const durationSec = parseDurationSec(item.contentDetails?.duration ?? "");
    if (!id || knownIds.has(id) || item.status?.embeddable !== true || item.status?.privacyStatus !== "public") return [];
    if (durationSec === null || durationSec < 8 || durationSec > MAX_SOURCE_DURATION_SEC) return [];
    return candidateWindows(durationSec).map((windowStartSec) => ({
      video_id: id,
      window_start_sec: windowStartSec,
      title: item.snippet?.title?.trim().slice(0, 140) || `Clip ${id}`,
      channel_title: item.snippet?.channelTitle?.trim().slice(0, 80) || "Unknown",
      duration_sec: durationSec,
      category,
      difficulty: "Intermediate",
      added_at: now,
    }));
  });
  if (rows.length === 0) return { ok: true, count: 0 };
  const { error, count } = await supabase
    .from(queueTable(language))
    .upsert(rows, { onConflict: "video_id,window_start_sec", count: "exact", ignoreDuplicates: true });
  if (error) {
    log("candidate_queue_upsert_failed", { detail: error.message.slice(0, 120) });
    return { ok: false, reason: "candidate-queue-failed" };
  }
  return { ok: true, count: count ?? rows.length };
}

async function searchFresh(
  supabase: ReturnType<typeof serviceClient>,
  lane: Lane,
  language: CatalogLanguage,
  laneKey: string,
): Promise<
  | { ok: true; videos: FreshVideo[]; nextPageToken: string | null }
  | { ok: false; reason: string }
> {
  const ytKey = requireEnv("YOUTUBE_API_KEY");
  let channelId = lane.channelId;
  if (!channelId && lane.channelHandle) {
    if (!(await tryConsumeYoutubeQuota(supabase, 1))) {
      return { ok: false, reason: "youtube-quota" };
    }
    const channelParams = new URLSearchParams({
      part: "id",
      forHandle: lane.channelHandle,
      key: ytKey,
    });
    const channelRes = await fetch(`https://www.googleapis.com/youtube/v3/channels?${channelParams}`);
    if (!channelRes.ok) return { ok: false, reason: "youtube-channel-lookup-failed" };
    const channelJson = await channelRes.json() as { items?: ChannelItem[] };
    channelId = channelJson.items?.[0]?.id;
    if (!channelId) return { ok: false, reason: "youtube-channel-not-found" };
  }

  if (!(await tryConsumeYoutubeQuota(supabase, 100))) {
    return { ok: false, reason: "youtube-quota" };
  }
  const cursor = await loadCursor(supabase, laneKey);
  const variants = QUERY_VARIANTS[language];
  const variant = variants[cursor.variant % variants.length] ?? "";
  const query = `${lane.query} ${variant}`.trim();
  const searchParams = new URLSearchParams({
    part: "snippet",
    type: "video",
    maxResults: "25",
    videoEmbeddable: "true",
    // Channel uploads favor clips under four minutes. One-hour sources require a
    // separate cost-bounded extraction path and must not crowd out ready lessons.
    videoDuration: "short",
    order: "date",
    relevanceLanguage: language,
    regionCode: language === "ko" ? "KR" : "JP",
    key: ytKey,
  });
  if (query) searchParams.set("q", query);
  if (channelId) searchParams.set("channelId", channelId);
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
    // Short sources may become complete lessons; longer channel uploads are
    // processed as bounded 90-second windows with one checked excerpt per window.
    if (durationSec === null || durationSec < 8 || durationSec > MAX_SOURCE_DURATION_SEC) continue;
    videos.push({
      videoId,
      title: item.snippet?.title?.trim() || `Clip ${videoId}`,
      channelTitle: item.snippet?.channelTitle?.trim() || "Unknown",
      durationSec,
    });
  }
  // The API returns newest first; within that page prioritize sources that can
  // become complete 20–120 second lessons before longer excerpt candidates.
  videos.sort((a, b) => {
    const score = (seconds: number) => seconds >= 20 && seconds <= 120 ? 0 : seconds < 20 ? 1 : 2;
    return score(a.durationSec) - score(b.durationSec);
  });
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
  supabase: ReturnType<typeof serviceClient>, candidate: QueuedCandidate, language: CatalogLanguage,
): Promise<{ ok: true; id: string; difficulty: string; category: string } | { ok: false; reason: string; detail?: string }> {
  if (language !== "ja") return processCandidate(supabase, candidate, language);
  const attempt = await startPipeline(supabase, { video_id: candidate.videoId, window_start_sec: candidate.windowStartSec, title: candidate.title, channel_name: candidate.channelTitle, source: "automatic" });
  try {
    // Queued metadata can age. Recheck the actual source on every publication attempt.
    const video = await checkYouTubeVideo(supabase, candidate.videoId);
    if (!video.ok || video.video.durationSec > MAX_SOURCE_DURATION_SEC) {
      const reason = video.ok ? "source_over_4_minutes" : video.code;
      await updatePipeline(supabase, attempt, { status: failureStatus(reason), stage: "source_check", reason, detail: video.ok ? "Source exceeds four-minute publisher policy" : video.detail });
      return { ok: false, reason };
    }
    const result = await processCandidate(supabase, { ...candidate, durationSec: video.video.durationSec }, language, attempt);
    await updatePipeline(supabase, attempt, result.ok
      ? { status: "published", stage: "published", clip_id: result.id }
      : { status: failureStatus(result.reason, result.detail ?? ""), stage: "quality_gate", reason: result.reason, detail: result.detail ?? "" });
    return result;
  } catch (error) {
    const detail = error instanceof Error ? error.message : "Pipeline failed";
    await updatePipeline(supabase, attempt, { status: "failed", stage: "error", reason: "pipeline_error", detail: detail.slice(0, 300) });
    return { ok: false, reason: "pipeline_error" };
  }
}

async function processCandidate(
  supabase: ReturnType<typeof serviceClient>,
  candidate: QueuedCandidate,
  language: CatalogLanguage,
  attemptId?: string,
): Promise<{ ok: true; id: string; difficulty: string; category: string } | { ok: false; reason: string; detail?: string }> {
  const outcome = await analyzeWindow(supabase, {
    onStage: attemptId ? (stage) => updatePipeline(supabase, attemptId, { stage }) : undefined,
    videoId: candidate.videoId,
    windowStart: candidate.windowStartSec,
    // Inspect the entire source when it is at most two minutes. Longer sources keep
    // a bounded search window and yield short feed excerpts.
    // An unknown stored duration (0) must not collapse the window to nothing — fall back
    // to the default 90s window and let the model see the real video (2026-10-30 fix:
    // scraped candidates without a parsed length all failed with "bad window").
    windowEnd: candidate.durationSec > 0
      ? Math.min(candidate.durationSec, candidate.windowStartSec + (candidate.durationSec <= 120 ? 120 : SOURCE_WINDOW_SEC))
      : candidate.windowStartSec + SOURCE_WINDOW_SEC,
    sourceDurationSec: candidate.durationSec,
    language,
    askCategory: language === "ja",
    minSpokenSec: 6,
  });
  if (!outcome.ok) {
    log("catalog_candidate_rejected", {
      videoId: candidate.videoId,
      windowStartSec: candidate.windowStartSec,
      reason: outcome.reason,
      detail: outcome.detail,
    });
    // Persist for diagnosis — edge_logs is not always reachable (2026-10-30 incident).
    await supabase.from("catalog_rejections").insert({
      video_id: candidate.videoId,
      reason: outcome.reason,
      detail: (outcome.detail ?? "").slice(0, 300),
    });
    if (outcome.reason === "gemini_cap") return { ok: false, reason: "gemini-cap" };
    if (outcome.reason === "model_payment") return { ok: false, reason: "Gemini HTTP 402" };
    return { ok: false, reason: outcome.reason, detail: outcome.detail };
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
    category: outcome.draft.category ?? candidate.category,
    published: true,
    withProvenance: language === "ja",
  });
  const { error } = await supabase.from(catalogTable(language)).upsert(row);
  if (error) return { ok: false, reason: "insert-failed" };
  log("catalog_clip_published", { id, timingMode: outcome.draft.timingMode, model: outcome.draft.model });
  return { ok: true, id, difficulty: outcome.draft.difficulty, category: outcome.draft.category ?? candidate.category };
}

function parseDurationSec(iso: string): number | null {
  const match = iso.match(/^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$/);
  if (!match) return null;
  return Number(match[1] ?? 0) * 3600 + Number(match[2] ?? 0) * 60 + Number(match[3] ?? 0);
}
