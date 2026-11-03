import { applyLocalAlignment, snapshotJson, type LocalAlignment } from "../_shared/local-alignment.ts";
import { startPipeline, updatePipeline, failureStatus, sealCatalogLines } from "../_shared/pipeline.ts";
import { corsPreflight, errorResponse, jsonResponse, readJson } from "../_shared/http.ts";
import { isAdminOrCron } from "../_shared/admin.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { geminiModelTranslationReview } from "../_shared/env.ts";
import { tryIncrementGeminiUsage } from "../_shared/limits.ts";
import { AiBudgetError, GeminiError } from "../_shared/gemini.ts";
import { repairWordTiming } from "../_shared/word-timing.ts";
import { reviewJapaneseTranslations, type TranslationSource } from "../_shared/translation-review.ts";

export async function handler(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") return errorResponse(405, "Method not allowed");
  if (!isAdminOrCron(req)) return errorResponse(401, "Unauthorized");
  let attempt: string | undefined;
  try {
    const body = await readJson<{ id?: string; source?: TranslationSource; apply?: boolean; quarantine?: boolean; repairTiming?: boolean; localAlignment?: LocalAlignment; expectedLines?: unknown; lineIndexes?: number[]; translations?: Record<string, string> }>(req);
    if ((!!body.id) === (!!body.source)) return errorResponse(400, "Provide exactly one id or source");
    if (body.source && body.apply) return errorResponse(400, "External bundled sources are review-only");
    const supabase = serviceClient();
    let source = body.source;
    let originalLines: unknown;
    let originalCategory: string | undefined;
    let published = false;
    if (body.id) {
      const { data, error } = await supabase.from("clips").select("*").eq("id", body.id).maybeSingle();
      if (error) return errorResponse(500, "Catalog read failed");
      if (!data) return errorResponse(404, "Clip not found");
      source = {
        videoId: data.video_id, sourceStartSec: Number(data.source_start_sec ?? 0),
        durationSec: Number(data.duration_sec), lines: data.lines,
      };
      originalLines = data.lines;
      originalCategory = String(data.category);
      published = data.published === true;
    }
    if (!source || !Array.isArray(source.lines) || source.lines.length > 100) return errorResponse(400, "Invalid subtitle source");
    if (body.localAlignment) {
      if (!body.id || !published || body.source || body.translations || body.lineIndexes || body.repairTiming || !body.expectedLines) {
        return errorResponse(400, "Local alignment only updates an unchanged, already-published clip");
      }
      if (snapshotJson(originalLines) !== snapshotJson(body.expectedLines)) {
        return errorResponse(409, "Subtitles changed since local alignment started");
      }
      let lines;
      try { lines = applyLocalAlignment(source, body.localAlignment); }
      catch (error) { return errorResponse(422, error instanceof Error ? error.message : "Invalid local alignment"); }
      if (!body.apply) return jsonResponse({ id: body.id, status: "aligned_locally", paidApiCalls: 0, lines });
      const { data: originalHash, error: hashError } = await supabase.rpc("catalog_review_hash", {
        p_video_id: source.videoId, p_start: source.sourceStartSec, p_duration: source.durationSec, p_lines: originalLines,
      });
      if (hashError || typeof originalHash !== "string") return errorResponse(500, "Original subtitle integrity check unavailable");
      const receipt = {
        version: 1, method: body.localAlignment.method, model: body.localAlignment.model,
        revision: body.localAlignment.revision, audioSha256: body.localAlignment.audioSha256,
        videoId: source.videoId, sourceStartSec: source.sourceStartSec, durationSec: source.durationSec,
        sourceLinesHash: originalHash,
      };
      lines = lines.map((line) => ({ ...line, translationReview: {
        ...(line.translationReview as object ?? {}), localAlignment: receipt,
      } }));
      const { data: databaseHash, error: sealError } = await supabase.rpc("catalog_review_hash", {
        p_video_id: source.videoId, p_start: source.sourceStartSec, p_duration: source.durationSec, p_lines: lines,
      });
      if (sealError || typeof databaseHash !== "string") return errorResponse(500, "Local alignment integrity seal unavailable");
      lines = lines.map((line) => ({ ...line, translationReview: {
        ...(line.translationReview as object), localAlignment: { ...receipt, databaseHash },
      } }));
      const { data: applied, error } = await supabase.rpc("apply_catalog_local_alignment", {
        p_id: body.id, p_expected_lines: originalLines, p_video_id: source.videoId,
        p_source_start: source.sourceStartSec, p_duration: source.durationSec, p_lines: lines,
      });
      if (error) return errorResponse(500, "Local alignment could not be saved");
      if (!applied) return errorResponse(409, "Source changed since local alignment started");
      return jsonResponse({ id: body.id, status: "applied", method: receipt.method, paidApiCalls: 0, repairedWordLines: lines.length });
    }
    const completeSource = source;
    const indexes = body.lineIndexes ?? source.lines.map((_, i) => i);
    if (!Array.isArray(indexes) || indexes.length === 0 || new Set(indexes).size !== indexes.length ||
        indexes.some((i) => !Number.isInteger(i) || i < 0 || i >= completeSource.lines.length)) {
      return errorResponse(400, "Invalid original line indexes");
    }
    attempt = await startPipeline(supabase, { video_id: completeSource.videoId, clip_id: body.id, source: "review" });
    const candidateLines = indexes.map((i) => {
      const translation = body.translations?.[String(i)] ?? completeSource.lines[i].translation;
      return { ...completeSource.lines[i], translation };
    });
    source = { ...completeSource, lines: candidateLines };
    let repairedWordLines = 0;
    if (body.repairTiming) {
      if (indexes.length !== completeSource.lines.length) return errorResponse(400, "Timing repair requires the full original clip");
      const aligned = await repairWordTiming(source, { consumeUsage: () => tryIncrementGeminiUsage(supabase) });
      if (!aligned.ok) {
        await updatePipeline(supabase, attempt, { status: "held", stage: "word_alignment", reason: aligned.reason, detail: aligned.detail });
        return jsonResponse({ id: body.id, status: "needs_alignment", reason: aligned.reason, detail: aligned.detail }, aligned.reason === "quota" ? 429 : 422);
      }
      source = { ...source, lines: aligned.lines };
      repairedWordLines = aligned.repaired;
    }
    const result = await reviewJapaneseTranslations(source, {
      force: body.repairTiming === true,
      model: geminiModelTranslationReview(),
      consumeUsage: () => tryIncrementGeminiUsage(supabase),
    });
    if (!result.ok) {
      await updatePipeline(supabase, attempt, { status: failureStatus(result.reason, result.detail ?? ""), stage: "quality_gate", reason: result.reason, detail: result.detail });
      if (body.quarantine && body.id && result.reason !== "quota") {
        const { error } = await supabase.from("clips").update({ published: false }).eq("id", body.id);
        if (error) return errorResponse(500, "Failed to hold unsupported clip");
      }
      return jsonResponse({ id: body.id ?? null, status: "needs_review", reason: result.reason, detail: result.detail },
        result.reason === "quota" ? 429 : 422);
    }
    let merged = completeSource.lines.map((line, i) => {
      const selected = indexes.indexOf(i);
      return selected < 0 ? line : result.lines[selected];
    });
    const category = String((result.lines[0].translationReview as { contentClassification: { category: string } }).contentClassification.category);
    if (body.apply && body.id && indexes.length !== completeSource.lines.length) {
      await updatePipeline(supabase, attempt, { status: "held", stage: "quality_gate", reason: "partial_review", detail: "Full clip approval required before updating a live clip" });
      return jsonResponse({ id: body.id, status: "reviewed_partial", lines: merged, reviewedLineIndexes: indexes });
    }
    if (body.apply && body.id) {
      merged = await sealCatalogLines(supabase, { ...completeSource, lines: merged });
      const { data, error } = body.repairTiming
        ? await supabase.rpc("apply_catalog_word_timing", {
          p_id: body.id, p_expected_lines: originalLines, p_video_id: completeSource.videoId,
          p_source_start: completeSource.sourceStartSec, p_duration: completeSource.durationSec, p_lines: merged,
        })
        : await supabase.rpc("apply_catalog_review", {
          p_id: body.id, p_expected_lines: originalLines, p_expected_category: originalCategory,
          p_lines: merged, p_category: category,
        });
      if (error) {
        await updatePipeline(supabase, attempt, { status: "held", stage: "apply", reason: "compare_and_swap_pending", detail: "Approved update could not be saved; safe to retry" });
        // Keep the approved proposal for recovery if the database is unavailable.
        return jsonResponse({
          id: body.id, status: "reviewed_pending_apply", lines: merged,
          reviewedLineIndexes: indexes, expectedLines: originalLines, category, expectedCategory: originalCategory,
          timingPreserved: !body.repairTiming, repairedWordLines, lineIndexesPreserved: true,
        });
      }
      if (!data) {
        await updatePipeline(supabase, attempt, { status: "held", stage: "apply", reason: "concurrent_edit", detail: "Subtitles changed during review" });
        return errorResponse(409, "Subtitles changed while review was running; rerun review");
      }
    }
    await updatePipeline(supabase, attempt, { status: "reviewed", stage: "complete", reason: null, detail: body.apply ? "Review saved; publication state unchanged" : "Review-only; not applied" });
    const changed = source.lines.filter((line, i) => line.translation !== result.lines[i].translation).length;
    return jsonResponse({
      id: body.id ?? null, status: body.apply ? (indexes.length === completeSource.lines.length ? "applied" : "applied_partial") : "reviewed", reused: result.reused,
      changedTranslations: changed, category, timingPreserved: !body.repairTiming, repairedWordLines, lineIndexesPreserved: true, lines: merged, reviewedLineIndexes: indexes,
    });
  } catch (error) {
    if (error instanceof AiBudgetError) {
      if (attempt) await updatePipeline(serviceClient(), attempt, { status: "held", stage: "budget", reason: "gemini_cap", detail: "Shared AI spending allowance reached; retry after allowance is available" }).catch(() => {});
      return errorResponse(429, "AI processing allowance reached");
    }
    if (attempt) await updatePipeline(serviceClient(), attempt, { status: "failed", stage: "error", reason: "review_error", detail: error instanceof Error ? error.message.slice(0, 300) : "Review failed" }).catch(() => {});
    if (error instanceof GeminiError) return errorResponse(error.paymentRequired ? 402 : 503, error.message);
    return errorResponse(500, "Subtitle review failed");
  }
}
if (import.meta.main) Deno.serve(handler);
