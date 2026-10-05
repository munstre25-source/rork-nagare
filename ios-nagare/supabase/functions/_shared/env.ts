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

/** Primary key, then GEMINI_API_KEY2, then GEMINI_API_KEY3 when a key is overloaded. Never log these. */
export function geminiApiKeys(): string[] {
  const names = ["GEMINI_API_KEY", "GEMINI_API_KEY2", "GEMINI_API_KEY3"];
  const keys = names
    .map((name) => Deno.env.get(name)?.trim() ?? "")
    .filter((key) => key !== "");
  if (keys.length === 0) {
    throw new Error("Missing required env: GEMINI_API_KEY");
  }
  return keys;
}

export function geminiModelExplain(): string {
  return requireEnv("GEMINI_MODEL_EXPLAIN");
}

export function geminiModelAnalyze(): string {
  return requireEnv("GEMINI_MODEL_ANALYZE");
}

export function promptVersion(): string {
  return envOr("PROMPT_VERSION", "3");
}

/** OpenRouter key for word explanations. Never log the value. */
export function openRouterKey(): string | null {
  const value = Deno.env.get("OPENROUTER_API_KEY")?.trim() ?? "";
  return value === "" ? null : value;
}

export function openRouterModel(): string {
  return envOr("OPENROUTER_MODEL", "thinkingmachines/inkling:free");
}

export function utcDayString(d = new Date()): string {
  return d.toISOString().slice(0, 10);
}
