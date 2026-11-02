// deno-lint-ignore no-import-prefix
import { assertEquals } from "jsr:@std/assert@1";
import { contentClassification } from "./content-classification.ts";
const evidence = { classificationClear: true, classificationEvidence: "Adults discuss a topic in a podcast recording." };
Deno.test("podcasts and adult beginner lessons cannot be classified as kids", () => {
  assertEquals(contentClassification({ ...evidence, category: "kids", contentFormat: "podcast", childDirected: true }), null);
  assertEquals(contentClassification({ ...evidence, category: "kids", contentFormat: "children_program", childDirected: false }), null);
  assertEquals(contentClassification({ ...evidence, category: "kids", contentFormat: "language_lesson", childDirected: true }), null);
  assertEquals(contentClassification({ ...evidence, category: "podcast", contentFormat: "podcast", childDirected: false })?.category, "podcast");
  assertEquals(contentClassification({ ...evidence, category: "learning", contentFormat: "language_lesson", childDirected: false })?.category, "learning");
});
Deno.test("child-directed programs require clear audience evidence and matching format", () => {
  const valid = { ...evidence, category: "kids", contentFormat: "children_program", childDirected: true };
  assertEquals(contentClassification(valid)?.category, "kids");
  assertEquals(contentClassification({ ...valid, classificationClear: false }), null);
  assertEquals(contentClassification({ ...valid, classificationEvidence: "" }), null);
  assertEquals(contentClassification(undefined), null);
  assertEquals(contentClassification({ ...evidence, category: "interview", contentFormat: "podcast", childDirected: false }), null);
});
