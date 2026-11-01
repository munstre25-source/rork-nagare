import { corsPreflight, errorResponse, jsonResponse } from "../_shared/http.ts";
import { isAdminOrCron } from "../_shared/admin.ts";
import { envInt } from "../_shared/env.ts";
import { serviceClient } from "../_shared/supabase.ts";
import {
  analyzeWindow,
  AnalyzeOutcome,
  checkYouTubeVideo,
  clipId,
  clipRow,
  ERROR_MESSAGES,
  log,
} from "../_shared/immersion.ts";

/**
 * Drains the learner video queue (immersion_jobs).
 *
 * Called every minute by pg_cron while work exists, and immediately by immersion-submit.
 * Each run claims up to IMMERSION_MAX_CONCURRENCY jobs (global cap, enforced in SQL) and
 * processes one transcription window per job, so a run always fits the function time limit.
 * Long videos are scanned window by window across runs without consuming retry attempts.
 */

type Job = {
  id: string;
  video_id: string;
  language: "ja";
  status: string;
  stage: string;
  scan_offset_sec: number | string;
  windows_scanned: number;
  attempts: number;
  max_attempts: number;
  title: string | null;
  channel_name: string | null;
  video_duration_sec: number | string | null;
};

type Supabase = ReturnType<typeof serviceClient>;

const WINDOW_SEC = 180;
const WINDOW_STEP_SEC = 150;
const MAX_WINDOWS = 4;
const STALE_SECONDS = 240;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") return errorResponse(405, "Method not allowed");
  if (!isAdminOrCron(req)) return errorResponse(401, "Unauthorized");

  const supabase = serviceClient();
  const worker = `w-${crypto.randomUUID().slice(0, 8)}`;
  const { data, error } = await supabase.rpc("claim_immersion_jobs", {
    p_worker: worker,
    p_max_concurrency: envInt("IMMERSION_MAX_CONCURRENCY", 2),
    p_stale_seconds: STALE_SECONDS,
  });
  if (error) {
    log("immersion_claim_failed", { worker, message: error.message });
    return errorResponse(500, "Claim failed");
  }
  const jobs = (data ?? []) as Job[];
  if (jobs.length === 0) return jsonResponse({ worker, claimed: 0 });

  const results = await Promise.all(jobs.map((job) => processJob(supabase, worker, job)));
  return jsonResponse({ worker, claimed: jobs.length, results });
});

async function processJob(supabase: Supabase, worker: string, job: Job): Promise<Record<string, unknown>> {
  const started = Date.now();
  const ctx = { jobId: job.id, videoId: job.video_id, worker, attempt: job.attempts };
  log("immersion_job_started", ctx);
  try {
    const result = await runJob(supabase, worker, job);
    log("immersion_job_finished", { ...ctx, ...result, ms: Date.now() - started });
    return { id: job.id, ...result };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    log("immersion_job_crashed", { ...ctx, message: message.slice(0, 300) });
    await retryOrFail(supabase, worker, job, "internal", message);
    return { id: job.id, outcome: "crashed" };
  }
}

async function runJob(supabase: Supabase, worker: string, job: Job): Promise<Record<string, unknown>> {
  // Revalidate before reuse because YouTube owners can disable embeds later.
  const check = await checkYouTubeVideo(supabase, job.video_id);
  if (!check.ok) {
    log("immersion_video_rejected", { jobId: job.id, code: check.code, detail: check.detail });
    if (check.code === "quota_exhausted") {
      await requeue(supabase, worker, job, { at: nextUtcMidnight(), code: "quota_exhausted", refundAttempt: true });
      return { outcome: "deferred", reason: "youtube_quota" };
    }
    if (check.code === "youtube_unavailable") {
      await retryOrFail(supabase, worker, job, "internal", check.detail);
      return { outcome: "retry", reason: check.code };
    }
    await finish(supabase, worker, job, { status: "unprocessable", error_code: check.code });
    return { outcome: "unprocessable", reason: check.code };
  }

  // A published catalog clip or an earlier learner clip for this video can now be reused.
  const existing = await existingClip(supabase, job.video_id);
  if (existing) {
    await finish(supabase, worker, job, {
      status: "succeeded",
      clip_id: existing.id,
      timing_mode: existing.timing_mode ?? "word",
      model: existing.model,
      prompt_version: existing.prompt_version,
    });
    return { outcome: "reused", clipId: existing.id };
  }

  const video = check.video;
  await update(supabase, worker, job, {
    title: video.title.slice(0, 200),
    channel_name: video.channelTitle.slice(0, 120),
    video_duration_sec: video.durationSec,
  });

  const offset = Number(job.scan_offset_sec) || 0;
  const windowStart = Math.min(offset, Math.max(0, video.durationSec - 20));
  const windowEnd = Math.min(video.durationSec, windowStart + WINDOW_SEC);
  if (windowEnd - windowStart < 8) {
    await finish(supabase, worker, job, { status: "unprocessable", error_code: "no_japanese_dialogue" });
    return { outcome: "unprocessable", reason: "past_end" };
  }

  const outcome: AnalyzeOutcome = await analyzeWindow(supabase, {
    videoId: job.video_id,
    windowStart,
    windowEnd,
    sourceDurationSec: video.durationSec,
    language: "ja",
    askCategory: true,
    minSpokenSec: 6,
    onStage: (stage) => update(supabase, worker, job, { stage }),
  });

  if (outcome.ok) {
    await update(supabase, worker, job, { stage: "publishing" });
    const id = clipId("immersion", job.video_id, outcome.draft);
    const row = clipRow({
      id,
      video,
      draft: outcome.draft,
      category: outcome.draft.category ?? "variety",
      // Learner clips stay private to their requesters (RLS "requesters read their clips").
      published: false,
      withProvenance: true,
    });
    const { error } = await supabase.from("clips").upsert(row);
    if (error) throw new Error(`clip upsert failed: ${error.message}`);
    await finish(supabase, worker, job, {
      status: "succeeded",
      clip_id: id,
      timing_mode: outcome.draft.timingMode,
      model: outcome.draft.model,
      prompt_version: outcome.draft.promptVersion,
    });
    return {
      outcome: "succeeded",
      clipId: id,
      timingMode: outcome.draft.timingMode,
      timingConfidence: outcome.draft.timingConfidence,
      model: outcome.draft.model,
    };
  }

  log("immersion_window_failed", {
    jobId: job.id,
    windowStart,
    windowEnd,
    reason: outcome.reason,
    detail: outcome.detail,
  });
  switch (outcome.reason) {
    case "no_dialogue": {
      const nextStart = windowStart + WINDOW_STEP_SEC;
      const scanned = job.windows_scanned + 1;
      if (scanned < MAX_WINDOWS && nextStart < video.durationSec - 20) {
        // Scanning further into the video is progress, not a failure: keep the attempt.
        await requeue(supabase, worker, job, {
          at: new Date(),
          code: null,
          refundAttempt: true,
          extra: { scan_offset_sec: nextStart, windows_scanned: scanned },
        });
        return { outcome: "scanning", nextStart };
      }
      await finish(supabase, worker, job, {
        status: "unprocessable",
        error_code: "no_japanese_dialogue",
        windows_scanned: scanned,
      });
      return { outcome: "unprocessable", reason: "no_japanese_dialogue" };
    }
    case "gemini_cap":
      await requeue(supabase, worker, job, { at: nextUtcMidnight(), code: "quota_exhausted", refundAttempt: true });
      return { outcome: "deferred", reason: "gemini_cap" };
    case "model_payment":
      await retryOrFail(supabase, worker, job, "model_unavailable", outcome.detail, 2 * 60 * 60);
      return { outcome: "retry", reason: outcome.reason };
    case "model_rejected":
      await finish(supabase, worker, job, { status: "failed", error_code: "model_unavailable" });
      return { outcome: "failed", reason: outcome.reason };
    case "model_retryable":
      await retryOrFail(supabase, worker, job, "model_timeout", outcome.detail);
      return { outcome: "retry", reason: outcome.reason };
    case "enrichment_failed":
      await retryOrFail(supabase, worker, job, "model_unavailable", outcome.detail);
      return { outcome: "retry", reason: outcome.reason };
    case "transcript_invalid":
      await retryOrFail(supabase, worker, job, "transcript_invalid", outcome.detail);
      return { outcome: "retry", reason: outcome.reason };
  }
}

// MARK: - Job state

type ClipRef = { id: string; timing_mode: string | null; model: string | null; prompt_version: string | null };

async function existingClip(supabase: Supabase, videoId: string): Promise<ClipRef | null> {
  const { data, error } = await supabase
    .from("clips")
    .select("id, timing_mode, model, prompt_version, published")
    .eq("video_id", videoId)
    .order("published", { ascending: false })
    .limit(1);
  if (error) throw new Error(`clip lookup failed: ${error.message}`);
  return (data?.[0] as ClipRef | undefined) ?? null;
}

/** Writes only while this worker still owns the job, so a reclaimed job is never clobbered. */
async function update(supabase: Supabase, worker: string, job: Job, fields: Record<string, unknown>): Promise<void> {
  const { error } = await supabase
    .from("immersion_jobs")
    .update({ ...fields, updated_at: new Date().toISOString() })
    .eq("id", job.id)
    .eq("locked_by", worker);
  if (error) throw new Error(`job update failed: ${error.message}`);
}

async function finish(
  supabase: Supabase,
  worker: string,
  job: Job,
  fields: { status: "succeeded" | "failed" | "unprocessable"; error_code?: string } & Record<string, unknown>,
): Promise<void> {
  const now = new Date().toISOString();
  const errorCode = fields.error_code ?? null;
  await update(supabase, worker, job, {
    ...fields,
    stage: "done",
    error_code: errorCode,
    error_message: errorCode ? ERROR_MESSAGES[errorCode] ?? ERROR_MESSAGES.internal : null,
    locked_at: null,
    locked_by: null,
    finished_at: now,
  });
}

async function requeue(
  supabase: Supabase,
  worker: string,
  job: Job,
  opts: { at: Date; code: string | null; refundAttempt: boolean; extra?: Record<string, unknown> },
): Promise<void> {
  await update(supabase, worker, job, {
    ...opts.extra,
    status: "queued",
    stage: "queued",
    attempts: opts.refundAttempt ? Math.max(0, job.attempts - 1) : job.attempts,
    next_attempt_at: opts.at.toISOString(),
    error_code: opts.code,
    error_message: opts.code ? ERROR_MESSAGES[opts.code] ?? null : null,
    locked_at: null,
    locked_by: null,
  });
}

/** Exponential backoff (30s, 60s, 120s…) until max_attempts, then a final failure. */
async function retryOrFail(
  supabase: Supabase,
  worker: string,
  job: Job,
  code: string,
  detail: string,
  minDelaySec = 0,
): Promise<void> {
  if (job.attempts >= job.max_attempts) {
    log("immersion_job_exhausted", { jobId: job.id, code, detail: detail.slice(0, 200) });
    await finish(supabase, worker, job, { status: "failed", error_code: code });
    return;
  }
  const delaySec = Math.max(minDelaySec, 30 * 2 ** Math.max(0, job.attempts - 1));
  await requeue(supabase, worker, job, {
    at: new Date(Date.now() + delaySec * 1000),
    code,
    refundAttempt: false,
  });
}

function nextUtcMidnight(): Date {
  const d = new Date();
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + 1, 0, 5));
}

