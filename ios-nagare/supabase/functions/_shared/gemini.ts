import { geminiApiKeys, openRouterKey, openRouterModel } from "./env.ts";

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

const MODEL_FALLBACKS = ["gemini-3.6-flash", "gemini-flash-latest", "gemini-3.5-flash"];

async function callGemini(opts: {
  model: string;
  body: Record<string, unknown>;
  timeoutMs: number;
}): Promise<GeminiJsonResult> {
  const models = [opts.model, ...MODEL_FALLBACKS.filter((model) => model !== opts.model)];
  let lastError: Error | null = null;
  for (const model of models) {
    try {
      return await callGeminiOnce({ ...opts, model });
    } catch (err) {
      const message = err instanceof Error ? err.message : "";
      lastError = err instanceof Error ? err : new Error("Gemini failed");
      const overloaded = message.includes("Gemini HTTP 503") || message.includes("Gemini HTTP 429");
      if (!overloaded) throw lastError;
    }
  }
  throw lastError ?? new Error("Gemini empty response");
}

async function callGeminiOnce(opts: {
  model: string;
  body: Record<string, unknown>;
  timeoutMs: number;
}): Promise<GeminiJsonResult> {
  const keys = geminiApiKeys();
  let lastError: Error | null = null;
  for (const apiKey of keys) {
    try {
      return await callGeminiWithKey(apiKey, opts);
    } catch (err) {
      const message = err instanceof Error ? err.message : "";
      lastError = err instanceof Error ? err : new Error("Gemini failed");
      const overloaded = message.includes("Gemini HTTP 503") || message.includes("Gemini HTTP 429");
      if (!overloaded || apiKey === keys[keys.length - 1]) throw lastError;
    }
  }
  throw lastError ?? new Error("Gemini empty response");
}

async function callGeminiWithKey(apiKey: string, opts: {
  model: string;
  body: Record<string, unknown>;
  timeoutMs: number;
}): Promise<GeminiJsonResult> {
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
      const detail = redactSecrets(await res.text(), [apiKey]).slice(0, 240);
      throw new Error(`Gemini HTTP ${res.status}: ${detail}`);
    }
    const data = await res.json();
    const text = stripFence(extractText(data));
    if (!text) throw new Error("Gemini empty response");
    return { text, model: opts.model };
  } finally {
    clearTimeout(timer);
  }
}

/** Gemini fallback for a word explanation when OpenRouter is unavailable. */
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

/** Free text model. Returns null when the key is missing or the call fails. */
export async function openRouterTextJson(opts: {
  system: string;
  user: string;
  timeoutMs?: number;
}): Promise<GeminiJsonResult | null> {
  try {
    return await openRouterGenerateJson(opts);
  } catch {
    return null;
  }
}

/**
 * Text tasks. This model accepts text and images, not a YouTube link, so clip
 * watching stays on Gemini.
 */
async function openRouterGenerateJson(opts: {
  system: string;
  user: string;
  timeoutMs?: number;
}): Promise<GeminiJsonResult | null> {
  const apiKey = openRouterKey();
  if (!apiKey) return null;
  const model = openRouterModel();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), opts.timeoutMs ?? DEFAULT_TIMEOUT_MS);
  try {
    const res = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
        "X-Title": "Jojo",
      },
      body: JSON.stringify({
        model,
        temperature: 0.2,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: opts.system },
          { role: "user", content: opts.user },
        ],
      }),
      signal: controller.signal,
    });
    if (!res.ok) {
      const detail = redactSecrets(await res.text(), [apiKey]).slice(0, 240);
      throw new Error(`OpenRouter HTTP ${res.status}: ${detail}`);
    }
    const data = await res.json() as {
      choices?: Array<{ message?: { content?: string } }>;
    };
    const text = stripFence(data.choices?.[0]?.message?.content ?? "");
    if (!text) throw new Error("OpenRouter empty response");
    return { text, model };
  } finally {
    clearTimeout(timer);
  }
}

function redactSecrets(text: string, secrets: string[] = []): string {
  let redacted = text;
  for (const secret of secrets) {
    if (secret) redacted = redacted.split(secret).join("redacted");
  }
  for (const secret of geminiApiKeys()) {
    redacted = redacted.split(secret).join("redacted");
  }
  const openRouter = openRouterKey();
  if (openRouter) redacted = redacted.split(openRouter).join("redacted");
  return redacted
    .replace(/key=[^&\s"]+/gi, "key=redacted")
    .replace(/AIza[0-9A-Za-z_-]+/g, "redacted")
    .replace(/sk-or-[A-Za-z0-9_-]+/g, "redacted");
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
