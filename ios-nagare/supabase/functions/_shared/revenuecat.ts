import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { CatalogLanguage } from "./catalog.ts";
import { envInt, envOr, requireEnv } from "./env.ts";

const JAPANESE_ENTITLEMENT_ID = "nagare_learn_japanese_pro";
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
  language: CatalogLanguage = "ja",
): Promise<boolean> {
  const ttlSec = envInt("REVENUECAT_CACHE_TTL_SEC", 300);
  const cacheId = language === "ko" ? `ko:${appUserId}` : appUserId;
  const { data: cached } = await supabase
    .from("revenuecat_entitlement_cache")
    .select("entitled, checked_at")
    .eq("app_user_id", cacheId)
    .maybeSingle();

  if (cached) {
    const row = cached as CacheRow;
    const ageMs = Date.now() - new Date(row.checked_at).getTime();
    if (ageMs >= 0 && ageMs < ttlSec * 1000) {
      // Cache hit for entitled === true OR false.
      return row.entitled;
    }
  }

  const soriSecret = Deno.env.get("SORI_REVENUECAT_SECRET_API_KEY")?.trim() ?? "";
  const secret = language === "ko" && soriSecret !== ""
    ? soriSecret
    : requireEnv("REVENUECAT_SECRET_API_KEY");
  const entitlementId = language === "ko"
    ? envOr("SORI_ENTITLEMENT_ID", "sori_pro")
    : JAPANESE_ENTITLEMENT_ID;
  const productIds = language === "ko"
    ? envOr(
      "SORI_PRODUCT_IDS",
      "socialreporthq.supportlog.monthly,socialreporthq.supportlog.annual",
    ).split(",").map((id) => id.trim()).filter((id) => id !== "")
    : [];
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
          subscriptions?: Record<string, { expires_date?: string | null }>;
        };
      };
      const ent = body.subscriber?.entitlements?.[entitlementId];
      entitled = ent !== undefined && isCurrent(ent.expires_date);
      if (!entitled && productIds.length > 0) {
        const subscriptions = body.subscriber?.subscriptions ?? {};
        entitled = productIds.some((id) =>
          subscriptions[id] !== undefined && isCurrent(subscriptions[id].expires_date)
        );
      }
    }
  } catch {
    entitled = false;
  } finally {
    clearTimeout(timer);
  }

  // Persist negative results too (unentitled / RC errors) for the TTL window.
  await supabase.from("revenuecat_entitlement_cache").upsert({
    app_user_id: cacheId,
    entitled,
    checked_at: new Date().toISOString(),
  });

  return entitled;
}

function isCurrent(expires: string | null | undefined): boolean {
  if (!expires) return true;
  return new Date(expires).getTime() > Date.now();
}
