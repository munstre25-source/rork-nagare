import { corsPreflight, errorResponse, jsonResponse, readJson } from "../_shared/http.ts";
import { geminiModelExplain, promptVersion } from "../_shared/env.ts";
import { parseLanguage } from "../_shared/catalog.ts";
import { serviceClient, buildCacheKey } from "../_shared/supabase.ts";
import { hasProEntitlement } from "../_shared/revenuecat.ts";
import {
  tryIncrementExplainIngress,
  tryIncrementExplainRate,
  tryIncrementGeminiUsage,
} from "../_shared/limits.ts";
import { GeminiError, geminiGenerateJson, parseJsonObject } from "../_shared/gemini.ts";
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
  question?: string;
};

const MAX_QUESTION = 200;
const MAX_ANSWER = 900;

function askSystem(language: "ja" | "ko"): string {
  const name = language === "ko" ? "Korean" : "Japanese";
  return `You are Jojo, a warm, concise ${name} tutor inside a video app. Respond with a single JSON object only.
Keys: answer (string).
Answer the learner's question about the given word in the given sentence in at most 4 short English sentences. Include ${name} only when it helps, with readings in parentheses. Stay on topic: if the question is not about ${name} language, politely steer back to the word. No markdown.`;
}

function lookupSystem(language: "ja" | "ko"): string {
  const name = language === "ko" ? "Korean" : "Japanese";
  const reading = language === "ko"
    ? "readings (string[] Revised Romanization)"
    : "readings (string[] kana)";
  const jaGloss = language === "ko"
    ? "ja_definitions (string[] Korean-to-Korean glosses, 1-5, short dictionary style)"
    : "ja_definitions (string[] Japanese-to-Japanese glosses, 1-5, short 国語辞典 style)";
  return `You are a ${name} language tutor for learners. Respond with a single JSON object only.
Keys: word (string), ${reading}, romaji (string), pos (string), conjugation_class (string|null), definitions (string[] English glosses, 1-5), ${jaGloss}, formality_note (string|null), audio_hint (string|null).
Keep definitions short. No markdown.`;
}

function contextSystem(language: "ja" | "ko"): string {
  const name = language === "ko" ? "Korean" : "Japanese";
  return `You are a ${name} language tutor. Respond with a single JSON object only.
Keys: contextual_explanation (string), examples (string[]), related_words (string[]).
contextual_explanation is 2-3 short English sentences about THIS sentence only. Start with "In this sentence, 「word」 (reading) means ...". Then say what the speaker is doing with the word. Do not list dictionary senses.
examples: exactly 2 short, distinct ${name} sentences that use the word the same way, each followed by " — " and an English translation. Neither may repeat the supplied sentence.
related_words: up to 4 short ${name} words (synonym, polite form, or same family).
No markdown.`;
}

function otherExamples(value: unknown, sourceSentence: string): string[] {
  if (!Array.isArray(value)) return [];
  const source = sourceSentence.trim().normalize("NFKC");
  const seen = new Set<string>();
  return value.filter((entry): entry is string => {
    if (typeof entry !== "string") return false;
    const japanese = entry.split(" — ")[0].split("\n")[0].trim().normalize("NFKC");
    if (!japanese || japanese === source || seen.has(japanese)) return false;
    seen.add(japanese);
    return true;
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") return errorResponse(405, "Method not allowed");

  try {
    const appUserId = req.headers.get("x-app-user-id")?.trim() ?? "";
    if (!appUserId) return errorResponse(401, "Missing x-app-user-id");

    const body = await readJson<Body>(req);
    const kind = body.kind === "context"
      ? "context"
      : body.kind === "lookup"
      ? "lookup"
      : body.kind === "ask"
      ? "ask"
      : null;
    const question = typeof body.question === "string"
      ? body.question.trim().replace(/\s+/g, " ").slice(0, MAX_QUESTION)
      : "";
    if (kind === "ask" && !question) return errorResponse(400, "question is required");
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
    const language = parseLanguage(req.headers.get("x-app-language"));
    const entitled = await hasProEntitlement(supabase, appUserId, language);
    if (!entitled) return errorResponse(403, "Active subscription required");

    const version = promptVersion();

    // Ask Jojo: free-form follow-up about one word. Shares the context bucket and the
    // global Gemini cap, and caches identical questions so repeats cost nothing.
    if (kind === "ask") {
      const { cacheKey, sentenceHash } = await buildCacheKey(
        "context",
        word,
        `${sentence}\n?${question.toLowerCase()}`,
        `${version}|ask`,
        true,
        language,
      );
      const { data: cachedAsk } = await supabase
        .from("word_explanations")
        .select("payload")
        .eq("cache_key", cacheKey)
        .maybeSingle();
      if (cachedAsk?.payload?.answer) return jsonResponse(cachedAsk.payload);
      if (!(await tryIncrementExplainRate(supabase, appUserId, "context"))) {
        return errorResponse(429, "Rate limit exceeded");
      }
      if (!(await tryIncrementGeminiUsage(supabase))) {
        return errorResponse(429, "Global Gemini cap exceeded");
      }
      const viaGemini = await geminiGenerateJson({
        model: geminiModelExplain(),
        system: askSystem(language),
        user: `Word: ${word}\nSentence: ${sentence || "(none)"}\nQuestion: ${question}`,
        timeoutMs: 18_000,
      });
      const raw = parseJsonObject(viaGemini.text);
      const answer = typeof raw.answer === "string" ? raw.answer.trim().slice(0, MAX_ANSWER) : "";
      if (!answer) return errorResponse(502, "Invalid model response");
      const payload = { answer };
      await supabase.from("word_explanations").upsert({
        cache_key: cacheKey,
        kind: "context",
        word,
        sentence_hash: sentenceHash,
        payload,
        model: viaGemini.model,
        prompt_version: `${version}|ask`,
        updated_at: new Date().toISOString(),
      });
      return jsonResponse(payload);
    }

    const includeSentence = kind === "context" || sentence.trim().length > 0;
    const { cacheKey, sentenceHash } = await buildCacheKey(
      kind,
      word,
      sentence,
      version,
      includeSentence,
      language,
    );

    const { data: cached } = await supabase
      .from("word_explanations")
      .select("payload")
      .eq("cache_key", cacheKey)
      .maybeSingle();
    // Older context responses could contain zero examples. Regenerate those rather
    // than keeping an empty Examples tab indefinitely.
    if (cached?.payload) {
      if (kind !== "context") return jsonResponse(cached.payload);
      const examples = otherExamples(cached.payload.examples, sentence);
      if (examples.length > 0) return jsonResponse({ ...cached.payload, examples });
    }

    const underUserLimit = await tryIncrementExplainRate(supabase, appUserId, kind);
    if (!underUserLimit) return errorResponse(429, "Rate limit exceeded");

    const underGlobal = await tryIncrementGeminiUsage(supabase);
    if (!underGlobal) return errorResponse(429, "Global Gemini cap exceeded");

    const model = geminiModelExplain();
    const system = kind === "lookup" ? lookupSystem(language) : contextSystem(language);
    const userPrompt = kind === "lookup"
      ? `Word: ${word}\nSentence: ${sentence || "(none)"}`
      : `Explain how 「${word}」 is used in this sentence:\n${sentence}`;

    const viaGemini = await geminiGenerateJson({
      model,
      system,
      user: userPrompt,
      timeoutMs: 10_000,
    });
    const text = viaGemini.text;
    const usedModel = viaGemini.model;

    const raw = parseJsonObject(text);
    const payload = kind === "lookup"
      ? sanitizeLookup(raw, word)
      : sanitizeContext(raw);
    if (payload && "examples" in payload) {
      payload.examples = otherExamples(payload.examples, sentence);
    }
    if (!payload || ("examples" in payload && payload.examples.length === 0)) {
      return errorResponse(502, "Invalid model response");
    }

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
    if (err instanceof GeminiError) {
      console.error(JSON.stringify({
        event: "explain_word_ai_failed",
        status: err.status,
        error: err.name,
        detail: message.slice(0, 180),
      }));
      return err.status === 429
        ? errorResponse(429, "Jojo AI limit reached")
        : errorResponse(503, "Jojo AI temporarily unavailable");
    }
    if (message.startsWith("Missing required env")) {
      console.error(JSON.stringify({ event: "explain_word_misconfigured", error: message.slice(0, 180) }));
      return errorResponse(500, "Server misconfigured");
    }
    console.error(JSON.stringify({ event: "explain_word_failed", error: message.slice(0, 180) }));
    return errorResponse(500, "Explain failed");
  }
});
