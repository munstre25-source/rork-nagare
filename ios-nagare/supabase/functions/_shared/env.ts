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

export function geminiModelExplain(): string {
  return requireEnv("GEMINI_MODEL_EXPLAIN");
}

export function geminiModelAnalyze(): string {
  return requireEnv("GEMINI_MODEL_ANALYZE");
}

export function promptVersion(): string {
  return envOr("PROMPT_VERSION", "3");
}

export function utcDayString(d = new Date()): string {
  return d.toISOString().slice(0, 10);
}
