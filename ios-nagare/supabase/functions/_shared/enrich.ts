import { geminiModelExplain } from "./env.ts";
import { geminiGenerateJson, openRouterTextJson, parseJsonObject } from "./gemini.ts";

/** Gemini's job: hear the clip. Dictionary fields are added afterwards. */
export const HEAR_SYSTEM = `You transcribe a short Japanese YouTube video segment for language learners.
Return a single JSON object: { "lines": [ { "translation": string (English), "start": number, "end": number, "tokens": [ { "surface": string, "start": number, "end": number } ] } ] }.
Rules:
- Transcribe speech you can actually hear. Do not invent dialogue.
- Timestamps are absolute seconds within the given segment window; strictly increasing; each token within its line; each line within [startSec, endSec].
- Tokenize into learner-friendly units, with particles as their own tokens. Punctuation may be its own token.
- Japanese dialogue only; no English in surface.
- Do not add readings, romaji, part of speech, JLPT, or definitions.
- No markdown.`;

export const HEAR_SYSTEM_CATALOG = `${HEAR_SYSTEM}
- If the clip is mostly music, silence, or has no Japanese speech, return {"lines":[]}.`;

const ENRICH_SYSTEM = `You add dictionary fields to a Japanese transcript that was already heard.
Do not change surfaces. Do not add, remove, or reorder tokens or lines.
Return { "lines": [ { "i": number, "tokens": [ Token ] } ] }.
Each Token keeps the same "i" and adds: reading (hiragana when the surface has kanji; omit when the surface is already kana), romaji, pos, jlpt ("N5"|"N4"|"N3"|"N2"|"N1", omit if unknown), definitions (one to three short English glosses), tappable (false for punctuation), formality (optional), conjugationClass (optional), baseForm/baseReading/baseRomaji (optional, for conjugated stems), altReadings (optional string[]).
Every tappable token needs at least one definition.
No markdown.`;

const JLPT = new Set(["N5", "N4", "N3", "N2", "N1"]);

type HeardLine = {
  tokens?: unknown;
  [key: string]: unknown;
};

type HeardToken = {
  surface?: unknown;
  [key: string]: unknown;
};

/**
 * Fills reading, meaning, and JLPT on words Gemini already heard.
 * Surfaces and timestamps stay exactly as heard. OpenRouter does this;
 * Gemini text is only used when OpenRouter is unavailable.
 */
export async function enrichHeardLines(lines: unknown): Promise<unknown> {
  if (!Array.isArray(lines) || lines.length === 0) return lines;
  const sketch = lines.map((line, lineIndex) => {
    const row = line as HeardLine;
    const tokens = Array.isArray(row.tokens) ? row.tokens : [];
    return {
      i: lineIndex,
      translation: typeof row.translation === "string" ? row.translation : "",
      tokens: tokens.map((token, tokenIndex) => {
        const tok = token as HeardToken;
        return {
          i: tokenIndex,
          surface: typeof tok.surface === "string" ? tok.surface : "",
        };
      }),
    };
  });

  const user = JSON.stringify(sketch);
  const viaOpenRouter = await openRouterTextJson({
    system: ENRICH_SYSTEM,
    user,
    timeoutMs: 25_000,
  });
  let text = viaOpenRouter?.text ?? null;
  if (!text) {
    try {
      const viaGemini = await geminiGenerateJson({
        model: geminiModelExplain(),
        system: ENRICH_SYSTEM,
        user,
        timeoutMs: 20_000,
      });
      text = viaGemini.text;
    } catch {
      return lines;
    }
  }

  try {
    const parsed = parseJsonObject(text);
    return mergeEnrichment(lines, parsed.lines);
  } catch {
    return lines;
  }
}

function mergeEnrichment(lines: unknown[], extra: unknown): unknown[] {
  if (!Array.isArray(extra)) return lines;
  const byLine = new Map<number, unknown>();
  for (const row of extra) {
    if (!row || typeof row !== "object") continue;
    const index = (row as { i?: unknown }).i;
    if (typeof index === "number") byLine.set(index, row);
  }

  return lines.map((line, lineIndex) => {
    const source = line as HeardLine;
    const patch = byLine.get(lineIndex) as { tokens?: unknown } | undefined;
    if (!patch || !Array.isArray(source.tokens) || !Array.isArray(patch.tokens)) return line;
    const byToken = new Map<number, unknown>();
    for (const token of patch.tokens) {
      if (!token || typeof token !== "object") continue;
      const index = (token as { i?: unknown }).i;
      if (typeof index === "number") byToken.set(index, token);
    }
    return {
      ...source,
      tokens: source.tokens.map((token, tokenIndex) => {
        const heard = token as HeardToken;
        const added = byToken.get(tokenIndex);
        if (!added || typeof added !== "object") return token;
        return { ...heard, ...linguisticFields(added as Record<string, unknown>) };
      }),
    };
  });
}

function linguisticFields(raw: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  const reading = cleanString(raw.reading, 40);
  if (reading) out.reading = reading;
  const romaji = cleanString(raw.romaji, 60);
  if (romaji) out.romaji = romaji;
  const pos = cleanString(raw.pos, 40);
  if (pos) out.pos = pos;
  const formality = cleanString(raw.formality, 24);
  if (formality) out.formality = formality;
  const conjugationClass = cleanString(raw.conjugationClass, 24);
  if (conjugationClass) out.conjugationClass = conjugationClass;
  const baseForm = cleanString(raw.baseForm, 24);
  if (baseForm) out.baseForm = baseForm;
  const baseReading = cleanString(raw.baseReading, 40);
  if (baseReading) out.baseReading = baseReading;
  const baseRomaji = cleanString(raw.baseRomaji, 60);
  if (baseRomaji) out.baseRomaji = baseRomaji;
  if (typeof raw.jlpt === "string" && JLPT.has(raw.jlpt)) out.jlpt = raw.jlpt;
  if (typeof raw.tappable === "boolean") out.tappable = raw.tappable;
  const definitions = stringList(raw.definitions, 3, 80);
  if (definitions.length > 0) out.definitions = definitions;
  const altReadings = stringList(raw.altReadings, 4, 40);
  if (altReadings.length > 0) out.altReadings = altReadings;
  return out;
}

function cleanString(value: unknown, max: number): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  return trimmed.slice(0, max);
}

function stringList(value: unknown, maxItems: number, maxLen: number): string[] {
  if (!Array.isArray(value)) return [];
  const out: string[] = [];
  for (const item of value) {
    if (typeof item !== "string") continue;
    const trimmed = item.trim();
    if (!trimmed) continue;
    out.push(trimmed.slice(0, maxLen));
    if (out.length === maxItems) break;
  }
  return out;
}
