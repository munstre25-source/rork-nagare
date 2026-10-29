import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { authedUser } from "./user.ts";
import { resolveIngressIdentity } from "./identity.ts";

export type FeedbackIdentity = {
  /** Stable key for votes, reports and rate limits. Never returned to clients. */
  key: string;
  /** Verified anonymous Supabase user, when the app sent its session. */
  userId: string | null;
  /** Legacy RevenueCat id header (older app builds, and Messages threads). */
  appUserId: string | null;
  ipHash: string;
};

/**
 * Prefers the verified anonymous Supabase session. Older builds only send `x-app-user-id`,
 * which stays accepted so the App Store version keeps working; writes from either path are
 * also rate-limited per IP hash.
 */
export async function feedbackIdentity(req: Request, sb: SupabaseClient): Promise<FeedbackIdentity | null> {
  const ingress = await resolveIngressIdentity(req);
  const header = (req.headers.get("x-app-user-id") ?? "").trim();
  const appUserId = header && header.length <= 128 ? header : null;
  const user = ingress.isAuthenticatedUser ? await authedUser(req, sb) : null;
  if (user) return { key: `u:${user.id}`, userId: user.id, appUserId, ipHash: ingress.ipHash };
  if (appUserId) return { key: appUserId, userId: null, appUserId, ipHash: ingress.ipHash };
  return null;
}
