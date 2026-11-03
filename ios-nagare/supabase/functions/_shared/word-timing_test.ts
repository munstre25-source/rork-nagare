import { assert, assertEquals } from "jsr:@std/assert@1";
import { repairWordTiming, type WordTimingSource } from "./word-timing.ts";

function source(): WordTimingSource {
  return { videoId: "dQw4w9WgXcQ", sourceStartSec: 10, durationSec: 2,
    lines: [{ start: 0, end: 2, translation: "Today.", timing: "line",
      tokens: [{ surface: "今日", start: 0, end: 2, reading: "きょう", definitions: ["today"] },
               { surface: "です", start: 0, end: 2, definitions: ["to be"] }] }] };
}
const good = { lines: [{ i: 0, tokens: [{ i: 0, start: 10.1, end: 10.7 }, { i: 1, start: 10.8, end: 11.8 }] }] };

Deno.test("audio repair preserves content and converts absolute token times to clip-relative", async () => {
  const original = source();
  const before = structuredClone(original);
  const result = await repairWordTiming(original, { consumeUsage: () => Promise.resolve(true), request: (prompt) => {
    assert(prompt.user.includes("今日"));
    assert(prompt.system.includes("actual onset and offset"));
    assertEquals(prompt.startSec, 9.8);
    assertEquals(prompt.endSec, 12);
    return Promise.resolve(JSON.stringify(good));
  } });
  assert(result.ok);
  assertEquals(result.repaired, 1);
  assertEquals(result.lines[0].timing, "word");
  assert(Math.abs(result.lines[0].tokens[0].start - 0.1) < 0.00001);
  assertEquals(result.lines[0].tokens[0].reading, "きょう");
  assertEquals(result.lines[0].tokens[0].definitions, ["today"]);
  assertEquals(result.lines[0].translation, original.lines[0].translation);
  assertEquals(original, before);
});

Deno.test("valid word timings do not spend another AI call", async () => {
  const input = source();
  input.lines[0].tokens[0].start = 0.1; input.lines[0].tokens[0].end = 0.7;
  input.lines[0].tokens[1].start = 0.8; input.lines[0].tokens[1].end = 1.8;
  const result = await repairWordTiming(input, { consumeUsage: () => { throw new Error("must not charge"); } });
  assert(result.ok);
  assertEquals(result.repaired, 0);
});

Deno.test("quota refusal never fabricates timings or calls AI", async () => {
  const result = await repairWordTiming(source(), { consumeUsage: () => Promise.resolve(false),
    request: () => { throw new Error("must not call"); } });
  assert(!result.ok);
  assertEquals(result.reason, "quota");
});

for (const [name, payload] of [
  ["missing line", { lines: [] }],
  ["missing token", { lines: [{ i: 0, tokens: [{ i: 0, start: 10.1, end: 10.7 }] }] }],
  ["duplicate token", { lines: [{ i: 0, tokens: [{ i: 0, start: 10.1, end: 10.7 }, { i: 0, start: 10.8, end: 11.8 }] }] }],
  ["wrong line", { lines: [{ i: 1, tokens: good.lines[0].tokens }] }],
  ["outside source", { lines: [{ i: 0, tokens: [{ i: 0, start: 2, end: 3 }, { i: 1, start: 3, end: 4 }] }] }],
  ["repeated sentence windows", { lines: [{ i: 0, tokens: [{ i: 0, start: 10, end: 12 }, { i: 1, start: 10, end: 12 }] }] }],
] as const) {
  Deno.test("rejects " + name + " without altering original content", async () => {
    const input = source(); const before = structuredClone(input);
    const result = await repairWordTiming(input, { consumeUsage: () => Promise.resolve(true), request: () => Promise.resolve(JSON.stringify(payload)) });
    assert(!result.ok);
    assertEquals(result.reason, "unverified");
    assertEquals(input, before);
  });
}

Deno.test("AI failure is held instead of accepting sentence-only content", async () => {
  const result = await repairWordTiming(source(), { consumeUsage: () => Promise.resolve(true), request: () => Promise.reject(new Error("unavailable")) });
  assert(!result.ok);
  assertEquals(result.reason, "unverified");
});

Deno.test("invalid source bounds consume no budget", async () => {
  const input = source(); input.lines[0].end = 20;
  const result = await repairWordTiming(input, { consumeUsage: () => { throw new Error("must not charge"); } });
  assert(!result.ok);
  assertEquals(result.reason, "unverified");
});
