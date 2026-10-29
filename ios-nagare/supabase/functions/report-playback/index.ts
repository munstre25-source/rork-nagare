import { corsPreflight, errorResponse, jsonResponse, readJson } from "../_shared/http.ts";
import { utcDayString } from "../_shared/env.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { feedbackIdentity } from "../_shared/feedback.ts";

/**
 * A learner's phone reports that a catalog clip could not play (YouTube IFrame error or a
 * player that never became ready / stalled). YouTube's Data API can't see rights-holder
 * embed blocks, so real devices are the only reliable signal. The database function
 * decides when the evidence is strong enough to unpublish the video for everyone.
 *
 *   POST /functions/v1/report-playback  { "videoId": "...", "clipId": "...", "code": 150 }
 */

const VIDEO_ID = /^[A-Za-z0-9_-]{11}$/;
const DAILY_LIMIT = 30;

type Body = { videoId?: unknown; clipId?: unknown; code?: unknown };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") return errorResponse(405, "Method not allowed");

  try {
    const sb = serviceClient();
    const identity = await feedbackIdentity(req, sb);
    if (!identity) return errorResponse(401, "Missing identity");

    const body = await readJson<Body>(req);
    const videoId = typeof body.videoId === "string" ? body.videoId.trim() : "";
    const clipId = typeof body.clipId === "string" ? body.clipId.trim().slice(0, 128) : null;
    const code = typeof body.code === "number" && Number.isFinite(body.code) ? Math.trunc(body.code) : NaN;
    if (!VIDEO_ID.test(videoId) || Number.isNaN(code) || code < -10 || code > 1000) {
      return errorResponse(400, "Invalid report");
    }

    const { data: allowed } = await sb.rpc("increment_insight_rate", {
      p_app_user_id: identity.key,
      p_day_utc: utcDayString(),
      p_kind: "playback_report",
      p_limit: DAILY_LIMIT,
    });
    if (allowed === false) return jsonResponse({ ok: true, unpublished: false, limited: true });

    const { data: unpublished, error } = await sb.rpc("report_clip_playback_failure", {
      p_video_id: videoId,
      p_reporter: identity.key,
      p_clip_id: clipId,
      p_error_code: code,
    });
    if (error) {
      console.error(JSON.stringify({ event: "playback_report_failed", detail: error.message.slice(0, 160) }));
      return errorResponse(500, "Could not record report");
    }
    console.log(JSON.stringify({ event: "playback_report", videoId, code, unpublished: unpublished === true }));
    return jsonResponse({ ok: true, unpublished: unpublished === true });
  } catch {
    return errorResponse(500, "Could not record report");
  }
});
