import { corsPreflight, errorResponse, jsonResponse, readJson } from "../_shared/http.ts";
import { requireEnv, utcDayString } from "../_shared/env.ts";
import { serviceClient } from "../_shared/supabase.ts";

const CATEGORIES = new Set(["bug", "feature", "general"]);

type Body = {
  action?: string;
  id?: number;
  category?: string;
  title?: string;
  body?: string;
};

type PostRow = {
  id: number;
  category: string;
  title: string;
  body: string;
  vote_count: number;
  comment_count: number;
  created_at: string;
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
    vote_count: row.vote_count,
    comment_count: row.comment_count,
    created_at: stamp(row.created_at),
    voted,
  };
}

function clean(value: string, max: number): string {
  return value.replace(/\s+/g, " ").trim().slice(0, max);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();

  try {
    requireEnv("SUPABASE_URL");
    const appUserId = (req.headers.get("x-app-user-id") ?? "").trim();
    if (!appUserId || appUserId.length > 128) {
      return errorResponse(400, "Missing or invalid x-app-user-id");
    }

    const sb = serviceClient();

    if (req.method === "GET") {
      const url = new URL(req.url);
      const postId = Number(url.searchParams.get("id") ?? "");
      if (Number.isFinite(postId) && postId > 0) {
        const { data: post, error } = await sb
          .from("feedback_posts")
          .select("id, category, title, body, vote_count, comment_count, created_at, status")
          .eq("id", postId)
          .maybeSingle();
        if (error || !post || post.status === "hidden") return errorResponse(404, "Not found");
        const [{ data: comments }, { data: vote }] = await Promise.all([
          sb.from("feedback_comments")
            .select("id, body, created_at")
            .eq("post_id", postId)
            .order("created_at", { ascending: true })
            .limit(100),
          sb.from("feedback_votes")
            .select("post_id")
            .eq("post_id", postId)
            .eq("app_user_id", appUserId)
            .maybeSingle(),
        ]);
        return jsonResponse({
          post: publicPost(post as PostRow, Boolean(vote)),
          comments: (comments ?? []).map((row) => ({
            id: row.id,
            body: row.body,
            created_at: stamp(row.created_at),
          })),
        });
      }

      const { data, error } = await sb
        .from("feedback_posts")
        .select("id, category, title, body, vote_count, comment_count, created_at")
        .neq("status", "hidden")
        .order("vote_count", { ascending: false })
        .order("created_at", { ascending: false })
        .limit(80);
      if (error) return errorResponse(500, "Failed to load board");
      const rows = (data ?? []) as PostRow[];
      const ids = rows.map((row) => row.id);
      const voted = new Set<number>();
      if (ids.length > 0) {
        const { data: votes } = await sb
          .from("feedback_votes")
          .select("post_id")
          .eq("app_user_id", appUserId)
          .in("post_id", ids);
        for (const vote of votes ?? []) voted.add(vote.post_id as number);
      }
      return jsonResponse({ posts: rows.map((row) => publicPost(row, voted.has(row.id))) });
    }

    if (req.method !== "POST") return errorResponse(405, "Method not allowed");

    const body = await readJson<Body>(req);
    const action = (body.action ?? "").trim().toLowerCase();

    const { data: allowed, error: rateErr } = await sb.rpc("increment_insight_rate", {
      p_app_user_id: appUserId,
      p_day_utc: utcDayString(),
      p_kind: "board",
      p_limit: 40,
    });
    if (rateErr) return errorResponse(500, "Rate limit check failed");
    if (allowed !== true) return errorResponse(429, "Too many requests");

    if (action === "create") {
      const category = (body.category ?? "").trim().toLowerCase();
      const text = clean(body.body ?? "", 1000);
      const title = clean(body.title ?? "", 80) || clean(text, 80);
      if (!CATEGORIES.has(category)) return errorResponse(400, "Pick bug, feature, or general");
      if (!text || !title) return errorResponse(400, "Tell us what you want");
      const { data, error } = await sb
        .from("feedback_posts")
        .insert({
          app_user_id: appUserId,
          category,
          title,
          body: text,
          status: "open",
        })
        .select("id, category, title, body, vote_count, comment_count, created_at")
        .single();
      if (error || !data) return errorResponse(500, "Failed to post");
      return jsonResponse({ post: publicPost(data as PostRow, false) });
    }

    const postId = Number(body.id);
    if (!Number.isFinite(postId) || postId <= 0) return errorResponse(400, "Invalid id");

    if (action === "vote") {
      const { data: existing } = await sb
        .from("feedback_votes")
        .select("post_id")
        .eq("post_id", postId)
        .eq("app_user_id", appUserId)
        .maybeSingle();
      if (existing) {
        const { error } = await sb
          .from("feedback_votes")
          .delete()
          .eq("post_id", postId)
          .eq("app_user_id", appUserId);
        if (error) return errorResponse(500, "Failed to update vote");
      } else {
        const { error } = await sb.from("feedback_votes").insert({
          post_id: postId,
          app_user_id: appUserId,
        });
        if (error) return errorResponse(500, "Failed to update vote");
      }
      const { count, error: countErr } = await sb
        .from("feedback_votes")
        .select("post_id", { count: "exact", head: true })
        .eq("post_id", postId);
      if (countErr || count == null) return errorResponse(500, "Failed to count votes");
      const { error: updateErr } = await sb
        .from("feedback_posts")
        .update({ vote_count: count })
        .eq("id", postId)
        .neq("status", "hidden");
      if (updateErr) return errorResponse(500, "Failed to update vote");
      return jsonResponse({ vote_count: count, voted: !existing });
    }

    if (action === "comment") {
      const text = clean(body.body ?? "", 500);
      if (!text) return errorResponse(400, "Write a comment");
      const { data: post } = await sb
        .from("feedback_posts")
        .select("id")
        .eq("id", postId)
        .neq("status", "hidden")
        .maybeSingle();
      if (!post) return errorResponse(404, "Not found");
      const { data, error } = await sb
        .from("feedback_comments")
        .insert({ post_id: postId, app_user_id: appUserId, body: text })
        .select("id, body, created_at")
        .single();
      if (error || !data) return errorResponse(500, "Failed to comment");
      const { count } = await sb
        .from("feedback_comments")
        .select("id", { count: "exact", head: true })
        .eq("post_id", postId);
      if (count != null) {
        await sb.from("feedback_posts").update({ comment_count: count }).eq("id", postId);
      }
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
