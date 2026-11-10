import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { envInt, utcDayString } from "./env.ts";
import type { RequestIdentity } from "./identity.ts";

export async function tryIncrementExplainRate(
  supabase: SupabaseClient,
  appUserId: string,
  kind: "lookup" | "context",
): Promise<boolean> {
  const limit = kind === "lookup"
    ? envInt("EXPLAIN_LOOKUP_DAILY_LIMIT", 60)
    : envInt("EXPLAIN_CONTEXT_DAILY_LIMIT", 20);
  const { data, error } = await supabase.rpc("increment_explain_rate", {
    p_app_user_id: appUserId,
    p_day_utc: utcDayString(),
    p_kind: kind,
    p_limit: limit,
  });
  if (error) throw error;
  return data === true;
}

export async function tryIncrementGeminiUsage(
  supabase: SupabaseClient,
): Promise<boolean> {
  const limit = envInt("GEMINI_GLOBAL_DAILY_CAP", 2000);
  const { data, error } = await supabase.rpc("increment_gemini_usage", {
    p_day_utc: utcDayString(),
    p_limit: limit,
  });
  if (error) throw error;
  return data === true;
}

export async function tryConsumeYoutubeQuota(
  supabase: SupabaseClient,
  units: number,
): Promise<boolean> {
  const limit = envInt("YOUTUBE_QUOTA_DAILY_CAP", 8000);
  const { data, error } = await supabase.rpc("consume_youtube_quota", {
    p_day_utc: utcDayString(),
    p_units: units,
    p_limit: limit,
  });
  if (error) throw error;
  return data === true;
}

function minuteWindowStart(d = new Date()): string {
  const ms = Math.floor(d.getTime() / 60_000) * 60_000;
  return new Date(ms).toISOString();
}

async function tryIncrementIngressKey(
  supabase: SupabaseClient,
  bucketKey: string,
  limit: number,
): Promise<boolean> {
  const { data, error } = await supabase.rpc("increment_explain_ingress", {
    p_bucket_key: bucketKey,
    p_window_start: minuteWindowStart(),
    p_limit: limit,
  });
  if (error) throw error;
  return data === true;
}

/**
 * Cheap pre-RevenueCat limits: always per-IP; also per-JWT sub when the caller
 * is an authenticated user (shared anon JWT is intentionally not limited by sub,
 * since every client would share one bucket).
 */
export async function tryIncrementExplainIngress(
  supabase: SupabaseClient,
  identity: RequestIdentity,
): Promise<boolean> {
  const ipLimit = envInt("EXPLAIN_INGRESS_IP_PER_MINUTE", 60);
  const underIp = await tryIncrementIngressKey(
    supabase,
    `ip:${identity.ipHash}`,
    ipLimit,
  );
  if (!underIp) return false;

  if (identity.isAuthenticatedUser && identity.jwtSub) {
    const jwtLimit = envInt("EXPLAIN_INGRESS_JWT_PER_MINUTE", 30);
    return await tryIncrementIngressKey(
      supabase,
      `jwt:${identity.jwtSub}`,
      jwtLimit,
    );
  }
  return true;
}
