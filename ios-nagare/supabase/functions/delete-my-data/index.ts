import { corsPreflight, errorResponse, jsonResponse } from "../_shared/http.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { authedUser } from "../_shared/user.ts";
import { log } from "../_shared/immersion.ts";
import { isUuid } from "../_shared/analytics.ts";

/**
 * Deletes the caller's anonymous Supabase user. Saved vocabulary, practice attempts, and video
 * requests cascade with it (foreign keys on auth.users). Shared lesson clips are not personal
 * data and stay for other requesters. Analytics rows for this user (and the install id the app
 * sends) and private feedback notes linked to the user are deleted too.
 */
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") return errorResponse(405, "Method not allowed");
  const supabase = serviceClient();
  const user = await authedUser(req, supabase);
  if (!user) return errorResponse(401, "Sign-in session required");
  let installId: string | null = null;
  try {
    const body = await req.json() as { install_id?: unknown };
    if (isUuid(body.install_id)) installId = body.install_id.toLowerCase();
  } catch { /* body is optional */ }
  await Promise.all([
    supabase.from("analytics_events").delete().eq("user_id", user.id),
    supabase.from("analytics_sessions").delete().eq("user_id", user.id),
    supabase.from("feedback_items").delete().eq("user_id", user.id),
    ...(installId
      ? [
        supabase.from("analytics_events").delete().eq("install_id", installId),
        supabase.from("analytics_sessions").delete().eq("install_id", installId),
      ]
      : []),
  ]);
  const { error } = await supabase.auth.admin.deleteUser(user.id);
  if (error) {
    log("delete_my_data_failed", { userId: user.id, message: error.message });
    return errorResponse(500, "Could not delete data");
  }
  log("delete_my_data", { userId: user.id });
  return jsonResponse({ deleted: true });
});
