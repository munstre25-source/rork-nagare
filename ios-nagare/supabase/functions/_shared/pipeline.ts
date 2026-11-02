import { serviceClient } from "./supabase.ts";
import { TRANSLATION_REVIEW_VERSION } from "./translation-review.ts";
import type { TranslationSource } from "./translation-review.ts";
type Client = ReturnType<typeof serviceClient>;
export async function startPipeline(sb: Client, input: { video_id: string; window_start_sec?: number; clip_id?: string; title?: string; channel_name?: string; source: "automatic" | "manual" | "review" }): Promise<string> {
  const { data, error } = await sb.from("catalog_pipeline_attempts").insert({ ...input, status: "processing", stage: "checking", review_version: TRANSLATION_REVIEW_VERSION }).select("id").single();
  if (error || !data) throw new Error("Pipeline tracking unavailable");
  return data.id;
}
export async function updatePipeline(sb: Client, id: string, patch: Record<string, unknown>): Promise<void> {
  const { error } = await sb.from("catalog_pipeline_attempts").update({ ...patch, updated_at: new Date().toISOString(), ...(patch.status && patch.status !== "processing" ? { finished_at: new Date().toISOString() } : {}) }).eq("id", id);
  if (error) throw new Error("Pipeline tracking update failed");
}
export function failureStatus(reason: string, detail = ""): "held" | "failed" | "rejected" {
  if (/not valid JSON|not a JSON|incomplete review|duplicate review|review must contain/i.test(detail)) return "failed";
  if (/visual subtitle check is incomplete|subtitle detection lacks|visual subtitle check is inconsistent|category or child audience/i.test(detail)) return "held";
  if (/cap|quota|payment|402|unavailable/.test(reason)) return "held";
  if (/retryable|insert|tracking|timeout|pipeline_error/.test(reason)) return "failed";
  return "rejected";
}
export async function sealCatalogLines(sb: Client, source: TranslationSource) {
  const { data, error } = await sb.rpc("catalog_review_hash", {
    p_video_id: source.videoId, p_start: source.sourceStartSec, p_duration: source.durationSec, p_lines: source.lines,
  });
  if (error || typeof data !== "string") throw new Error("Publication integrity seal unavailable");
  return source.lines.map((line) => ({ ...line, translationReview: { ...(line.translationReview as object), databaseHash: data } }));
}
