import { cookies } from "next/headers";

export const HQ_ACCESS_COOKIE = "socialreporthq_hq_access";

/** Prefer `HQ_ACCESS_TOKEN1` (Vercel), fall back to `HQ_ACCESS_TOKEN`. */
export function getHQAccessToken(): string | undefined {
  const primary = process.env.HQ_ACCESS_TOKEN1?.trim();
  if (primary) return primary;
  const fallback = process.env.HQ_ACCESS_TOKEN?.trim();
  return fallback || undefined;
}

/** True when the request carries a valid HQ unlock cookie. */
export async function hasHQAccess(): Promise<boolean> {
  const configured = getHQAccessToken();
  if (!configured) return false;
  const cookieStore = await cookies();
  return cookieStore.get(HQ_ACCESS_COOKIE)?.value === configured;
}

export function jojoInsightsConfig() {
  const supabaseUrl = (process.env.JOJO_SUPABASE_URL ?? "").trim().replace(/\/+$/, "");
  const anonKey = (process.env.JOJO_SUPABASE_ANON_KEY ?? "").trim();
  const adminToken = (process.env.JOJO_ADMIN_TOKEN ?? process.env.ADMIN_TOKEN ?? "").trim();
  return {
    supabaseUrl,
    anonKey,
    adminToken,
    configured: Boolean(supabaseUrl && anonKey && adminToken),
  };
}
