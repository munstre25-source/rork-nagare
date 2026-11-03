import { handler } from "../review-catalog/index.ts";
import { assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { applyLocalAlignment, LOCAL_ALIGNMENT_MODEL, LOCAL_ALIGNMENT_REVISION, type LocalAlignment } from "./local-alignment.ts";
import type { TranslationSource } from "./translation-review.ts";
const source: TranslationSource = { videoId: "abcdefghijk", sourceStartSec: 8, durationSec: 3,
  lines: [{ start: 0, end: 3, timing: "line", translation: "Hello there!", tokens: [
    { surface: "hello", start: 0, end: 3, definitions: ["greeting"] },
    { surface: "!", start: 0, end: 3 }, { surface: "there", start: 0, end: 3 },
  ] }] };
function valid(): LocalAlignment { return {
  version: 1, method: "local-forced-alignment", model: LOCAL_ALIGNMENT_MODEL, revision: LOCAL_ALIGNMENT_REVISION,
  videoId: source.videoId, sourceStartSec: 8, durationSec: 3, audioSha256: "a".repeat(64),
  sampleRate: 16000, audioDurationSec: 3, lines: [{start: .1, end: 2.5, tokens: [
    {start: .1, end: .6}, {start: .6, end: .6}, {start: 2, end: 2.5},
  ]}],
}; }
Deno.test("local alignment preserves silence, source text, dictionary and original review", () => {
  const original = structuredClone(source);
  const out = applyLocalAlignment(source, valid());
  assertEquals(out[0].tokens[0].definitions, ["greeting"]);
  assertEquals(out[0].tokens[2].start, 2);
  assertEquals(out[0].translation, "Hello there!");
  assertEquals(out[0].timing, "word");
  assertEquals(out[0].translationReview, undefined);
  assertEquals(source, original);
});
Deno.test("local timing rejects changed source or incomplete provenance", () => {
  for (const patch of [{videoId: "other"}, {sourceStartSec: 9}, {durationSec: 4}, {model: "other"},
    {revision: "main"}, {audioSha256: "bad"}, {sampleRate: 8000}, {audioDurationSec: 2}, {version: 2}]) {
    assertThrows(() => applyLocalAlignment(source, { ...valid(), ...patch }));
  }
});
Deno.test("local timing rejects missing words, overlapping intervals, collapsed spoken words and NaN", () => {
  for (const tokens of [[], [{start: 0, end: 1}],
    [{start: .1, end: 0.1}, {start: .6, end: .6}, {start: 2, end: 2.5}],
    [{start: .1, end: 2.1}, {start: .6, end: .6}, {start: 2, end: 2.5}],
    [{start: NaN, end: .6}, {start: .6, end: .6}, {start: 2, end: 2.5}]]) {
    const input = valid(); input.lines[0].tokens = tokens;
    assertThrows(() => applyLocalAlignment(source, input));
  }
});
Deno.test("local timing ignores caller-supplied definitions and word mutations", () => {
  const input = valid();
  Object.assign(input.lines[0].tokens[0], {surface: "malicious", definitions: ["changed"]});
  const out = applyLocalAlignment(source, input);
  assertEquals(out[0].tokens[0].surface, "hello");
  assertEquals(out[0].tokens[0].definitions, ["greeting"]);
});
Deno.test("local timing rejects out of bounds and overlapping lines", () => {
  const input = valid(); input.lines[0].end = 4;
  assertThrows(() => applyLocalAlignment(source, input));
  const two = { ...source, lines: [...source.lines, ...source.lines] };
  assertThrows(() => applyLocalAlignment(two, {...valid(), lines: [...valid().lines, ...valid().lines]}));
});

Deno.test("local save never reserves AI budget or calls a provider", async () => {
  const names = ["SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY", "ADMIN_TOKEN"];
  const saved = names.map((name) => Deno.env.get(name));
  const originalFetch = globalThis.fetch;
  const calls: string[] = [];
  let persisted: Record<string, unknown> | undefined;
  try {
    Deno.env.set("SUPABASE_URL", "https://catalog.example.test");
    Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-service-role");
    Deno.env.set("ADMIN_TOKEN", "test-local-maintenance-token");
    globalThis.fetch = async (input, init) => {
      const url = new URL(input instanceof Request ? input.url : String(input));
      calls.push(url.pathname);
      assertEquals(url.hostname, "catalog.example.test");
      if (url.pathname === "/rest/v1/clips") return Response.json({
        id: "test-clip", published: true, video_id: source.videoId, source_start_sec: 8,
        duration_sec: 3, lines: source.lines, category: "learning",
      });
      if (url.pathname === "/rest/v1/rpc/catalog_review_hash") return Response.json("a".repeat(64));
      if (url.pathname === "/rest/v1/rpc/apply_catalog_local_alignment") {
        persisted = JSON.parse(String(init?.body));
        return Response.json(true);
      }
      throw new Error("Unexpected network call: " + url.pathname);
    };
    const response = await handler(new Request("https://example.test", { method: "POST",
      headers: {"x-admin-token": "test-local-maintenance-token", "content-type": "application/json"},
      body: JSON.stringify({id: "test-clip", apply: true, expectedLines: source.lines, localAlignment: valid()}),
    }));
    assertEquals(response.status, 200);
    assertEquals((await response.json()).paidApiCalls, 0);
    assertEquals(calls, ["/rest/v1/clips", "/rest/v1/rpc/catalog_review_hash", "/rest/v1/rpc/catalog_review_hash", "/rest/v1/rpc/apply_catalog_local_alignment"]);
    const lines = persisted!.p_lines as Array<Record<string, unknown>>;
    const receipt = lines[0].translationReview as Record<string, unknown>;
    assertEquals(receipt.wordTimingVerified, undefined);
    assertEquals(receipt.timingVerified, undefined);
    assertEquals((receipt.localAlignment as Record<string, unknown>).method, "local-forced-alignment");
    assertEquals(lines[0].translation, "Hello there!");
  } finally {
    globalThis.fetch = originalFetch;
    names.forEach((name, index) => saved[index] === undefined ? Deno.env.delete(name) : Deno.env.set(name, saved[index]!));
  }
});
