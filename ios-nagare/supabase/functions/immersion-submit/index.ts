import { corsPreflight, errorResponse, jsonResponse, readJson } from "../_shared/http.ts";
import { envInt, utcDayString } from "../_shared/env.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { authedUser } from "../_shared/user.ts";
import { ERROR_MESSAGES, log, parseYouTubeUrl } from "../_shared/immersion.ts";

/**
 * A learner asks for a YouTube video to become a lesson.
 *
 * Body: { "url": "<YouTube link or 11-char id>" }
 * Auth: the learner's Supabase session (anonymous sessions are fine).
 *
 * One job per video is shared by everyone who asks for it. Resubmitting a failed video is the
 * manual retry. Returns the job immediately; the app polls immersion_jobs (RLS: requesters only).
 */

declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void } | undefined;

const JOB_FIELDS =
  "id, video_id, status, stage, attempts, max_attempts, error_code, error_message, title, channel_name, video_duration_sec, clip_id, timing_mode, model, created_at, updated_at, finished_at";

type JobRow = {
  id: string;
  status: string;
  attempts: number;
  max_attempts: number;
  clip_id: string | null;
  error_code: string | null;
  updated_at: string;
  finished_at: string | null;
};

/** Unprocessable results that can change on YouTube's side get a fresh look after this long. */
const RECHECK_UNPROCESSABLE_MS = 6 * 60 * 60 * 1000;
const RECHECKABLE = new Set(["live_stream", "private_video", "not_embeddable", "video_not_found"]);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") return errorResponse(405, "Method not allowed");

  const supabase = serviceClient();
  try {
    const user = await authedUser(req, supabase);
    if (!user) return errorResponse(401, "Sign-in session required");

    const body = await readJson<{ url?: unknown }>(req).catch(() => ({} as { url?: unknown }));
    const parsed = typeof body.url === "string" ? parseYouTubeUrl(body.url) : null;
    if (!parsed) {
      return jsonResponse({ error: "invalid_url", message: ERROR_MESSAGES.invalid_url }, 400);
    }

    const { data: found, error: findError } = await supabase
      .from("immersion_jobs")
      .select(JOB_FIELDS)
      .eq("video_id", parsed.videoId)
      .eq("language", "ja")
      .maybeSingle();
    if (findError) throw new Error(findError.message);
    let job = found as JobRow | null;

    const { data: request } = job
      ? await supabase.from("immersion_job_requests").select("job_id").eq("job_id", job.id).eq("user_id", user.id)
        .maybeSingle()
      : { data: null };
    if (!request && !(await underDailyLimit(supabase, user.id))) {
      return jsonResponse({
        error: "daily_limit",
        message: "You've added the most videos allowed for today. Try again tomorrow.",
      }, 429);
    }

    let created = false;
    if (!job) {
      const { data: inserted, error: insertError } = await supabase
        .from("immersion_jobs")
        .upsert(
          {
            video_id: parsed.videoId,
            language: "ja",
            scan_offset_sec: Math.max(0, (parsed.startSec ?? 0) - 5),
          },
          { onConflict: "video_id,language", ignoreDuplicates: true },
        )
        .select(JOB_FIELDS)
        .maybeSingle();
      if (insertError) throw new Error(insertError.message);
      job = inserted as JobRow | null;
      created = job !== null;
      if (!job) {
        // Another learner created it between our read and write.
        const { data: raced } = await supabase.from("immersion_jobs").select(JOB_FIELDS)
          .eq("video_id", parsed.videoId).eq("language", "ja").single();
        job = raced as JobRow;
      }
    } else if (shouldReset(job, parsed.startSec)) {
      const { data: reset, error: resetError } = await supabase
        .from("immersion_jobs")
        .update({
          status: "queued",
          stage: "queued",
          attempts: 0,
          windows_scanned: 0,
          scan_offset_sec: Math.max(0, (parsed.startSec ?? 0) - 5),
          next_attempt_at: new Date().toISOString(),
          error_code: null,
          error_message: null,
          clip_id: null,
          finished_at: null,
          locked_at: null,
          locked_by: null,
          updated_at: new Date().toISOString(),
        })
        .eq("id", job.id)
        .in("status", ["failed", "unprocessable", "succeeded"])
        .select(JOB_FIELDS)
        .maybeSingle();
      if (resetError) throw new Error(resetError.message);
      if (reset) {
        job = reset as JobRow;
        log("immersion_job_reset", { jobId: job.id, userId: user.id });
      }
    }

    const { error: requestError } = await supabase
      .from("immersion_job_requests")
      .upsert({ job_id: job.id, user_id: user.id }, { onConflict: "job_id,user_id", ignoreDuplicates: true });
    if (requestError) throw new Error(requestError.message);

    if (job.status === "queued") kickWorker();
    log("immersion_job_submitted", { jobId: job.id, videoId: parsed.videoId, userId: user.id, created, status: job.status });
    return jsonResponse({ job }, created ? 201 : 200);
  } catch (err) {
    log("immersion_submit_error", { message: err instanceof Error ? err.message.slice(0, 200) : "unknown" });
    return jsonResponse({ error: "internal", message: ERROR_MESSAGES.internal }, 500);
  }
});

function shouldReset(job: JobRow, startSec: number | null): boolean {
  const finished = Date.parse(job.finished_at ?? job.updated_at);
  const age = Number.isFinite(finished) ? Date.now() - finished : Number.POSITIVE_INFINITY;
  // Manual retry, with a short cool-down so repeated taps don't re-run the model.
  if (job.status === "failed") return age > 60_000;
  if (job.status === "succeeded") return job.clip_id === null;
  if (job.status !== "unprocessable" || !job.error_code) return false;
  // A timestamped link points the scan at a different part of the video.
  if (job.error_code === "no_japanese_dialogue" && startSec !== null) return age > 60_000;
  return RECHECKABLE.has(job.error_code) && age > RECHECK_UNPROCESSABLE_MS;
}

async function underDailyLimit(supabase: ReturnType<typeof serviceClient>, userId: string): Promise<boolean> {
  const limit = envInt("IMMERSION_USER_DAILY_LIMIT", 10);
  const { count, error } = await supabase
    .from("immersion_job_requests")
    .select("job_id", { count: "exact", head: true })
    .eq("user_id", userId)
    .gte("created_at", `${utcDayString()}T00:00:00Z`);
  if (error) throw new Error(error.message);
  return (count ?? 0) < limit;
}

/** Starts the worker now instead of waiting for the next cron minute. Best effort. */
function kickWorker(): void {
  const url = Deno.env.get("SUPABASE_URL")?.replace(/\/$/, "");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  const token = Deno.env.get("CRON_FILL_TOKEN")?.trim() || Deno.env.get("ADMIN_TOKEN")?.trim();
  if (!url || !anon || !token) return;
  const call = fetch(`${url}/functions/v1/immersion-worker`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${anon}`, "x-admin-token": token },
    body: JSON.stringify({ source: "submit" }),
  }).then((res) => res.body?.cancel()).catch((err) => {
    log("immersion_kick_failed", { message: err instanceof Error ? err.message : "unknown" });
  });
  if (typeof EdgeRuntime !== "undefined") EdgeRuntime.waitUntil(call);
}
