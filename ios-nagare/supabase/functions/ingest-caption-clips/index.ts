/**
 * Admin-only ingest for caption-tier clips.
 *
 * Accepts clip JSON produced by Tools/build_caption_clips.py. Every import now
 * requires source-audio word alignment and independent verification before publication.
 * Requires x-admin-token == ADMIN_TOKEN. Clients never write to clips.
 */
import { corsPreflight, errorResponse, jsonResponse, readJson } from "../_shared/http.ts";
import { requireEnv } from "../_shared/env.ts";
import { requireAdmin } from "../_shared/admin.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { repairWordTiming } from "../_shared/word-timing.ts";
import { reviewJapaneseTranslations } from "../_shared/translation-review.ts";
import { geminiModelTranslationReview } from "../_shared/env.ts";
import { tryIncrementGeminiUsage } from "../_shared/limits.ts";
import { sealCatalogLines } from "../_shared/pipeline.ts";
import type { TimedLine } from "../_shared/timing.ts";

type CaptionLine = {
  tokens: unknown[];
  translation: string;
  start: number;
  end: number;
  timing?: string;
  translationReview?: Record<string, unknown>;
};

type CaptionClip = {
  id: string;
  video_id: string;
  title: string;
  channel_name: string;
  category: string;
  difficulty?: string;
  source_start_sec: number;
  duration_sec: number;
  lines: CaptionLine[];
  channel_avatar_color?: string;
  thumbnail_gradient?: string[];
  video_orientation?: string;
};

type Body = {
  action?: "state";
  clips?: CaptionClip[];
  publish?: boolean;
};

type CategoryDemand = {
  category: string;
  live_clips: number;
  views: number;
  demand_index: number;
  /** 1–4 slots in the daily round-robin; higher means publish more of this category. */
  priority: number;
};

/** Demand index = view share ÷ catalog share × 100. Cap slots so one category cannot monopolize a day. */
function demandPriority(demandIndex: number): number {
  if (demandIndex >= 180) return 4;
  if (demandIndex >= 130) return 3;
  if (demandIndex >= 80) return 2;
  return 1;
}

function categoryDemandFromPerformance(payload: unknown): CategoryDemand[] {
  const rows = (payload as { categories?: Array<Record<string, unknown>> } | null)?.categories ?? [];
  const catalog = rows.filter((r) => r.category !== "personal" && Number(r.live_clips ?? 0) > 0);
  const totalLive = catalog.reduce((n, r) => n + Number(r.live_clips ?? 0), 0);
  const totalViews = catalog.reduce((n, r) => n + Number(r.views ?? 0), 0);
  return catalog.map((r) => {
    const live = Number(r.live_clips ?? 0);
    const views = Number(r.views ?? 0);
    const catalogShare = totalLive ? live / totalLive : 0;
    const viewShare = totalViews ? views / totalViews : 0;
    const demandIndex = catalogShare > 0 && totalViews > 0 ? (viewShare / catalogShare) * 100 : 100;
    return {
      category: String(r.category),
      live_clips: live,
      views,
      demand_index: Math.round(demandIndex),
      priority: demandPriority(demandIndex),
    };
  }).sort((a, b) => b.demand_index - a.demand_index);
}

/** What the daily caption job needs: approved channels, captioned videos, and watch-demand priorities. */
async function pipelineState(supabase: ReturnType<typeof serviceClient>) {
  const end = new Date();
  const start = new Date(end.getTime() - 90 * 86_400_000);
  const [{ data: sources, error: sourceError }, { data: clips, error: clipError }, demandRpc] =
    await Promise.all([
      supabase.from("catalog_sources").select("channel_id, title").eq("caption_tier_ok", true),
      supabase.from("clips").select("video_id, channel_name, category, review_tier").limit(20000),
      // Include test/legacy until production watches dominate; otherwise demand stays empty.
      supabase.rpc("admin_category_performance", {
        p_start: start.toISOString(),
        p_end: end.toISOString(),
        p_include_test: true,
      }),
    ]);
  if (sourceError || clipError) throw new Error("state unavailable");
  const votes = new Map<string, Map<string, number>>();
  const captioned = new Set<string>();
  for (const clip of clips ?? []) {
    if (clip.review_tier === "caption") captioned.add(clip.video_id);
    const byCategory = votes.get(clip.channel_name) ?? new Map<string, number>();
    byCategory.set(clip.category, (byCategory.get(clip.category) ?? 0) + 1);
    votes.set(clip.channel_name, byCategory);
  }
  const categoryDemand = demandRpc.error ? [] : categoryDemandFromPerformance(demandRpc.data);
  const priorityByCategory = new Map(categoryDemand.map((d) => [d.category, d.priority]));
  const channels = (sources ?? []).filter((s) => s.channel_id).map((s) => {
    const ranked = [...(votes.get(s.title)?.entries() ?? [])].sort((a, b) => b[1] - a[1]);
    const category = ranked[0]?.[0] ?? "learning";
    return {
      channel_id: s.channel_id,
      title: s.title,
      category,
      demand_priority: priorityByCategory.get(category) ?? 2,
    };
  }).sort((a, b) => (b.demand_priority - a.demand_priority) || a.title.localeCompare(b.title));
  return {
    channels,
    captioned_video_ids: [...captioned],
    category_demand: categoryDemand,
  };
}

const CATEGORIES = new Set([
  "anime", "drama", "variety", "vtuber", "interview", "kids", "gaming", "learning", "podcast",
]);

function validateClip(clip: CaptionClip): string | null {
  if (!clip?.id || !clip.video_id || !clip.title || !clip.channel_name) {
    return "id, video_id, title, channel_name required";
  }
  if (!CATEGORIES.has(clip.category)) return `invalid category ${clip.category}`;
  if (!Number.isFinite(clip.source_start_sec) || clip.source_start_sec < 0) {
    return "source_start_sec invalid";
  }
  if (!Number.isFinite(clip.duration_sec) || clip.duration_sec < 6 || clip.duration_sec > 120) {
    return "duration_sec must be 6–120";
  }
  if (!Array.isArray(clip.lines) || clip.lines.length < 4) return "need at least 4 lines";
  let tappable = 0;
  for (const line of clip.lines) {
    if (!line || typeof line.translation !== "string" || !line.translation.trim()) {
      return "every line needs a non-empty translation";
    }
    if (!Array.isArray(line.tokens) || line.tokens.length === 0) return "line missing tokens";
    for (const token of line.tokens as Array<{ tappable?: boolean }>) {
      if (token?.tappable) tappable += 1;
    }
  }
  if (tappable < 4) return "need at least 4 tappable tokens";
  return null;
}

async function stampLines(
  supabase: ReturnType<typeof serviceClient>,
  clip: CaptionClip,
): Promise<CaptionLine[]> {
  const source = { videoId: clip.video_id, sourceStartSec: clip.source_start_sec,
    durationSec: clip.duration_sec, lines: clip.lines as TimedLine[] };
  const aligned = await repairWordTiming(source, { consumeUsage: () => tryIncrementGeminiUsage(supabase) });
  if (!aligned.ok) throw new Error("Word alignment required: " + aligned.detail);
  const reviewed = await reviewJapaneseTranslations({ ...source, lines: aligned.lines }, {
    model: geminiModelTranslationReview(), consumeUsage: () => tryIncrementGeminiUsage(supabase),
  });
  if (!reviewed.ok) throw new Error("Audio verification required: " + reviewed.detail);
  return await sealCatalogLines(supabase, { ...source, lines: reviewed.lines });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") return errorResponse(405, "Method not allowed");

  try {
    if (!requireAdmin(req, requireEnv("ADMIN_TOKEN"))) return errorResponse(401, "Unauthorized");

    const body = await readJson<Body>(req);
    if (body.action === "state") return jsonResponse(await pipelineState(serviceClient()));
    const clips = Array.isArray(body.clips) ? body.clips : [];
    if (!clips.length) return errorResponse(400, "clips[] required");
    if (clips.length > 50) return errorResponse(400, "max 50 clips per request");
    const publish = body.publish !== false;

    const supabase = serviceClient();
    const accepted: string[] = [];
    const rejected: Array<{ id: string; reason: string }> = [];

    for (const clip of clips) {
      const reason = validateClip(clip);
      if (reason) {
        rejected.push({ id: clip?.id ?? "?", reason });
        continue;
      }
      try {
        const lines = await stampLines(supabase, clip);
        const row = {
          id: clip.id,
          video_id: clip.video_id,
          title: clip.title,
          channel_name: clip.channel_name,
          category: clip.category,
          difficulty: clip.difficulty === "Intermediate" || clip.difficulty === "Advanced"
            ? clip.difficulty
            : "Beginner",
          source_start_sec: clip.source_start_sec,
          duration_sec: clip.duration_sec,
          lines,
          published: publish,
          review_tier: "ai_v3",
          channel_avatar_color: clip.channel_avatar_color ?? "#F97316",
          thumbnail_gradient: clip.thumbnail_gradient ?? ["#1C1917", "#44403C", "#78716C"],
          timing_mode: "word",
          video_orientation: clip.video_orientation === "portrait" ? "portrait" : "landscape",
          model: "audio-word-aligned",
          prompt_version: "word-alignment-1",
        };
        const { error } = await supabase.from("clips").upsert(row, { onConflict: "id" });
        if (error) {
          rejected.push({ id: clip.id, reason: error.message.slice(0, 240) });
        } else {
          accepted.push(clip.id);
        }
      } catch (err) {
        rejected.push({
          id: clip.id,
          reason: err instanceof Error ? err.message.slice(0, 240) : "stamp failed",
        });
      }
    }

    return jsonResponse({
      accepted: accepted.length,
      rejected: rejected.length,
      ids: accepted,
      errors: rejected,
    });
  } catch (err) {
    return errorResponse(500, err instanceof Error ? err.message : "ingest failed");
  }
});
