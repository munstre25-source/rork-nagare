import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { requireEnv } from "./env.ts";
import { sha1Hex } from "./supabase.ts";

export type RequestIdentity = {
  ipHash: string;
  /** JWT `sub` when present; null if missing/unparseable. */
  jwtSub: string | null;
  /** True when JWT role is authenticated (not the shared anon key). */
  isAuthenticatedUser: boolean;
  /**
   * Trusted RevenueCat app user id from app_metadata when present.
   * Only set after `loadBoundRcAppUserId` for authenticated users.
   */
  boundRcAppUserId: string | null;
};

function clientIp(req: Request): string {
  const cf = req.headers.get("cf-connecting-ip")?.trim();
  if (cf) return cf;
  const xff = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  if (xff) return xff;
  const real = req.headers.get("x-real-ip")?.trim();
  if (real) return real;
  return "unknown";
}

/** Decode JWT payload without verifying signature (cheap rate-limit / role peek only). */
export function peekJwtPayload(authHeader: string | null): Record<string, unknown> | null {
  if (!authHeader?.toLowerCase().startsWith("bearer ")) return null;
  const token = authHeader.slice(7).trim();
  const parts = token.split(".");
  if (parts.length < 2) return null;
  try {
    const json = atob(parts[1]!.replace(/-/g, "+").replace(/_/g, "/"));
    return JSON.parse(json) as Record<string, unknown>;
  } catch {
    return null;
  }
}

/** Cheap identity (no network): IP hash + JWT peek for ingress rate limiting. */
export async function resolveIngressIdentity(req: Request): Promise<RequestIdentity> {
  const ipHash = await sha1Hex(clientIp(req));
  const peeked = peekJwtPayload(req.headers.get("authorization"));
  const jwtSub = typeof peeked?.sub === "string" ? peeked.sub : null;
  const role = typeof peeked?.role === "string" ? peeked.role : null;
  const isAuthenticatedUser = role === "authenticated" && !!jwtSub;
  return { ipHash, jwtSub, isAuthenticatedUser, boundRcAppUserId: null };
}

/**
 * Load trusted RC id from app_metadata for an authenticated user JWT.
 * Call only after ingress rate limiting.
 */
export async function loadBoundRcAppUserId(req: Request, identity: RequestIdentity): Promise<string | null> {
  if (!identity.isAuthenticatedUser) return null;
  const authHeader = req.headers.get("authorization");
  if (!authHeader?.toLowerCase().startsWith("bearer ")) return null;
  const token = authHeader.slice(7).trim();
  const url = requireEnv("SUPABASE_URL");
  const anon = requireEnv("SUPABASE_ANON_KEY");
  const userClient = createClient(url, anon, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data } = await userClient.auth.getUser();
  const meta = data.user?.app_metadata as Record<string, unknown> | undefined;
  const linked = meta?.revenuecat_app_user_id;
  return typeof linked === "string" && linked.trim() ? linked.trim() : null;
}

/**
 * When the JWT is an authenticated user with a linked RC id, require header match.
 * When authenticated but not linked yet → 403.
 * When using the shared anon key → no bind (rely on ingress IP limits).
 */
export function assertAppUserIdBinding(
  headerAppUserId: string,
  identity: RequestIdentity,
): { ok: true } | { ok: false; status: number; message: string } {
  if (!identity.isAuthenticatedUser) {
    return { ok: true };
  }
  if (!identity.boundRcAppUserId) {
    return {
      ok: false,
      status: 403,
      message: "RevenueCat identity not linked to Supabase user",
    };
  }
  if (identity.boundRcAppUserId !== headerAppUserId) {
    return {
      ok: false,
      status: 403,
      message: "x-app-user-id does not match authenticated user",
    };
  }
  return { ok: true };
}
