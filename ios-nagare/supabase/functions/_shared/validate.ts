/** Clip / lines validation shared by analyze-clip and publish-clip. */

export const CATEGORIES = new Set([
  "anime",
  "drama",
  "variety",
  "vtuber",
  "interview",
  "kids",
  "gaming",
  "learning",
  "podcast",
]);

export const DIFFICULTIES = new Set(["Beginner", "Intermediate", "Advanced"]);

export type TokenLike = {
  surface?: unknown;
  start?: unknown;
  end?: unknown;
  romaji?: unknown;
  pos?: unknown;
  definitions?: unknown;
  tappable?: unknown;
  reading?: unknown;
  altReadings?: unknown;
  [key: string]: unknown;
};

export type LineLike = {
  tokens?: unknown;
  translation?: unknown;
  start?: unknown;
  end?: unknown;
};

export type ValidationResult = { ok: true } | { ok: false; error: string };

/** Deterministic sanity checks only; these cannot establish semantic translation accuracy. */
export function translationQualityIssue(value: unknown): string | null {
  if (typeof value !== "string" || !value.trim()) return "translation required";
  const text = value.trim();
  if (/^(?:translation|meaning) (?:unavailable|pending)|^this word$/i.test(text)) {
    return "translation is a placeholder";
  }
  if (/[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7a3]/u.test(text)) {
    return "translation contains untranslated source-language text";
  }
  if (/^(?:test|todo|tbd|n\/a|undefined|null)$/i.test(text)) {
    return "translation is a placeholder";
  }
  if (/^(?:translation|english translation)\s*:/i.test(text) || /\uFFFD/u.test(text)) {
    return "translation contains generation artifacts";
  }
  const standard = text.replace(/[’‘]/gu, "'");
  if (/^(?:(?:he|she|it)\s+(?:are|were|have|don't)\b|(?:you|we|they)\s+(?:is|was|has|doesn't)\b|i\s+(?:is|are|has|doesn't)\b)/i.test(standard)) {
    return "translation has subject-verb disagreement";
  }
  if (/^[a-z]$/i.test(text)) return "translation is a single letter";
  if (/,\s*["'”’]?$/u.test(text) || /\b(?:and|but|because)\s*$/i.test(text)) {
    return "translation ends mid-thought";
  }
  return null;
}

/** A pair of complete sentences should be two timed cards, each with its own English. */
export function lineAlignmentIssue(surfaces: string, translation: string): string | null {
  const japaneseEnds = [...surfaces.matchAll(/[。！？!?]/gu)].length;
  const englishEnds = [...translation.matchAll(/[.!?](?=\s|$)/gu)].length;
  if (japaneseEnds >= 2 && englishEnds >= 2) {
    return "multiple translated sentences must be separate lines";
  }
  return null;
}

function isFiniteNumber(n: unknown): n is number {
  return typeof n === "number" && Number.isFinite(n);
}

/** Hiragana, katakana, kanji, prolonged sound mark, iteration marks, common JP punctuation. */
function isJapaneseChar(ch: string): boolean {
  const cp = ch.codePointAt(0) ?? 0;
  return (
    (cp >= 0x3040 && cp <= 0x309f) || // hiragana
    (cp >= 0x30a0 && cp <= 0x30ff) || // katakana
    (cp >= 0x4e00 && cp <= 0x9fff) || // CJK
    (cp >= 0x3400 && cp <= 0x4dbf) || // CJK ext A
    cp === 0x3005 ||
    cp === 0x30fc ||
    (cp >= 0x3000 && cp <= 0x303f) // CJK punctuation
  );
}

export function mostlyJapanese(text: string, minRatio = 0.55): boolean {
  const chars = [...text].filter((c) => !/\s/.test(c));
  if (chars.length === 0) return false;
  const jp = chars.filter(isJapaneseChar).length;
  return jp / chars.length >= minRatio;
}

/** Hangul syllables, jamo, hanja, and CJK punctuation. */
function isKoreanChar(ch: string): boolean {
  const cp = ch.codePointAt(0) ?? 0;
  return (
    (cp >= 0xac00 && cp <= 0xd7a3) ||
    (cp >= 0x1100 && cp <= 0x11ff) ||
    (cp >= 0x3130 && cp <= 0x318f) ||
    (cp >= 0x4e00 && cp <= 0x9fff) ||
    (cp >= 0x3000 && cp <= 0x303f)
  );
}

export function mostlyKorean(text: string, minRatio = 0.55): boolean {
  const chars = [...text].filter((c) => !/\s/.test(c));
  if (chars.length === 0) return false;
  const ko = chars.filter(isKoreanChar).length;
  return ko / chars.length >= minRatio;
}

export function validateEnums(
  category: string,
  difficulty: string,
): ValidationResult {
  if (!CATEGORIES.has(category)) {
    return { ok: false, error: `Invalid category: ${category}` };
  }
  if (!DIFFICULTIES.has(difficulty)) {
    return { ok: false, error: `Invalid difficulty: ${difficulty}` };
  }
  return { ok: true };
}

/**
 * Validate lines JSON:
 * - non-empty lines and tokens with non-empty surfaces
 * - timestamps strictly increasing and clamped to [startSec, endSec]
 * - joined surfaces mostly Japanese, or mostly Korean when language is "ko"
 * - enums checked separately by callers when present
 */
export function validateLines(
  lines: unknown,
  startSec: number,
  endSec: number,
  language: "ja" | "ko" = "ja",
): ValidationResult {
  if (!Array.isArray(lines) || lines.length === 0) {
    return { ok: false, error: "lines must be a non-empty array" };
  }
  if (!(endSec > startSec)) {
    return { ok: false, error: "endSec must be greater than startSec" };
  }

  let prevEnd = startSec - 0.0001;
  const surfaces: string[] = [];

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i] as LineLike;
    if (!isFiniteNumber(line.start) || !isFiniteNumber(line.end)) {
      return { ok: false, error: `line[${i}] missing numeric start/end` };
    }
    if (line.start < startSec || line.end > endSec) {
      return {
        ok: false,
        error: `line[${i}] timestamps must be within [${startSec}, ${endSec}]`,
      };
    }
    if (line.end <= line.start) {
      return { ok: false, error: `line[${i}] end must be > start` };
    }
    if (line.start < prevEnd) {
      return {
        ok: false,
        error: `line[${i}] start must be strictly after previous end`,
      };
    }
    prevEnd = line.end;

    const translationIssue = translationQualityIssue(line.translation);
    if (translationIssue) return { ok: false, error: `line[${i}] ${translationIssue}` };

    if (!Array.isArray(line.tokens) || line.tokens.length === 0) {
      return { ok: false, error: `line[${i}] tokens must be non-empty` };
    }

    const lineText = line.tokens.map((token: TokenLike) =>
      typeof token.surface === "string" ? token.surface : "").join("");
    const alignmentIssue = lineAlignmentIssue(lineText, String(line.translation));
    if (alignmentIssue) return { ok: false, error: `line[${i}] ${alignmentIssue}` };

    let tokenPrev = line.start - 0.0001;
    for (let t = 0; t < line.tokens.length; t++) {
      const tok = line.tokens[t] as TokenLike;
      if (typeof tok.surface !== "string" || tok.surface.trim() === "") {
        return {
          ok: false,
          error: `line[${i}].tokens[${t}] surface must be non-empty`,
        };
      }
      surfaces.push(tok.surface);
      if (!isFiniteNumber(tok.start) || !isFiniteNumber(tok.end)) {
        return {
          ok: false,
          error: `line[${i}].tokens[${t}] missing numeric start/end`,
        };
      }
      if (tok.start < line.start || tok.end > line.end) {
        return {
          ok: false,
          error: `line[${i}].tokens[${t}] must stay within line bounds`,
        };
      }
      // Punctuation the hearing pass marks non-tappable is often an instant (start == end);
      // the catalog pipeline publishes those and the client handles them. Words must have length.
      if (tok.end < tok.start || (tok.end === tok.start && tok.tappable !== false)) {
        return {
          ok: false,
          error: `line[${i}].tokens[${t}] end must be > start`,
        };
      }
      if (tok.start < tokenPrev) {
        return {
          ok: false,
          error: `line[${i}].tokens[${t}] timestamps must be strictly increasing`,
        };
      }
      tokenPrev = tok.end;
    }
  }

  const joined = surfaces.join("");
  if (language === "ko") {
    if (!mostlyKorean(joined)) {
      return { ok: false, error: "transcript text must be mostly Korean" };
    }
  } else if (!mostlyJapanese(joined)) {
    return { ok: false, error: "transcript text must be mostly Japanese" };
  }

  return { ok: true };
}

/** Clamp and lightly normalize numeric timings onto [startSec, endSec] before validation when repairing AI output is not desired — callers validate strictly. */
export function durationFromLines(lines: LineLike[], fallback: number): number {
  const last = lines[lines.length - 1];
  if (last && isFiniteNumber(last.end)) return last.end;
  return fallback;
}
