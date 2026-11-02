import { hasCurrentTranslationReview } from "./translation-review.ts";
import { lineAlignmentIssue, translationQualityIssue } from "./validate.ts";
import type { TimedLine } from "./timing.ts";

/** Read-only triage, never a claim that grammar checks prove translation fidelity. */
export async function auditSubtitleTranslations(
  clips: Array<Record<string, unknown>>,
) {
  const issues: Array<
    {
      clipId: string;
      lineIndex: number;
      issue: string;
      japanese: string;
      translation: string;
    }
  > = [];
  const unreviewedClipIds: string[] = [];
  let checkedLines = 0;
  for (const clip of clips) {
    const id = String(clip.id ?? "");
    const lines = Array.isArray(clip.lines) ? clip.lines as TimedLine[] : [];
    const source = {
      videoId: String(clip.videoId ?? clip.video_id ?? ""),
      sourceStartSec: Number(clip.sourceStartSec ?? clip.source_start_sec ?? 0),
      durationSec: Number(clip.durationSec ?? clip.duration_sec),
      lines,
    };
    if (!(await hasCurrentTranslationReview(source))) {
      unreviewedClipIds.push(id);
    }
    for (const [index, line] of lines.entries()) {
      checkedLines++;
      const japanese = Array.isArray(line.tokens)
        ? line.tokens.map((token) => token.surface).join("")
        : "";
      const translation = typeof line.translation === "string"
        ? line.translation
        : "";
      const issue = translationQualityIssue(line.translation) ??
        lineAlignmentIssue(japanese, translation);
      if (issue) {
        issues.push({
          clipId: id,
          lineIndex: index,
          issue,
          japanese,
          translation,
        });
      }
    }
  }
  return {
    checkedClips: clips.length,
    checkedLines,
    unreviewedClipIds,
    issues,
    limitation:
      "Sanity checks do not verify meaning. Clips without a current audio review require review; do not auto-rewrite them from glosses.",
  };
}

if (import.meta.main) {
  const path = Deno.args[0];
  if (!path) {
    throw new Error(
      "Pass a JSON array of clips to audit. No model or database calls are made.",
    );
  }
  const data = JSON.parse(await Deno.readTextFile(path));
  if (!Array.isArray(data)) throw new Error("Input must be an array of clips.");
  console.log(JSON.stringify(await auditSubtitleTranslations(data), null, 2));
}
