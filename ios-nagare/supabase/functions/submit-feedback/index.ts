import { corsPreflight, errorResponse, jsonResponse, readJson } from "../_shared/http.ts";
import { requireEnv, utcDayString } from "../_shared/env.ts";
import { serviceClient } from "../_shared/supabase.ts";

const CATEGORIES = new Set([
  "bug",
  "feature",
  "general",
  "cancel_price",
  "cancel_time",
  "cancel_content",
  "cancel_hard",
  "cancel_curious",
  "cancel_other",
]);

type Body = {
  enjoyed?: boolean | null;
  category?: string | null;
  message?: string;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") return errorResponse(405, "Method not allowed");

  try {
    requireEnv("SUPABASE_URL");
    const appUserId = (req.headers.get("x-app-user-id") ?? "").trim();
    if (!appUserId || appUserId.length > 128) {
      return errorResponse(400, "Missing or invalid x-app-user-id");
    }

    const body = await readJson<Body>(req);
    const enjoyed = typeof body.enjoyed === "boolean" ? body.enjoyed : null;
    const categoryRaw = (body.category ?? "").trim().toLowerCase();
    const category = categoryRaw && CATEGORIES.has(categoryRaw) ? categoryRaw : null;
    const message = (body.message ?? "").trim().slice(0, 2000);

    // Positive "yes I'm enjoying" can be empty message; negative / cancellation needs text or category.
    const isCancellation = category?.startsWith("cancel_") === true;
    if (enjoyed === false && !message && !category) {
      return errorResponse(400, "Tell us a bit more");
    }
    if (enjoyed === null && !message && !isCancellation) {
      return errorResponse(400, "Message required");
    }

    const sb = serviceClient();
    const { data: allowed, error: rateErr } = await sb.rpc("increment_insight_rate", {
      p_app_user_id: appUserId,
      p_day_utc: utcDayString(),
      p_kind: "feedback",
      p_limit: 20,
    });
    if (rateErr) return errorResponse(500, "Rate limit check failed");
    if (allowed !== true) return errorResponse(429, "Too many requests");

    const { error } = await sb.from("feedback_items").insert({
      app_user_id: appUserId,
      enjoyed,
      category,
      message: message || (enjoyed === true ? "Enjoying the app" : ""),
      status: "new",
    });
    if (error) return errorResponse(500, "Failed to save feedback");

    return jsonResponse({ ok: true });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "Unknown error";
    if (msg.startsWith("Missing required env")) return errorResponse(500, "Server misconfigured");
    return errorResponse(400, "Invalid request");
  }
});
