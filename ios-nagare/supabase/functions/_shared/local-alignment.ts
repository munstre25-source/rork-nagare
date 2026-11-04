import { isPunctuationSurface } from "./timing.ts";
import type { TranslationSource } from "./translation-review.ts";

export const LOCAL_ALIGNMENT_MODEL = "Qwen/Qwen3-ForcedAligner-0.6B";
export const LOCAL_ALIGNMENT_REVISION = "c7cbfc2048c462b0d63a45797104fc9db3ad62b7";
export const LOCAL_DTW_ALIGNMENT_MODEL = "dropbox-dash/faster-whisper-large-v3-turbo";
export const LOCAL_DTW_ALIGNMENT_REVISION = "0a363e9161cbc7ed1431c9597a8ceaf0c4f78fcf";
export type LocalAlignment = {
  version: number; method: string; model: string; revision: string;
  videoId: string; sourceStartSec: number; durationSec: number;
  audioSha256: string; sampleRate: number; audioDurationSec: number;
  lines: Array<{ start: number; end: number; tokens: Array<{start: number; end: number}> }>;
};

/** Admin-supplied results from the offline operator. No paid review or guessed times. */
export function applyLocalAlignment(source: TranslationSource, input: LocalAlignment): TranslationSource["lines"] {
  const supported = (input.method === "local-forced-alignment" && input.model === LOCAL_ALIGNMENT_MODEL && input.revision === LOCAL_ALIGNMENT_REVISION) ||
    (input.method === "local-attention-dtw" && input.model === LOCAL_DTW_ALIGNMENT_MODEL && input.revision === LOCAL_DTW_ALIGNMENT_REVISION);
  if (input.version !== 1 || !supported ||
      !/^[a-f0-9]{64}$/.test(input.audioSha256) || input.sampleRate !== 16000 ||
      !Number.isFinite(input.audioDurationSec) || Math.abs(input.audioDurationSec - source.durationSec) > .25 ||
      input.videoId !== source.videoId || input.sourceStartSec !== source.sourceStartSec || input.durationSec !== source.durationSec ||
      !Array.isArray(input.lines) || input.lines.length !== source.lines.length || input.lines.length === 0) {
    throw new Error("Local alignment provenance or source bounds do not match");
  }
  let previousEnd = 0;
  return source.lines.map((line, i) => {
    const aligned = input.lines[i];
    if (!aligned || !Number.isFinite(aligned.start) || !Number.isFinite(aligned.end) ||
        aligned.start < previousEnd || aligned.end <= aligned.start || aligned.end > source.durationSec + .001 ||
        !Array.isArray(aligned.tokens) || aligned.tokens.length !== line.tokens.length) {
      throw new Error(`Local alignment line[${i}] is incomplete or outside its source`);
    }
    let cursor = aligned.start;
    const tokens = line.tokens.map((token, j) => {
      const span = aligned.tokens[j];
      if (!span || !Number.isFinite(span.start) || !Number.isFinite(span.end) ||
          span.start < cursor - .001 || span.start < aligned.start - .001 || span.end > aligned.end + .001 ||
          span.end < span.start || (!isPunctuationSurface(token.surface) && span.end <= span.start) ||
          span.end - span.start > Math.max(2.5, [...token.surface].length * .7)) {
        throw new Error(`Local alignment token[${i}][${j}] is missing or implausible`);
      }
      cursor = span.end;
      // All text/dictionary fields come exclusively from the database snapshot.
      return { ...token, start: span.start, end: span.end };
    });
    if (!tokens.some((token) => !isPunctuationSurface(token.surface))) throw new Error("No spoken tokens");
    previousEnd = aligned.end;
    return { ...line, start: aligned.start, end: aligned.end, tokens, timing: "word" };
  });
}

export function snapshotJson(value: unknown): string {
  if (Array.isArray(value)) return "[" + value.map(snapshotJson).join(",") + "]";
  if (value && typeof value === "object") {
    const record = value as Record<string, unknown>;
    return "{" + Object.keys(record).sort().map((key) => JSON.stringify(key) + ":" + snapshotJson(record[key])).join(",") + "}";
  }
  return JSON.stringify(value);
}
