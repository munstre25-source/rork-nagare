import { corsPreflight, errorResponse, jsonResponse, readJson } from "../_shared/http.ts";
import { requireEnv, utcDayString } from "../_shared/env.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { feedbackIdentity } from "../_shared/feedback.ts";
import { cleanText, FEEDBACK_CATEGORIES, FEEDBACK_SOURCES } from "../_shared/analytics.ts";

/**
 * Private inbox. Only the developer dashboard reads these rows; they never reach the public board.
 * `anonymous: true` stores no app or user identifier with the note (rate limits still apply).
 */
type Body = {
  enjoyed?: boolean | null;
  category?: string | null;
  message?: string;
  source?: string;
  anonymous?: boolean;
  app_version?: string;
  build?: string;
  os_version?: string;
  device_class?: string;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") return errorResponse(405, "Method not allowed");

  try {
    requireEnv("SUPABASE_URL");
    const sb = serviceClient();
    const identity = await feedbackIdentity(req, sb);
    if (!identity) return errorResponse(400, "Missing identity");

    const body = await readJson<Body>(req);
    const enjoyed = typeof body.enjoyed === "boolean" ? body.enjoyed : null;
    const categoryRaw = (body.category ?? "").trim().toLowerCase();
    const category = categoryRaw && FEEDBACK_CATEGORIES.has(categoryRaw) ? categoryRaw : null;
    const message = (body.message ?? "").trim().slice(0, 2000);
    const source = FEEDBACK_SOURCES.has(body.source ?? "") ? body.source! : null;
    const anonymous = body.anonymous === true;

    const isCancellation = category?.startsWith("cancel_") === true;
    if (enjoyed === false && !message && !category) return errorResponse(400, "Tell us a bit more");
    if (enjoyed === null && !message && !isCancellation) return errorResponse(400, "Message required");

    const day = utcDayString();
    const [userGate, ipGate] = await Promise.all([
      sb.rpc("increment_insight_rate", { p_app_user_id: identity.key, p_day_utc: day, p_kind: "feedback", p_limit: 20 }),
      sb.rpc("increment_insight_rate", { p_app_user_id: identity.ipHash, p_day_utc: day, p_kind: "board_ip", p_limit: 200 }),
    ]);
    if (userGate.error || ipGate.error) return errorResponse(500, "Rate limit check failed");
    if (userGate.data !== true || ipGate.data !== true) return errorResponse(429, "Too many requests");

    const { error } = await sb.from("feedback_items").insert({
      app_user_id: anonymous ? "anonymous" : (identity.appUserId ?? identity.key),
      user_id: anonymous ? null : identity.userId,
      enjoyed,
      category,
      message: message || (enjoyed === true ? "Enjoying the app" : ""),
      status: "new",
      source,
      is_anonymous: anonymous,
      app_version: cleanText(body.app_version, 24) || null,
      build: cleanText(body.build, 16) || null,
      os_version: cleanText(body.os_version, 16) || null,
      device_class: cleanText(body.device_class, 16) || null,
    });
    if (error) return errorResponse(500, "Failed to save feedback");

    // Named notes open a private Messages thread so the developer can reply. Anonymous notes can't.
    if (!anonymous && enjoyed !== true && message && identity.appUserId) {
      const note = category ? `[${category}] ${message}` : message;
      await sb.from("direct_messages").insert({
        app_user_id: identity.appUserId,
        sender: "user",
        body: note.slice(0, 2000),
      });
    }

    return jsonResponse({ ok: true, can_reply: !anonymous && Boolean(identity.appUserId) });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "Unknown error";
    if (msg.startsWith("Missing required env")) return errorResponse(500, "Server misconfigured");
    return errorResponse(400, "Invalid request");
  }
});
