import { isAdminOrCron } from "../_shared/admin.ts";
import { catalogTable, type CatalogLanguage } from "../_shared/catalog.ts";
import { requireEnv } from "../_shared/env.ts";
import { errorResponse, jsonResponse } from "../_shared/http.ts";
import { tryConsumeYoutubeQuota } from "../_shared/limits.ts";
import { serviceClient } from "../_shared/supabase.ts";

const YOUTUBE_BATCH_SIZE = 50;
const DB_PAGE_SIZE = 500;
type ClipRow = { id: string; video_id: string };

/** Check YouTube's current embed setting; unpublish only confirmed blocked videos. */
Deno.serve(async (req) => {
  if (req.method !== "POST") return errorResponse(405, "Method not allowed");

  try {
    requireEnv("ADMIN_TOKEN");
    if (!isAdminOrCron(req)) return errorResponse(401, "Unauthorized");
    const youtubeKey = requireEnv("YOUTUBE_API_KEY");
    const supabase = serviceClient();
    const summary = { checked: 0, unpublished: 0, quotaLimited: false, errors: [] as string[] };

    for (const language of ["ja", "ko"] as CatalogLanguage[]) {
      const table = catalogTable(language);
      let offset = 0;
      const allRows: ClipRow[] = [];
      while (true) {
        const { data, error } = await supabase
          .from(table).select("id,video_id").eq("published", true)
          .order("id").range(offset, offset + DB_PAGE_SIZE - 1);
        if (error) throw new Error(`Catalog read failed (${language})`);
        const rows = (data ?? []) as ClipRow[];
        if (rows.length === 0) break;
        allRows.push(...rows);
        offset += rows.length;
        if (rows.length < DB_PAGE_SIZE) break;
      }

      for (let start = 0; start < allRows.length; start += YOUTUBE_BATCH_SIZE) {
        const valid = allRows.slice(start, start + YOUTUBE_BATCH_SIZE)
          .filter((row) => /^[A-Za-z0-9_-]{11}$/.test(row.video_id));
        if (valid.length === 0) continue;
        if (!(await tryConsumeYoutubeQuota(supabase, 1))) {
          summary.quotaLimited = true;
          return jsonResponse(summary);
        }

        const params = new URLSearchParams({ part: "status", id: valid.map((r) => r.video_id).join(","), key: youtubeKey });
        const response = await fetch(`https://www.googleapis.com/youtube/v3/videos?${params}`);
        if (!response.ok) {
          summary.errors.push(`YouTube check failed (${language}, HTTP ${response.status})`);
          continue;
        }
        const result = await response.json() as { items?: Array<{ id: string; status?: { embeddable?: boolean } }> };
        const statuses = new Map((result.items ?? []).map((item) => [item.id, item.status?.embeddable]));
        // A successful videos.list response omits deleted, private, or otherwise
        // inaccessible IDs. Treat those as unavailable to learners too.
        const blocked = valid.filter((row) => statuses.get(row.video_id) !== true);
        summary.checked += valid.length;
        if (blocked.length === 0) continue;

        // Keep rows for history and recovery; unpublished rows disappear from client feeds.
        const { data: changed, error: updateError } = await supabase
          .from(table).update({ published: false }).eq("published", true)
          .in("id", blocked.map((row) => row.id)).select("id");
        if (updateError) summary.errors.push(`Could not unpublish blocked clips (${language})`);
        else summary.unpublished += changed?.length ?? 0;
      }
    }
    return jsonResponse(summary, summary.errors.length ? 207 : 200);
  } catch (err) {
    const message = err instanceof Error ? err.message : "";
    if (message.startsWith("Missing required env")) return errorResponse(500, "Server misconfigured");
    return errorResponse(500, "Embed audit failed");
  }
});
