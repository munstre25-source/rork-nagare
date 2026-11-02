export type ContentClassification = {
  category: string; contentFormat: string; childDirected: boolean; classificationClear: true; classificationEvidence: string;
};
const FORMAT_CATEGORY: Record<string, string> = {
  anime: "anime", scripted_drama: "drama", variety: "variety", vtuber_stream: "vtuber",
  street_interview: "interview", children_program: "kids", gameplay: "gaming", language_lesson: "learning", podcast: "podcast",
};
export const CLASSIFICATION_PROMPT = `Classify the ACTUAL clip from its audible content, visible setting and intended audience, not the discovery lane, title alone, difficulty, speaking speed or animation alone.
Return category, contentFormat, childDirected, classificationClear and classificationEvidence (a short specific observation).
Allowed format → category pairs: anime→anime; scripted_drama→drama; variety→variety; vtuber_stream→vtuber; street_interview→interview; children_program→kids; gameplay→gaming; language_lesson→learning; podcast→podcast.
Kids requires clear evidence this program is made FOR children (for example preschool songs, children's characters addressing children or children's stories); easy Japanese, cartoons, a cute avatar, a beginner lesson, adult conversation or a podcast do not establish a child audience.
Podcasts, including educational podcasts and studio/remote host-and-guest discussion, are podcast, never kids. Street interviews require real on-location questions and answers; an indoor podcast is not a street interview.
Adult learner instruction is learning; anime dialogue is anime unless clearly a child-directed program; game commentary is gaming; VTuber talk without gameplay is vtuber. Child-directed animation belongs to kids/children_program.
If the format/audience is unclear, classificationClear=false. Never choose kids or another category merely to fill an underrepresented lane.`;
export function contentClassification(value: unknown): ContentClassification | null {
  if (!value || typeof value !== "object") return null;
  const raw = value as Record<string, unknown>;
  if (raw.classificationClear !== true || typeof raw.category !== "string" || typeof raw.contentFormat !== "string" ||
      FORMAT_CATEGORY[raw.contentFormat] !== raw.category || typeof raw.childDirected !== "boolean" ||
      (raw.category === "kids") !== raw.childDirected || typeof raw.classificationEvidence !== "string" ||
      raw.classificationEvidence.trim().length < 12 || raw.classificationEvidence.trim().length > 600) return null;
  return { category: raw.category, contentFormat: raw.contentFormat, childDirected: raw.childDirected, classificationClear: true, classificationEvidence: raw.classificationEvidence.trim() };
}
