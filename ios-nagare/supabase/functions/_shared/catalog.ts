/** Which catalog a request writes. Japanese stays on `clips` so older Jojo builds never see Korean rows. */

export type CatalogLanguage = "ja" | "ko";

export function parseLanguage(value: unknown): CatalogLanguage {
  return value === "ko" ? "ko" : "ja";
}

export function catalogTable(language: CatalogLanguage): "clips" | "sori_clips" {
  return language === "ko" ? "sori_clips" : "clips";
}

export function languageName(language: CatalogLanguage): "Japanese" | "Korean" {
  return language === "ko" ? "Korean" : "Japanese";
}
