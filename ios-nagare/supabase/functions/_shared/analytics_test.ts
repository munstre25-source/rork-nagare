import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { cleanEvents, cleanProps, cleanSessions, cleanSearch } from "./analytics.ts";

const now = Date.parse("2026-10-29T08:00:00Z");
const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;

Deno.test("props drop learner text and free-form values", () => {
  const props = cleanProps({
    clip: "jojo_001",
    word: "食べる",
    surface: "x",
    count: 3,
    reason: "Some error: with spaces",
    step: "understand",
    nested: { a: 1 },
    Bad: "x",
  });
  assertEquals(props, { clip: "jojo_001", count: 3, step: "understand" });
});

Deno.test("events dedupe ids and reject bad names and times", () => {
  const events = cleanEvents([
    { id: id(1), name: "clip_view", occurred_at: "2026-10-29T07:59:00Z", props: {} },
    { id: id(1), name: "clip_view", occurred_at: "2026-10-29T07:59:00Z" },
    { id: id(2), name: "Clip View", occurred_at: "2026-10-29T07:59:00Z" },
    { id: id(3), name: "old_event", occurred_at: "2025-01-01T00:00:00Z" },
    { id: "nope", name: "x_y", occurred_at: "2026-10-29T07:59:00Z" },
    { id: id(4), name: "session_start", occurred_at: "2026-10-29T07:00:00Z", session_id: id(9) },
  ], now);
  assertEquals(events.map((e) => e.id), [id(1), id(4)]);
  assertEquals(events[1]!.session_id, id(9));
});

Deno.test("sessions clamp active time and ordering", () => {
  const sessions = cleanSessions([
    { id: id(5), started_at: "2026-10-29T07:00:00Z", last_seen_at: "2026-10-29T06:00:00Z", active_seconds: 999999 },
  ], now);
  assertEquals(sessions[0]!.active_seconds, 86400);
  assertEquals(sessions[0]!.last_seen_at, sessions[0]!.started_at);
});

Deno.test("search strips control characters", () => {
  assertEquals(cleanSearch("  dark\u0000 mode "), "dark mode");
});
