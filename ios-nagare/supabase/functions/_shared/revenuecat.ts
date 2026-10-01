import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { envInt, requireEnv } from "./env.ts";

const ENTITLEMENT_ID = "nagare_learn_japanese_pro";
const RC_TIMEOUT_MS = 2000;

type CacheRow = { entitled: boolean; checked_at: string };

/**
 * Check RevenueCat pro entitlement with a short DB-backed cache.
 * Both positive and negative results are cached for REVENUECAT_CACHE_TTL_SEC
 * (default 300s) so random / unentitled x-app-user-id values cannot flood RC.
 * Never logs the secret API key.
 */
export async function hasProEntitlement(
  supabase: SupabaseClient,
  appUserId: string,
): Promise<boolean> {
  const ttlSec = envInt("REVENUECAT_CACHE_TTL_SEC", 300);
  const { data: cached } = await supabase
    .from("revenuecat_entitlement_cache")
    .select("entitled, checked_at")
    .eq("app_user_id", appUserId)
    .maybeSingle();

  if (cached) {
    const row = cached as CacheRow;
    const ageMs = Date.now() - new Date(row.checked_at).getTime();
    if (ageMs >= 0 && ageMs < ttlSec * 1000) {
      // Cache hit for entitled === true OR false.
      return row.entitled;
    }
  }

  const secret = requireEnv("REVENUECAT_SECRET_API_KEY");
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), RC_TIMEOUT_MS);
  let entitled = false;
  try {
    const url =
      `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(appUserId)}`;
    const res = await fetch(url, {
      headers: {
        Authorization: `Bearer ${secret}`,
        "Content-Type": "application/json",
      },
      signal: controller.signal,
    });
    if (!res.ok) {
      entitled = false;
    } else {
      const body = await res.json() as {
        subscriber?: {
          entitlements?: Record<string, { expires_date?: string | null }>;
        };
      };
      const ent = body.subscriber?.entitlements?.[ENTITLEMENT_ID];
      if (ent) {
        if (!ent.expires_date) {
          entitled = true;
        } else {
          entitled = new Date(ent.expires_date).getTime() > Date.now();
        }
      }
    }
  } catch {
    entitled = false;
  } finally {
    clearTimeout(timer);
  }

  // Persist negative results too (unentitled / RC errors) for the TTL window.
  await supabase.from("revenuecat_entitlement_cache").upsert({
    app_user_id: appUserId,
    entitled,
    checked_at: new Date().toISOString(),
  });

  return entitled;
}
