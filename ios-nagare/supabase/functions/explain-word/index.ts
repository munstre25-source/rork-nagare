import { corsPreflight, errorResponse, jsonResponse, readJson } from "../_shared/http.ts";
import { geminiModelExplain, promptVersion } from "../_shared/env.ts";
import { serviceClient, buildCacheKey } from "../_shared/supabase.ts";
import { hasProEntitlement } from "../_shared/revenuecat.ts";
import {
  tryIncrementExplainIngress,
  tryIncrementExplainRate,
  tryIncrementGeminiUsage,
} from "../_shared/limits.ts";
import { geminiGenerateJson, parseJsonObject } from "../_shared/gemini.ts";
import { sanitizeContext, sanitizeLookup } from "../_shared/explain.ts";
import {
  assertAppUserIdBinding,
  loadBoundRcAppUserId,
  resolveIngressIdentity,
} from "../_shared/identity.ts";

type Body = {
  kind?: string;
  word?: string;
  sentence?: string;
};

const LOOKUP_SYSTEM = `You are a Japanese language tutor for learners. Respond with a single JSON object only.
Keys: word (string), readings (string[] kana), romaji (string), pos (string), conjugation_class (string|null), definitions (string[] English glosses, 1-5), ja_definitions (string[] Japanese-to-Japanese glosses, 1-5, short 国語辞典 style), formality_note (string|null), audio_hint (string|null).
Keep definitions short. No markdown.`;

const CONTEXT_SYSTEM = `You are a Japanese language tutor. Respond with a single JSON object only.
Keys: contextual_explanation (string, how the word works in THIS sentence, English, concise), examples (string[] up to 4 short Japanese example sentences), related_words (string[] up to 6).
No markdown.`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") return errorResponse(405, "Method not allowed");

  try {
    const appUserId = req.headers.get("x-app-user-id")?.trim() ?? "";
    if (!appUserId) return errorResponse(401, "Missing x-app-user-id");

    const body = await readJson<Body>(req);
    const kind = body.kind === "context" ? "context" : body.kind === "lookup" ? "lookup" : null;
    const word = typeof body.word === "string" ? body.word.trim() : "";
    const sentence = typeof body.sentence === "string" ? body.sentence : "";
    if (!kind || !word) return errorResponse(400, "kind and word are required");

    const supabase = serviceClient();

    // 1) Cheap ingress limits BEFORE any RevenueCat / Auth network calls.
    const identity = await resolveIngressIdentity(req);
    if (!(await tryIncrementExplainIngress(supabase, identity))) {
      return errorResponse(429, "Too many requests");
    }

    // 2) Bind x-app-user-id to authenticated Supabase user when possible.
    identity.boundRcAppUserId = await loadBoundRcAppUserId(req, identity);
    const binding = assertAppUserIdBinding(appUserId, identity);
    if (!binding.ok) return errorResponse(binding.status, binding.message);

    // 3) Entitlement (positive + negative results cached for a few minutes).
    const entitled = await hasProEntitlement(supabase, appUserId);
    if (!entitled) return errorResponse(403, "Pro entitlement required");

    const version = promptVersion();
    const includeSentence = kind === "context" || sentence.trim().length > 0;
    const { cacheKey, sentenceHash } = await buildCacheKey(
      kind,
      word,
      sentence,
      version,
      includeSentence,
    );

    const { data: cached } = await supabase
      .from("word_explanations")
      .select("payload")
      .eq("cache_key", cacheKey)
      .maybeSingle();
    if (cached?.payload) {
      return jsonResponse(cached.payload);
    }

    const underUserLimit = await tryIncrementExplainRate(supabase, appUserId, kind);
    if (!underUserLimit) return errorResponse(429, "Rate limit exceeded");

    const underGlobal = await tryIncrementGeminiUsage(supabase);
    if (!underGlobal) return errorResponse(429, "Global Gemini cap exceeded");

    const model = geminiModelExplain();
    const userPrompt = kind === "lookup"
      ? `Word: ${word}\nSentence: ${sentence || "(none)"}`
      : `Explain how 「${word}」 is used in this sentence:\n${sentence}`;

    const { text, model: usedModel } = await geminiGenerateJson({
      model,
      system: kind === "lookup" ? LOOKUP_SYSTEM : CONTEXT_SYSTEM,
      user: userPrompt,
      timeoutMs: 10_000,
    });

    const raw = parseJsonObject(text);
    const payload = kind === "lookup"
      ? sanitizeLookup(raw, word)
      : sanitizeContext(raw);
    if (!payload) return errorResponse(502, "Invalid model response");

    await supabase.from("word_explanations").upsert({
      cache_key: cacheKey,
      kind,
      word,
      sentence_hash: sentenceHash,
      payload,
      model: usedModel,
      prompt_version: version,
      updated_at: new Date().toISOString(),
    });

    return jsonResponse(payload);
  } catch (err) {
    const message = err instanceof Error ? err.message : "Internal error";
    if (message.startsWith("Missing required env")) {
      return errorResponse(500, "Server misconfigured");
    }
    return errorResponse(500, "Explain failed");
  }
});
