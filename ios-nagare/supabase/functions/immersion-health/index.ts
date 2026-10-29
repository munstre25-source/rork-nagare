import { corsPreflight, errorResponse, jsonResponse } from "../_shared/http.ts";
import { isAdminOrCron, timingSafeEqualString } from "../_shared/admin.ts";
import { geminiModelAnalyze, geminiModelFallback } from "../_shared/env.ts";
import { GeminiError, describeProviders, geminiAnalyzeYouTubeSegment, geminiGenerateJson } from "../_shared/gemini.ts";
import { readJson } from "../_shared/http.ts";
import { serviceClient } from "../_shared/supabase.ts";

/**
 * Operator health check for the immersion pipeline: model reachability (primary and fallback)
 * and queue depth. Admin/cron token, or IMMERSION_HEALTH_TOKEN, in x-admin-token.
 */
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  const healthToken = Deno.env.get("IMMERSION_HEALTH_TOKEN")?.trim() ?? "";
  const provided = req.headers.get("x-admin-token") ?? "";
  const allowed = isAdminOrCron(req) || (healthToken.length >= 24 && timingSafeEqualString(provided, healthToken));
  if (!allowed) return errorResponse(401, "Unauthorized");

  const transports = describeProviders();
  const transport = transports.join("+");
  const models = [...new Set([geminiModelAnalyze(), geminiModelFallback()])];
  const probes = await Promise.all(models.map(async (model) => {
    const started = Date.now();
    try {
      const result = await geminiGenerateJson({
        model,
        system: "Reply with JSON only.",
        user: 'Return {"ok":true,"word":"猫","reading":"ねこ"}',
        timeoutMs: 25_000,
      });
      return { requested: model, answeredBy: result.model, ok: true, ms: Date.now() - started };
    } catch (err) {
      return {
        requested: model,
        ok: false,
        status: err instanceof GeminiError ? err.status : null,
        detail: err instanceof Error ? err.message.slice(0, 240) : "unknown",
        ms: Date.now() - started,
      };
    }
  }));

  // Optional: {"videoId":"..."} also probes video understanding on the first 20 seconds.
  const body = await readJson<{ videoId?: unknown }>(req).catch(() => ({} as { videoId?: unknown }));
  let video: Record<string, unknown> | null = null;
  if (typeof body.videoId === "string" && /^[A-Za-z0-9_-]{11}$/.test(body.videoId)) {
    const started = Date.now();
    try {
      const result = await geminiAnalyzeYouTubeSegment({
        model: geminiModelAnalyze(),
        system: "Reply with JSON only.",
        user: 'Return {"heard": "<first spoken sentence, verbatim>", "start": <seconds>}.',
        youtubeUrl: `https://www.youtube.com/watch?v=${body.videoId}`,
        startSec: 0,
        endSec: 20,
      });
      video = { ok: true, answeredBy: result.model, sample: result.text.slice(0, 200), ms: Date.now() - started };
    } catch (err) {
      video = {
        ok: false,
        status: err instanceof GeminiError ? err.status : null,
        detail: err instanceof Error ? err.message.slice(0, 300) : "unknown",
        ms: Date.now() - started,
      };
    }
  }

  const supabase = serviceClient();
  const { data: queue } = await supabase.from("immersion_jobs").select("status");
  const counts: Record<string, number> = {};
  for (const row of (queue ?? []) as Array<{ status: string }>) counts[row.status] = (counts[row.status] ?? 0) + 1;
  return jsonResponse({ transport, transports, probes, video, queue: counts });
});
