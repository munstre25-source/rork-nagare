import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { CatalogLanguage, languageName } from "./catalog.ts";
import { geminiModelExplain } from "./env.ts";
import { geminiGenerateJson, parseJsonObject } from "./gemini.ts";
import { tryIncrementGeminiUsage } from "./limits.ts";

/**
 * Gemini's job: hear the clip and add learner fields in the same pass.
 *
 * Japanese learner fields, including short meanings, ride along in the single hearing
 * pass. All learning modes render the persisted lines without another AI call.
 * Rich explanations and legacy clips still use explain-word's shared cache on demand.
 */
export function hearSystem(language: CatalogLanguage): string {
  const name = languageName(language);
  const script = language === "ko"
    ? "Hangul only in surface. No Japanese."
    : "Japanese dialogue only; no English in surface.";
  const fields = language === "ko"
    ? "reading (Revised Romanization; omit when the surface is plain hangul), romaji, pos, jlpt (\"TOPIK1\"|\"TOPIK2\"|\"TOPIK3\"|\"TOPIK4\"|\"TOPIK5\"|\"TOPIK6\", omit if unknown; never N1–N5)"
    : "reading (hiragana when the surface has kanji; omit when the surface is already kana), romaji, pos, jlpt (\"N5\"|\"N4\"|\"N3\"|\"N2\"|\"N1\", omit if unknown)";
  const meanings = language === "ja"
    ? "definitions (one or two short English meanings in this sentence; for particles describe their grammatical role)"
    : "";
  const meaningRule = language === "ja"
    ? "Every tappable token must include definitions with at least one concise English meaning, romaji, and a hiragana reading when its surface contains kanji. Add these in this same hearing pass, never as a separate mode-specific transcript. Do not add ja_definitions."
    : "Do NOT add definitions, glosses, or meanings for tokens. Do not add ja_definitions.";
  return `You transcribe a short ${name} YouTube video segment for language learners.
Return a single JSON object: { "lines": [ { "translation": string (English), "start": number, "end": number, "tokens": [ { "surface": string, "start": number, "end": number, ${fields}${meanings ? `, ${meanings}` : ""}, "tappable": boolean, "baseForm": string (dictionary form, for conjugated stems), "baseReading": string, "baseRomaji": string } ] } ] }.
Rules:
- Transcribe speech you can actually hear. Do not invent dialogue.
- Each line is one short spoken phrase with its own English translation directly underneath in the player. Split a long turn at natural clause or sentence boundaries so the learner does not have to read several wrapped Japanese rows before seeing any English. Aim for roughly 2–6 seconds and at most one concise thought per line. Never split at a particle or in the middle of a word; keep a dependent phrase with the words needed to make its meaning clear. Short standalone replies and interjections are fine.
- Translate only the Japanese speech in that line into natural, grammatical English using the surrounding conversation for context. Do not combine the translations of multiple lines into the final line or repeat the whole turn in every line. Preserve meaning, tense, politeness, and uncertainty; supply ordinary English pronouns or articles when needed. Do not produce word-by-word glosses or untranslated Japanese text in the English field. Romanize spoken names when needed.
- Preserve Japanese negation, tense/aspect, possibility versus obligation, passive/causative forms, conditions, questions, and register. Resolve omitted subjects from audible conversation only. Do not invent identities, gender, relationships, or events from a plausible story; prefer neutral phrasing when faithful.
- Use standard English subject-verb agreement, articles, prepositions, word order, contractions, and punctuation. Translate idioms and brief replies naturally; do not translate by concatenating token meanings.
- Do not fill gaps in unclear audio by guessing. If a line cannot be transcribed and translated faithfully, omit it. Before returning, reread every English line for meaning, grammar, and completeness.
- Timestamps are absolute seconds within the given segment window; strictly increasing; each token within its line; each line within [startSec, endSec].
- Tokenize into learner-friendly units, with particles as their own tokens. Punctuation may be its own token and is tappable=false.
- ${script}
- Set tappable true for real words and false for punctuation and filler sounds.
- ${meaningRule}
- No markdown.`;
}

export function hearSystemCatalog(language: CatalogLanguage, maxClipSec = 40, preferWholeVideo = false): string {
  const selection = preferWholeVideo
    ? `This source is at most two minutes. Prefer the whole meaningful spoken scene, up to ${maxClipSec} seconds, when it is coherent and mostly speech. Trim intros, music, silence, and unrelated material; choose a shorter complete exchange if the whole scene is not a good lesson.`
    : `Find one coherent, self-contained exchange in the supplied video window. Prefer 15–30 seconds; never exceed ${maxClipSec} seconds or go below 8 seconds. Keep the full setup and response, and do not cut a sentence or turn in half.`;
  return `${hearSystem(language)}
- ${selection}
- Return between 2 and ${preferWholeVideo ? 80 : 24} spoken lines from that exchange, with enough context for a learner to understand what is happening. Skip music, titles, silence, and unrelated dialogue.
- Include numeric "clip_start_sec" and "clip_end_sec" using absolute source-video timestamps. Start shortly before the exchange begins and end shortly after it finishes. The chosen clip must be at least 8 and at most ${maxClipSec} seconds long.
- Include "video_orientation": "portrait" or "landscape" based on the source video's actual frame shape. A vertical scene letterboxed inside a 16:9 upload is landscape.
- If this window has no complete, useful exchange in that duration, return {"lines":[]}.
- Also include "difficulty": "Beginner" or "Intermediate" or "Advanced", judged only from the words and grammar you heard.`;
}

/**
 * Legacy second-pass enrichment, retained for explicit repair jobs only.
 * New Japanese clips include concise meanings in the hearing pass; older clips
 * can still resolve missing meanings through the local lexicon and shared lookup cache.
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
