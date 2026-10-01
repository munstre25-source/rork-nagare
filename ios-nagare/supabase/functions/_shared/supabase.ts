import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { requireEnv } from "./env.ts";

export function serviceClient(): SupabaseClient {
  const url = requireEnv("SUPABASE_URL");
  const key = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export async function sha1Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-1", data);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export function normalizeSentence(sentence: string): string {
  return sentence.replace(/\s+/g, " ").trim();
}

export async function buildCacheKey(
  kind: "lookup" | "context",
  word: string,
  sentence: string,
  promptVersion: string,
  includeSentence: boolean,
): Promise<{ cacheKey: string; sentenceHash: string | null }> {
  const normalized = normalizeSentence(sentence);
  const sentenceHash = includeSentence || kind === "context"
    ? await sha1Hex(normalized)
    : null;
  if (sentenceHash) {
    return {
      cacheKey: `${promptVersion}|${kind}|${word}|${sentenceHash}`,
      sentenceHash,
    };
  }
  return {
    cacheKey: `${promptVersion}|${kind}|${word}`,
    sentenceHash: null,
  };
}
