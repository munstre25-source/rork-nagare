import { startPipeline, updatePipeline, sealCatalogLines } from "../_shared/pipeline.ts";
import { corsPreflight, errorResponse, jsonResponse, readJson } from "../_shared/http.ts";
import { requireEnv, geminiModelTranslationReview } from "../_shared/env.ts";
import { tryIncrementGeminiUsage } from "../_shared/limits.ts";
import { reviewJapaneseTranslations } from "../_shared/translation-review.ts";
import type { TimedLine } from "../_shared/timing.ts";
import { isAdminOrCron } from "../_shared/admin.ts";
import { catalogTable, parseLanguage } from "../_shared/catalog.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { LineLike, validateEnums, validateLines } from "../_shared/validate.ts";
import { checkYouTubeVideo, ERROR_MESSAGES } from "../_shared/immersion.ts";

type Body = {
  id?: string;
  action?: string;
  language?: string;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") return errorResponse(405, "Method not allowed");

  let pipelineAttempt: string | null = null;
  try {
    requireEnv("ADMIN_TOKEN");
    if (!isAdminOrCron(req)) return errorResponse(401, "Unauthorized");

    const body = await readJson<Body>(req);
    const id = typeof body.id === "string" ? body.id.trim() : "";
    const action = body.action === "publish" || body.action === "unpublish"
      ? body.action
      : null;
    if (!id || !action) {
      return errorResponse(400, 'id and action ("publish"|"unpublish") required');
    }

    const language = parseLanguage(body.language);
    const table = catalogTable(language);
    const supabase = serviceClient();
    const { data: clip, error } = await supabase
      .from(table)
      .select("*")
      .eq("id", id)
      .maybeSingle();

    if (error || !clip) return errorResponse(404, "Clip not found");

    if (action === "unpublish") {
      const { data, error: upErr } = await supabase
        .from(table)
        .update({ published: false })
        .eq("id", id)
        .select("*")
        .single();
      if (upErr) return errorResponse(500, "Unpublish failed");
      return jsonResponse({ clip: data });
    }

    const attempt = language === "ja" ? await startPipeline(supabase, { video_id: clip.video_id, clip_id: id, title: clip.title, channel_name: clip.channel_name, source: "manual" }) : null;
    pipelineAttempt = attempt;
    const fail = async (status: number, message: string) => {
      if (attempt) await updatePipeline(supabase, attempt, { status: status >= 500 || status === 429 ? "held" : "rejected", stage: "quality_gate", reason: "publication_refused", detail: message.slice(0, 500) });
      return errorResponse(status, message);
    };
    const durationSec = Number(clip.duration_sec);
    if (!Number.isFinite(durationSec) || durationSec < 8 || durationSec > 120) {
      return fail(422, "Refuse to publish: clip duration must be between 8 and 120 seconds");
    }

    // Recheck on every publish: owners can change a video's embedding setting
    // after discovery or after a previous publish.
    const videoCheck = await checkYouTubeVideo(supabase, String(clip.video_id ?? ""));
    if (!videoCheck.ok) {
      const message = videoCheck.code === "not_embeddable"
        ? ERROR_MESSAGES.not_embeddable
        : videoCheck.code === "private_video" || videoCheck.code === "video_not_found"
        ? ERROR_MESSAGES[videoCheck.code]
        : videoCheck.code === "quota_exhausted"
        ? "YouTube verification quota is exhausted. Try publishing again tomorrow."
        : "YouTube could not verify this video. Try again later.";
      return fail(videoCheck.code === "quota_exhausted" || videoCheck.code === "youtube_unavailable" ? 503 : 422, message);
    }

    if (language === "ja" && videoCheck.video.durationSec > 240) return fail(422, "Refuse to publish: source exceeds four-minute catalog policy");
    // publish — validate lines first
    const enums = validateEnums(clip.category, clip.difficulty);
    if (!enums.ok) return fail(422, enums.error);

    const lines = clip.lines as LineLike[];
    const startSec = Array.isArray(lines) && lines.length > 0
      ? Number((lines[0] as LineLike).start) || 0
      : 0;
    const endSec = Array.isArray(lines) && lines.length > 0
      ? Number((lines[lines.length - 1] as LineLike).end) ||
        Number(clip.duration_sec) ||
        startSec
      : Number(clip.duration_sec) || 0;

    const validated = validateLines(lines, startSec, endSec, language);
    if (!validated.ok) {
      return fail(422, `Refuse to publish: ${validated.error}`);
    }

    let reviewedLines: TimedLine[] | undefined;
    if (language === "ja") {
      const review = await reviewJapaneseTranslations({
        videoId: String(clip.video_id ?? ""),
        sourceStartSec: Number(clip.source_start_sec ?? 0),
        durationSec,
        lines: clip.lines as TimedLine[],
      }, {
        model: geminiModelTranslationReview(),
        consumeUsage: () => tryIncrementGeminiUsage(supabase),
      });
      if (!review.ok) {
        return fail(review.reason === "quota" ? 429 : 422,
          "Refuse to publish: " + review.detail);
      }
      reviewedLines = await sealCatalogLines(supabase, { videoId: clip.video_id, sourceStartSec: Number(clip.source_start_sec ?? 0), durationSec, lines: review.lines });
    }

    const { data, error: pubErr } = language === "ja"
      ? await supabase.rpc("publish_reviewed_catalog_clip", { p_id: id, p_expected_lines: clip.lines, p_reviewed_lines: reviewedLines }).maybeSingle()
      : await supabase.from(table).update({ published: true }).eq("id", id).select("*").single();
    if (pubErr) return fail(500, "Publish failed");
    if (!data) return fail(409, "Subtitles changed during review; rerun publication");
    if (attempt) await updatePipeline(supabase, attempt, { status: "published", stage: "published", clip_id: id });
    return jsonResponse({ clip: data });
  } catch (err) {
    if (pipelineAttempt) await updatePipeline(serviceClient(), pipelineAttempt, { status: "failed", stage: "error", reason: "publication_error", detail: err instanceof Error ? err.message.slice(0, 300) : "Publication failed" }).catch(() => {});
    const message = err instanceof Error ? err.message : "";
    if (message.startsWith("Missing required env")) {
      return errorResponse(500, "Server misconfigured");
    }
    return errorResponse(500, "Publish failed");
  }
});
