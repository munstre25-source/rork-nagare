import { geminiApiKey, geminiModelFallback } from "./env.ts";

const DEFAULT_TIMEOUT_MS = 12_000;
const ANALYZE_TIMEOUT_MS = 90_000;
const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";

export type GeminiJsonResult = {
  text: string;
  /** The model that actually answered (primary or fallback), as an OpenRouter-style slug. */
  model: string;
};

/** A failed model call with the HTTP status (0 for timeouts and network errors). */
export class GeminiError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
    this.name = "GeminiError";
  }

  /** Rate limits, provider outages, and timeouts are worth retrying later. */
  get retryable(): boolean {
    return this.status === 0 || this.status === 408 || this.status === 429 || this.status >= 500;
  }

  /** Out of credits / billing problem on the model account. */
  get paymentRequired(): boolean {
    return this.status === 402;
  }

  /** The model id itself was rejected, so another model may work. */
  get modelRejected(): boolean {
    if (this.status === 404) return true;
    return this.status === 400 && /model|not (a )?valid|not found|unsupported|thinking/i.test(this.message);
  }
}

type GeminiCall = {
  model: string;
  system: string;
  user: string;
  timeoutMs: number;
  youtube?: {
    url: string;
    startSec: number;
    endSec: number;
  };
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

function isOpenRouterKey(apiKey: string): boolean {
  return apiKey.startsWith("sk-or-");
}

/** OpenRouter slugs look like `google/gemini-2.5-flash`. Google's API wants the bare id. */
function modelForTransport(model: string, openRouter: boolean): string {
  if (openRouter) return model.includes("/") ? model : `google/${model}`;
  return model.startsWith("google/") ? model.slice("google/".length) : model;
}

async function callOnce(apiKey: string, opts: GeminiCall): Promise<GeminiJsonResult> {
  try {
    if (isOpenRouterKey(apiKey)) return await callOpenRouter(apiKey, opts);
    return await callGoogleGemini(apiKey, opts);
  } catch (err) {
    if (err instanceof GeminiError) throw err;
    if (err instanceof DOMException && err.name === "AbortError") {
      throw new GeminiError(0, `Gemini timeout after ${opts.timeoutMs}ms`);
    }
    throw new GeminiError(0, `Gemini network error: ${err instanceof Error ? err.message : "unknown"}`);
  }
}

/** Calls the configured model; if that model id is rejected, retries once on the fallback model. */
async function callGemini(opts: GeminiCall): Promise<GeminiJsonResult> {
  const apiKey = geminiApiKey();
  try {
    return await callOnce(apiKey, opts);
  } catch (err) {
    const fallback = geminiModelFallback();
    if (!(err instanceof GeminiError) || !err.modelRejected) throw err;
    if (normalizeSlug(fallback) === normalizeSlug(opts.model)) throw err;
    console.warn(JSON.stringify({
      event: "gemini_model_fallback",
      from: normalizeSlug(opts.model),
      to: normalizeSlug(fallback),
      status: err.status,
      detail: err.message.slice(0, 160),
    }));
    return await callOnce(apiKey, { ...opts, model: fallback });
  }
}

function normalizeSlug(model: string): string {
  return model.includes("/") ? model : `google/${model}`;
}

/** Gemini 3+ only accepts thinking levels; 2.x accepts token budgets. */
function isGemini3OrLater(model: string): boolean {
  const match = model.match(/gemini-(\d+)/);
  return match ? Number(match[1]) >= 3 : false;
}

async function callOpenRouter(apiKey: string, opts: GeminiCall): Promise<GeminiJsonResult> {
  const model = modelForTransport(opts.model, true);
  const userContent = opts.youtube
    ? [
      {
        type: "text",
        text:
          `${opts.user}\nOnly transcribe speech between ${opts.youtube.startSec}s and ${opts.youtube.endSec}s. Ignore the rest of the video.`,
      },
      {
        type: "video_url",
        video_url: {
          url: opts.youtube.url,
          processing: "agentic",
        },
      },
    ]
    : opts.user;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), opts.timeoutMs);
  try {
    const res = await fetch(OPENROUTER_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
        "X-Title": "Jojo",
      },
      body: JSON.stringify({
        model,
        temperature: 0.2,
        max_tokens: opts.youtube ? 8192 : 4096,
        response_format: { type: "json_object" },
        reasoning: { effort: opts.youtube ? "low" : "minimal", exclude: true },
        provider: { only: ["google-ai-studio"], allow_fallbacks: false },
        messages: [
          { role: "system", content: opts.system },
          { role: "user", content: userContent },
        ],
      }),
      signal: controller.signal,
    });
    if (!res.ok) {
      const detail = redactSecrets(await res.text(), apiKey).slice(0, 240);
      throw new GeminiError(res.status, `Gemini HTTP ${res.status}: ${detail}`);
    }
    const data = await res.json() as {
      choices?: Array<{ message?: { content?: string } }>;
    };
    const text = stripFence(data.choices?.[0]?.message?.content ?? "");
    if (!text) throw new GeminiError(502, "Gemini empty response");
    return { text, model };
  } finally {
    clearTimeout(timer);
  }
}

async function callGoogleGemini(apiKey: string, opts: GeminiCall): Promise<GeminiJsonResult> {
  const model = modelForTransport(opts.model, false);
  const userParts: Array<Record<string, unknown>> = [];
  if (opts.youtube) {
    userParts.push({
      fileData: {
        fileUri: opts.youtube.url,
        mimeType: "video/*",
      },
      videoMetadata: {
        startOffset: `${Math.max(0, opts.youtube.startSec)}s`,
        endOffset: `${Math.max(opts.youtube.startSec, opts.youtube.endSec)}s`,
      },
    });
  }
  userParts.push({ text: opts.user });

  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(apiKey)}`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), opts.timeoutMs);
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: opts.system }] },
        contents: [{ role: "user", parts: userParts }],
        generationConfig: {
          temperature: 0.2,
          responseMimeType: "application/json",
          thinkingConfig: isGemini3OrLater(model)
            ? { thinkingLevel: "low" }
            : { thinkingBudget: opts.youtube ? 1024 : 0 },
        },
      }),
      signal: controller.signal,
    });
    if (!res.ok) {
      const detail = redactSecrets(await res.text(), apiKey).slice(0, 240);
      throw new GeminiError(res.status, `Gemini HTTP ${res.status}: ${detail}`);
    }
    const data = await res.json();
    const text = stripFence(extractText(data));
    if (!text) throw new GeminiError(502, "Gemini empty response");
    return { text, model: normalizeSlug(model) };
  } finally {
    clearTimeout(timer);
  }
}

/** Text JSON from the single Gemini key. Used for word explanations and dictionary enrichment. */
export async function geminiGenerateJson(opts: {
  model: string;
  system: string;
  user: string;
  timeoutMs?: number;
}): Promise<GeminiJsonResult> {
  return await callGemini({
    model: opts.model,
    system: opts.system,
    user: opts.user,
    timeoutMs: opts.timeoutMs ?? DEFAULT_TIMEOUT_MS,
  });
}

/** Watch a YouTube segment and return JSON. Same key as text tasks. */
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
    system: opts.system,
    user: opts.user,
    timeoutMs: ANALYZE_TIMEOUT_MS,
    youtube: {
      url: opts.youtubeUrl,
      startSec: opts.startSec,
      endSec: opts.endSec,
    },
  });
}

function redactSecrets(text: string, apiKey: string): string {
  return text
    .split(apiKey).join("redacted")
    .replace(/key=[^&\s"]+/gi, "key=redacted")
    .replace(/keys\/[0-9a-f]{8,}/gi, "keys/redacted")
    .replace(/AIza[0-9A-Za-z_-]+/g, "redacted")
    .replace(/sk-or-[A-Za-z0-9_-]+/g, "redacted");
}

export function parseJsonObject(text: string): Record<string, unknown> {
  const parsed = JSON.parse(text) as unknown;
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("Expected JSON object");
  }
  return parsed as Record<string, unknown>;
}
