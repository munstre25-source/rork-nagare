import { corsPreflight, errorResponse, jsonResponse, readJson } from "../_shared/http.ts";
import { requireEnv } from "../_shared/env.ts";
import { requireAdmin } from "../_shared/admin.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { POST_STATUSES } from "../_shared/analytics.ts";

/**
 * Developer dashboard API. Every request needs `x-admin-token` (ADMIN_TOKEN secret).
 * GET  → live aggregates from admin_dashboard_metrics + private inbox + moderation queue.
 * POST → moderation: { action: "post_status" | "post_hold" | "item_status", id, status?, held? }.
 * All numbers come from the database at request time; nothing is cached or hardcoded.
 */
type Body = { action?: string; id?: number; status?: string; held?: boolean };

/** Pseudonymous ids are shortened in the inbox: enough to group notes, not to look anyone up. */
function shortId(value: string | null): string {
  if (!value || value === "anonymous") return "anonymous";
  return value.length > 10 ? `${value.slice(0, 4)}…${value.slice(-4)}` : value;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  try {
    const adminToken = requireEnv("ADMIN_TOKEN");
    if (!requireAdmin(req, adminToken)) return errorResponse(401, "Unauthorized");
    const sb = serviceClient();

    if (req.method === "POST") {
      const body = await readJson<Body>(req);
      const id = Number(body.id);
      if (!Number.isFinite(id) || id <= 0) return errorResponse(400, "Invalid id");
      if (body.action === "post_status") {
        const status = (body.status ?? "").trim();
        if (!POST_STATUSES.has(status)) return errorResponse(400, "Invalid status");
        const { error } = await sb.from("feedback_posts")
          .update({ status, moderated_at: new Date().toISOString(), updated_at: new Date().toISOString() })
          .eq("id", id);
        if (error) return errorResponse(500, "Failed to update");
        return jsonResponse({ ok: true });
      }
      if (body.action === "post_hold") {
        const { error } = await sb.from("feedback_posts")
          .update({ held: body.held === true, moderated_at: new Date().toISOString() })
          .eq("id", id);
        if (error) return errorResponse(500, "Failed to update");
        return jsonResponse({ ok: true });
      }
      if (body.action === "item_status") {
        const status = (body.status ?? "").trim();
        if (!["new", "reviewed", "done"].includes(status)) return errorResponse(400, "Invalid status");
        const { error } = await sb.from("feedback_items").update({ status }).eq("id", id);
        if (error) return errorResponse(500, "Failed to update");
        return jsonResponse({ ok: true });
      }
      return errorResponse(400, "Unknown action");
    }

    if (req.method !== "GET") return errorResponse(405, "Method not allowed");
    const url = new URL(req.url);
    const days = Math.min(Math.max(Number(url.searchParams.get("days") ?? "30") || 30, 1), 365);

    const [metrics, inbox, moderation] = await Promise.all([
      sb.rpc("admin_dashboard_metrics", { p_days: days }),
      sb.from("feedback_items")
        .select("id, app_user_id, enjoyed, category, message, status, source, is_anonymous, app_version, os_version, device_class, created_at")
        .order("created_at", { ascending: false })
        .limit(150),
      sb.from("feedback_posts")
        .select("id, title, body, category, status, vote_count, comment_count, report_count, held, created_at")
        .order("held", { ascending: false })
        .order("report_count", { ascending: false })
        .order("created_at", { ascending: false })
        .limit(150),
    ]);
    if (metrics.error) return errorResponse(500, "Failed to load metrics");

    return jsonResponse({
      metrics: metrics.data,
      inbox: (inbox.data ?? []).map((row) => ({ ...row, app_user_id: shortId(row.app_user_id as string) })),
      moderation: moderation.data ?? [],
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "Unknown error";
    if (msg.startsWith("Missing required env")) return errorResponse(500, "Server misconfigured");
    return errorResponse(400, "Invalid request");
  }
});
