import { applyLocalAlignment, type LocalAlignment } from "./local-alignment.ts";
import { translationQualityIssue } from "./validate.ts";
import type { TranslationSource } from "./translation-review.ts";
export const LOCAL_ASR_MODEL = "Qwen/Qwen3-ASR-0.6B";
export const LOCAL_ASR_REVISION = "5eb144179a02acc5e5ba31e748d22b0cf3e303b0";
export const LOCAL_TRANSLATION_MODEL = "Helsinki-NLP/opus-mt-ja-en";
export const LOCAL_TRANSLATION_REVISION = "0770961a39ba6bd66305b149c3f4110bcafca2e6";
export const LOCAL_CATEGORIES = new Set(["anime", "drama", "variety", "vtuber", "interview", "kids", "gaming", "learning", "podcast"]);
export type LocalCatalogClip = {
  id: string; video_id: string; title: string; channel_name: string; category: string;
  difficulty?: string; source_start_sec: number; duration_sec: number;
  video_orientation: string; lines: TranslationSource["lines"]; alignment: LocalAlignment;
  translationIssues?: Array<{lineIndex:number;reason:string}>;
  processing: { operatorReview?: string; language: string; asrModel: string; asrRevision: string; translationModel: string; translationRevision: string };
};
export function validateLocalCatalogClip(clip: LocalCatalogClip): TranslationSource["lines"] {
  if (!clip || !/^[A-Za-z0-9_.-]{1,150}$/.test(clip.id) || !/^[A-Za-z0-9_-]{11}$/.test(clip.video_id) ||
      !LOCAL_CATEGORIES.has(clip.category) || !Number.isFinite(clip.source_start_sec) || clip.source_start_sec < 0 ||
      !Number.isFinite(clip.duration_sec) || clip.duration_sec < 3 || clip.duration_sec > 300 ||
      !Array.isArray(clip.lines) || clip.lines.length < 1 || clip.lines.length > 100) throw new Error("Invalid local clip identity, category or bounds");
  const proof = clip.processing;
  if (clip.translationIssues?.length && proof?.operatorReview !== "english-checked") throw new Error("Offline English requires operator review");
  if (!proof || proof.language !== "Japanese" || proof.asrModel !== LOCAL_ASR_MODEL || proof.asrRevision !== LOCAL_ASR_REVISION ||
      proof.translationModel !== LOCAL_TRANSLATION_MODEL || proof.translationRevision !== LOCAL_TRANSLATION_REVISION) throw new Error("Local transcription/translation provenance required");
  let spoken = "", count = 0, tappable = 0;
  for (const line of clip.lines) {
    if (!line || !Array.isArray(line.tokens) || !line.tokens.length || line.tokens.length > 300 || translationQualityIssue(line.translation)) throw new Error("Incomplete local subtitle line or English translation");
    for (const token of line.tokens) {
      if (typeof token.surface !== "string" || !token.surface.trim() || token.surface.length > 80) throw new Error("Invalid local word");
      spoken += token.surface; count++;
      if (token.tappable === true) tappable++;
    }
  }
  if (count > 2000 || !tappable || (spoken.match(/[\u3040-\u30ff\u3400-\u9fff]/g)?.length ?? 0) / Math.max(1, spoken.length) < .35) throw new Error("No usable Japanese learning transcript");
  // Do not trust or retain caller-supplied review claims.
  const source = {videoId: clip.video_id, sourceStartSec: clip.source_start_sec, durationSec: clip.duration_sec,
    lines: clip.lines.map(({ translationReview: _ignored, ...line }) => line)};
  return applyLocalAlignment(source, clip.alignment);
}
export function seconds(iso: string): number {
  const match = /^P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?$/.exec(iso);
  if (!match) return 0;
  return Number(match[1] ?? 0)*86400 + Number(match[2] ?? 0)*3600 + Number(match[3] ?? 0)*60 + Number(match[4] ?? 0);
}
export function normalizeChannel(text: string): string {
  return text.normalize("NFKC").toLowerCase().replace(/[^\p{L}\p{N}]/gu, "");
}
