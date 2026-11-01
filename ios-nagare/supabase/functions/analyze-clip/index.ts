import { corsPreflight, errorResponse, jsonResponse, readJson } from "../_shared/http.ts";
import { requireEnv } from "../_shared/env.ts";
import { isAdminOrCron } from "../_shared/admin.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { catalogTable, parseLanguage } from "../_shared/catalog.ts";
import { analyzeWindow, clipId, clipRow } from "../_shared/immersion.ts";
import { validateEnums } from "../_shared/validate.ts";

type Body = {
  videoId?: string;
  title?: string;
  channelName?: string;
  category?: string;
  difficulty?: string;
  startSec?: number;
  endSec?: number;
  id?: string;
  language?: string;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") return errorResponse(405, "Method not allowed");

  try {
    requireEnv("ADMIN_TOKEN");
    // Same gate as publish-clip: the admin token or the Vault-held cron token.
    if (!isAdminOrCron(req)) return errorResponse(401, "Unauthorized");

    const body = await readJson<Body>(req);
    const videoId = typeof body.videoId === "string" ? body.videoId.trim() : "";
    if (!/^[A-Za-z0-9_-]{11}$/.test(videoId)) {
      return errorResponse(400, "videoId must be an 11-character YouTube id");
    }
    const category = typeof body.category === "string" ? body.category : "";
    const difficulty = typeof body.difficulty === "string" ? body.difficulty : "";
    const enums = validateEnums(category, difficulty);
    if (!enums.ok) return errorResponse(400, enums.error);

    const startSec = Number(body.startSec);
    const endSec = Number(body.endSec);
    if (!Number.isFinite(startSec) || startSec < 0 || !Number.isFinite(endSec) || endSec <= startSec) {
      return errorResponse(400, "startSec and endSec required with 0 <= startSec < endSec");
    }
    if (endSec - startSec < 8 || endSec - startSec > 120) {
      return errorResponse(400, "Segment must be between 8 and 120 seconds");
    }

    const title = (typeof body.title === "string" && body.title.trim()) ||
      `Clip ${videoId}`;
    const channelName =
      (typeof body.channelName === "string" && body.channelName.trim()) ||
      "Unknown";
    const language = parseLanguage(body.language);

    const supabase = serviceClient();
    // Same single hearing pass and timing repair as the catalog fill (analyzeWindow):
    // repairs degenerate token times, keeps the excerpt inside 8–40 s and returns
    // clip-relative lines. The reviewed window bounds what the model may choose.
    const outcome = await analyzeWindow(supabase, {
      videoId,
      windowStart: startSec,
      windowEnd: endSec,
      sourceDurationSec: endSec,
      language,
      askCategory: false,
      minSpokenSec: 6,
    });
    if (!outcome.ok) {
      const status = outcome.reason === "gemini_cap" ? 429
        : outcome.reason.startsWith("model_") ? 502 : 422;
      return errorResponse(status, `${outcome.reason}: ${outcome.detail}`.slice(0, 240));
    }
    const draft = { ...outcome.draft, difficulty: difficulty || outcome.draft.difficulty };
    const id = (typeof body.id === "string" && body.id.trim()) ||
      clipId(language === "ko" ? "sori" : "immersion", videoId, draft);
    const row = clipRow({
      id,
      video: { videoId, title, channelTitle: channelName, durationSec: endSec },
      draft,
      category,
      published: false,
      withProvenance: language === "ja",
    });

    const { data, error } = await supabase.from(catalogTable(language)).upsert(row).select("*")
      .single();
    if (error) return errorResponse(500, "Failed to insert clip");

    return jsonResponse({ clip: data });
  } catch (err) {
    const message = err instanceof Error ? err.message : "";
    if (message.startsWith("Missing required env")) {
      return errorResponse(500, "Server misconfigured");
    }
    if (message.startsWith("Gemini HTTP ") || message === "Gemini empty response") {
      return errorResponse(502, message.slice(0, 240));
    }
    return errorResponse(500, "Analyze failed");
  }
});
