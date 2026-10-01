import { corsPreflight, errorResponse, jsonResponse, readJson } from "../_shared/http.ts";
import { requireEnv, utcDayString } from "../_shared/env.ts";
import { serviceClient } from "../_shared/supabase.ts";

const SOURCES = new Set([
  "instagram",
  "tiktok",
  "web_search",
  "app_store",
  "friend",
  "youtube",
  "other",
]);

type Body = {
  source?: string;
  source_detail?: string | null;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") return errorResponse(405, "Method not allowed");

  try {
    const appUserId = (req.headers.get("x-app-user-id") ?? "").trim();
    if (!appUserId || appUserId.length > 128) {
      return errorResponse(400, "Missing or invalid x-app-user-id");
    }

    const body = await readJson<Body>(req);
    const source = (body.source ?? "").trim().toLowerCase();
    if (!SOURCES.has(source)) {
      return errorResponse(400, "Invalid source");
    }
    const detail = (body.source_detail ?? "").trim().slice(0, 200) || null;

    const sb = serviceClient();
    const { data: allowed, error: rateErr } = await sb.rpc("increment_insight_rate", {
      p_app_user_id: appUserId,
      p_day_utc: utcDayString(),
      p_kind: "acquisition",
      p_limit: 5,
    });
    if (rateErr) return errorResponse(500, "Rate limit check failed");
    if (allowed !== true) return errorResponse(429, "Too many requests");

    const { error } = await sb.from("acquisition_events").upsert(
      {
        app_user_id: appUserId,
        source,
        source_detail: detail,
      },
      { onConflict: "app_user_id" },
    );
    if (error) return errorResponse(500, "Failed to save acquisition");

    return jsonResponse({ ok: true });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "Unknown error";
    if (msg.startsWith("Missing required env")) return errorResponse(500, "Server misconfigured");
    return errorResponse(400, "Invalid request");
  }
});
