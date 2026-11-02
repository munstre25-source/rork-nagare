import { corsPreflight, errorResponse, jsonResponse } from "../_shared/http.ts";
import { isAdminOrCron } from "../_shared/admin.ts";
import { serviceClient } from "../_shared/supabase.ts";
export async function handler(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return corsPreflight();
  if (!isAdminOrCron(req)) return errorResponse(401, "Unauthorized");
  if (req.method !== "GET") return errorResponse(405, "Method not allowed");
  const q = new URL(req.url).searchParams;
  const end = q.has("to") ? new Date(q.get("to")!) : new Date();
  const start = q.has("from") ? new Date(q.get("from")!) : new Date(end.getTime() - 30 * 86400000);
  const view = q.get("view") ?? "live";
  const page = Number(q.get("page") ?? 0);
  if (!Number.isFinite(start.getTime()) || !Number.isFinite(end.getTime()) || start >= end || end.getTime()-start.getTime()>366*86400000 ||
    !Number.isInteger(page) || page<0 || page>100000 || !["live","drafts","queued","attempts","publications","rejections","jobs"].includes(view)) return errorResponse(400, "Invalid pipeline filters");
  const { data, error } = await serviceClient().rpc("admin_catalog_pipeline", {
    p_from: start.toISOString(), p_to: end.toISOString(), p_view: view,
    p_status: (q.get("status") ?? "").slice(0,50), p_search: (q.get("search") ?? "").trim().slice(0,200), p_page: page,
  });
  if (error) return errorResponse(500, "Pipeline data unavailable");
  return jsonResponse(data);
}
if (import.meta.main) Deno.serve(handler);
