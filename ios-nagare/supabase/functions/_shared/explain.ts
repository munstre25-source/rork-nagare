/** Validate and length-cap Gemini explain payloads before caching. */

const MAX_WORD = 80;
const MAX_STR = 500;
const MAX_DEFS = 8;
const MAX_DEF_LEN = 200;
const MAX_READINGS = 8;
const MAX_EXAMPLES = 6;
const MAX_RELATED = 8;
const MAX_CONTEXT = 1200;
const MAX_PAYLOAD_CHARS = 8000;

function asString(v: unknown, max: number): string | null {
  if (typeof v !== "string") return null;
  const t = v.trim();
  if (!t || t.length > max) return null;
  return t.slice(0, max);
}

function asStringArray(v: unknown, maxItems: number, maxLen: number): string[] | null {
  if (!Array.isArray(v)) return null;
  const out: string[] = [];
  for (const item of v.slice(0, maxItems)) {
    if (typeof item !== "string") continue;
    const t = item.trim().slice(0, maxLen);
    if (t) out.push(t);
  }
  return out;
}

export type LookupPayload = {
  word: string;
  readings: string[];
  romaji: string;
  pos: string;
  conjugation_class: string | null;
  definitions: string[];
  ja_definitions: string[];
  formality_note: string | null;
  audio_hint: string | null;
};

export type ContextPayload = {
  contextual_explanation: string;
  examples: string[];
  related_words: string[];
};

export function sanitizeLookup(
  raw: Record<string, unknown>,
  fallbackWord: string,
): LookupPayload | null {
  const word = asString(raw.word, MAX_WORD) ?? asString(fallbackWord, MAX_WORD);
  const definitions = asStringArray(raw.definitions, MAX_DEFS, MAX_DEF_LEN);
  const ja_definitions = asStringArray(raw.ja_definitions, MAX_DEFS, MAX_DEF_LEN) ?? [];
  if (!word || !definitions || definitions.length === 0) return null;

  const readings = asStringArray(raw.readings, MAX_READINGS, MAX_WORD) ?? [];
  const romaji = asString(raw.romaji, MAX_WORD) ?? "";
  const pos = asString(raw.pos, 40) ?? "word";
  const conjugation_class = asString(raw.conjugation_class, 40);
  const formality_note = asString(raw.formality_note, MAX_STR);
  const audio_hint = asString(raw.audio_hint, MAX_STR);

  const payload: LookupPayload = {
    word,
    readings,
    romaji,
    pos,
    conjugation_class,
    definitions,
    ja_definitions,
    formality_note,
    audio_hint,
  };
  if (JSON.stringify(payload).length > MAX_PAYLOAD_CHARS) return null;
  return payload;
}

export function sanitizeContext(raw: Record<string, unknown>): ContextPayload | null {
  const contextual_explanation = asString(raw.contextual_explanation, MAX_CONTEXT);
  if (!contextual_explanation) return null;
  const examples = asStringArray(raw.examples, MAX_EXAMPLES, MAX_STR) ?? [];
  const related_words = asStringArray(raw.related_words, MAX_RELATED, MAX_WORD) ?? [];
  const payload: ContextPayload = {
    contextual_explanation,
    examples,
    related_words,
  };
  if (JSON.stringify(payload).length > MAX_PAYLOAD_CHARS) return null;
  return payload;
}
