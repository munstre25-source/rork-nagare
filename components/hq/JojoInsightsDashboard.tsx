"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { AppStoreReviews } from "./AppStoreReviews";

type FeedbackItem = {
  id: number;
  app_user_id: string;
  enjoyed: boolean | null;
  category: string | null;
  message: string;
  status: string;
  created_at: string;
};

type DirectMessage = {
  id: number;
  app_user_id: string;
  sender: string;
  body: string;
  created_at: string;
};

type InsightsPayload = {
  metrics?: {
    active_users: number;
    new_installs: number;
    retention: {
      d1_eligible: number; d1_returned: number; d1_percent: number | null;
      d7_eligible: number; d7_returned: number; d7_percent: number | null;
    };
    conversion: {
      paywall_viewers: number; purchasers: number; view_to_purchase_percent: number | null;
    };
    acquisition: { total: number; by_source: Record<string, number> };
    sessions: { count: number; avg_active_seconds: number };
    learning: {
      clip_views: number; clip_completions: number; completion_percent: number;
      likes: number; vocab_saves: number; reviews_completed: number;
      quiz_completion_percent: number;
    };
    playback: {
      failure_reports: number; affected_videos: number;
      top_videos: { video_id: string; reports: number }[];
    };
    dau_series: { day: string; users: number }[];
    feedback: { total: number; positive: number; negative: number };
    core_funnel: { name: string; users: number }[];
    errors: { name: string; code: string; n: number }[];
  } | null;
  metrics_error?: string;
  acquisition: { total: number; by_source: Record<string, number> };
  feedback: {
    total: number;
    enjoyed_yes: number;
    enjoyed_no: number;
    items: FeedbackItem[];
  };
  messages?: DirectMessage[];
};

type ThreadEntry = { key: string; at: string; from: "user" | "jojo"; text: string };

type Thread = { appUserId: string; entries: ThreadEntry[]; latest: string };

function buildThreads(items: FeedbackItem[], messages: DirectMessage[]): Thread[] {
  const ids = new Set<string>();
  for (const item of items) if (item.app_user_id !== "anonymous") ids.add(item.app_user_id);
  for (const message of messages) ids.add(message.app_user_id);
  const copied = new Map<string, Set<string>>();
  for (const message of messages) {
    if (message.sender !== "user") continue;
    const set = copied.get(message.app_user_id) ?? new Set<string>();
    set.add(message.body);
    copied.set(message.app_user_id, set);
  }
  return [...ids]
    .map((appUserId) => {
      const entries: ThreadEntry[] = [];
      for (const item of items) {
        if (item.app_user_id !== appUserId) continue;
        const text = item.message || (item.enjoyed === true ? "Enjoying the app" : "Feedback submitted");
        const labeled = item.category ? `[${item.category}] ${text}` : text;
        const known = copied.get(appUserId);
        if (known?.has(text) || known?.has(labeled)) continue;
        entries.push({ key: `f-${item.id}`, at: item.created_at, from: "user", text: labeled });
      }
      for (const message of messages) {
        if (message.app_user_id !== appUserId) continue;
        entries.push({
          key: `m-${message.id}`,
          at: message.created_at,
          from: message.sender === "jojo" ? "jojo" : "user",
          text: message.body,
        });
      }
      entries.sort((a, b) => a.at.localeCompare(b.at));
      return { appUserId, entries, latest: entries.at(-1)?.at ?? "" };
    })
    .filter((thread) => thread.entries.length > 0)
    .sort((a, b) => b.latest.localeCompare(a.latest));
}

export function JojoInsightsDashboard() {
  const [data, setData] = useState<InsightsPayload | null>(null);
  const [status, setStatus] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [drafts, setDrafts] = useState<Record<string, string>>({});
  const [sendingTo, setSendingTo] = useState("");
  const [range, setRange] = useState({ from: "", to: "", label: "Last 30 days" });
  const [customFrom, setCustomFrom] = useState("");
  const [customTo, setCustomTo] = useState("");
  const [theme, setTheme] = useState<"dark" | "light">("dark");
  const [themeReady, setThemeReady] = useState(false);
  const requestSequence = useRef(0);

  useEffect(() => {
    const saved = localStorage.getItem("jojo-insights-theme");
    if (saved === "light") setTheme("light");
    setThemeReady(true);
  }, []);
  useEffect(() => {
    if (!themeReady) return;
    document.documentElement.dataset.insightsTheme = theme;
    localStorage.setItem("jojo-insights-theme", theme);
    return () => { delete document.documentElement.dataset.insightsTheme; };
  }, [theme, themeReady]);

  function choosePreset(days: number, label: string) {
    const end = new Date();
    const start = new Date(end);
    if (days === 1) start.setHours(0, 0, 0, 0);
    else start.setDate(start.getDate() - days);
    setRange({ from: start.toISOString(), to: end.toISOString(), label });
  }

  function applyCustomRange() {
    const start = new Date(customFrom);
    const end = new Date(customTo);
    if (!Number.isFinite(start.getTime()) || !Number.isFinite(end.getTime()) ||
        start.getTime() >= end.getTime() || end.getTime() - start.getTime() > 366 * 86_400_000) {
      setError("Choose a valid start and end, up to 366 days apart.");
      return;
    }
    setRange({ from: start.toISOString(), to: end.toISOString(), label: "Custom range" });
  }

  const load = useCallback(async () => {
    const requestId = ++requestSequence.current;
    setLoading(true);
    setError("");
    try {
      const params = new URLSearchParams();
      if (range.from && range.to) {
        params.set("from", range.from);
        params.set("to", range.to);
      }
      const res = await fetch(`/hq/jojo-insights/api?${params}`, { cache: "no-store" });
      const json = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(json.error || `HTTP ${res.status}`);
      if (requestId === requestSequence.current) setData(json as InsightsPayload);
    } catch (e) {
      if (requestId === requestSequence.current) {
        setError(e instanceof Error ? e.message : "Failed to load");
        setData(null);
      }
    } finally {
      if (requestId === requestSequence.current) setLoading(false);
    }
  }, [range.from, range.to]);

  useEffect(() => {
    void load();
  }, [load]);

  async function setItemStatus(id: number, next: string) {
    setError("");
    try {
      const res = await fetch("/hq/jojo-insights/api", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ id, status: next }),
      });
      const json = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(json.error || `HTTP ${res.status}`);
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Update failed");
    }
  }

  async function sendReply(appUserId: string) {
    const message = (drafts[appUserId] ?? "").trim();
    if (!message) return;
    setSendingTo(appUserId);
    setError("");
    try {
      const res = await fetch("/hq/jojo-insights/api", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ app_user_id: appUserId, message }),
      });
      const json = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(json.error || `HTTP ${res.status}`);
      setDrafts((current) => ({ ...current, [appUserId]: "" }));
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Reply failed");
    } finally {
      setSendingTo("");
    }
  }

  const bySource = Object.entries(data?.metrics?.acquisition?.by_source ?? {}).sort((a, b) => b[1] - a[1]);
  const threads = buildThreads(data?.feedback.items ?? [], data?.messages ?? []);
  const visibleFeedback = (data?.feedback.items ?? []).filter((item) => !status || item.status === status);
  const maxSource = Math.max(1, ...bySource.map(([, n]) => n));
  const maxDaily = Math.max(1, ...(data?.metrics?.dau_series ?? []).map((point) => point.users));

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-[#ff6b00]">Jojo · noindex</p>
          <h1 className="mt-2 text-3xl font-semibold tracking-tight text-white">Insights</h1>
          <p className="mt-2 max-w-2xl text-sm text-white/55">
            Acquisition, private feedback, and a one-to-one thread with each learner. Only you and that person see the replies.
          </p>
        </div>
        <div className="flex gap-2">
          <button type="button" onClick={() => setTheme(theme === "dark" ? "light" : "dark")}
            className="rounded-full border border-white/10 px-4 py-2.5 text-sm font-semibold">
            {theme === "dark" ? "Light mode" : "Dark mode"}
          </button>
          <button
            type="button"
            onClick={() => void load()}
            className="rounded-full bg-[#ff6b00] px-5 py-2.5 text-sm font-bold text-black disabled:opacity-60"
            disabled={loading}
          >
            {loading ? "Loading…" : "Refresh"}
          </button>
        </div>
      </div>

      <section className="rounded-2xl border border-white/10 bg-[#171a21] p-4">
        <p className="text-sm font-semibold">Analytics date and time · {range.label}</p>
        <p className="mt-1 text-xs text-white/50">Presets use your local time. Reports use UTC boundaries; the feedback inbox stays recent.</p>
        <div className="mt-3 flex flex-wrap gap-2">
          {([[1, "Today"], [7, "Last 7 days"], [30, "Last 30 days"], [90, "Last 90 days"]] as const).map(([days, label]) => (
            <button key={days} type="button" onClick={() => choosePreset(days, label)}
              className="rounded-full border border-white/10 bg-white/5 px-3 py-1.5 text-xs font-semibold hover:bg-white/10">
              {label}
            </button>
          ))}
        </div>
        <div className="mt-3 flex flex-wrap items-end gap-2 text-xs">
          <label>From <input type="datetime-local" value={customFrom} onChange={(e) => setCustomFrom(e.target.value)}
            className="mt-1 block rounded-lg border border-white/10 bg-[#0c0e13] p-2" /></label>
          <label>To <input type="datetime-local" value={customTo} onChange={(e) => setCustomTo(e.target.value)}
            className="mt-1 block rounded-lg border border-white/10 bg-[#0c0e13] p-2" /></label>
          <button type="button" onClick={applyCustomRange}
            className="rounded-lg bg-[#ff6b00] px-4 py-2 text-xs font-bold text-black">Apply</button>
        </div>
      </section>

      {error ? (
        <p className="rounded-xl border border-red-500/30 bg-red-500/10 px-4 py-3 text-sm text-red-200">{error}</p>
      ) : null}

      {data?.metrics_error ? (
        <p className="rounded-xl border border-amber-500/30 bg-amber-500/10 px-4 py-3 text-sm text-amber-100">
          Product analytics could not load: {data.metrics_error}
        </p>
      ) : null}

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <Stat label="Active users · selected range" value={data?.metrics?.active_users ?? "—"} />
        <Stat label="First-seen users · selected range" value={data?.metrics?.new_installs ?? "—"} />
        <Stat label="Sessions" value={data?.metrics?.sessions.count ?? "—"} />
        <Stat label="Average active minutes" value={data?.metrics ? Math.round(data.metrics.sessions.avg_active_seconds / 60) : "—"} />
      </div>

      {data?.metrics ? (
        <section className="rounded-2xl border border-white/10 bg-[#171a21] p-5">
          <h2 className="text-lg font-semibold text-white">Return visits and conversion</h2>
          <p className="mt-1 text-xs text-white/50">
            D1 and D7 count first-seen learners who returned on the next or seventh UTC calendar day.
            Only cohorts old enough for a complete day are included.
          </p>
          <div className="mt-4 grid gap-2 sm:grid-cols-2 lg:grid-cols-4">
            <Stat label={`D1 return · ${data.metrics.retention.d1_eligible} eligible`}
              value={data.metrics.retention.d1_percent == null ? "—" : `${data.metrics.retention.d1_percent}%`} />
            <Stat label={`D7 return · ${data.metrics.retention.d7_eligible} eligible`}
              value={data.metrics.retention.d7_percent == null ? "—" : `${data.metrics.retention.d7_percent}%`} />
            <Stat label="Paywall viewers" value={data.metrics.conversion.paywall_viewers} />
            <Stat label={`Purchased · ${data.metrics.conversion.purchasers} users`}
              value={data.metrics.conversion.view_to_purchase_percent == null ? "—"
                : `${data.metrics.conversion.view_to_purchase_percent}%`} />
          </div>
        </section>
      ) : null}

      {data?.metrics ? (
        <section className="rounded-2xl border border-white/10 bg-[#171a21] p-5">
          <h2 className="text-lg font-semibold text-white">Learning activity · {range.label}</h2>
          <p className="mt-2 text-sm text-white/55">
            {data.metrics.sessions.count} sessions · {Math.round(data.metrics.sessions.avg_active_seconds / 60)} average active minutes
          </p>
          <div className="mt-4 grid gap-2 sm:grid-cols-3">
            {data.metrics.core_funnel.map((step) => (
              <div key={step.name} className="rounded-lg bg-white/5 px-3 py-2 text-sm">
                <p className="text-white/50">{step.name.replaceAll("_", " ")}</p>
                <p className="mt-1 font-semibold text-white">{step.users} users</p>
              </div>
            ))}
          </div>
          <div className="mt-5 grid gap-2 sm:grid-cols-2 lg:grid-cols-4">
            <Stat label="Unique clip views" value={data.metrics.learning.clip_views} />
            <Stat label="Unique clip completions" value={data.metrics.learning.clip_completions} />
            <Stat label="Viewed and completed" value={`${data.metrics.learning.completion_percent}%`} />
            <Stat label="Video likes" value={data.metrics.learning.likes} />
            <Stat label="Words saved" value={data.metrics.learning.vocab_saves} />
            <Stat label="Reviews completed" value={data.metrics.learning.reviews_completed} />
            <Stat label="Quick-check completion" value={`${data.metrics.learning.quiz_completion_percent}%`} />
            <Stat label="Playback failures · videos" value={`${data.metrics.playback.failure_reports} · ${data.metrics.playback.affected_videos}`} />
          </div>
          {data.metrics.dau_series.length > 0 ? (
            <div className="mt-5">
              <p className="mb-2 text-xs text-white/50">Daily active users (UTC)</p>
              <div className="flex h-20 items-end gap-1" aria-label="Daily active users chart">
                {data.metrics.dau_series.map((point) => (
                  <div key={point.day} title={`${point.day}: ${point.users} users`}
                    className="min-w-1 flex-1 rounded-t bg-[#ff6b00]"
                    style={{ height: `${Math.max(4, point.users / maxDaily * 100)}%` }} />
                ))}
              </div>
            </div>
          ) : null}
          {data.metrics.errors.length > 0 ? (
            <p className="mt-4 text-sm text-amber-100">
              Errors in range: {data.metrics.errors.slice(0, 3).map((item) => `${item.name}${item.code ? ` (${item.code})` : ""}: ${item.n}`).join(" · ")}
            </p>
          ) : null}
          {data.metrics.playback.top_videos.length > 0 ? (
            <div className="mt-4 text-sm">
              <p className="font-semibold">Most reported playback failures</p>
              <div className="mt-2 flex flex-wrap gap-2">
                {data.metrics.playback.top_videos.map((item) => (
                  <a key={item.video_id} href={`https://www.youtube.com/watch?v=${encodeURIComponent(item.video_id)}`}
                    target="_blank" rel="noopener noreferrer"
                    className="rounded-full border border-white/10 bg-white/5 px-3 py-1.5 hover:bg-white/10">
                    {item.video_id} · {item.reports} reports
                  </a>
                ))}
              </div>
            </div>
          ) : null}
        </section>
      ) : null}

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <Stat label={`Acquisition answers · ${range.label}`} value={data?.metrics?.acquisition?.total ?? "—"} />
        <Stat label={`Feedback items · ${range.label}`} value={data?.metrics?.feedback.total ?? "—"} />
        <Stat label="Enjoying · Yes" value={data?.metrics?.feedback.positive ?? "—"} />
        <Stat label="Enjoying · No" value={data?.metrics?.feedback.negative ?? "—"} />
      </div>

      <section className="rounded-2xl border border-white/10 bg-[#171a21] p-5">
        <h2 className="text-lg font-semibold text-white">Where users found Jojo · {range.label}</h2>
        <div className="mt-4 space-y-3">
          {bySource.length === 0 ? (
            <p className="text-sm text-white/45">No acquisition answers yet.</p>
          ) : (
            bySource.map(([source, n]) => (
              <div key={source} className="grid grid-cols-[140px_1fr_40px] items-center gap-3 text-sm">
                <span className="capitalize text-white/80">{source.replaceAll("_", " ")}</span>
                <div className="h-2.5 overflow-hidden rounded-full bg-black/40">
                  <div
                    className="h-full rounded-full bg-gradient-to-r from-[#ff8a3d] to-[#ff6b00]"
                    style={{ width: `${(n / maxSource) * 100}%` }}
                  />
                </div>
                <span className="text-right text-white/50">{n}</span>
              </div>
            ))
          )}
        </div>
      </section>

      <section className="rounded-2xl border border-white/10 bg-[#171a21] p-5">
        <h2 className="text-lg font-semibold text-white">Messages</h2>
        <p className="mt-1 text-sm text-white/50">
          Your private board. A reply shows up only in that learner&apos;s app, under Feedback → Messages with Jojo.
        </p>
        <div className="mt-4 space-y-4">
          {threads.length === 0 ? (
            <p className="text-sm text-white/45">No conversations yet.</p>
          ) : (
            threads.map((thread) => (
              <article key={thread.appUserId} className="rounded-xl border border-white/10 bg-[#12151c] p-4">
                <p className="break-all text-xs text-white/40">{thread.appUserId}</p>
                <div className="mt-3 space-y-2">
                  {thread.entries.map((entry) => (
                    <div
                      key={entry.key}
                      className={`max-w-[85%] rounded-2xl px-3 py-2 text-sm ${
                        entry.from === "jojo"
                          ? "ml-auto bg-[#ff6b00] text-black"
                          : "bg-white/10 text-white/90"
                      }`}
                    >
                      <p className="mb-1 text-[10px] font-bold uppercase tracking-wide opacity-70">
                        {entry.from === "jojo" ? "You" : "Learner"}
                      </p>
                      <p className="whitespace-pre-wrap">{entry.text}</p>
                      <p className="mt-1 text-[10px] opacity-60">{new Date(entry.at).toLocaleString()}</p>
                    </div>
                  ))}
                </div>
                <form
                  className="mt-3 flex gap-2"
                  onSubmit={(event) => {
                    event.preventDefault();
                    void sendReply(thread.appUserId);
                  }}
                >
                  <input
                    value={drafts[thread.appUserId] ?? ""}
                    onChange={(event) =>
                      setDrafts((current) => ({ ...current, [thread.appUserId]: event.target.value }))
                    }
                    placeholder="Reply just to this person"
                    className="min-w-0 flex-1 rounded-lg border border-white/10 bg-[#0c0e13] px-3 py-2 text-sm text-white"
                  />
                  <button
                    type="submit"
                    disabled={sendingTo === thread.appUserId || !(drafts[thread.appUserId] ?? "").trim()}
                    className="rounded-full bg-[#ff6b00] px-4 py-2 text-sm font-bold text-black disabled:opacity-50"
                  >
                    {sendingTo === thread.appUserId ? "Sending…" : "Send"}
                  </button>
                </form>
              </article>
            ))
          )}
        </div>
      </section>

      <section className="rounded-2xl border border-white/10 bg-[#171a21] p-5">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h2 className="text-lg font-semibold text-white">Feedback</h2>
          <select
            value={status}
            onChange={(e) => setStatus(e.target.value)}
            className="rounded-lg border border-white/10 bg-[#0c0e13] px-3 py-2 text-sm text-white"
          >
            <option value="">All statuses</option>
            <option value="new">New</option>
            <option value="reviewed">Reviewed</option>
            <option value="done">Done</option>
          </select>
        </div>
        <div className="mt-4 space-y-3">
          {visibleFeedback.length === 0 ? (
            <p className="text-sm text-white/45">No feedback yet.</p>
          ) : (
            visibleFeedback.map((item) => (
              <article key={item.id} className="rounded-xl border border-white/10 bg-[#12151c] p-4">
                <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
                  <div className="flex flex-wrap gap-2">
                    <Pill
                      tone={item.enjoyed === true ? "yes" : item.enjoyed === false ? "no" : "neutral"}
                      label={item.enjoyed === true ? "Yes" : item.enjoyed === false ? "No" : "—"}
                    />
                    {item.category ? <Pill tone="neutral" label={item.category} /> : null}
                    <Pill tone="neutral" label={item.status} />
                  </div>
                  <span className="text-xs text-white/45">{new Date(item.created_at).toLocaleString()}</span>
                </div>
                <p className="whitespace-pre-wrap text-sm text-white/90">{item.message}</p>
                <p className="mt-2 break-all text-xs text-white/40">{item.app_user_id}</p>
                {item.app_user_id === "anonymous" ? (
                  <p className="mt-2 text-xs text-white/45">Anonymous feedback cannot receive a private reply.</p>
                ) : null}
                <div className="mt-3 flex flex-wrap gap-2">
                  {(["reviewed", "done", "new"] as const).map((s) => (
                    <button
                      key={s}
                      type="button"
                      onClick={() => void setItemStatus(item.id, s)}
                      className="rounded-full border border-white/10 bg-white/5 px-3 py-1.5 text-xs font-semibold text-white/80 hover:bg-white/10"
                    >
                      Mark {s}
                    </button>
                  ))}
                </div>
              </article>
            ))
          )}
        </div>
      </section>
      <AppStoreReviews />
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string | number }) {
  return (
    <article className="rounded-2xl border border-white/10 bg-[#171a21] p-4">
      <p className="text-xs text-white/45">{label}</p>
      <p className="mt-2 text-3xl font-extrabold text-white">{value}</p>
    </article>
  );
}

function Pill({ label, tone }: { label: string; tone: "yes" | "no" | "neutral" }) {
  const cls =
    tone === "yes"
      ? "bg-emerald-500/20 text-emerald-200"
      : tone === "no"
        ? "bg-rose-500/20 text-rose-200"
        : "bg-white/10 text-white/60";
  return <span className={`rounded-full px-2.5 py-1 text-[11px] font-bold uppercase ${cls}`}>{label}</span>;
}
