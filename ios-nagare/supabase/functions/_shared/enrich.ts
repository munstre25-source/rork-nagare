import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { CatalogLanguage, languageName } from "./catalog.ts";
import { geminiModelExplain } from "./env.ts";
import { geminiGenerateJson, parseJsonObject } from "./gemini.ts";
import { tryIncrementGeminiUsage } from "./limits.ts";

/** Gemini's job: hear the clip. Dictionary fields are added afterwards. */
export function hearSystem(language: CatalogLanguage): string {
  const name = languageName(language);
  const script = language === "ko"
    ? "Hangul only in surface. No Japanese."
    : "Japanese dialogue only; no English in surface.";
  return `You transcribe a short ${name} YouTube video segment for language learners.
Return a single JSON object: { "lines": [ { "translation": string (English), "start": number, "end": number, "tokens": [ { "surface": string, "start": number, "end": number } ] } ] }.
Rules:
- Transcribe speech you can actually hear. Do not invent dialogue.
- Timestamps are absolute seconds within the given segment window; strictly increasing; each token within its line; each line within [startSec, endSec].
- Tokenize into learner-friendly units, with particles as their own tokens. Punctuation may be its own token.
- ${script}
- Do not add readings, romaji, part of speech, JLPT, or definitions.
- No markdown.`;
}

export function hearSystemCatalog(language: CatalogLanguage): string {
  return `${hearSystem(language)}
- Return 2 to 4 short lines that form one complete everyday exchange (a greeting, an order, a question and its answer). Skip music, titles, and silence.
- If this window has no such exchange, return {"lines":[]}.
- Also include "difficulty": "Beginner" or "Intermediate" or "Advanced", judged only from the words and grammar you heard.`;
}

export const HEAR_SYSTEM = hearSystem("ja");

export const HEAR_SYSTEM_CATALOG = hearSystemCatalog("ja");

function enrichSystem(language: CatalogLanguage): string {
  const reading = language === "ko"
    ? "reading (Revised Romanization; omit when the surface is already plain hangul with no hanja)"
    : "reading (hiragana when the surface has kanji; omit when the surface is already kana)";
  const level = language === "ko"
    ? "jlpt (\"TOPIK1\"|\"TOPIK2\"|\"TOPIK3\"|\"TOPIK4\"|\"TOPIK5\"|\"TOPIK6\", omit if unknown). Do not use N1–N5."
    : "jlpt (\"N5\"|\"N4\"|\"N3\"|\"N2\"|\"N1\", omit if unknown)";
  return `You add dictionary fields to a ${languageName(language)} transcript that was already heard.
Do not change surfaces. Do not add, remove, or reorder tokens or lines.
Return { "lines": [ { "i": number, "tokens": [ Token ] } ] }.
Each Token keeps the same "i" and adds: ${reading}, romaji, pos, ${level}, definitions (one to three short English glosses), tappable (false for punctuation), formality (optional), conjugationClass (optional), baseForm/baseReading/baseRomaji (optional, for conjugated stems), altReadings (optional string[]).
Every tappable token needs at least one definition.
No markdown.`;
}

const JLPT = new Set(["N5", "N4", "N3", "N2", "N1"]);
const TOPIK = new Set(["TOPIK1", "TOPIK2", "TOPIK3", "TOPIK4", "TOPIK5", "TOPIK6"]);

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
 * Surfaces and timestamps stay exactly as heard. Uses the same Gemini key as transcription.
 * Returns the heard lines unchanged when the daily cap is spent or the model call fails.
 */
export async function enrichHeardLines(
  lines: unknown,
  supabase?: SupabaseClient,
  language: CatalogLanguage = "ja",
): Promise<unknown> {
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

  if (supabase && !(await tryIncrementGeminiUsage(supabase))) return lines;

  const user = JSON.stringify(sketch);
  let text: string;
  try {
    const viaGemini = await geminiGenerateJson({
      model: geminiModelExplain(),
      system: enrichSystem(language),
      user,
      timeoutMs: 25_000,
    });
    text = viaGemini.text;
  } catch {
    return lines;
  }

  try {
    const parsed = parseJsonObject(text);
    return mergeEnrichment(lines, parsed.lines, language);
  } catch {
    return lines;
  }
}

function mergeEnrichment(lines: unknown[], extra: unknown, language: CatalogLanguage): unknown[] {
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
        return { ...heard, ...linguisticFields(added as Record<string, unknown>, language) };
      }),
    };
  });
}

function topikLabel(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const match = value.trim().toUpperCase().replace(/\s+/g, "").match(/^(?:TOPIK)?([1-6])$/);
  return match ? `TOPIK${match[1]}` : null;
}

function linguisticFields(raw: Record<string, unknown>, language: CatalogLanguage): Record<string, unknown> {
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
  if (language === "ko") {
    const level = topikLabel(raw.jlpt) ?? topikLabel(raw.topik);
    if (level && TOPIK.has(level)) out.jlpt = level;
  } else if (typeof raw.jlpt === "string" && JLPT.has(raw.jlpt)) {
    out.jlpt = raw.jlpt;
  }
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
