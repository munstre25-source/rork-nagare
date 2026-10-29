import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export type AuthedUser = { id: string; isAnonymous: boolean };

/**
 * Verifies the caller's Supabase access token (anonymous sessions included) with the Auth server.
 * Returns null for the shared anon key, expired tokens, or deleted users.
 */
export async function authedUser(req: Request, supabase: SupabaseClient): Promise<AuthedUser | null> {
  const header = req.headers.get("authorization") ?? "";
  if (!header.toLowerCase().startsWith("bearer ")) return null;
  const token = header.slice(7).trim();
  if (token.split(".").length !== 3) return null;
  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data.user) return null;
  return { id: data.user.id, isAnonymous: data.user.is_anonymous === true };
}
