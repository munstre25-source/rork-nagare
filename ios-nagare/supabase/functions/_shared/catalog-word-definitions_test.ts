import { assertEquals, assertRejects, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { completeWordDefinitions, MissingWordDefinitions, requireWordDefinitions } from "./catalog-word-definitions.ts";
import type { TimedLine } from "./timing.ts";

function lines(): TimedLine[] {
  return [{
    start: 0,
    end: 2,
    timing: "word",
    translation: "Everyone will come.",
    tokens: [
      { surface: "みんな", start: 0, end: 1, definitions: ["everyone"] },
      { surface: "来る", reading: "くる", start: 1, end: 2, definitions: ["こちらへ近づく"], tappable: false },
      { surface: "ぁ", pos: "punct", start: 2, end: 2 },
      { surface: "JLPT", pos: "noun", start: 2, end: 2 },
    ],
  }];
}

Deno.test("publication fills word definitions in one pass and preserves transcript and timings", async () => {
  const input = lines();
  const completed = await completeWordDefinitions(input, async (words) => {
    assertEquals(words.map(({ id, word, reading }) => [id, word, reading]), [["0:1", "来る", "くる"]]);
    return [{ id: "0:1", word: "来る", definitions: ["to come"] }];
  });
  assertEquals(completed[0].translation, input[0].translation);
  assertEquals(completed[0].tokens[0], input[0].tokens[0]);
  assertEquals(completed[0].tokens[2], input[0].tokens[2]);
  assertEquals(completed[0].tokens[3], input[0].tokens[3]);
  assertEquals(completed[0].tokens[1], { ...input[0].tokens[1], tappable: true, definitions: ["to come"] });
  assertEquals(requireWordDefinitions(completed), completed);
  assertEquals(await completeWordDefinitions(completed, async () => { throw new Error("Unexpected resolver call"); }), completed);
});

Deno.test("publication holds unresolved words and rejects misaddressed or duplicate meanings", async () => {
  assertThrows(() => requireWordDefinitions(lines()), MissingWordDefinitions, "来る");
  for (const response of [
    [{ id: "0:1", word: "来る", definitions: ["untranslated"] }],
    [{ id: "0:0", word: "みんな", definitions: ["everyone"] }],
    [
      { id: "not-a-token", definitions: ["extra definition"] },
      { id: "0:1", word: "来る", definitions: ["to come"] },
    ],
    [
      { id: "0:1", word: "来る", definitions: ["to come"] },
      { id: "0:1", word: "来る", definitions: ["to approach"] },
    ],
  ]) {
    await assertRejects(() => completeWordDefinitions(lines(), async () => response), MissingWordDefinitions);
  }
});
