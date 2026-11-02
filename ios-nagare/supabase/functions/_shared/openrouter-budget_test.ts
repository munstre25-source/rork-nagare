import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { AiBudgetError, GeminiError, geminiGenerateJson, geminiAnalyzeYouTubeSegment } from "./gemini.ts";

const reservation = "11111111-1111-4111-8111-111111111111";
async function run(
  handle: (url: string, body: Record<string, unknown>) => Response | Promise<Response>,
  work: () => Promise<void>,
) {
  const names = ["SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY", "OPENROUTER_API_KEY", "GEMINI_API_KEY", "AI_PROVIDER_ORDER"];
  const previous = names.map((key) => Deno.env.get(key));
  const original = globalThis.fetch;
  Deno.env.set("SUPABASE_URL", "https://budget.test");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-service");
  Deno.env.set("OPENROUTER_API_KEY", "sk-or-test");
  Deno.env.delete("GEMINI_API_KEY");
  Deno.env.set("AI_PROVIDER_ORDER", "openrouter,google");
  globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) =>
    Promise.resolve(handle(String(input), JSON.parse(String(init?.body ?? "{}"))))) as typeof fetch;
  try { await work(); } finally {
    globalThis.fetch = original;
    names.forEach((key, i) => previous[i] === undefined ? Deno.env.delete(key) : Deno.env.set(key, previous[i]!));
  }
}
const call = () => geminiGenerateJson({ model: "google/gemini-3.8-flash", system: "test", user: "test" });
const json = (value: unknown, status = 200) => new Response(JSON.stringify(value), { status });

Deno.test("denied reservation makes no paid-provider request or failover", async () => {
  let paid = 0;
  await run((url) => {
    if (url.includes("openrouter_reserve_lookup_budget")) return json(null);
    paid++;
    throw new Error("paid request must not run");
  }, async () => {
    Deno.env.set("GEMINI_API_KEY", "test-google");
    await assertRejects(call, AiBudgetError);
    assertEquals(paid, 0);
  });
});

Deno.test("unavailable budget fails closed", async () => {
  let paid = 0;
  await run((url) => {
    if (url.includes("openrouter_reserve_lookup_budget")) return json({}, 503);
    paid++;
    return json({});
  }, async () => {
    await assertRejects(call, AiBudgetError);
    assertEquals(paid, 0);
  });
});

Deno.test("successful provider call settles actual cost rather than its full hold", async () => {
  const costs: unknown[] = [];
  await run((url, body) => {
    if (url.includes("openrouter_reserve_lookup_budget")) {
      assertEquals(body.p_amount, 0.1);
      return json(reservation);
    }
    if (url.includes("openrouter_settle_budget")) { costs.push(body.p_cost); return json(0.012); }
    return json({ choices: [{ message: { content: '{"ok":true}' } }], usage: { cost: 0.012 } });
  }, async () => {
    assertEquals((await call()).text, '{"ok":true}');
    assertEquals(costs, [0.012]);
  });
});

Deno.test("rejected provider request releases its hold without charging", async () => {
  const costs: unknown[] = [];
  await run((url, body) => {
    if (url.includes("openrouter_reserve_lookup_budget")) return json(reservation);
    if (url.includes("openrouter_settle_budget")) { costs.push(body.p_cost); return json(0); }
    return json({ error: "payment" }, 402);
  }, async () => {
    await assertRejects(call, GeminiError);
    assertEquals(costs, [0]);
  });
});

Deno.test("uncertain request cost conservatively consumes the reservation", async () => {
  const costs: unknown[] = [];
  await run((url, body) => {
    if (url.includes("openrouter_reserve_lookup_budget")) return json(reservation);
    if (url.includes("openrouter_settle_budget")) { costs.push(body.p_cost); return json(0.1); }
    throw new TypeError("network disconnected after sending");
  }, async () => {
    await assertRejects(call, GeminiError);
    assertEquals(costs, [0.1]);
  });
});

Deno.test("video calls cannot spend the lookup-only launch allowance", async () => {
  await run((url, body) => {
    if (url.includes("openrouter_reserve_budget")) {
      assertEquals(body.p_amount, 0.5);
      return json(null);
    }
    throw new Error("A video must not reserve lookup funds or call a provider");
  }, async () => {
    await assertRejects(() => geminiAnalyzeYouTubeSegment({
      model: "google/gemini-3.8-flash", system: "test", user: "test",
      youtubeUrl: "https://www.youtube.com/watch?v=12345678901", startSec: 0, endSec: 20,
    }), AiBudgetError);
  });
});
