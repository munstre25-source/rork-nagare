import { corsPreflight, errorResponse, jsonResponse, readJson } from "../_shared/http.ts";
import { requireEnv } from "../_shared/env.ts";
import { requireAdmin } from "../_shared/admin.ts";
import { serviceClient } from "../_shared/supabase.ts";

type PatchBody = {
  id?: number;
  status?: string;
};

type ReplyBody = {
  app_user_id?: string;
  message?: string;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();

  try {
    const adminToken = requireEnv("ADMIN_TOKEN");
    if (!requireAdmin(req, adminToken)) return errorResponse(401, "Unauthorized");

    const sb = serviceClient();

    if (req.method === "POST") {
      const body = await readJson<ReplyBody>(req);
      const appUserId = (body.app_user_id ?? "").trim();
      const message = (body.message ?? "").replace(/\s+/g, " ").trim().slice(0, 2000);
      if (!appUserId || appUserId.length > 128) return errorResponse(400, "Missing user");
      if (!message) return errorResponse(400, "Write a reply");
      const { data, error } = await sb
        .from("direct_messages")
        .insert({ app_user_id: appUserId, sender: "jojo", body: message })
        .select("id, app_user_id, sender, body, created_at")
        .single();
      if (error || !data) return errorResponse(500, "Failed to send reply");
      return jsonResponse({ message: data });
    }

    if (req.method === "PATCH") {
      const body = await readJson<PatchBody>(req);
      const id = Number(body.id);
      const status = (body.status ?? "").trim().toLowerCase();
      if (!Number.isFinite(id) || id <= 0) return errorResponse(400, "Invalid id");
      if (!["new", "reviewed", "done"].includes(status)) {
        return errorResponse(400, "Invalid status");
      }
      const { error } = await sb.from("feedback_items").update({ status }).eq("id", id);
      if (error) return errorResponse(500, "Failed to update");
      return jsonResponse({ ok: true });
    }

    if (req.method !== "GET") return errorResponse(405, "Method not allowed");

    const url = new URL(req.url);
    const limit = Math.min(Number(url.searchParams.get("limit") ?? "100") || 100, 300);
    const statusFilter = (url.searchParams.get("status") ?? "").trim().toLowerCase();

    let feedbackQuery = sb
      .from("feedback_items")
      .select("id, app_user_id, enjoyed, category, message, status, created_at")
      .order("created_at", { ascending: false })
      .limit(limit);
    if (["new", "reviewed", "done"].includes(statusFilter)) {
      feedbackQuery = feedbackQuery.eq("status", statusFilter);
    }

    const [acq, fb, board, notes] = await Promise.all([
      sb.from("acquisition_events").select("source, created_at"),
      feedbackQuery,
      sb.from("feedback_posts")
        .select("id, category, title, body, vote_count, comment_count, status, created_at")
        .order("vote_count", { ascending: false })
        .limit(100),
      sb.from("direct_messages")
        .select("id, app_user_id, sender, body, created_at")
        .order("created_at", { ascending: false })
        .limit(400),
    ]);

    if (acq.error || fb.error) return errorResponse(500, "Failed to load insights");

    const bySource: Record<string, number> = {};
    for (const row of acq.data ?? []) {
      const s = String((row as { source: string }).source);
      bySource[s] = (bySource[s] ?? 0) + 1;
    }

    const feedback = fb.data ?? [];
    const enjoyedYes = feedback.filter((r) => (r as { enjoyed: boolean | null }).enjoyed === true).length;
    const enjoyedNo = feedback.filter((r) => (r as { enjoyed: boolean | null }).enjoyed === false).length;

    return jsonResponse({
      acquisition: {
        total: (acq.data ?? []).length,
        by_source: bySource,
      },
      feedback: {
        total: feedback.length,
        enjoyed_yes: enjoyedYes,
        enjoyed_no: enjoyedNo,
        items: feedback,
      },
      board: {
        items: board.error ? [] : (board.data ?? []),
      },
      messages: notes.error ? [] : (notes.data ?? []),
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "Unknown error";
    if (msg.startsWith("Missing required env")) return errorResponse(500, "Server misconfigured");
    return errorResponse(400, "Invalid request");
  }
});
