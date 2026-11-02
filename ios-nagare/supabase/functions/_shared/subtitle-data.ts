import type { TimedLine, TimedToken } from "./timing.ts";
import { isPunctuationSurface } from "./timing.ts";

function shortMeanings(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.filter((item): item is string => typeof item === "string")
    .map((item) => item.trim().slice(0, 120)).filter(Boolean))].slice(0, 3);
}

/** One canonical dataset, shared by every device and learning mode. No model calls. */
export function normalizeHeardLines(lines: TimedLine[]): TimedLine[] {
  const out: TimedLine[] = [];
  for (const line of lines) {
    const tokens: TimedToken[] = [];
    for (const token of line.tokens) {
      const surface = typeof token.surface === "string" ? token.surface.trim() : "";
      if (!surface) continue;
      const romaji = typeof token.romaji === "string" ? token.romaji.trim().toLowerCase() : "";
      const tappable = token.tappable !== false && !isPunctuationSurface(surface);
      tokens.push({
        ...token, surface, romaji, tappable,
        reading: typeof token.reading === "string" ? token.reading.trim() || null : null,
        definitions: shortMeanings(token.definitions),
      });
    }
    if (tokens.length > 0) out.push({ ...line, tokens });
  }
  return out;
}

/** Used only for newly processed Japanese clips; old stored clips stay compatible. */
export function subtitleEnrichmentIssue(lines: TimedLine[]): string | null {
  for (let i = 0; i < lines.length; i++) {
    for (let j = 0; j < lines[i].tokens.length; j++) {
      const token = lines[i].tokens[j];
      if (!token.tappable) continue;
      const field = !token.romaji ? "romaji"
        : /[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff々〆ヵヶ]/u.test(token.surface) && !token.reading ? "reading"
        : !Array.isArray(token.definitions) || token.definitions.length === 0 ? "definitions"
        : null;
      if (field) return `line[${i}].tokens[${j}] missing ${field}`;
    }
  }
  return null;
}
