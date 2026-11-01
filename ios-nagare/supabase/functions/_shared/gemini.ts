import { geminiApiKey, geminiModelFallback, openRouterApiKey } from "./env.ts";

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

type AiProvider = {
  transport: "openrouter" | "google";
  apiKey: string;
};

/**
 * Ordered provider list built from whatever keys are configured. OpenRouter goes
 * first by default (AI_PROVIDER_ORDER), and the other provider is the failover
 * when this one is rate-limited, out of credits, or down.
 */
function aiProviders(): AiProvider[] {
  const openRouter = openRouterApiKey() ?? (geminiApiKey()?.startsWith("sk-or-") ? geminiApiKey() : null);
  const google = geminiApiKey() && !geminiApiKey()!.startsWith("sk-or-") ? geminiApiKey() : null;
  const byName: Record<string, AiProvider | null> = {
    openrouter: openRouter ? { transport: "openrouter", apiKey: openRouter } : null,
    google: google ? { transport: "google", apiKey: google } : null,
  };
  const order = (Deno.env.get("AI_PROVIDER_ORDER") ?? "openrouter,google")
    .split(",").map((s) => s.trim().toLowerCase()).filter(Boolean);
  return order.map((name) => byName[name]).filter((p): p is AiProvider => p !== null);
}

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
  return err.retryable || err.paymentRequired || err.modelRejected ||
    err.status === 401 || err.status === 403;
}

/**
 * Calls the prioritized provider chain: for each provider, the configured model;
 * if that model id is rejected, once on the fallback model; on provider-level
 * failures (rate limit, out of credits, outage, timeout) moves to the next provider.
 */
async function callGemini(opts: GeminiCall): Promise<GeminiJsonResult> {
  const providers = aiProviders();
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

  if (!(await openRouterBudget("openrouter_budget_ok", { reserve: opts.youtube ? 0.1 : 0.01 }))) {
    throw new GeminiError(402, "OpenRouter budget cap reached");
  }
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
        max_tokens: opts.youtube ? (opts.youtube.endSec - opts.youtube.startSec > 60 ? 16384 : 8192) : 4096,
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
      const detail = redactSecrets(await res.text(), apiKey).slice(0, 240);
      throw new GeminiError(res.status, `Gemini HTTP ${res.status}: ${detail}`);
    }
    const data = await res.json() as {
      choices?: Array<{ message?: { content?: string } }>;
      usage?: { cost?: number };
    };
    // Unknown cost is booked pessimistically so the cap can never be overrun silently.
    const cost = typeof data.usage?.cost === "number" ? data.usage.cost : (opts.youtube ? 0.05 : 0.005);
    await openRouterBudget("openrouter_add_spend", { cost });
    const text = stripFence(data.choices?.[0]?.message?.content ?? "");
    if (!text) throw new GeminiError(502, "Gemini empty response");
    return { text, model };
  } finally {
    clearTimeout(timer);
  }
}

/** Calls the spend-ledger RPCs with the service role. Fails closed (false) on any error. */
async function openRouterBudget(fn: string, args: Record<string, unknown>): Promise<boolean> {
  const base = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!base || !key) return false;
  try {
    const res = await fetch(`${base}/rest/v1/rpc/${fn}`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: key, Authorization: `Bearer ${key}` },
      body: JSON.stringify(args),
      signal: AbortSignal.timeout(5000),
    });
    if (!res.ok) return false;
    const value = await res.json();
    return fn === "openrouter_budget_ok" ? value === true : true;
  } catch {
    return false;
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
    timeoutMs: opts.endSec - opts.startSec > 60 ? 120_000 : ANALYZE_TIMEOUT_MS,
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
