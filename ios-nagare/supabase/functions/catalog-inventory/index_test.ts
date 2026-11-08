import { durationSeconds, handler, videoInventory } from "./index.ts";
function assert(ok: unknown, message = "Assertion failed"): asserts ok {
  if (!ok) throw new Error(message);
}
const channel = "UC" + "A".repeat(22), video = "abcdefghijk";
async function mock(
  body: unknown,
  payload: unknown,
  check: (response: Response, urls: URL[]) => Promise<void>,
  googleStatus = 200,
  authorized = true,
) {
  const names = ["ADMIN_TOKEN", "CRON_FILL_TOKEN", "YOUTUBE_API_KEY"];
  const before = names.map((n) => Deno.env.get(n));
  const original = globalThis.fetch;
  const urls: URL[] = [];
  try {
    Deno.env.set("ADMIN_TOKEN", "inventory-test-admin");
    Deno.env.set("CRON_FILL_TOKEN", "");
    Deno.env.set("YOUTUBE_API_KEY", "test-key-must-stay-server-side");
    globalThis.fetch = ((url: URL | RequestInfo) => {
      urls.push(new URL(String(url)));
      return Promise.resolve(
        new Response(JSON.stringify(payload), { status: googleStatus }),
      );
    }) as typeof fetch;
    const req = new Request("https://example.test/catalog-inventory", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(authorized ? { "x-admin-token": "inventory-test-admin" } : {}),
      },
      body: JSON.stringify(body),
    });
    await check(await handler(req), urls);
  } finally {
    globalThis.fetch = original;
    names.forEach((n, i) =>
      before[i] === undefined ? Deno.env.delete(n) : Deno.env.set(n, before[i]!)
    );
  }
}
Deno.test("inventory denies unauthenticated callers before any Google request", () =>
  mock(
    { action: "channels", ids: [channel] },
    {},
    async (r, urls) => {
      assert(r.status === 401);
      assert(urls.length === 0);
    },
    200,
    false,
  ));
Deno.test("inventory rejects oversized or malformed identifiers without consuming quota", async () => {
  for (
    const body of [
      { action: "channels", ids: Array(51).fill(channel) },
      { action: "videos", ids: ["bad"] },
      { action: "uploads", channelId: "../secret" },
      { action: "unknown" },
    ]
  ) {
    await mock(body, {}, async (r, urls) => {
      assert(r.status === 400);
      assert(urls.length === 0);
    });
  }
});
Deno.test("uploads use page cursors and retain whole archives beyond the first fifty", () =>
  mock({ action: "uploads", channelId: channel, pageToken: "second-page" }, {
    pageInfo: { totalResults: 1234 },
    nextPageToken: "third-page",
    items: [{
      contentDetails: { videoId: video },
      snippet: { title: "Source", videoOwnerChannelId: channel },
    }],
  }, async (r, urls) => {
    const p = await r.json();
    assert(r.status === 200);
    assert(urls[0].pathname.endsWith("playlistItems"));
    assert(urls[0].searchParams.get("maxResults") === "50");
    assert(urls[0].searchParams.get("pageToken") === "second-page");
    assert(p.nextPageToken === "third-page");
    assert(p.playlist_total === 1234);
    assert(p.videos[0].video_id === video);
    assert(p.readOnly && p.paidInferenceCalls === 0);
  }));
Deno.test("channel statistics distinguish public upload totals from confirmed lessons", () =>
  mock({ action: "channels", ids: [channel] }, {
    items: [{
      id: channel,
      snippet: { title: "Creator", customUrl: "@creator" },
      contentDetails: {
        relatedPlaylists: { uploads: "UU" + channel.slice(2) },
      },
      statistics: { videoCount: "1234", subscriberCount: "5000" },
    }],
  }, async (r) => {
    const p = await r.json();
    assert(p.channels[0].public_upload_count === 1234);
    assert(p.channels[0].handle === "@creator");
    assert(!JSON.stringify(p).includes("test-key-must-stay-server-side"));
  }));
Deno.test("video metadata does not require creator captions, forty-second limits or Japanese language declarations", () => {
  const p = videoInventory({
    id: video,
    snippet: { title: "Long source", liveBroadcastContent: "none" },
    status: { privacyStatus: "public", embeddable: true },
    contentDetails: { duration: "PT2H3M4S", caption: "false" },
  });
  assert(p.metadata_candidate);
  assert(p.duration_sec === 7384);
  assert(!p.caption_available);
  assert(p.declared_audio_language === null);
  assert(p.transcript_timing_review === "not_reviewed");
  assert(durationSeconds("P1DT2H") == 93600);
});
Deno.test("unembeddable, private, active live, underlength and age-restricted sources stay explicit", () => {
  const p = videoInventory({
    id: video,
    snippet: { liveBroadcastContent: "live" },
    status: { privacyStatus: "private", embeddable: false },
    contentDetails: {
      duration: "PT2S",
      contentRating: { ytRating: "ytAgeRestricted" },
    },
  });
  assert(!p.metadata_candidate);
  assert(p.exclusion_reasons.length === 5);
});
Deno.test("quota errors are actionable and never expose Google credential/error URLs", () =>
  mock({ action: "channels", ids: [channel] }, {
    error: { message: "secret-key-url", errors: [{ reason: "quotaExceeded" }] },
  }, async (r) => {
    const t = await r.text();
    assert(r.status === 429);
    assert(t.includes("quotaExceeded"));
    assert(!t.includes("secret-key-url"));
    assert(!t.includes("test-key-must-stay-server-side"));
  }, 403));
Deno.test("OR channel searches stay bounded and never call an inference provider", () =>
  mock({ action: "search_channels", query: '"Creator A"|"Creator B"' }, {
    items: [{ id: { channelId: channel }, snippet: { title: "Creator A" } }],
  }, async (r, urls) => {
    const p = await r.json();
    assert(urls.length === 1 && urls[0].hostname === "www.googleapis.com");
    assert(urls[0].searchParams.get("type") === "channel");
    assert(p.channels[0].channel_id === channel);
    assert(p.paidInferenceCalls === 0);
  }));
