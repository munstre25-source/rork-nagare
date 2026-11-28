import type { TimedLine, TimedToken } from "./timing.ts";

const STRUCTURAL_POS = new Set(["punctuation", "punct", "symbol", "記号", "補助記号"]);
const PLACEHOLDERS = new Set([
  "meaning available when you're back online",
  "meaning available when online",
  "unknown",
  "untranslated",
  "n/a",
]);

export function needsWordDefinition(token: TimedToken): boolean {
  return !STRUCTURAL_POS.has(String(token.pos ?? "").toLowerCase()) &&
    /[\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Han}]/u.test(token.surface.replaceAll("ー", ""));
}

function englishDefinitions(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  return Array.from(new Set(raw.flatMap((value) => {
    if (typeof value !== "string") return [];
    const text = value.trim();
    if (!text || text.length > 240 || PLACEHOLDERS.has(text.toLowerCase())) return [];
    if (/[A-Za-z]/.test(text) || (/^[0-9:.,+\-− ]+$/.test(text) && /\d/.test(text))) return [text];
    return [];
  }))).slice(0, 8);
}

export type WordDefinitionRequest = {
  id: string;
  word: string;
  lemma: string | null;
  reading: string | null;
  partOfSpeech: string | null;
  japanese: string;
  english: string;
};

function textOrNull(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value : null;
}

function unresolvedWords(lines: TimedLine[]): WordDefinitionRequest[] {
  return lines.flatMap((line, i) => {
    const japanese = line.tokens.map((token) => token.surface).join("").slice(0, 600);
    return line.tokens.flatMap((token, j) => {
      if (!needsWordDefinition(token) || englishDefinitions(token.definitions).length) return [];
      return [{
        id: i + ":" + j,
        word: token.surface,
        lemma: textOrNull(token.baseForm ?? token.base_form),
        reading: textOrNull(token.baseReading ?? token.base_reading ?? token.reading),
        partOfSpeech: textOrNull(token.pos),
        japanese,
        english: line.translation.slice(0, 600),
      }];
    });
  });
}

export class MissingWordDefinitions extends Error {
  readonly words: WordDefinitionRequest[];

  constructor(words: WordDefinitionRequest[]) {
    const examples = words.slice(0, 5).map(({ id, word }) => word + " [" + id + "]").join(", ");
    super("English word definitions need review for " + words.length + " token(s): " + examples);
    this.name = "MissingWordDefinitions";
    this.words = words;
  }
}

export function requireWordDefinitions(lines: TimedLine[]): TimedLine[] {
  const missing = unresolvedWords(lines);
  if (missing.length) throw new MissingWordDefinitions(missing);
  return lines;
}

/** Only add lexical metadata. The source text, readings, translations and timings stay intact. */
export async function completeWordDefinitions(
  lines: TimedLine[],
  resolve: (words: WordDefinitionRequest[]) => Promise<unknown>,
): Promise<TimedLine[]> {
  const missing = unresolvedWords(lines);
  if (!missing.length) return lines;
  if (missing.length > 40) throw new MissingWordDefinitions(missing);

  const response = await resolve(missing);
  if (!Array.isArray(response)) throw new MissingWordDefinitions(missing);
  const requested = new Map(missing.map((word) => [word.id, word.word]));
  const accepted = new Map<string, string[]>();
  const seen = new Set<string>();
  for (const entry of response) {
    if (!entry || typeof entry.id !== "string" || !requested.has(entry.id) || requested.get(entry.id) !== entry.word ||
      seen.has(entry.id)) {
      throw new MissingWordDefinitions(missing);
    }
    seen.add(entry.id);
    const definitions = englishDefinitions(entry.definitions);
    if (definitions.length) accepted.set(entry.id, definitions);
  }
  const unresolved = missing.filter((word) => !accepted.has(word.id));
  if (unresolved.length) throw new MissingWordDefinitions(unresolved);

  return lines.map((line, i) => ({
    ...line,
    tokens: line.tokens.map((token, j) => {
      const definitions = accepted.get(i + ":" + j);
      return definitions ? { ...token, definitions, tappable: true } : token;
    }),
  }));
}
