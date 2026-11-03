import { geminiModelAnalyze } from "./env.ts";
import { AiBudgetError, geminiAnalyzeYouTubeSegment, parseJsonObject } from "./gemini.ts";
import { assessTiming, type TimedLine } from "./timing.ts";

export type WordTimingSource = {
  videoId: string;
  sourceStartSec: number;
  durationSec: number;
  lines: TimedLine[];
};

type TimingPrompt = { system: string; user: string; videoId: string; startSec: number; endSec: number };
type Result = { ok: true; lines: TimedLine[]; repaired: number }
  | { ok: false; reason: "quota" | "unverified"; detail: string };

/** One audio-grounded retry. Never interpolates, changes words, or accepts partial repairs. */
export async function repairWordTiming(source: WordTimingSource, options: {
  consumeUsage: () => Promise<boolean>;
  request?: (prompt: TimingPrompt) => Promise<string>;
}): Promise<Result> {
  if (!/^[A-Za-z0-9_-]{11}$/.test(source.videoId) || !Array.isArray(source.lines) || !source.lines.length ||
      source.lines.length > 100 || !Number.isFinite(source.sourceStartSec) || source.sourceStartSec < 0 ||
      !Number.isFinite(source.durationSec) || source.durationSec <= 0 ||
      source.lines.some((line) => !Number.isFinite(line.start) || !Number.isFinite(line.end) ||
        line.end <= line.start || line.start < -0.05 || line.end > source.durationSec + 0.05 ||
        !Array.isArray(line.tokens) || !line.tokens.length)) {
    return { ok: false, reason: "unverified", detail: "Invalid word-timing source" };
  }
  const assessed = assessTiming(source.lines);
  if (assessed.mode === "word") return { ok: true, lines: assessed.lines, repaired: 0 };
  const indexes = assessed.lines.flatMap((line, i) => line.timing === "line" ? [i] : []);
  if (!(await options.consumeUsage())) return { ok: false, reason: "quota", detail: "Word alignment allowance reached" };
  const sketch = indexes.map((i) => ({
    i, start: source.sourceStartSec + source.lines[i].start, end: source.sourceStartSec + source.lines[i].end,
    tokens: source.lines[i].tokens.map((token, i) => ({ i, surface: token.surface })),
  }));
  const prompt: TimingPrompt = {
    system: `Listen to the ORIGINAL video audio and align the supplied exact tokens to what is spoken.
Do not transcribe new words, change tokenization, change sentences, or infer evenly spaced times.
Return JSON only: {"lines":[{"i":originalLineIndex,"tokens":[{"i":originalTokenIndex,"start":number,"end":number}]}]}.
Return every requested line and every token exactly once. Times MUST be absolute seconds from the start of the original video, within the supplied sentence bounds. Silent punctuation has equal start/end at the preceding word's end.
Listen for the actual onset and offset of each word, including particles. Do not spread tokens proportionally across a sentence. If any word cannot be aligned confidently from the audio, return {"lines":[]} instead of guessing.`,
    user: JSON.stringify({ lines: sketch }), videoId: source.videoId,
    startSec: Math.max(0, source.sourceStartSec + Math.min(...source.lines.map((line) => line.start)) - 0.2),
    endSec: source.sourceStartSec + Math.min(source.durationSec, Math.max(...source.lines.map((line) => line.end)) + 0.2),
  };
  try {
    const text = options.request ? await options.request(prompt) : (await geminiAnalyzeYouTubeSegment({
      model: geminiModelAnalyze(), system: prompt.system, user: prompt.user,
      youtubeUrl: `https://www.youtube.com/watch?v=${source.videoId}`,
      startSec: prompt.startSec, endSec: prompt.endSec,
    })).text;
    const parsed = parseJsonObject(text);
    if (!Array.isArray(parsed.lines) || parsed.lines.length !== indexes.length) throw new Error("Incomplete word alignment");
    const replacements = new Map<number, TimedLine>();
    for (const raw of parsed.lines) {
      const row = raw as { i: number; tokens: { i: number; start: number; end: number }[] };
      if (!Number.isInteger(row.i) || !indexes.includes(row.i) || replacements.has(row.i)) throw new Error("Invalid alignment line index");
      const original = source.lines[row.i];
      if (!Array.isArray(row.tokens) || row.tokens.length !== original.tokens.length) throw new Error("Incomplete token alignment");
      const times = new Map<number, { start: number; end: number }>();
      for (const token of row.tokens) {
        if (!Number.isInteger(token.i) || token.i < 0 || token.i >= original.tokens.length || times.has(token.i) ||
            !Number.isFinite(token.start) || !Number.isFinite(token.end)) throw new Error("Invalid alignment token");
        times.set(token.i, { start: token.start - source.sourceStartSec, end: token.end - source.sourceStartSec });
      }
      replacements.set(row.i, { ...original, timing: "word", tokens: original.tokens.map((token, i) => ({ ...token, ...times.get(i)! })) });
    }
    const verified = assessTiming(source.lines.map((line, i) => replacements.get(i) ?? line));
    if (verified.mode !== "word") throw new Error("Audio alignment failed timing validation: " + verified.problems.join("; "));
    return { ok: true, lines: verified.lines, repaired: indexes.length };
  } catch (error) {
    if (error instanceof AiBudgetError) return { ok: false, reason: "quota", detail: "Word alignment allowance reached" };
    return { ok: false, reason: "unverified", detail: error instanceof Error ? error.message : "Word timing not verified" };
  }
}
