import { corsPreflight, errorResponse, jsonResponse, readJson } from "../_shared/http.ts";
import { utcDayString } from "../_shared/env.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { authedUser } from "../_shared/user.ts";
import { resolveIngressIdentity } from "../_shared/identity.ts";
import { cleanEvents, cleanSessions, isUuid } from "../_shared/analytics.ts";

/**
 * First-party analytics batches. Identity is a random install ID (pseudonymous); when the caller
 * also sends its anonymous Supabase session, the verified user id is attached. Never stores IPs:
 * the IP hash only feeds a rate-limit bucket.
 */
type Body = { install_id?: string; events?: unknown; sessions?: unknown };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") return errorResponse(405, "Method not allowed");

  try {
    const body = await readJson<Body>(req);
    if (!isUuid(body.install_id)) return errorResponse(400, "Invalid install_id");
    const installId = body.install_id.toLowerCase();
    const events = cleanEvents(body.events);
    const sessions = cleanSessions(body.sessions);
    if (events.length === 0 && sessions.length === 0) return jsonResponse({ accepted: 0 });

    const sb = serviceClient();
    const ingress = await resolveIngressIdentity(req);
    const day = utcDayString();
    const [installGate, ipGate] = await Promise.all([
      sb.rpc("increment_insight_rate", { p_app_user_id: installId, p_day_utc: day, p_kind: "analytics", p_limit: 600 }),
      sb.rpc("increment_insight_rate", { p_app_user_id: ingress.ipHash, p_day_utc: day, p_kind: "analytics_ip", p_limit: 6000 }),
    ]);
    if (installGate.error || ipGate.error) return errorResponse(500, "Rate limit check failed");
    if (installGate.data !== true || ipGate.data !== true) return errorResponse(429, "Too many requests");

    const user = ingress.isAuthenticatedUser ? await authedUser(req, sb) : null;
    const { data, error } = await sb.rpc("analytics_ingest", {
      p_install: installId,
      p_user: user?.id ?? null,
      p_events: events,
      p_sessions: sessions,
    });
    if (error) return errorResponse(500, "Ingest failed");
    // Client ids that were sent are acknowledged even when they were duplicates or dropped
    // by validation, so the queue never retries a poison event forever.
    return jsonResponse({ accepted: data ?? 0, received: events.length, sessions: sessions.length });
  } catch {
    return errorResponse(400, "Invalid request");
  }
});
