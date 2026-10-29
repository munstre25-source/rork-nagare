import { corsPreflight, errorResponse, jsonResponse, readJson } from "../_shared/http.ts";
import { requireEnv, utcDayString } from "../_shared/env.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { feedbackIdentity } from "../_shared/feedback.ts";
import { BOARD_SORTS, cleanSearch, cleanText, REPORT_REASONS } from "../_shared/analytics.ts";
import { filterMessage, screenPublicText } from "../_shared/moderation.ts";

/**
 * Public feature-request board. Responses never include author ids, voter ids or IPs.
 * Votes, counts, reports and moderation all run in SQL functions with the service role.
 */
const CATEGORIES = new Set(["bug", "feature", "general"]);
const PAGE = 20;

type Body = {
  action?: string;
  id?: number;
  category?: string;
  title?: string;
  body?: string;
  reason?: string;
  comment_id?: number;
};

type PostRow = {
  id: number;
  category: string;
  title: string;
  body: string;
  status: string;
  vote_count: number;
  comment_count: number;
  created_at: string;
  voted?: boolean;
};

function stamp(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}

function publicPost(row: PostRow, voted: boolean) {
  return {
    id: row.id,
    category: row.category,
    title: row.title,
    body: row.body,
    status: row.status === "open" ? "under_review" : row.status,
    vote_count: row.vote_count,
    comment_count: row.comment_count,
    created_at: stamp(row.created_at),
    voted,
  };
}

async function blockedAuthors(sb: ReturnType<typeof serviceClient>, viewer: string): Promise<Set<string>> {
  const { data } = await sb.from("feedback_blocks").select("blocked_author").eq("blocker", viewer).limit(500);
  return new Set((data ?? []).map((row: { blocked_author: string }) => row.blocked_author));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();

  try {
    requireEnv("SUPABASE_URL");
    const sb = serviceClient();
    const identity = await feedbackIdentity(req, sb);
    if (!identity) return errorResponse(400, "Missing identity");

    if (req.method === "GET") {
      const url = new URL(req.url);
      const postId = Number(url.searchParams.get("id") ?? "");
      if (Number.isFinite(postId) && postId > 0) {
        const { data: post, error } = await sb
          .from("feedback_posts")
          .select("id, category, title, body, status, vote_count, comment_count, created_at, held, app_user_id")
          .eq("id", postId)
          .maybeSingle();
        if (error || !post || post.status === "hidden" || post.held) return errorResponse(404, "Not found");
        const blocked = await blockedAuthors(sb, identity.key);
        if (blocked.has(post.app_user_id)) return errorResponse(404, "Not found");
        const [{ data: comments }, { data: vote }] = await Promise.all([
          sb.from("feedback_comments")
            .select("id, body, created_at, app_user_id")
            .eq("post_id", postId)
            .eq("hidden", false)
            .order("created_at", { ascending: true })
            .limit(100),
          sb.from("feedback_votes")
            .select("post_id")
            .eq("post_id", postId)
            .eq("app_user_id", identity.key)
            .maybeSingle(),
        ]);
        return jsonResponse({
          post: publicPost(post as PostRow, Boolean(vote)),
          comments: (comments ?? [])
            .filter((row) => !blocked.has(row.app_user_id))
            .map((row) => ({ id: row.id, body: row.body, created_at: stamp(row.created_at) })),
        });
      }

      // Older builds send no paging params and expect the top 80 in one response.
      const legacy = !url.searchParams.has("sort") && !url.searchParams.has("offset");
      const sortParam = url.searchParams.get("sort") ?? "top";
      const sort = BOARD_SORTS.has(sortParam) ? sortParam : "top";
      const offset = Math.max(0, Number(url.searchParams.get("offset") ?? "0") || 0);
      const limit = legacy ? 50 : PAGE;
      const { data, error } = await sb.rpc("feedback_board_page", {
        p_viewer: identity.key,
        p_sort: sort,
        p_search: cleanSearch(url.searchParams.get("q")),
        p_limit: limit + 1,
        p_offset: offset,
      });
      if (error) return errorResponse(500, "Failed to load board");
      const rows = (data ?? []) as PostRow[];
      const page = rows.slice(0, limit);
      let visible = page;
      const blocked = await blockedAuthors(sb, identity.key);
      if (blocked.size > 0 && page.length > 0) {
        const { data: authors } = await sb.from("feedback_posts").select("id, app_user_id").in("id", page.map((r) => r.id));
        const hiddenIds = new Set(
          (authors ?? []).filter((a: { app_user_id: string }) => blocked.has(a.app_user_id)).map((a: { id: number }) => a.id),
        );
        visible = page.filter((row) => !hiddenIds.has(row.id));
      }
      return jsonResponse({
        posts: visible.map((row) => publicPost(row, row.voted === true)),
        has_more: rows.length > limit,
        next_offset: offset + page.length,
      });
    }

    if (req.method !== "POST") return errorResponse(405, "Method not allowed");

    const body = await readJson<Body>(req);
    const action = (body.action ?? "").trim().toLowerCase();

    const day = utcDayString();
    const [userGate, ipGate] = await Promise.all([
      sb.rpc("increment_insight_rate", { p_app_user_id: identity.key, p_day_utc: day, p_kind: "board", p_limit: 60 }),
      sb.rpc("increment_insight_rate", { p_app_user_id: identity.ipHash, p_day_utc: day, p_kind: "board_ip", p_limit: 200 }),
    ]);
    if (userGate.error || ipGate.error) return errorResponse(500, "Rate limit check failed");
    if (userGate.data !== true || ipGate.data !== true) return errorResponse(429, "Too many requests");

    if (action === "create") {
      const category = (body.category ?? "").trim().toLowerCase();
      const text = cleanText(body.body, 1000);
      const title = cleanText(body.title, 80) || cleanText(text, 80);
      if (!CATEGORIES.has(category)) return errorResponse(400, "Pick bug, feature, or general");
      if (!text || !title) return errorResponse(400, "Tell us what you want");
      const screen = screenPublicText(`${title}\n${text}`);
      if (!screen.ok) return errorResponse(422, filterMessage(screen.reason));
      const { data, error } = await sb
        .from("feedback_posts")
        .insert({ app_user_id: identity.key, category, title, body: text, status: "under_review" })
        .select("id, category, title, body, status, vote_count, comment_count, created_at")
        .single();
      if (error || !data) return errorResponse(500, "Failed to post");
      return jsonResponse({ post: publicPost(data as PostRow, false) });
    }

    if (action === "report_comment" || action === "block") {
      const commentId = Number(body.comment_id);
      const hasComment = Number.isFinite(commentId) && commentId > 0;
      if (action === "report_comment") {
        if (!hasComment) return errorResponse(400, "Invalid id");
        const reason = REPORT_REASONS.has(body.reason ?? "") ? body.reason! : "other";
        const { data: reportGate } = await sb.rpc("increment_insight_rate", {
          p_app_user_id: identity.key, p_day_utc: day, p_kind: "report", p_limit: 15,
        });
        if (reportGate !== true) return errorResponse(429, "Too many reports today");
        const { error } = await sb.rpc("feedback_report_comment", { p_comment: commentId, p_reporter: identity.key, p_reason: reason });
        if (error) return errorResponse(500, "Failed to report");
        return jsonResponse({ reported: true });
      }
      // Block the author of a post or comment. The author id never leaves the server.
      const targetId = hasComment ? commentId : Number(body.id);
      if (!Number.isFinite(targetId) || targetId <= 0) return errorResponse(400, "Invalid id");
      const { data: target } = await sb
        .from(hasComment ? "feedback_comments" : "feedback_posts")
        .select("app_user_id")
        .eq("id", targetId)
        .maybeSingle();
      if (!target) return errorResponse(404, "Not found");
      if (target.app_user_id === identity.key) return errorResponse(400, "That's your own post");
      const { error } = await sb
        .from("feedback_blocks")
        .upsert({ blocker: identity.key, blocked_author: target.app_user_id }, { onConflict: "blocker,blocked_author" });
      if (error) return errorResponse(500, "Failed to block");
      return jsonResponse({ blocked: true });
    }

    const postId = Number(body.id);
    if (!Number.isFinite(postId) || postId <= 0) return errorResponse(400, "Invalid id");

    if (action === "vote") {
      const { data, error } = await sb.rpc("feedback_toggle_vote", { p_post: postId, p_voter: identity.key });
      if (error) return errorResponse(error.code === "P0002" ? 404 : 500, "Failed to update vote");
      const row = (Array.isArray(data) ? data[0] : data) as { vote_count: number; voted: boolean } | undefined;
      if (!row) return errorResponse(500, "Failed to update vote");
      return jsonResponse({ vote_count: row.vote_count, voted: row.voted });
    }

    if (action === "report") {
      const reason = REPORT_REASONS.has(body.reason ?? "") ? body.reason! : "other";
      const { data: reportGate } = await sb.rpc("increment_insight_rate", {
        p_app_user_id: identity.key, p_day_utc: day, p_kind: "report", p_limit: 15,
      });
      if (reportGate !== true) return errorResponse(429, "Too many reports today");
      const { error } = await sb.rpc("feedback_report_post", { p_post: postId, p_reporter: identity.key, p_reason: reason });
      if (error) return errorResponse(500, "Failed to report");
      return jsonResponse({ reported: true });
    }

    if (action === "comment") {
      const text = cleanText(body.body, 500);
      if (!text) return errorResponse(400, "Write a comment");
      const screen = screenPublicText(text);
      if (!screen.ok) return errorResponse(422, filterMessage(screen.reason));
      const { data: post } = await sb
        .from("feedback_posts")
        .select("id")
        .eq("id", postId)
        .neq("status", "hidden")
        .eq("held", false)
        .maybeSingle();
      if (!post) return errorResponse(404, "Not found");
      const { data, error } = await sb
        .from("feedback_comments")
        .insert({ post_id: postId, app_user_id: identity.key, body: text })
        .select("id, body, created_at")
        .single();
      if (error || !data) return errorResponse(500, "Failed to comment");
      const { count } = await sb
        .from("feedback_comments")
        .select("id", { count: "exact", head: true })
        .eq("post_id", postId);
      if (count != null) await sb.from("feedback_posts").update({ comment_count: count }).eq("id", postId);
      return jsonResponse({
        comment: { id: data.id, body: data.body, created_at: stamp(data.created_at) },
        comment_count: count ?? 0,
      });
    }

    return errorResponse(400, "Unknown action");
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    if (message.startsWith("Missing required env")) return errorResponse(500, "Server misconfigured");
    return errorResponse(400, "Invalid request");
  }
});
