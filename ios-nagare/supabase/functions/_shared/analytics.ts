/**
 * Pure validation for first-party analytics batches. No network, no secrets: unit-tested.
 *
 * Privacy rules enforced here (the client enforces the same rules first):
 * - Event names are stable snake_case identifiers.
 * - Props are a small flat map of short scalar values. Keys that could carry learner text
 *   (words, sentences, messages, names, emails) are dropped, never stored.
 */

export const EVENT_NAME = /^[a-z][a-z0-9_]{1,63}$/;
const PROP_KEY = /^[a-z][a-z0-9_]{0,31}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const BLOCKED_KEYS = new Set([
  "word", "surface", "text", "sentence", "line_text", "transcript", "message", "body",
  "title", "query", "email", "name", "phone", "ip", "url", "audio",
]);
export const MAX_EVENTS = 200;
export const MAX_SESSIONS = 20;
const MAX_PROPS = 12;
const MAX_VALUE = 64;
const PAST_WINDOW_MS = 30 * 24 * 3600 * 1000;
const FUTURE_SKEW_MS = 24 * 3600 * 1000;

export type CleanEvent = {
  id: string;
  session_id: string | null;
  name: string;
  props: Record<string, string | number | boolean>;
  occurred_at: string;
  app_version: string | null;
  os_version: string | null;
};

export type CleanSession = {
  id: string;
  started_at: string;
  last_seen_at: string;
  active_seconds: number;
  app_version: string | null;
  build: string | null;
  os_version: string | null;
  device_class: string | null;
};

export function isUuid(value: unknown): value is string {
  return typeof value === "string" && UUID.test(value);
}

function shortText(value: unknown, max: number): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  return trimmed.slice(0, max);
}

function validTime(value: unknown, now: number): string | null {
  if (typeof value !== "string") return null;
  const ms = Date.parse(value);
  if (!Number.isFinite(ms)) return null;
  if (ms < now - PAST_WINDOW_MS || ms > now + FUTURE_SKEW_MS) return null;
  return new Date(ms).toISOString();
}

export function cleanProps(raw: unknown): Record<string, string | number | boolean> {
  const out: Record<string, string | number | boolean> = {};
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return out;
  let kept = 0;
  for (const [key, value] of Object.entries(raw as Record<string, unknown>)) {
    if (kept >= MAX_PROPS) break;
    if (!PROP_KEY.test(key) || BLOCKED_KEYS.has(key)) continue;
    if (typeof value === "boolean") {
      out[key] = value;
    } else if (typeof value === "number" && Number.isFinite(value)) {
      out[key] = Math.round(value * 1000) / 1000;
    } else if (typeof value === "string") {
      // Identifiers and enums only: anything with spaces or non-ASCII is treated as free text.
      const v = value.trim().slice(0, MAX_VALUE);
      if (!/^[A-Za-z0-9_.:\-]*$/.test(v)) continue;
      out[key] = v;
    } else {
      continue;
    }
    kept += 1;
  }
  return out;
}

export function cleanEvents(raw: unknown, now = Date.now()): CleanEvent[] {
  if (!Array.isArray(raw)) return [];
  const seen = new Set<string>();
  const out: CleanEvent[] = [];
  for (const item of raw.slice(0, MAX_EVENTS)) {
    if (!item || typeof item !== "object") continue;
    const e = item as Record<string, unknown>;
    if (!isUuid(e.id) || seen.has(e.id.toLowerCase())) continue;
    if (typeof e.name !== "string" || !EVENT_NAME.test(e.name)) continue;
    const occurred = validTime(e.occurred_at, now);
    if (!occurred) continue;
    seen.add(e.id.toLowerCase());
    out.push({
      id: e.id.toLowerCase(),
      session_id: isUuid(e.session_id) ? e.session_id.toLowerCase() : null,
      name: e.name,
      props: cleanProps(e.props),
      occurred_at: occurred,
      app_version: shortText(e.app_version, 24),
      os_version: shortText(e.os_version, 16),
    });
  }
  return out;
}

export function cleanSessions(raw: unknown, now = Date.now()): CleanSession[] {
  if (!Array.isArray(raw)) return [];
  const out: CleanSession[] = [];
  for (const item of raw.slice(0, MAX_SESSIONS)) {
    if (!item || typeof item !== "object") continue;
    const s = item as Record<string, unknown>;
    if (!isUuid(s.id)) continue;
    const started = validTime(s.started_at, now);
    const last = validTime(s.last_seen_at, now);
    if (!started || !last) continue;
    const active = typeof s.active_seconds === "number" && Number.isFinite(s.active_seconds)
      ? Math.max(0, Math.min(86400, Math.round(s.active_seconds)))
      : 0;
    out.push({
      id: s.id.toLowerCase(),
      started_at: started,
      last_seen_at: Date.parse(last) < Date.parse(started) ? started : last,
      active_seconds: active,
      app_version: shortText(s.app_version, 24),
      build: shortText(s.build, 16),
      os_version: shortText(s.os_version, 16),
      device_class: shortText(s.device_class, 16),
    });
  }
  return out;
}

// ── Feedback ────────────────────────────────────────────────────────────────

export const FEEDBACK_CATEGORIES = new Set([
  "bug", "feature", "general", "content", "learning", "performance",
  "cancel_price", "cancel_time", "cancel_content", "cancel_hard", "cancel_curious", "cancel_other",
]);
export const FEEDBACK_SOURCES = new Set(["experience_prompt", "manual", "cancellation", "board"]);
export const BOARD_SORTS = new Set(["top", "newest", "trending"]);
export const REPORT_REASONS = new Set(["spam", "offensive", "personal_info", "other"]);
export const POST_STATUSES = new Set(["open", "under_review", "planned", "in_progress", "done", "declined", "hidden"]);

/** Collapses whitespace and trims to a length. */
export function cleanText(value: unknown, max: number): string {
  if (typeof value !== "string") return "";
  return value.replace(/\s+/g, " ").trim().slice(0, max);
}

/** Search input for ILIKE: printable, short. SQL escaping of % and _ happens in the database. */
export function cleanSearch(value: string | null): string {
  if (!value) return "";
  return value.replace(/[\u0000-\u001f]/g, "").trim().slice(0, 60);
}
