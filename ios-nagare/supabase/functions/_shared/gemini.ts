import { geminiApiKey, geminiModelFallback, openRouterApiKey } from "./env.ts";
import { reserveOpenRouterBudget, settleOpenRouterBudget } from "./openrouter-budget.ts";

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

/** Budget holds never fall through to another paid provider. */
export class AiBudgetError extends GeminiError {
  constructor() { super(429, "AI spending allowance exhausted or unavailable"); }
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

type AiProvider = {
  transport: "openrouter" | "google";
  apiKey: string;
};

/**
 * Ordered provider list built from whatever keys are configured. OpenRouter goes
 * first by default (AI_PROVIDER_ORDER), and the other provider is the failover
 * when this one is rate-limited, out of credits, or down. Text calls (word explanations)
 * use TEXT_AI_PROVIDER_ORDER, which puts the direct Gemini key first.
 */
function aiProviders(textOnly = false): AiProvider[] {
  const openRouter = openRouterApiKey() ?? (geminiApiKey()?.startsWith("sk-or-") ? geminiApiKey() : null);
  const google = geminiApiKey() && !geminiApiKey()!.startsWith("sk-or-") ? geminiApiKey() : null;
  const byName: Record<string, AiProvider | null> = {
    openrouter: openRouter ? { transport: "openrouter", apiKey: openRouter } : null,
    google: google ? { transport: "google", apiKey: google } : null,
  };
  const order = (textOnly
    ? Deno.env.get("TEXT_AI_PROVIDER_ORDER") ?? "google,openrouter"
    : Deno.env.get("AI_PROVIDER_ORDER") ?? "openrouter,google")
    .split(",").map((s) => s.trim().toLowerCase()).filter(Boolean);
  return order.map((name) => byName[name]).filter((p): p is AiProvider => p !== null);
}

function extractText(data: unknown): string {
  const root = data as {
    candidates?: Array<{
      content?: { parts?: Array<{ text?: string; thought?: boolean }> };
      finishReason?: string;
    }>;
  };
  const candidate = root.candidates?.[0];
  const parts = candidate?.content?.parts ?? [];
  // Gemini 3 thinking can emit non-JSON crumbs first; prefer the last JSON-shaped part.
  const texts = parts
    .filter((p) => !p.thought && typeof p.text === "string" && p.text.trim())
    .map((p) => p.text!.trim());
  for (let i = texts.length - 1; i >= 0; i--) {
    const t = texts[i]!;
    if (t.startsWith("{") || t.startsWith("```")) return t;
  }
  const joined = texts.join("\n").trim();
  if (joined) return joined;
  if (candidate?.finishReason && candidate.finishReason !== "STOP") {
    throw new GeminiError(502, `Gemini empty response (${candidate.finishReason})`);
  }
  return "";
}

function stripFence(text: string): string {
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fenced?.[1]) return fenced[1].trim();
  return text.trim();
}

async function callProvider(provider: AiProvider, opts: GeminiCall): Promise<GeminiJsonResult> {
  try {
    if (provider.transport === "openrouter") return await callOpenRouter(provider.apiKey, opts);
    return await callGoogleGemini(provider.apiKey, opts);
  } catch (err) {
    if (err instanceof GeminiError) throw err;
    if (err instanceof DOMException && err.name === "AbortError") {
      throw new GeminiError(0, `AI timeout after ${opts.timeoutMs}ms`);
    }
    throw new GeminiError(0, `AI network error: ${err instanceof Error ? err.message : "unknown"}`);
  }
}

/** Configured provider transports in priority order, e.g. ["openrouter","google"]. */
export function describeProviders(): string[] {
  return aiProviders().map((p) => p.transport);
}

/** Failures where a different provider could realistically succeed. */
function shouldFailOverProvider(err: GeminiError): boolean {
  if (err instanceof AiBudgetError) return false;
  return err.retryable || err.paymentRequired || err.modelRejected ||
    err.status === 401 || err.status === 403;
}

/**
 * Calls the prioritized provider chain: for each provider, the configured model;
 * if that model id is rejected, once on the fallback model; on provider-level
 * failures (rate limit, out of credits, outage, timeout) moves to the next provider.
 */
async function callGemini(opts: GeminiCall): Promise<GeminiJsonResult> {
  const providers = aiProviders(!opts.youtube);
  if (providers.length === 0) throw new GeminiError(500, "No AI provider key configured");
  const fallbackModel = geminiModelFallback();
  const models = [opts.model];
  if (normalizeSlug(fallbackModel) !== normalizeSlug(opts.model)) models.push(fallbackModel);

  let lastError: GeminiError | null = null;
  for (let p = 0; p < providers.length; p++) {
    const provider = providers[p];
    for (let m = 0; m < models.length; m++) {
      const model = models[m];
      try {
        return await callProvider(provider, { ...opts, model });
      } catch (err) {
        if (!(err instanceof GeminiError)) throw err;
        lastError = err;
        if (err.modelRejected && m < models.length - 1) {
          console.warn(JSON.stringify({
            event: "gemini_model_fallback",
            provider: provider.transport,
            from: normalizeSlug(model),
            to: normalizeSlug(fallbackModel),
            status: err.status,
            detail: err.message.slice(0, 160),
          }));
          continue;
        }
        break;
      }
    }
    if (lastError && !shouldFailOverProvider(lastError)) throw lastError;
    if (p < providers.length - 1) {
      console.warn(JSON.stringify({
        event: "gemini_provider_failover",
        from: provider.transport,
        to: providers[p + 1].transport,
        status: lastError?.status ?? 0,
        detail: (lastError?.message ?? "").slice(0, 160),
      }));
    }
  }
  throw lastError ?? new GeminiError(500, "AI call failed");
}

/** OpenRouter slugs look like `google/gemini-2.5-flash`. Google's API wants the bare id. */
function modelForTransport(model: string, openRouter: boolean): string {
  if (openRouter) return model.includes("/") ? model : `google/${model}`;
  return model.startsWith("google/") ? model.slice("google/".length) : model;
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
  // Conservative holds cover bounded requests; actual provider costs release unused allowance.
  let reservation;
  try { reservation = await reserveOpenRouterBudget(opts.youtube ? 0.50 : 0.10, opts.youtube ? "catalog" : "lookup"); }
  catch { throw new AiBudgetError(); }
  if (!reservation) throw new AiBudgetError();
  let settled = false;
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
        // Per-token timings, readings and meanings for dense Shorts exceed 8k tokens (2026-11-03: 25k-char replies cut mid-object).
        max_tokens: opts.youtube ? 32768 : 4096,
        response_format: { type: "json_object" },
        reasoning: { effort: opts.youtube ? "low" : "minimal", exclude: true },
        usage: { include: true },
        provider: { only: ["google-ai-studio"], allow_fallbacks: false },
        messages: [
          { role: "system", content: opts.system },
          { role: "user", content: userContent },
        ],
      }),
      signal: controller.signal,
    });
    if (!res.ok) {
      settled = await settleOpenRouterBudget(reservation, 0);
      const detail = redactSecrets(await res.text(), apiKey).slice(0, 240);
      throw new GeminiError(res.status, `Gemini HTTP ${res.status}: ${detail}`);
    }
    const data = await res.json() as {
      choices?: Array<{ message?: { content?: string } }>;
      usage?: { cost?: number };
    };
    // Unknown billing keeps the whole hold; never assume a cheap successful request.
    const cost = typeof data.usage?.cost === "number" && Number.isFinite(data.usage.cost) && data.usage.cost >= 0
      ? data.usage.cost : reservation.amount;
    settled = await settleOpenRouterBudget(reservation, cost);
    const text = stripFence(data.choices?.[0]?.message?.content ?? "");
    if (!text) throw new GeminiError(502, "Gemini empty response");
    return { text, model };
  } finally {
    clearTimeout(timer);
    if (!settled) await settleOpenRouterBudget(reservation, reservation.amount);
  }
}

/** Protobuf Duration allows at most nine fractional digits; JS sums can exceed that. */
export function videoOffset(seconds: number): string {
  if (!Number.isFinite(seconds)) throw new Error("Invalid video offset");
  return Math.max(0, seconds).toFixed(3).replace(/\.?0+$/, "") + "s";
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
        startOffset: videoOffset(opts.youtube.startSec),
        endOffset: videoOffset(Math.max(opts.youtube.startSec, opts.youtube.endSec)),
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
          // Video reviews return one object per line; short clips still truncate under the default.
          maxOutputTokens: opts.youtube ? 32768 : 8192,
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
  /** Optional shorter bound for a focused verification call. */
  timeoutMs?: number;
}): Promise<GeminiJsonResult> {
  return await callGemini({
    model: opts.model,
    system: opts.system,
    user: opts.user,
    timeoutMs: opts.timeoutMs ?? (opts.endSec - opts.startSec > 60 ? 120_000 : ANALYZE_TIMEOUT_MS),
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
  const parsed = parseLooseJson(text);
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("Expected JSON object");
  }
  return parsed as Record<string, unknown>;
}

/** Models sometimes wrap JSON in fences or prose (2026-10-30: 5/9 analysis rejections were
 * "response is not a JSON object"). Strip fences and take the first balanced object. */
function parseLooseJson(text: string): unknown {
  const trimmed = text.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*$/, "");
  try {
    return JSON.parse(trimmed);
  } catch {
    // Fall through: extract the first balanced {…} block.
  }
  const start = trimmed.indexOf("{");
  if (start < 0) throw new Error("no JSON object in response");
  let depth = 0, inString = false, escaped = false;
  for (let i = start; i < trimmed.length; i++) {
    const ch = trimmed[i];
    if (inString) {
      if (escaped) escaped = false;
      else if (ch === "\\") escaped = true;
      else if (ch === '"') inString = false;
      continue;
    }
    if (ch === '"') inString = true;
    else if (ch === "{") depth++;
    else if (ch === "}") {
      depth--;
      if (depth === 0) return JSON.parse(trimmed.slice(start, i + 1));
    }
  }
  throw new Error("no balanced JSON object in response");
}
