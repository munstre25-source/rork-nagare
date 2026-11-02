// Shared tests use versioned JSR imports rather than an import map.
// deno-lint-ignore no-import-prefix
import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  applyTranslationReview,
  sourceVisualIssue,
  hasCurrentTranslationReview,
  reviewJapaneseTranslations,
  TRANSLATION_REVIEW_SYSTEM,
  type TranslationSource,
} from "./translation-review.ts";
import { translationQualityIssue } from "./validate.ts";
import { GeminiError, videoOffset } from "./gemini.ts";
import { auditSubtitleTranslations } from "./translation-audit.ts";
import { clipRow } from "./immersion.ts";

function source(): TranslationSource {
  return {
    videoId: "dQw4w9WgXcQ",
    sourceStartSec: 10,
    durationSec: 8,
    lines: [{
      start: 0.2,
      end: 3,
      timing: "word",
      translation: "Can wash face you?",
      tokens: [
        {
          surface: "一人で",
          reading: "ひとりで",
          romaji: "hitori de",
          start: 0.2,
          end: 1,
          tappable: true,
        },
        {
          surface: "顔を",
          reading: "かおを",
          romaji: "kao o",
          start: 1,
          end: 1.5,
          tappable: true,
        },
        {
          surface: "洗える？",
          reading: "あらえる",
          romaji: "araeru",
          start: 1.5,
          end: 3,
          tappable: true,
        },
      ],
    }],
  };
}

function approved(i = 0): Record<string, unknown> {
  return {
    i,
    audioClear: true,
    timingMatchesAudio: true,
    sourceMatchesAudio: true,
    meaningAccurate: true,
    grammarCorrect: true,
    translation: "Can you wash your face by yourself?",
  };
}

Deno.test("translation sanity rejects clear grammar defects without rejecting brief replies or idioms", () => {
  for (
    const text of [
      "He are ready.",
      "They is here.",
      "I has a pen.",
      "She don’t know.",
      "TBD",
      "test",
      "English translation: Hello.",
      "Bad \uFFFD text",
    ]
  ) {
    assert(translationQualityIssue(text) !== null, text);
  }
  for (
    const text of [
      "No.",
      "Not yet.",
      "If I were you, I'd wait.",
      "They have arrived.",
      "She has a pen.",
      "It can't be helped.",
      "I don't know.",
      "You're welcome.",
    ]
  ) {
    assertEquals(translationQualityIssue(text), null, text);
  }
});

Deno.test("supported English corrections preserve all Japanese tokens, meanings, and timing", () => {
  const input = source().lines;
  const before = structuredClone(input);
  const result = applyTranslationReview(input, {
    lines: [{ ...approved(), start: 99, tokens: [], timing: "line" }],
  });
  assert(result.ok);
  assertEquals(input, before);
  assertEquals(result.lines[0], {
    ...before[0],
    translation: approved().translation,
  });
});

Deno.test("unclear audio, unsupported meanings, and unreviewed rows fail closed", () => {
  for (
    const flag of [
      "audioClear",
      "sourceMatchesAudio",
      "meaningAccurate",
      "grammarCorrect",
      "timingMatchesAudio",
    ]
  ) {
    const result = applyTranslationReview(source().lines, {
      lines: [{ ...approved(), [flag]: false }],
    });
    assert(!result.ok);
    assertEquals(result.reason, "unsupported");
    const missing = approved();
    delete missing[flag];
    assert(!applyTranslationReview(source().lines, { lines: [missing] }).ok);
  }
});

Deno.test("incomplete, duplicate, extra, or invalid indexes cannot approve a clip", () => {
  const input = source().lines;
  const two = [input[0], { ...input[0], start: 3, end: 6 }];
  for (
    const raw of [
      {},
      { lines: [] },
      { lines: [approved(), approved()] },
      { lines: [{ ...approved(), i: "0" }] },
      { lines: [{ ...approved(), i: 2 }] },
      { lines: [{ ...approved(), translation: "He are here." }] },
    ]
  ) assert(!applyTranslationReview(input, raw).ok);
  assert(!applyTranslationReview(two, { lines: [approved(), approved()] }).ok);
});

Deno.test("one review uses the original audio and cached unchanged subtitles consume no more usage", async () => {
  const input = source();
  let usage = 0;
  let generated = 0;
  const dependencies = {
    model: "review-model",
    consumeUsage: () => {
      usage++;
      return Promise.resolve(true);
    },
    generate: (
      call: {
        youtubeUrl: string;
        startSec: number;
        endSec: number;
        timeoutMs?: number;
        user: string;
      },
    ) => {
      generated++;
      assertEquals(
        call.youtubeUrl,
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
      );
      assertEquals([call.startSec, call.endSec, call.timeoutMs], [
        10,
        18,
        45_000,
      ]);
      assertEquals(
        JSON.parse(call.user).lines[0].japanese,
        "一人で顔を洗える？",
      );
      return Promise.resolve({
        model: "actual-review-model",
        text: JSON.stringify({ category: "drama", contentFormat: "scripted_drama", childDirected: false, classificationClear: true, classificationEvidence: "Two adults speak in a scripted scene.", visualCheckComplete: true, englishSubtitlesVisible: false, lines: [approved()] }),
      });
    },
  };
  const result = await reviewJapaneseTranslations(input, dependencies);
  assert(result.ok);
  assertEquals(result.reused, false);
  assertEquals([usage, generated], [1, 1]);
  const reviewed = { ...input, lines: result.lines };
  assert(await hasCurrentTranslationReview(reviewed));
  const again = await reviewJapaneseTranslations(reviewed, dependencies);
  assert(again.ok && again.reused);
  assertEquals([usage, generated], [1, 1]);
  assertEquals(input.lines[0].translation, "Can wash face you?");
});

Deno.test("changing any translation-relevant data invalidates a prior review", async () => {
  const input = source();
  const result = await reviewJapaneseTranslations(input, {
    model: "review-model",
    consumeUsage: () => Promise.resolve(true),
    generate: () =>
      Promise.resolve({
        model: "review-model",
        text: JSON.stringify({ category: "drama", contentFormat: "scripted_drama", childDirected: false, classificationClear: true, classificationEvidence: "Two adults speak in a scripted scene.", visualCheckComplete: true, englishSubtitlesVisible: false, lines: [approved()] }),
      }),
  });
  assert(result.ok);
  const reviewed = { ...input, lines: result.lines };
  for (
    const change of [
      (s: TranslationSource) => {
        s.videoId = "abcdefghijk";
      },
      (s: TranslationSource) => {
        s.sourceStartSec++;
      },
      (s: TranslationSource) => {
        s.durationSec++;
      },
      (s: TranslationSource) => {
        s.lines[0].translation = "A different meaning.";
      },
      (s: TranslationSource) => {
        s.lines[0].tokens[0].surface = "みんなで";
      },
      (s: TranslationSource) => {
        s.lines[0].tokens[0].start = 0.3;
      },
      (s: TranslationSource) => {
        s.lines[0].start = 0.1;
      },
      (s: TranslationSource) => {
        s.lines[0].translationReview = { version: 0 };
      },
    ]
  ) {
    const changed = structuredClone(reviewed);
    change(changed);
    assertEquals(await hasCurrentTranslationReview(changed), false);
  }
});

Deno.test("quota exhaustion and malformed review never fall back to the draft English", async () => {
  let generated = 0;
  const deps = {
    model: "review-model",
    consumeUsage: () => Promise.resolve(false),
    generate: () => {
      generated++;
      return Promise.resolve({ model: "review-model", text: "not JSON" });
    },
  };
  const quota = await reviewJapaneseTranslations(source(), deps);
  assert(!quota.ok && quota.reason === "quota");
  assertEquals(generated, 0);
  const malformed = await reviewJapaneseTranslations(source(), {
    ...deps,
    consumeUsage: () => Promise.resolve(true),
  });
  assert(!malformed.ok && malformed.reason === "invalid");
  assertEquals(generated, 1);
});

Deno.test("review provider failures propagate for bounded worker retry rather than approval", async () => {
  await assertRejects(() =>
    reviewJapaneseTranslations(source(), {
      model: "review-model",
      consumeUsage: () => Promise.resolve(true),
      generate: () =>
        Promise.reject(new GeminiError(503, "Provider unavailable")),
    }), GeminiError);
});

Deno.test("review requires source evidence rather than a confidence score", () => {
  assert(TRANSLATION_REVIEW_SYSTEM.includes("Independently listen"));
  assert(
    TRANSLATION_REVIEW_SYSTEM.includes(
      "Never guess or approve on confidence alone",
    ),
  );
  const result = applyTranslationReview(source().lines, {
    lines: [{
      i: 0,
      confidence: 1,
      translation: "Can you wash your face by yourself?",
    }],
  });
  assert(!result.ok);
});

Deno.test("invalid source bounds do not consume budget or make model calls", async () => {
  let calls = 0;
  const result = await reviewJapaneseTranslations({
    ...source(),
    sourceStartSec: -1,
  }, {
    model: "review-model",
    consumeUsage: () => {
      calls++;
      return Promise.resolve(true);
    },
    generate: () => {
      calls++;
      return Promise.resolve({ model: "review-model", text: "{}" });
    },
  });
  assert(!result.ok && result.reason === "invalid");
  assertEquals(calls, 0);
});

Deno.test("legacy audit flags defects and never calls fluent unreviewed English verified", async () => {
  const input = source();
  input.lines[0].translation = "Can you wash your face by yourself?";
  const report = await auditSubtitleTranslations([{ ...input, id: "legacy" }]);
  assertEquals(report.checkedLines, 1);
  assertEquals(report.issues, []);
  assertEquals(report.unreviewedClipIds, ["legacy"]);
  input.lines[0].translation = "Now then, from this moment on,";
  const broken = await auditSubtitleTranslations([{ ...input, id: "legacy" }]);
  assertEquals(broken.issues[0].issue, "translation ends mid-thought");
});

Deno.test("review survives catalog row serialization and republishing without another AI call", async () => {
  const input = { ...source(), sourceStartSec: 12.345 };
  const result = await reviewJapaneseTranslations(input, {
    model: "review-model",
    consumeUsage: () => Promise.resolve(true),
    generate: () =>
      Promise.resolve({
        model: "review-model",
        text: JSON.stringify({ category: "drama", contentFormat: "scripted_drama", childDirected: false, classificationClear: true, classificationEvidence: "Two adults speak in a scripted scene.", visualCheckComplete: true, englishSubtitlesVisible: false, lines: [approved()] }),
      }),
  });
  assert(result.ok);
  const row = JSON.parse(JSON.stringify(clipRow({
    id: "immersion-reviewed-test",
    video: {
      videoId: input.videoId,
      title: "Test",
      channelTitle: "Test",
      durationSec: 30,
    },
    draft: {
      clipStart: input.sourceStartSec,
      clipEnd: input.sourceStartSec + input.durationSec,
      lines: result.lines,
      difficulty: "Beginner",
      category: "anime",
      videoOrientation: "landscape",
      timingMode: "word",
      timingConfidence: 1,
      model: "hearing-model",
      promptVersion: "6",
    },
    category: "anime",
    published: true,
    withProvenance: true,
  })));
  assert(
    await hasCurrentTranslationReview({
      videoId: row.video_id,
      sourceStartSec: row.source_start_sec,
      durationSec: row.duration_sec,
      lines: row.lines,
    }),
  );
});

Deno.test("audio-approved Japanese clause continuations preserve slots with English ellipses", () => {
  const first = { ...source().lines[0], tokens: [{ surface: "では、", start: 0, end: 1 }], start: 0, end: 1 };
  const second = { ...source().lines[0], start: 1, end: 3 };
  const result = applyTranslationReview([first, second], {
    lines: [{ ...approved(0), translation: "And now," }, approved(1)],
  });
  assert(result.ok);
  assertEquals(result.lines[0].translation, "And now…");
  assertEquals(result.lines[0].tokens, first.tokens);
  assert(!applyTranslationReview([first], { lines: [{ ...approved(), translation: "And now," }] }).ok);
});


Deno.test("video metadata offsets stay valid at millisecond precision after floating-point sums", () => {
  assertEquals(videoOffset(0.1 + 0.2), "0.3s");
  assertEquals(videoOffset(38.075 + 16.941), "55.016s");
  assertEquals(videoOffset(10), "10s");
  assertEquals(videoOffset(0), "0s");
  assertEquals(videoOffset(-1), "0s");
});

Deno.test("English burned into video and incomplete visual checks fail closed", () => {
  assertEquals(sourceVisualIssue({ visualCheckComplete: true, englishSubtitlesVisible: false }), null);
  for (const raw of [{}, { visualCheckComplete: false, englishSubtitlesVisible: false }, { visualCheckComplete: true }, { visualCheckComplete: true, englishSubtitlesVisible: true }]) {
    assert(sourceVisualIssue(raw) !== null);
  }
});
Deno.test("old review receipts cannot bypass the source visual and timing policy", async () => {
  const s = source();
  const result = await reviewJapaneseTranslations(s, {
    model: "test", consumeUsage: () => Promise.resolve(true),
    generate: () => Promise.resolve({ model: "test", text: JSON.stringify({ category: "drama", contentFormat: "scripted_drama", childDirected: false, classificationClear: true, classificationEvidence: "Two adults speak in a scripted scene.", visualCheckComplete: true, englishSubtitlesVisible: false, lines: [approved()] }) }),
  });
  assert(result.ok);
  result.lines[0].translationReview = { ...(result.lines[0].translationReview as object), version: 1 };
  assertEquals(await hasCurrentTranslationReview({ ...s, lines: result.lines }), false);
});
