import { assert, assertEquals } from "jsr:@std/assert@1";
import { assessTiming, toClipRelative, validateLineTimeline, wordTimingProblem, type TimedLine } from "./timing.ts";
import { maybeShiftRelative, parseIsoDurationSec, parseYouTubeUrl } from "./immersion.ts";

function line(start: number, end: number, tokens: Array<[string, number, number]>): Record<string, unknown> {
  return {
    translation: "test",
    start,
    end,
    tokens: tokens.map(([surface, s, e]) => ({ surface, start: s, end: e })),
  };
}

Deno.test("plausible word timings keep word-level sync", () => {
  const result = validateLineTimeline(
    [line(10, 12.4, [["今日", 10.05, 10.5], ["は", 10.5, 10.7], ["いい", 10.75, 11.1], ["天気", 11.1, 11.7], ["ですね", 11.7, 12.3], ["。", 12.3, 12.3]])],
    0,
    60,
  );
  assert(result.ok);
  const assessed = assessTiming(result.lines);
  assertEquals(assessed.mode, "word");
  assertEquals(assessed.lines[0]!.timing, "word");
  // Punctuation never takes the highlight.
  const period = assessed.lines[0]!.tokens[5]!;
  assertEquals(period.start, period.end);
});

Deno.test("missing or reversed token times fall back to the sentence", () => {
  const result = validateLineTimeline(
    [line(5, 8, [["おはよう", 7, 6], ["ございます", 6, 7.9]])],
    0,
    30,
  );
  assert(result.ok);
  const assessed = assessTiming(result.lines);
  assertEquals(assessed.mode, "line");
  const tokens = assessed.lines[0]!.tokens;
  assert(tokens.every((t) => t.start === 5 && t.end === 8));
});

Deno.test("interpolated uniform spacing is rejected", () => {
  const surfaces = ["私", "は", "学生", "です", "けど", "ね"];
  const tokens = surfaces.map((s, i) => [s, 20 + i * 0.5, 20.5 + i * 0.5] as [string, number, number]);
  const result = validateLineTimeline([line(20, 23, tokens)], 0, 60);
  assert(result.ok);
  assertEquals(wordTimingProblem(result.lines[0]!), "uniform spacing looks interpolated");
});

Deno.test("mixed clips report mixed timing", () => {
  const result = validateLineTimeline(
    [
      line(1, 3, [["はい", 1.1, 1.6], ["そう", 1.7, 2.2], ["です", 2.2, 2.8]]),
      line(3.2, 6, [["本当", Number.NaN, Number.NaN], ["に", 4, 4.2]]),
    ],
    0,
    30,
  );
  assert(result.ok);
  const assessed = assessTiming(result.lines);
  assertEquals(assessed.mode, "mixed");
  assertEquals(assessed.confidence, 0.5);
});

Deno.test("line-level problems reject the transcript", () => {
  assert(!validateLineTimeline([line(5, 4, [["あ", 4, 5]])], 0, 30).ok);
  assert(!validateLineTimeline([line(40, 45, [["あ", 40, 41]])], 0, 30).ok);
  assert(!validateLineTimeline([{ start: 1, end: 3, tokens: [{ surface: "あ" }] }], 0, 30).ok);
  assert(!validateLineTimeline([line(1, 3, [["hello", 1, 2], ["world", 2, 3]])], 0, 30).ok);
  assert(!validateLineTimeline([], 0, 30).ok);
});

Deno.test("clip-relative shift moves lines and tokens", () => {
  const result = validateLineTimeline([line(100, 102, [["はい", 100.1, 100.6], ["どうぞ", 100.7, 101.5]])], 90, 200);
  assert(result.ok);
  const relative = toClipRelative(assessTiming(result.lines).lines as TimedLine[], 99.5);
  assertEquals(relative[0]!.start, 0.5);
  assertEquals(relative[0]!.tokens[0]!.start, 0.6);
});

Deno.test("window-relative answers are shifted to absolute", () => {
  const raw: Record<string, unknown> = {
    clip_start_sec: 2,
    clip_end_sec: 40,
    lines: [line(3, 5, [["はい", 3.1, 3.5]]), line(6, 9, [["いいえ", 6.2, 7]])],
  };
  assert(maybeShiftRelative(raw, 150, 330));
  assertEquals(raw.clip_start_sec, 152);
  assertEquals((raw.lines as Array<{ start: number }>)[0]!.start, 153);
  const absolute: Record<string, unknown> = { lines: [line(160, 162, [["はい", 160.1, 160.5]])] };
  assert(!maybeShiftRelative(absolute, 150, 330));
});

Deno.test("YouTube URL forms", () => {
  assertEquals(parseYouTubeUrl("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=43s"), { videoId: "dQw4w9WgXcQ", startSec: 43 });
  assertEquals(parseYouTubeUrl("https://youtu.be/dQw4w9WgXcQ?t=1m5s")?.startSec, 65);
  assertEquals(parseYouTubeUrl("youtube.com/shorts/dQw4w9WgXcQ")?.videoId, "dQw4w9WgXcQ");
  assertEquals(parseYouTubeUrl("https://m.youtube.com/embed/dQw4w9WgXcQ?start=12")?.startSec, 12);
  assertEquals(parseYouTubeUrl("https://www.youtube.com/live/dQw4w9WgXcQ")?.videoId, "dQw4w9WgXcQ");
  assertEquals(parseYouTubeUrl("dQw4w9WgXcQ")?.videoId, "dQw4w9WgXcQ");
  assertEquals(parseYouTubeUrl("https://vimeo.com/123"), null);
  assertEquals(parseYouTubeUrl("https://www.youtube.com/watch?v=short"), null);
  assertEquals(parseYouTubeUrl("not a url at all"), null);
});

Deno.test("ISO 8601 durations", () => {
  assertEquals(parseIsoDurationSec("PT1M5S"), 65);
  assertEquals(parseIsoDurationSec("PT2H"), 7200);
  assertEquals(parseIsoDurationSec("P0D"), 0);
  assertEquals(parseIsoDurationSec("garbage"), null);
});
