// deno-lint-ignore no-import-prefix
import { assertEquals } from "jsr:@std/assert@1";
import { failureStatus } from "./pipeline.ts";
import { handler as pipeline } from "../admin-pipeline/index.ts";
import { handler as review } from "../review-catalog/index.ts";
import { handler as seed, windowStarts } from "../seed-catalog-sources/index.ts";

Deno.test("maintenance endpoints reject unauthenticated requests before touching catalog data", async () => {
  for (const handler of [review, seed]) {
    assertEquals((await handler(new Request("https://example.test", { method: "POST", body: "{}" }))).status, 401);
    assertEquals((await handler(new Request("https://example.test", { method: "GET" }))).status, 405);
    assertEquals((await handler(new Request("https://example.test", { method: "OPTIONS" }))).status, 204);
  }
});
Deno.test("source seeding preserves bounded windows and defers the supplied hour-long videos", () => {
  assertEquals(windowStarts(7), []);
  assertEquals(windowStarts(8), [0]);
  assertEquals(windowStarts(120), [0]);
  assertEquals(windowStarts(121), [0, 90]);
  assertEquals(windowStarts(240), [0, 90, 180]);
  for (const seconds of [241, 1800, 3604, 3646, 3768, 3751, 3745, 3863, 3848, 3780, 7712, 3652, 5214]) {
    assertEquals(windowStarts(seconds), []);
  }
});

Deno.test("pipeline distinguishes technical errors, unknown evidence and actual rejection", () => {
  assertEquals(failureStatus("invalid", "review is not valid JSON"), "failed");
  assertEquals(failureStatus("unsupported", "Source visual subtitle check is incomplete"), "held");
  assertEquals(failureStatus("unsupported", "English subtitles are burned into the source video"), "rejected");
  assertEquals(failureStatus("gemini_cap"), "held");
  assertEquals(failureStatus("model_retryable"), "failed");
  assertEquals(failureStatus("pipeline_error"), "failed");
  assertEquals(failureStatus("transcript_invalid", "response is not a JSON object"), "failed");
  assertEquals(failureStatus("transcript_invalid", "line[0] translation ends mid-thought"), "rejected");
});

Deno.test("pipeline API rejects unauthorized requests", async () => {
  assertEquals((await pipeline(new Request("https://example.test", { method: "GET" }))).status, 401);
});
