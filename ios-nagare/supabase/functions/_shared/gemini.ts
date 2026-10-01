import { requireEnv } from "./env.ts";

const DEFAULT_TIMEOUT_MS = 12_000;
const ANALYZE_TIMEOUT_MS = 90_000;

export type GeminiJsonResult = {
  text: string;
  model: string;
};

function extractText(data: unknown): string {
  const root = data as {
    candidates?: Array<{
      content?: { parts?: Array<{ text?: string }> };
    }>;
  };
  const parts = root.candidates?.[0]?.content?.parts ?? [];
  return parts.map((p) => p.text ?? "").join("").trim();
}

function stripFence(text: string): string {
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fenced?.[1]) return fenced[1].trim();
  return text.trim();
}

async function callGemini(opts: {
  model: string;
  body: Record<string, unknown>;
  timeoutMs: number;
}): Promise<GeminiJsonResult> {
  const apiKey = requireEnv("GEMINI_API_KEY");
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(opts.model)}:generateContent?key=${encodeURIComponent(apiKey)}`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), opts.timeoutMs);
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(opts.body),
      signal: controller.signal,
    });
    if (!res.ok) {
      throw new Error(`Gemini HTTP ${res.status}`);
    }
    const data = await res.json();
    const text = stripFence(extractText(data));
    if (!text) throw new Error("Gemini empty response");
    return { text, model: opts.model };
  } finally {
    clearTimeout(timer);
  }
}

export async function geminiGenerateJson(opts: {
  model: string;
  system: string;
  user: string;
  timeoutMs?: number;
}): Promise<GeminiJsonResult> {
  return await callGemini({
    model: opts.model,
    timeoutMs: opts.timeoutMs ?? DEFAULT_TIMEOUT_MS,
    body: {
      systemInstruction: { parts: [{ text: opts.system }] },
      contents: [{ role: "user", parts: [{ text: opts.user }] }],
      generationConfig: {
        temperature: 0.2,
        responseMimeType: "application/json",
      },
    },
  });
}

/** Send a YouTube URL as video input with start/end offsets (seconds). */
export async function geminiAnalyzeYouTubeSegment(opts: {
  model: string;
  system: string;
  user: string;
  youtubeUrl: string;
  startSec: number;
  endSec: number;
}): Promise<GeminiJsonResult> {
  return await callGemini({
    model: opts.model,
    timeoutMs: ANALYZE_TIMEOUT_MS,
    body: {
      systemInstruction: { parts: [{ text: opts.system }] },
      contents: [{
        role: "user",
        parts: [
          {
            fileData: {
              fileUri: opts.youtubeUrl,
              mimeType: "video/*",
            },
            videoMetadata: {
              startOffset: `${Math.max(0, opts.startSec)}s`,
              endOffset: `${Math.max(opts.startSec, opts.endSec)}s`,
            },
          },
          { text: opts.user },
        ],
      }],
      generationConfig: {
        temperature: 0.2,
        responseMimeType: "application/json",
      },
    },
  });
}

export function parseJsonObject(text: string): Record<string, unknown> {
  const parsed = JSON.parse(text) as unknown;
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("Expected JSON object");
  }
  return parsed as Record<string, unknown>;
}
