/** Env helpers. Never log secret values. */

export function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value || value.trim() === "") {
    throw new Error(`Missing required env: ${name}`);
  }
  return value;
}

export function envOr(name: string, fallback: string): string {
  const value = Deno.env.get(name);
  return value && value.trim() !== "" ? value : fallback;
}

export function envInt(name: string, fallback: number): number {
  const raw = Deno.env.get(name);
  if (!raw) return fallback;
  const n = Number.parseInt(raw, 10);
  return Number.isFinite(n) && n >= 0 ? n : fallback;
}

/**
 * A Google AI Studio key calling Gemini directly. Never log the value.
 * (Legacy: if this value is an OpenRouter key, the caller treats it as OpenRouter.)
 */
export function geminiApiKey(): string | null {
  return Deno.env.get("GEMINI_API_KEY")?.trim() || null;
}

/**
 * Optional OpenRouter key (`sk-or-…`). When set, it is preferred over the Google key
 * (see `AI_PROVIDER_ORDER` in gemini.ts) and used as failover when the other is down.
 */
export function openRouterApiKey(): string | null {
  return Deno.env.get("OPENROUTER_API_KEY")?.trim() || null;
}

/** Primary model for transcription, translation, and vocabulary. */
const DEFAULT_GEMINI_MODEL = "google/gemini-3.8-flash";
/** Used only when the primary model id is rejected (400/404 for the model itself). */
const DEFAULT_GEMINI_FALLBACK_MODEL = "google/gemini-2.5-flash";

export function geminiModelFallback(): string {
  return envOr("GEMINI_MODEL_FALLBACK", DEFAULT_GEMINI_FALLBACK_MODEL);
}

export function geminiModelExplain(): string {
  return envOr("GEMINI_MODEL_EXPLAIN", DEFAULT_GEMINI_MODEL);
}

export function geminiModelAnalyze(): string {
  return envOr("GEMINI_MODEL_ANALYZE", DEFAULT_GEMINI_MODEL);
}

export function promptVersion(): string {
  return envOr("PROMPT_VERSION", "4");
}

export function utcDayString(d = new Date()): string {
  return d.toISOString().slice(0, 10);
}
