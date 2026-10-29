import { corsPreflight, errorResponse, jsonResponse, readJson } from "../_shared/http.ts";
import { requireEnv } from "../_shared/env.ts";
import { isAdminOrCron } from "../_shared/admin.ts";
import { catalogTable, parseLanguage } from "../_shared/catalog.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { LineLike, validateEnums, validateLines } from "../_shared/validate.ts";
import { checkYouTubeVideo, ERROR_MESSAGES } from "../_shared/immersion.ts";

type Body = {
  id?: string;
  action?: string;
  language?: string;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") return errorResponse(405, "Method not allowed");

  try {
    requireEnv("ADMIN_TOKEN");
    if (!isAdminOrCron(req)) return errorResponse(401, "Unauthorized");

    const body = await readJson<Body>(req);
    const id = typeof body.id === "string" ? body.id.trim() : "";
    const action = body.action === "publish" || body.action === "unpublish"
      ? body.action
      : null;
    if (!id || !action) {
      return errorResponse(400, 'id and action ("publish"|"unpublish") required');
    }

    const language = parseLanguage(body.language);
    const table = catalogTable(language);
    const supabase = serviceClient();
    const { data: clip, error } = await supabase
      .from(table)
      .select("*")
      .eq("id", id)
      .maybeSingle();

    if (error || !clip) return errorResponse(404, "Clip not found");

    if (action === "unpublish") {
      const { data, error: upErr } = await supabase
        .from(table)
        .update({ published: false })
        .eq("id", id)
        .select("*")
        .single();
      if (upErr) return errorResponse(500, "Unpublish failed");
      return jsonResponse({ clip: data });
    }

    // Recheck on every publish: owners can change a video's embedding setting
    // after discovery or after a previous publish.
    const videoCheck = await checkYouTubeVideo(supabase, String(clip.video_id ?? ""));
    if (!videoCheck.ok) {
      const message = videoCheck.code === "not_embeddable"
        ? ERROR_MESSAGES.not_embeddable
        : videoCheck.code === "private_video" || videoCheck.code === "video_not_found"
        ? ERROR_MESSAGES[videoCheck.code]
        : videoCheck.code === "quota_exhausted"
        ? "YouTube verification quota is exhausted. Try publishing again tomorrow."
        : "YouTube could not verify this video. Try again later.";
      return errorResponse(videoCheck.code === "quota_exhausted" || videoCheck.code === "youtube_unavailable" ? 503 : 422, message);
    }

    // publish — validate lines first
    const enums = validateEnums(clip.category, clip.difficulty);
    if (!enums.ok) return errorResponse(422, enums.error);

    const lines = clip.lines as LineLike[];
    const startSec = Array.isArray(lines) && lines.length > 0
      ? Number((lines[0] as LineLike).start) || 0
      : 0;
    const endSec = Array.isArray(lines) && lines.length > 0
      ? Number((lines[lines.length - 1] as LineLike).end) ||
        Number(clip.duration_sec) ||
        startSec
      : Number(clip.duration_sec) || 0;

    const validated = validateLines(lines, startSec, endSec, language);
    if (!validated.ok) {
      return errorResponse(422, `Refuse to publish: ${validated.error}`);
    }

    const { data, error: pubErr } = await supabase
      .from(table)
      .update({ published: true })
      .eq("id", id)
      .select("*")
      .single();
    if (pubErr) return errorResponse(500, "Publish failed");
    return jsonResponse({ clip: data });
  } catch (err) {
    const message = err instanceof Error ? err.message : "";
    if (message.startsWith("Missing required env")) {
      return errorResponse(500, "Server misconfigured");
    }
    return errorResponse(500, "Publish failed");
  }
});
