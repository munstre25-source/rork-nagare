/**
 * Shared YouTube → timed lesson pipeline.
 *
 * 1. YouTube Data API decides whether a video may be played in the app (public/unlisted,
 *    embeddable, not live). We never download media; Gemini reads the public YouTube URL.
 * 2. Gemini hears one window of the video and returns lines with word timestamps.
 * 3. Lines are validated strictly; word timings are checked per line and fall back to
 *    sentence-level highlighting when implausible (see timing.ts).
 * 4. Dictionary fields are added to the heard words.
 *
 * Used by fill-catalog (published catalog clips) and immersion-worker (learner requests).
 */
import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { CatalogLanguage, languageName } from "./catalog.ts";
import { hearSystemCatalog } from "./enrich.ts";
import { normalizeHeardLines, subtitleEnrichmentIssue } from "./subtitle-data.ts";
import { sealCatalogLines } from "./pipeline.ts";
import { reviewJapaneseTranslations } from "./translation-review.ts";
import { geminiModelAnalyze, geminiModelTranslationReview, subtitlePromptVersion, requireEnv } from "./env.ts";
import { GeminiError, geminiAnalyzeYouTubeSegment, parseJsonObject } from "./gemini.ts";
import { tryConsumeYoutubeQuota, tryIncrementGeminiUsage } from "./limits.ts";
import { assessTiming, ClipTimingMode, TimedLine, toClipRelative, validateLineTimeline } from "./timing.ts";
import { CATEGORIES, validateEnums } from "./validate.ts";

export const GRADIENTS = [
  ["#0B1030", "#2B2F7A", "#F29E4C"],
  ["#10261A", "#2E7D4F", "#F6E27F"],
  ["#2B1405", "#9C3D10", "#F2B134"],
];

export function log(event: string, fields: Record<string, unknown> = {}): void {
  console.log(JSON.stringify({ event, at: new Date().toISOString(), ...fields }));
}

// MARK: - YouTube

export type VideoFacts = {
  videoId: string;
  title: string;
  channelTitle: string;
  channelId?: string;
  durationSec: number;
};

export type VideoCheck =
  | { ok: true; video: VideoFacts }
  | {
    ok: false;
    code:
      | "video_not_found"
      | "private_video"
      | "not_embeddable"
      | "live_stream"
      | "too_short"
      | "quota_exhausted"
      | "youtube_unavailable";
    detail: string;
  };

export function parseIsoDurationSec(iso: string): number | null {
  const match = iso.match(/^P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$/);
  if (!match || iso === "P" || iso === "PT") return null;
  return Number(match[1] ?? 0) * 86400 + Number(match[2] ?? 0) * 3600 + Number(match[3] ?? 0) * 60 +
    Number(match[4] ?? 0);
}

type VideoItem = {
  id?: string;
  status?: { embeddable?: boolean; privacyStatus?: string; uploadStatus?: string };
  contentDetails?: { duration?: string };
  snippet?: { title?: string; channelTitle?: string; channelId?: string; liveBroadcastContent?: string };
};

/** One videos.list call (1 quota unit). Decides whether this video may be used at all. */
/**
 * True when real phones reported this video can't play in the app (rights-holder embed
 * blocks the Data API can't see). Same evidence rule as report_clip_playback_failure().
 */
export async function isDeviceBlocked(supabase: SupabaseClient, videoId: string): Promise<boolean> {
  const { data } = await supabase
    .from("clip_playback_failures")
    .select("error_code")
    .eq("environment", "production")
    .eq("video_id", videoId)
    .limit(10);
  const rows = (data ?? []) as Array<{ error_code: number }>;
  return rows.some((r) => [100, 101, 150].includes(r.error_code)) || rows.length >= 2;
}

/**
 * The real player frame shape. oEmbed asked about the /shorts/ URL answers with the Short's
 * own portrait size (e.g. 113x200) and a 16:9 size for normal uploads. null when unknown,
 * so the caller can fall back to the model's guess.
 */
export async function detectVideoOrientation(videoId: string): Promise<"portrait" | "landscape" | null> {
  try {
    const url = `https://www.youtube.com/oembed?format=json&url=${
      encodeURIComponent(`https://www.youtube.com/shorts/${videoId}`)
    }`;
    const res = await fetch(url, { signal: AbortSignal.timeout(6000) });
    if (!res.ok) return null;
    const body = await res.json() as { width?: number; height?: number };
    if (typeof body.width !== "number" || typeof body.height !== "number") return null;
    return body.height > body.width ? "portrait" : "landscape";
  } catch {
    return null;
  }
}

/**
 * Quota-free embed gate. YouTube's Data API can say `embeddable: true` while the watch
 * oEmbed answers 401 (owner disabled embedding) — those videos error 150/101 in every app
 * player (2026-10-30: ZXeSXMqsSBQ). 401/403/404 = blocked; anything else = unknown.
 */
export async function oembedBlocked(videoId: string): Promise<boolean | null> {
  try {
    const url = `https://www.youtube.com/oembed?format=json&url=${
      encodeURIComponent(`https://www.youtube.com/watch?v=${videoId}`)
    }`;
    const res = await fetch(url, { signal: AbortSignal.timeout(6000) });
    await res.body?.cancel();
    if (res.ok) return false;
    if ([401, 403, 404].includes(res.status)) return true;
    return null;
  } catch {
    return null;
  }
}

export async function checkYouTubeVideo(supabase: SupabaseClient, videoId: string): Promise<VideoCheck> {
  if (await isDeviceBlocked(supabase, videoId)) {
    return { ok: false, code: "not_embeddable", detail: "device playback reports" };
  }
  if (await oembedBlocked(videoId) === true) {
    return { ok: false, code: "not_embeddable", detail: "oembed refused" };
  }
  if (!(await tryConsumeYoutubeQuota(supabase, 1))) {
    return { ok: false, code: "quota_exhausted", detail: "youtube daily cap" };
  }
  const params = new URLSearchParams({
    part: "snippet,status,contentDetails",
    id: videoId,
    key: requireEnv("YOUTUBE_API_KEY"),
  });
  let res: Response;
  try {
    res = await fetch(`https://www.googleapis.com/youtube/v3/videos?${params}`, {
      signal: AbortSignal.timeout(10_000),
    });
  } catch (err) {
    return { ok: false, code: "youtube_unavailable", detail: err instanceof Error ? err.message : "fetch failed" };
  }
  if (res.status === 403) {
    const body = await res.text();
    if (/quota/i.test(body)) return { ok: false, code: "quota_exhausted", detail: "youtube 403 quota" };
    return { ok: false, code: "youtube_unavailable", detail: `youtube 403 ${body.slice(0, 120)}` };
  }
  if (!res.ok) return { ok: false, code: "youtube_unavailable", detail: `youtube HTTP ${res.status}` };
  const json = await res.json() as { items?: VideoItem[] };
  const item = json.items?.[0];
  if (!item?.id) return { ok: false, code: "video_not_found", detail: "no item" };
  const live = item.snippet?.liveBroadcastContent;
  if (live === "live" || live === "upcoming") return { ok: false, code: "live_stream", detail: live };
  const privacy = item.status?.privacyStatus;
  if (privacy !== "public" && privacy !== "unlisted") {
    return { ok: false, code: "private_video", detail: privacy ?? "unknown" };
  }
  if (item.status?.uploadStatus && item.status.uploadStatus !== "processed") {
    return { ok: false, code: "video_not_found", detail: `upload ${item.status.uploadStatus}` };
  }
  if (item.status?.embeddable !== true) return { ok: false, code: "not_embeddable", detail: "embeddable=false" };
  const durationSec = parseIsoDurationSec(item.contentDetails?.duration ?? "");
  if (durationSec === null || durationSec === 0) return { ok: false, code: "live_stream", detail: "no duration" };
  if (durationSec < 8) return { ok: false, code: "too_short", detail: `${durationSec}s` };
  if (item.snippet?.channelId) {
    const { error } = await supabase.from("catalog_video_sources").upsert({ video_id: item.id, channel_id: item.snippet.channelId, channel_title: item.snippet.channelTitle ?? "", checked_at: new Date().toISOString() });
    if (error) return { ok: false, code: "youtube_unavailable", detail: "Source metadata could not be recorded" };
  }
  return {
    ok: true,
    video: {
      videoId: item.id, channelId: item.snippet?.channelId,
      title: item.snippet?.title?.trim() || `Video ${item.id}`,
      channelTitle: item.snippet?.channelTitle?.trim() || "YouTube",
      durationSec,
    },
  };
}

// MARK: - Analysis

export type ClipDraft = {
  clipStart: number;
  clipEnd: number;
  /** Clip-relative lines with per-line `timing`. */
  lines: TimedLine[];
  difficulty: string;
  category: string | null;
  videoOrientation: "portrait" | "landscape";
  timingMode: ClipTimingMode;
  timingConfidence: number;
  model: string;
  promptVersion: string;
};

export type AnalyzeFailure =
  | "no_dialogue"
  | "transcript_invalid"
  | "translation_unverified"
  | "gemini_cap"
  | "model_payment"
  | "model_rejected"
  | "model_retryable"
  | "enrichment_failed";

export type AnalyzeOutcome =
  | { ok: true; draft: ClipDraft }
  | { ok: false; reason: AnalyzeFailure; detail: string };

export type AnalyzeStage = "transcribing" | "validating" | "enriching";

const MIN_CLIP = 8;
const MAX_SHORT_CLIP = 40;
const MAX_WHOLE_LESSON = 120;

/** Short source videos can be complete lessons; longer sources stay quick feed excerpts. */
export function maxLessonDuration(sourceDurationSec: number): number {
  return sourceDurationSec >= MIN_CLIP && sourceDurationSec <= MAX_WHOLE_LESSON
    ? MAX_WHOLE_LESSON
    : MAX_SHORT_CLIP;
}

/**
 * Hears one window of a YouTube video and returns a validated, enriched, clip-relative lesson.
 * Never invents timing: lines without trustworthy word timings are marked `timing: "line"`.
 */
export async function analyzeWindow(
  supabase: SupabaseClient,
  opts: {
    videoId: string;
    windowStart: number;
    windowEnd: number;
    sourceDurationSec: number;
    language: CatalogLanguage;
    /** Learner videos also need a category; catalog lanes already have one. */
    askCategory: boolean;
    /** Minimum seconds of speech between the first and last line. */
    minSpokenSec: number;
    onStage?: (stage: AnalyzeStage) => Promise<void>;
  },
): Promise<AnalyzeOutcome> {
  const { videoId, windowStart, windowEnd, language } = opts;
  const maxClipSec = maxLessonDuration(opts.sourceDurationSec);
  const preferWholeVideo = maxClipSec === MAX_WHOLE_LESSON;
  if (!(await tryIncrementGeminiUsage(supabase))) return { ok: false, reason: "gemini_cap", detail: "daily cap" };
  await opts.onStage?.("transcribing");

  const categoryAsk = opts.askCategory
    ? ` Also include "category": one of ${[...CATEGORIES].map((c) => `"${c}"`).join(", ")} that best fits the video.`
    : "";
  let text = "";
  let model = geminiModelAnalyze();
  try {
    const result = await geminiAnalyzeYouTubeSegment({
      model,
      system: hearSystemCatalog(language, maxClipSec, preferWholeVideo),
      user:
        `Inspect the source window [${windowStart}, ${windowEnd}] seconds and select exactly one coherent, self-contained ${
          languageName(language)
        } exchange lasting ${MIN_CLIP}–${maxClipSec} seconds. Return absolute source-video timestamps (seconds from the start of the whole video) for clip_start_sec, clip_end_sec, every line, and every token. Token start/end must be when that word is actually heard; if you cannot hear a word's boundaries, still give your best estimate within its line. Include only dialogue inside the chosen boundaries. If there is no clearly audible ${
          languageName(language)
        } speech, return {"lines":[]}. Also return "video_orientation" as "portrait" or "landscape" based on the source video's actual frame shape. Classify a portrait Short as portrait; classify any 16:9 upload as landscape even if it contains a vertical video with black side bars, since the YouTube player frame itself is landscape.${categoryAsk}`,
      youtubeUrl: `https://www.youtube.com/watch?v=${videoId}`,
      startSec: windowStart,
      endSec: windowEnd,
    });
    text = result.text;
    model = result.model;
  } catch (err) {
    return { ok: false, ...classifyModelError(err) };
  }

  await opts.onStage?.("validating");
  let raw: Record<string, unknown>;
  try {
    raw = parseJsonObject(text);
  } catch {
    return { ok: false, reason: "transcript_invalid", detail: "response is not a JSON object" };
  }
  if (!Array.isArray(raw.lines) || raw.lines.length === 0) {
    return { ok: false, reason: "no_dialogue", detail: "model returned no lines" };
  }

  const shifted = maybeShiftRelative(raw, windowStart, windowEnd);
  if (shifted) log("timestamps_shifted_to_absolute", { videoId, windowStart });

  const timeline = validateLineTimeline(raw.lines, windowStart, windowEnd, language);
  if (!timeline.ok) return { ok: false, reason: "transcript_invalid", detail: timeline.error };
  const lines = timeline.lines;

  const first = lines[0]!;
  const last = lines[lines.length - 1]!;
  let clipStart = finiteOr(raw.clip_start_sec, first.start - 0.3);
  let clipEnd = finiteOr(raw.clip_end_sec, last.end + 0.3);
  // The clip must contain every heard line; widen to them, then keep inside the window.
  clipStart = Math.max(windowStart, Math.min(clipStart, first.start - 0.2));
  clipEnd = Math.min(windowEnd, Math.max(clipEnd, last.end + 0.2));
  if (clipEnd - clipStart < MIN_CLIP) {
    // Short exchanges are padded with surrounding context instead of being dropped.
    const missing = MIN_CLIP - (clipEnd - clipStart);
    clipStart = Math.max(windowStart, clipStart - missing / 2);
    clipEnd = Math.min(windowEnd, clipStart + MIN_CLIP);
  }
  if (clipEnd - clipStart < MIN_CLIP - 0.5) {
    return { ok: false, reason: "no_dialogue", detail: "window too short for a clip" };
  }
  if (clipEnd - clipStart > maxClipSec + 0.01) {
    return { ok: false, reason: "transcript_invalid", detail: `clip exceeds ${maxClipSec}s limit` };
  }
  const spokenFirst = lines[0]!;
  const spokenLast = lines[lines.length - 1]!;
  if (lines.length < 2 || lines.length > (preferWholeVideo ? 80 : 24)) {
    return { ok: false, reason: lines.length < 2 ? "no_dialogue" : "transcript_invalid", detail: `${lines.length} lines` };
  }
  if (spokenLast.end - spokenFirst.start < opts.minSpokenSec) {
    return { ok: false, reason: "no_dialogue", detail: "too little speech" };
  }
  const clipDuration = clipEnd - clipStart;
  if (clipDuration > 60) {
    const spokenSeconds = lines.reduce((sum, line) => sum + (line.end - line.start), 0);
    if (spokenSeconds < clipDuration * 0.35) {
      return { ok: false, reason: "no_dialogue", detail: "too little speech for a long lesson" };
    }
  }

  const timing = assessTiming(lines);
  if (timing.problems.length > 0) {
    log("word_timing_fallback", { videoId, mode: timing.mode, problems: timing.problems.slice(0, 8) });
  }

  // Learner fields and concise Japanese meanings come from this single hearing pass.
  // Persist them once; clients only change presentation. Legacy lookup remains available.
  const normalized = normalizeHeardLines(timing.lines);
  if (language === "ja") {
    const issue = subtitleEnrichmentIssue(normalized);
    if (issue) return { ok: false, reason: "enrichment_failed", detail: issue };
  }
  const tappable = countTappable(normalized);
  if (tappable < 4) {
    return { ok: false, reason: "enrichment_failed", detail: `${tappable} tappable tokens` };
  }

  let storedLines = toClipRelative(normalized, clipStart);
  if (language === "ja") {
    try {
      const review = await reviewJapaneseTranslations({
        videoId,
        sourceStartSec: round3(clipStart),
        durationSec: round3(round3(clipEnd) - round3(clipStart)),
        lines: storedLines,
      }, {
        model: geminiModelTranslationReview(),
        consumeUsage: () => tryIncrementGeminiUsage(supabase),
      });
      if (!review.ok) {
        return {
          ok: false,
          reason: review.reason === "quota" ? "gemini_cap" : "translation_unverified",
          detail: review.detail,
        };
      }
      storedLines = await sealCatalogLines(supabase, { videoId, sourceStartSec: round3(clipStart), durationSec: round3(round3(clipEnd) - round3(clipStart)), lines: review.lines });
    } catch (err) {
      return { ok: false, ...classifyModelError(err) };
    }
  }

  return {
    ok: true,
    draft: {
      clipStart: round3(clipStart),
      clipEnd: round3(clipEnd),
      lines: storedLines,
      difficulty: gradeDifficulty(raw.difficulty, normalized, language),
      category: language === "ja"
        ? String((storedLines[0].translationReview as { contentClassification: { category: string } }).contentClassification.category)
        : typeof raw.category === "string" && CATEGORIES.has(raw.category) ? raw.category : null,
      videoOrientation: (await detectVideoOrientation(videoId)) ??
        (raw.video_orientation === "portrait" ? "portrait" : "landscape"),
      timingMode: timing.mode,
      timingConfidence: timing.confidence,
      model,
      promptVersion: subtitlePromptVersion(),
    },
  };
}

function classifyModelError(err: unknown): { reason: AnalyzeFailure; detail: string } {
  if (err instanceof GeminiError) {
    if (err.paymentRequired) return { reason: "model_payment", detail: err.message.slice(0, 160) };
    if (err.modelRejected) return { reason: "model_rejected", detail: err.message.slice(0, 160) };
    if (err.retryable) return { reason: "model_retryable", detail: err.message.slice(0, 160) };
    if (err.status === 400) return { reason: "transcript_invalid", detail: err.message.slice(0, 160) };
    return { reason: "model_retryable", detail: err.message.slice(0, 160) };
  }
  return { reason: "model_retryable", detail: err instanceof Error ? err.message.slice(0, 160) : "unknown" };
}

/**
 * Some transports answer with times relative to the clipped window instead of the whole video.
 * When every timestamp only fits the window after adding its start, shift them; returns true if shifted.
 */
export function maybeShiftRelative(raw: Record<string, unknown>, windowStart: number, windowEnd: number): boolean {
  if (windowStart < 5 || !Array.isArray(raw.lines)) return false;
  const lines = raw.lines as Array<Record<string, unknown>>;
  const starts = lines.map((l) => l.start).filter((n): n is number => typeof n === "number" && Number.isFinite(n));
  const ends = lines.map((l) => l.end).filter((n): n is number => typeof n === "number" && Number.isFinite(n));
  if (starts.length !== lines.length || ends.length !== lines.length) return false;
  const length = windowEnd - windowStart;
  const fitsAbsolute = Math.min(...starts) >= windowStart - 0.5;
  const fitsRelative = Math.min(...starts) >= 0 && Math.max(...ends) <= length + 0.5;
  if (fitsAbsolute || !fitsRelative) return false;
  const shift = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v + windowStart : v);
  for (const line of lines) {
    line.start = shift(line.start);
    line.end = shift(line.end);
    if (Array.isArray(line.tokens)) {
      for (const token of line.tokens as Array<Record<string, unknown>>) {
        token.start = shift(token.start);
        token.end = shift(token.end);
      }
    }
  }
  raw.clip_start_sec = shift(raw.clip_start_sec);
  raw.clip_end_sec = shift(raw.clip_end_sec);
  return true;
}

/** Tappable = a real word the learner can tap. Punctuation and fillers never are. */
function countTappable(lines: TimedLine[]): number {
  let count = 0;
  for (const line of lines) {
    for (const token of line.tokens) {
      if ((token as { tappable?: unknown }).tappable !== false) count += 1;
    }
  }
  return count;
}

function finiteOr(value: unknown, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function round3(n: number): number {
  return Math.round(n * 1000) / 1000;
}

export function gradeDifficulty(modelValue: unknown, lines: TimedLine[], language: CatalogLanguage): string {
  if (typeof modelValue === "string" && validateEnums("drama", modelValue).ok) return modelValue;
  const rank: Record<string, number> = language === "ko"
    ? { TOPIK1: 1, TOPIK2: 2, TOPIK3: 3, TOPIK4: 4, TOPIK5: 5, TOPIK6: 6 }
    : { N5: 1, N4: 2, N3: 3, N2: 4, N1: 5 };
  let score = 0;
  let counted = 0;
  for (const line of lines) {
    for (const token of line.tokens) {
      const label = (token as { jlpt?: unknown }).jlpt;
      if (typeof label === "string" && rank[label]) {
        score += rank[label];
        counted += 1;
      }
    }
  }
  if (counted === 0) return "Intermediate";
  const average = score / counted;
  if (language === "ko") return average < 2.5 ? "Beginner" : average < 4.5 ? "Intermediate" : "Advanced";
  return average < 2.2 ? "Beginner" : average < 3.4 ? "Intermediate" : "Advanced";
}

export function hashCode(value: string): number {
  let hash = 0;
  for (let i = 0; i < value.length; i++) hash = (Math.imul(31, hash) + value.charCodeAt(i)) | 0;
  return hash;
}

/** Row for `clips` / `sori_clips`. */
export function clipRow(opts: {
  id: string;
  video: VideoFacts;
  draft: ClipDraft;
  category: string;
  published: boolean;
  withProvenance: boolean;
}): Record<string, unknown> {
  const { id, video, draft } = opts;
  const row: Record<string, unknown> = {
    id,
    video_id: video.videoId,
    title: video.title.slice(0, 140),
    channel_name: video.channelTitle.slice(0, 80),
    category: opts.category,
    difficulty: draft.difficulty,
    source_start_sec: draft.clipStart,
    duration_sec: Math.round((draft.clipEnd - draft.clipStart) * 1000) / 1000,
    lines: draft.lines,
    published: opts.published,
    channel_avatar_color: "#FF6B00",
    thumbnail_gradient: GRADIENTS[Math.abs(hashCode(id)) % GRADIENTS.length],
    video_orientation: draft.videoOrientation,
  };
  if (opts.withProvenance) {
    row.timing_mode = draft.timingMode;
    row.model = draft.model;
    row.prompt_version = draft.promptVersion;
  }
  return row;
}

export function clipId(prefix: string, videoId: string, draft: ClipDraft): string {
  return `${prefix}-${videoId}-${Math.floor(draft.clipStart)}-${Math.floor(draft.clipEnd)}`;
}

// MARK: - URL parsing

const VIDEO_ID = /^[A-Za-z0-9_-]{11}$/;

/** Accepts watch, youtu.be, shorts, embed, live, music, and bare 11-character ids. */
export function parseYouTubeUrl(input: string): { videoId: string; startSec: number | null } | null {
  const trimmed = input.trim();
  if (VIDEO_ID.test(trimmed)) return { videoId: trimmed, startSec: null };
  let url: URL;
  try {
    url = new URL(/^https?:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`);
  } catch {
    return null;
  }
  const host = url.hostname.toLowerCase().replace(/^(www\.|m\.|music\.)/, "");
  let id: string | null = null;
  if (host === "youtu.be") {
    id = url.pathname.split("/")[1] ?? null;
  } else if (host === "youtube.com" || host === "youtube-nocookie.com") {
    const parts = url.pathname.split("/").filter(Boolean);
    if (parts[0] === "watch") id = url.searchParams.get("v");
    else if (["shorts", "embed", "live", "v", "e"].includes(parts[0] ?? "")) id = parts[1] ?? null;
  }
  if (!id || !VIDEO_ID.test(id)) return null;
  return { videoId: id, startSec: parseStart(url.searchParams.get("t") ?? url.searchParams.get("start")) };
}

function parseStart(value: string | null): number | null {
  if (!value) return null;
  if (/^\d+s?$/.test(value)) return Number.parseInt(value, 10);
  const match = value.match(/^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$/);
  if (!match || value === "") return null;
  const total = Number(match[1] ?? 0) * 3600 + Number(match[2] ?? 0) * 60 + Number(match[3] ?? 0);
  return total > 0 ? total : null;
}

// MARK: - Learner-facing error copy

export const ERROR_MESSAGES: Record<string, string> = {
  invalid_url: "That doesn't look like a YouTube video link.",
  video_not_found: "We couldn't find that video. It may have been removed.",
  private_video: "This video is private, so it can't be played in Jojo.",
  not_embeddable: "The owner doesn't allow this video to play inside other apps.",
  live_stream: "Live streams and premieres can't be turned into lessons yet. Try again after it ends.",
  too_short: "This video is under 8 seconds, which is too short for a lesson.",
  no_japanese_dialogue: "We couldn't find clear Japanese speech in this video.",
  transcript_invalid: "We couldn't build a reliable transcript for this video.",
  model_unavailable: "Transcription is temporarily unavailable. Please try again later.",
  model_timeout: "Transcription is taking longer than usual. We'll keep trying.",
  quota_exhausted: "Today's processing limit was reached. It will continue automatically.",
  internal: "Something went wrong while processing. Please try again.",
};
