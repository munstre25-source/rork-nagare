/**
 * Pre-publication filter for public board posts and comments. Pure and unit-testable.
 * Rejects abusive language, sexual content, threats, links (spam) and contact details.
 * Text is normalised first so simple spacing, symbols and leetspeak don't slip through.
 */

const LEET: Record<string, string> = { "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s", "!": "i" };

// Whole-word stems, matched after normalisation. Kept short on purpose: obvious abuse only.
const BLOCKED_STEMS = [
  "fuck", "fucking", "fucker", "motherfucker", "shit", "bullshit", "bitch", "bastard", "cunt", "dick", "cock",
  "pussy", "whore", "slut", "asshole", "dumbass", "retard", "retarded", "faggot", "fag", "nigger", "nigga",
  "chink", "spic", "kike", "tranny", "rape", "rapist", "porn", "porno", "nude", "nudes", "sex", "sexy",
  "hentai", "onlyfans", "kill yourself", "kys", "killyourself", "nazi", "hitler",
  "ちんこ", "まんこ", "死ね", "殺す", "セックス", "エロ",
];

const LINK = /(https?:\/\/|www\.|\b[a-z0-9-]+\.(com|net|org|io|ru|xyz|top|ly|gg|me|co)\b)/i;
const EMAIL = /[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}/i;
const PHONE = /(\+?\d[\d\s().-]{8,}\d)/;

function leet(text: string): string {
  const lowered = text.toLowerCase().normalize("NFKC");
  let out = "";
  for (const ch of lowered) out += LEET[ch] ?? ch;
  return out;
}

/** Leetspeak undone, then runs of one letter collapsed ("fuuuck" -> "fuck"). */
export function normalizeForFilter(text: string): string {
  return leet(text).replace(/(\p{L})\1+/gu, "$1");
}

export type FilterResult = { ok: true } | { ok: false; reason: "language" | "link" | "contact" };

export function screenPublicText(text: string): FilterResult {
  if (LINK.test(text)) return { ok: false, reason: "link" };
  if (EMAIL.test(text) || PHONE.test(text)) return { ok: false, reason: "contact" };
  const forms = [leet(text), normalizeForFilter(text)];
  const squashed = forms.map((f) => f.replace(/[^\p{L}\p{N}]+/gu, ""));
  for (const stem of BLOCKED_STEMS) {
    if (/[^\x00-\x7F]/.test(stem)) {
      if (forms[0].includes(stem)) return { ok: false, reason: "language" };
      continue;
    }
    const word = new RegExp(`(^|[^a-z])${stem.replace(/ /g, "\\s*")}(s|es|ed|ing)?([^a-z]|$)`);
    if (forms.some((f) => word.test(f))) return { ok: false, reason: "language" };
    // Spaced-out spellings like "f u c k" become "fuck" once squashed.
    if (stem.length >= 4 && !stem.includes(" ") && squashed.includes(stem)) return { ok: false, reason: "language" };
  }
  return { ok: true };
}

export function filterMessage(reason: "language" | "link" | "contact"): string {
  switch (reason) {
    case "link": return "Links aren't allowed on the public board.";
    case "contact": return "Please don't share emails or phone numbers on the public board.";
    default: return "Please keep it respectful. Offensive language isn't allowed on the board.";
  }
}
