import { corsPreflight, errorResponse, jsonResponse, readJson } from "../_shared/http.ts";
import { requireEnv, utcDayString } from "../_shared/env.ts";
import { serviceClient } from "../_shared/supabase.ts";

type Body = { body?: string };

type Row = { id: number; sender: string; body: string; created_at: string };

function stamp(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}

function publicMessage(row: Row) {
  return {
    id: row.id,
    sender: row.sender,
    body: row.body,
    created_at: stamp(row.created_at),
  };
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
    const environment = req.headers.get("x-jojo-environment") === "production" ? "production" : "test";

    if (req.method === "GET") {
      const { data, error } = await sb
        .from("direct_messages")
        .select("id, sender, body, created_at")
        .eq("app_user_id", appUserId)
        .order("created_at", { ascending: true })
        .limit(200);
      if (error) return errorResponse(500, "Failed to load messages");
      return jsonResponse({ messages: ((data ?? []) as Row[]).map(publicMessage) });
    }

    if (req.method !== "POST") return errorResponse(405, "Method not allowed");

    const body = await readJson<Body>(req);
    const text = (body.body ?? "").replace(/\s+/g, " ").trim().slice(0, 2000);
    if (!text) return errorResponse(400, "Write a message");

    const { data: allowed, error: rateErr } = await sb.rpc("increment_insight_rate", {
      p_app_user_id: appUserId,
      p_day_utc: utcDayString(),
      p_kind: "inbox",
      p_limit: 40,
    });
    if (rateErr) return errorResponse(500, "Rate limit check failed");
    if (allowed !== true) return errorResponse(429, "Too many requests");

    const { data, error } = await sb
      .from("direct_messages")
      .insert({ app_user_id: appUserId, sender: "user", body: text, environment })
      .select("id, sender, body, created_at")
      .single();
    if (error || !data) return errorResponse(500, "Failed to send");
    return jsonResponse({ message: publicMessage(data as Row) });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    if (message.startsWith("Missing required env")) return errorResponse(500, "Server misconfigured");
    return errorResponse(400, "Invalid request");
  }
});
