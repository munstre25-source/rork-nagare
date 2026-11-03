/**
 * Admin-only ingest for caption-tier clips.
 *
 * Accepts clip JSON produced by Tools/build_caption_clips.py, stamps a
 * caption-1 receipt with catalog_review_hash, and upserts with published=true.
 * Requires x-admin-token == ADMIN_TOKEN. Clients never write to clips.
 */
import { corsPreflight, errorResponse, jsonResponse, readJson } from "../_shared/http.ts";
import { requireEnv } from "../_shared/env.ts";
import { isAdminOrCron } from "../_shared/admin.ts";
import { serviceClient } from "../_shared/supabase.ts";

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
  clips?: CaptionClip[];
  publish?: boolean;
};

const CATEGORIES = new Set([
  "anime", "drama", "variety", "vtuber", "interview", "kids", "gaming", "learning", "podcast",
]);

function sha256Hex(text: string): Promise<string> {
  const data = new TextEncoder().encode(text);
  return crypto.subtle.digest("SHA-256", data).then((buf) =>
    [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("")
  );
}

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
  const sourceBlob = JSON.stringify(
    clip.lines.map((ln) => ({
      t: ln.translation,
      s: ln.start,
      e: ln.end,
      x: (ln.tokens as Array<{ surface?: string }>).map((t) => t.surface ?? "").join(""),
    })),
  );
  const sourceHash = await sha256Hex(sourceBlob);

  // Ask Postgres for the canonical databaseHash (same function the gate uses).
  const stripped = clip.lines.map((ln) => {
    const { translationReview: _r, ...rest } = ln;
    return { ...rest, timing: "line" };
  });
  const { data: hash, error } = await supabase.rpc("catalog_review_hash", {
    p_video_id: clip.video_id,
    p_start: clip.source_start_sec,
    p_duration: clip.duration_sec,
    p_lines: stripped,
  });
  if (error || typeof hash !== "string") {
    throw new Error(error?.message ?? "catalog_review_hash failed");
  }

  return stripped.map((ln) => ({
    ...ln,
    timing: "line",
    translationReview: {
      version: "caption-1",
      sourceTrack: "creator-manual",
      sourceHash,
      databaseHash: hash,
      category: clip.category,
      videoId: clip.video_id,
      sourceStartSec: clip.source_start_sec,
      durationSec: clip.duration_sec,
    },
  }));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") return errorResponse(405, "Method not allowed");

  try {
    requireEnv("ADMIN_TOKEN");
    if (!isAdminOrCron(req)) return errorResponse(401, "Unauthorized");

    const body = await readJson<Body>(req);
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
          review_tier: "caption",
          channel_avatar_color: clip.channel_avatar_color ?? "#F97316",
          thumbnail_gradient: clip.thumbnail_gradient ?? ["#1C1917", "#44403C", "#78716C"],
          timing_mode: "line",
          model: "caption-1",
          prompt_version: "caption-1",
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
