import { corsPreflight, errorResponse, jsonResponse, readJson } from "../_shared/http.ts";
import { geminiModelAnalyze, requireEnv } from "../_shared/env.ts";
import { requireAdmin } from "../_shared/admin.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { tryIncrementGeminiUsage } from "../_shared/limits.ts";
import { geminiAnalyzeYouTubeSegment, parseJsonObject } from "../_shared/gemini.ts";
import {
  durationFromLines,
  LineLike,
  validateEnums,
  validateLines,
} from "../_shared/validate.ts";

type Body = {
  videoId?: string;
  title?: string;
  channelName?: string;
  category?: string;
  difficulty?: string;
  startSec?: number;
  endSec?: number;
  id?: string;
};

const GRADIENTS = [
  ["#0B1030", "#2B2F7A", "#F29E4C"],
  ["#10261A", "#2E7D4F", "#F6E27F"],
  ["#2B1405", "#9C3D10", "#F2B134"],
];

const SYSTEM = `You analyze a short Japanese YouTube video segment for language learners.
Return a single JSON object: { "lines": [ { "translation": string (English), "start": number, "end": number, "tokens": [ Token ] } ] }.
Each Token: surface (required), reading (kana if kanji), altReadings (string[]), romaji, start, end, pos, conjugationClass (optional), jlpt (optional N5-N1), definitions (English string[]), formality (optional), tappable (bool), baseForm/baseReading/baseRomaji (optional for conjugated stems).
Rules:
- Timestamps are absolute seconds within the given segment window; strictly increasing; each token within its line; each line within [startSec, endSec].
- Tokenize into learner-friendly units (particles separate). Punctuation may be tokens with pos "punctuation" and tappable false.
- definitions required for tappable tokens.
- Japanese dialogue only; no English in surface.
- No markdown.`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") return errorResponse(405, "Method not allowed");

  try {
    const adminToken = requireEnv("ADMIN_TOKEN");
    if (!requireAdmin(req, adminToken)) return errorResponse(401, "Unauthorized");

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
    if (!Number.isFinite(startSec) || !Number.isFinite(endSec) || endSec <= startSec) {
      return errorResponse(400, "startSec and endSec required with endSec > startSec");
    }
    if (endSec - startSec > 180) {
      return errorResponse(400, "Segment must be <= 180 seconds");
    }

    const title = (typeof body.title === "string" && body.title.trim()) ||
      `Clip ${videoId}`;
    const channelName =
      (typeof body.channelName === "string" && body.channelName.trim()) ||
      "Unknown";
    const id = (typeof body.id === "string" && body.id.trim()) ||
      `${videoId}-${Math.floor(startSec)}-${Math.floor(endSec)}`;

    const supabase = serviceClient();
    if (!(await tryIncrementGeminiUsage(supabase))) {
      return errorResponse(429, "Global Gemini cap exceeded");
    }

    const youtubeUrl = `https://www.youtube.com/watch?v=${videoId}`;
    const model = geminiModelAnalyze();
    const { text } = await geminiAnalyzeYouTubeSegment({
      model,
      system: SYSTEM,
      user:
        `Segment window: startSec=${startSec}, endSec=${endSec}. Produce lines JSON for this Japanese clip.`,
      youtubeUrl,
      startSec,
      endSec,
    });

    const raw = parseJsonObject(text);
    const lines = raw.lines;
    const validated = validateLines(lines, startSec, endSec);
    if (!validated.ok) return errorResponse(422, validated.error);

    const durationSec = durationFromLines(lines as LineLike[], endSec - startSec);
    const gradient = GRADIENTS[Math.abs(hashCode(id)) % GRADIENTS.length];

    const row = {
      id,
      video_id: videoId,
      title,
      channel_name: channelName,
      category,
      difficulty,
      duration_sec: durationSec,
      lines,
      published: false,
      channel_avatar_color: "#FF6B00",
      thumbnail_gradient: gradient,
    };

    const { data, error } = await supabase.from("clips").upsert(row).select("*")
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

function hashCode(s: string): number {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (Math.imul(31, h) + s.charCodeAt(i)) | 0;
  return h;
}
