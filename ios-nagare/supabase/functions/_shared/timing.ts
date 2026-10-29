/**
 * Transcript timing checks for the karaoke highlight.
 *
 * Gemini hears the YouTube audio and returns line and word timestamps. There is no raw
 * audio on our side (we never download YouTube media), so classic forced alignment is not
 * possible. Instead every line is checked: when its word timings are physically plausible it
 * keeps word-level sync, otherwise the line falls back to sentence-level highlighting and its
 * word timings are dropped rather than guessed.
 */
import { mostlyJapanese, mostlyKorean } from "./validate.ts";

export type TimingMode = "word" | "line";
export type ClipTimingMode = "word" | "line" | "mixed";

export type TimedToken = { surface: string; start: number; end: number; [key: string]: unknown };
export type TimedLine = {
  translation: string;
  start: number;
  end: number;
  tokens: TimedToken[];
  timing: TimingMode;
  [key: string]: unknown;
};

export type TimelineResult =
  | { ok: true; lines: TimedLine[] }
  | { ok: false; error: string };

const PUNCTUATION = /^[\s\p{P}\p{S}ー〜]+$/u;
/** Slack allowed for model rounding at line and token edges. */
const EDGE_TOLERANCE = 0.25;
const TOKEN_TOLERANCE = 0.12;

function finite(n: unknown): n is number {
  return typeof n === "number" && Number.isFinite(n);
}

export function isPunctuationSurface(surface: string): boolean {
  return PUNCTUATION.test(surface);
}

/**
 * Strict sentence timeline. Every line must have real start/end inside the window, in order,
 * with a translation and non-empty token surfaces. Small overlaps from rounding are trimmed.
 */
export function validateLineTimeline(
  raw: unknown,
  windowStart: number,
  windowEnd: number,
  language: "ja" | "ko" = "ja",
): TimelineResult {
  if (!Array.isArray(raw) || raw.length === 0) return { ok: false, error: "no lines" };
  if (!(windowEnd > windowStart)) return { ok: false, error: "bad window" };
  const out: TimedLine[] = [];
  let prevEnd = windowStart;
  const surfaces: string[] = [];
  for (let i = 0; i < raw.length; i++) {
    const row = raw[i] as Record<string, unknown>;
    if (!row || typeof row !== "object") return { ok: false, error: `line[${i}] not an object` };
    if (!finite(row.start) || !finite(row.end)) return { ok: false, error: `line[${i}] missing start/end` };
    if (row.start < windowStart - EDGE_TOLERANCE || row.end > windowEnd + EDGE_TOLERANCE) {
      return { ok: false, error: `line[${i}] outside window` };
    }
    let start = Math.max(windowStart, row.start);
    const end = Math.min(windowEnd, row.end);
    if (i > 0 && start < prevEnd) {
      if (prevEnd - start > EDGE_TOLERANCE) return { ok: false, error: `line[${i}] overlaps previous line` };
      start = prevEnd;
    }
    if (end - start < 0.2) return { ok: false, error: `line[${i}] too short` };
    if (end - start > 30) return { ok: false, error: `line[${i}] longer than 30s` };
    const translation = typeof row.translation === "string" ? row.translation.trim() : "";
    if (!translation) return { ok: false, error: `line[${i}] translation required` };
    if (!Array.isArray(row.tokens) || row.tokens.length === 0) return { ok: false, error: `line[${i}] no tokens` };
    const tokens: TimedToken[] = [];
    for (let t = 0; t < row.tokens.length; t++) {
      const tok = row.tokens[t] as Record<string, unknown>;
      const surface = typeof tok?.surface === "string" ? tok.surface.trim() : "";
      if (!surface) return { ok: false, error: `line[${i}].tokens[${t}] empty surface` };
      surfaces.push(surface);
      tokens.push({
        ...tok,
        surface,
        start: finite(tok.start) ? tok.start : Number.NaN,
        end: finite(tok.end) ? tok.end : Number.NaN,
      });
    }
    out.push({ ...row, translation, start, end, tokens, timing: "word" });
    prevEnd = end;
  }
  const joined = surfaces.join("");
  if (language === "ko" ? !mostlyKorean(joined) : !mostlyJapanese(joined)) {
    return { ok: false, error: "transcript is not mostly the target language" };
  }
  return { ok: true, lines: out };
}

/** Why a line's word timings were rejected, or null when they hold up. */
export function wordTimingProblem(line: TimedLine): string | null {
  const spoken = line.tokens.filter((t) => !isPunctuationSurface(t.surface));
  if (spoken.length === 0) return "no spoken tokens";
  let prevEnd = line.start - TOKEN_TOLERANCE;
  let chars = 0;
  const durations: number[] = [];
  for (const token of spoken) {
    if (!finite(token.start) || !finite(token.end)) return "token missing timing";
    if (token.end <= token.start) return "token ends before it starts";
    if (token.start < line.start - TOKEN_TOLERANCE || token.end > line.end + TOKEN_TOLERANCE) {
      return "token outside its line";
    }
    if (token.start < prevEnd - 0.08) return "tokens out of order";
    const length = [...token.surface].length;
    const duration = token.end - token.start;
    if (duration < 0.04) return "token too short to be heard";
    if (duration > Math.max(2.5, 0.7 * length)) return "token too long";
    durations.push(duration);
    chars += length;
    prevEnd = token.end;
  }
  const first = spoken[0]!;
  const last = spoken[spoken.length - 1]!;
  const span = last.end - first.start;
  const lineSpan = line.end - line.start;
  if (span <= 0) return "empty token span";
  if (span / lineSpan < 0.5) return "tokens cover under half the line";
  const rate = chars / span;
  if (rate > 25) return "speech rate too fast to be real";
  if (rate < 0.6) return "speech rate too slow to be real";
  // Evenly spaced words with uneven lengths are the signature of interpolated, not heard, timing.
  if (durations.length >= 5) {
    const mean = durations.reduce((a, b) => a + b, 0) / durations.length;
    const variance = durations.reduce((a, b) => a + (b - mean) ** 2, 0) / durations.length;
    const lengths = new Set(spoken.map((t) => [...t.surface].length));
    if (mean > 0 && Math.sqrt(variance) / mean < 0.03 && lengths.size > 1) return "uniform spacing looks interpolated";
  }
  return null;
}

/**
 * Marks each line word- or line-timed. Word-timed tokens are clamped into their line.
 * Line-timed tokens all span the full line so clients never highlight a guessed word.
 */
export function assessTiming(lines: TimedLine[]): {
  lines: TimedLine[];
  mode: ClipTimingMode;
  confidence: number;
  problems: string[];
} {
  const problems: string[] = [];
  let wordLines = 0;
  const assessed = lines.map((line, index) => {
    const problem = wordTimingProblem(line);
    if (problem) {
      problems.push(`line[${index}]: ${problem}`);
      return {
        ...line,
        timing: "line" as const,
        tokens: line.tokens.map((t) => ({ ...t, start: line.start, end: line.end })),
      };
    }
    wordLines += 1;
    let cursor = line.start;
    const tokens = line.tokens.map((t) => {
      if (isPunctuationSurface(t.surface) || !finite(t.start) || !finite(t.end)) {
        // Punctuation is silent: pin it to the previous word's end so it never takes the highlight.
        return { ...t, start: cursor, end: cursor };
      }
      const start = Math.min(Math.max(t.start, line.start, cursor), line.end);
      const end = Math.max(Math.min(t.end, line.end), start + 0.01);
      cursor = end;
      return { ...t, start, end };
    });
    return { ...line, timing: "word" as const, tokens };
  });
  const confidence = lines.length === 0 ? 0 : wordLines / lines.length;
  const mode: ClipTimingMode = wordLines === lines.length ? "word" : wordLines === 0 ? "line" : "mixed";
  return { lines: assessed, mode, confidence: Math.round(confidence * 100) / 100, problems };
}

/** Shifts absolute source-video times so the clip starts at zero. */
export function toClipRelative(lines: TimedLine[], clipStart: number): TimedLine[] {
  const shift = (n: number) => Math.round((n - clipStart) * 1000) / 1000;
  return lines.map((line) => ({
    ...line,
    start: shift(line.start),
    end: shift(line.end),
    tokens: line.tokens.map((t) => ({ ...t, start: shift(t.start), end: shift(t.end) })),
  }));
}
