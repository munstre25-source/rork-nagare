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
 * The only model key for transcription, translation, enrichment, and word explanations.
 * An OpenRouter key (`sk-or-`) calls Gemini through OpenRouter. A Google AI Studio key
 * calls Gemini directly. Never log the value.
 */
export function geminiApiKey(): string {
  const value = Deno.env.get("GEMINI_API_KEY")?.trim() ?? "";
  if (!value) throw new Error("Missing required env: GEMINI_API_KEY");
  return value;
}

const DEFAULT_GEMINI_MODEL = "google/gemini-2.5-flash";

export function geminiModelExplain(): string {
  return envOr("GEMINI_MODEL_EXPLAIN", DEFAULT_GEMINI_MODEL);
}

export function geminiModelAnalyze(): string {
  return envOr("GEMINI_MODEL_ANALYZE", DEFAULT_GEMINI_MODEL);
}

export function promptVersion(): string {
  return envOr("PROMPT_VERSION", "3");
}

export function utcDayString(d = new Date()): string {
  return d.toISOString().slice(0, 10);
}
