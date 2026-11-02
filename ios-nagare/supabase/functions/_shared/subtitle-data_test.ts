import { assert, assertEquals } from "jsr:@std/assert@1";
import { normalizeHeardLines, subtitleEnrichmentIssue } from "./subtitle-data.ts";
import { hearSystem, hearSystemCatalog } from "./enrich.ts";
import { promptVersion, subtitlePromptVersion } from "./env.ts";
import { assessTiming, toClipRelative, type TimedLine } from "./timing.ts";

function example(): TimedLine[] {
  return [{
    start: 10, end: 12, timing: "word", translation: "Wash your face?",
    tokens: [
      { surface: "顔", reading: "かお", romaji: "KAO", pos: "noun", start: 10, end: 10.5, definitions: ["face"] },
      { surface: "を", romaji: "o", pos: "particle", start: 10.5, end: 10.7, definitions: ["object marker"] },
      { surface: "洗える", reading: "あらえる", romaji: "araeru", pos: "verb", start: 10.7, end: 12, definitions: ["can wash"], baseForm: "洗う" },
      { surface: "？", romaji: "", start: 12, end: 12, definitions: [] },
    ],
  }];
}

Deno.test("Japanese preprocessing requests meanings in its existing hearing pass", () => {
  const prompt = hearSystem("ja");
  assert(prompt.includes("Every tappable token must include definitions"));
  assert(!prompt.includes("Do NOT add definitions"));
  assert(hearSystemCatalog("ja").includes("same hearing pass"));
  assert(hearSystem("ko").includes("Do NOT add definitions"));
});

Deno.test("canonical enrichment preserves Japanese, meanings, order, and source timing without mutation", () => {
  const source = example();
  const before = structuredClone(source);
  const lines = normalizeHeardLines(source);
  assertEquals(source, before);
  assertEquals(lines[0].tokens.map((t) => t.surface).join(""), "顔を洗える？");
  assertEquals(lines[0].tokens.map((t) => [t.start, t.end]), [[10, 10.5], [10.5, 10.7], [10.7, 12], [12, 12]]);
  assertEquals(lines[0].tokens[0].romaji, "kao");
  assertEquals(lines[0].tokens[2].baseForm, "洗う");
  assertEquals(lines[0].translation, source[0].translation);
  assertEquals(lines[0].tokens[3].tappable, false);
  assertEquals(subtitleEnrichmentIssue(lines), null);
  assertEquals(normalizeHeardLines(lines), lines);
});

Deno.test("bad meanings are sanitized and incomplete new Japanese clips fail validation", () => {
  const source = example();
  source[0].tokens[0].definitions = [null, 3, "", " face ", "face", "long".repeat(60)];
  const lines = normalizeHeardLines(source);
  assertEquals(lines[0].tokens[0].definitions, ["face", "long".repeat(30)]);
  delete source[0].tokens[0].definitions;
  assertEquals(subtitleEnrichmentIssue(normalizeHeardLines(source)), "line[0].tokens[0] missing definitions");
  source[0].tokens[0].definitions = ["face"];
  source[0].tokens[0].reading = null;
  assertEquals(subtitleEnrichmentIssue(normalizeHeardLines(source)), "line[0].tokens[0] missing reading");
  source[0].tokens[0].reading = "かお";
  source[0].tokens[0].romaji = "";
  assertEquals(subtitleEnrichmentIssue(normalizeHeardLines(source)), "line[0].tokens[0] missing romaji");
});

Deno.test("word and sentence timing fallback retain the same enrichment", () => {
  const source = normalizeHeardLines(example());
  const word = toClipRelative(source, 10);
  assertEquals(word[0].tokens[0].start, 0);
  assertEquals(word[0].tokens[0].definitions, ["face"]);
  source[0].tokens[0].end = 9;
  const fallback = assessTiming(source);
  assertEquals(fallback.mode, "line");
  const relative = toClipRelative(fallback.lines, 10);
  assertEquals(relative[0].timing, "line");
  assertEquals(relative[0].tokens[0].reading, "かお");
  assertEquals(relative[0].tokens[0].definitions, ["face"]);
  assertEquals(subtitleEnrichmentIssue(relative), null);
});

Deno.test("legacy tokens remain normalizable without fabricated meanings or readings", () => {
  const source = example();
  delete source[0].tokens[0].reading;
  delete source[0].tokens[0].definitions;
  const lines = normalizeHeardLines(source);
  assertEquals(lines[0].tokens[0].definitions, []);
  assertEquals(lines[0].tokens[0].reading, null);
  assertEquals(lines[0].start, 10);
});

Deno.test("subtitle prompt updates do not invalidate cached word explanations", () => {
  const previous = Deno.env.get("SUBTITLE_PROMPT_VERSION");
  const explanationVersion = promptVersion();
  try {
    Deno.env.set("SUBTITLE_PROMPT_VERSION", "subtitle-test");
    assertEquals(subtitlePromptVersion(), "subtitle-test");
    assertEquals(promptVersion(), explanationVersion);
  } finally {
    if (previous === undefined) Deno.env.delete("SUBTITLE_PROMPT_VERSION");
    else Deno.env.set("SUBTITLE_PROMPT_VERSION", previous);
  }
});
