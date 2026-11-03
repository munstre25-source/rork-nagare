"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { CatalogPipeline } from "./CatalogPipeline";
import { AppStoreReviews } from "./AppStoreReviews";
import { CategoryPerformance } from "./CategoryPerformance";

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

type InsightsPage = "overview" | "learning" | "categories" | "acquisition" | "playback" | "pipeline" | "messages" | "feedback" | "reviews";
const pages: { id: InsightsPage; label: string; group: string; description: string }[] = [
  { id: "overview", label: "Overview", group: "Understand", description: "The health of Jojo at a glance" },
  { id: "learning", label: "Learning", group: "Understand", description: "Video and study engagement" },
  { id: "categories", label: "Categories", group: "Understand", description: "Live clips and watch rates per category, with what to add more or less of" },
  { id: "acquisition", label: "Acquisition", group: "Understand", description: "Where learners found Jojo" },
  { id: "playback", label: "Playback", group: "Understand", description: "Video failures and app errors" },
  { id: "pipeline", label: "Pipeline", group: "Operate", description: "Catalog discovery, quality checks, queue and publication history" },
  { id: "messages", label: "Messages", group: "Respond", description: "Private learner conversations" },
  { id: "feedback", label: "Feedback", group: "Respond", description: "Review and resolve app feedback" },
  { id: "reviews", label: "App Store", group: "Respond", description: "Public reviews and replies" },
];

function pageFromURL(): InsightsPage {
  const view = new URLSearchParams(window.location.search).get("view");
  return pages.find((page) => page.id === view)?.id ?? "overview";
}

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
  const [pipelineRefresh, setPipelineRefresh] = useState(0);
  const [page, setPage] = useState<InsightsPage>("overview");
  const [data, setData] = useState<InsightsPayload | null>(null);
  const [status, setStatus] = useState("");
  const [messageQuery, setMessageQuery] = useState("");
  const [messageReplyFilter, setMessageReplyFilter] = useState<"all" | "needs-reply">("all");
  const [feedbackQuery, setFeedbackQuery] = useState("");
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
    setPage(pageFromURL());
    const onPopState = () => setPage(pageFromURL());
    window.addEventListener("popstate", onPopState);
    return () => window.removeEventListener("popstate", onPopState);
  }, []);

  function navigate(next: InsightsPage) {
    setPage(next);
    const url = new URL(window.location.href);
    if (next === "overview") url.searchParams.delete("view");
    else url.searchParams.set("view", next);
    window.history.pushState(null, "", url);
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

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
  const visibleThreads = threads.filter((thread) => {
    if (messageReplyFilter === "needs-reply" && thread.entries.at(-1)?.from !== "user") return false;
    const query = messageQuery.trim().toLocaleLowerCase();
    return !query || thread.appUserId.toLocaleLowerCase().includes(query) ||
      thread.entries.some((entry) => entry.text.toLocaleLowerCase().includes(query));
  });
  const visibleFeedback = (data?.feedback.items ?? []).filter((item) => {
    if (status && item.status !== status) return false;
    const query = feedbackQuery.trim().toLocaleLowerCase();
    return !query || item.app_user_id.toLocaleLowerCase().includes(query) ||
      item.message.toLocaleLowerCase().includes(query) || Boolean(item.category?.toLocaleLowerCase().includes(query));
  });
  const maxSource = Math.max(1, ...bySource.map(([, n]) => n));
  const maxDaily = Math.max(1, ...(data?.metrics?.dau_series ?? []).map((point) => point.users));
  const selectedPage = pages.find((item) => item.id === page)!;
  const showsDateRange = page === "overview" || page === "learning" || page === "categories" || page === "acquisition" || page === "playback" || page === "pipeline";

  return (
    <div className="grid min-w-0 gap-6 lg:grid-cols-[220px_minmax(0,1fr)]">
      <aside className="min-w-0 lg:sticky lg:top-6 lg:self-start" aria-label="Insights navigation">
        <div className="rounded-2xl border border-white/10 bg-[#171a21] p-3">
          <p className="px-3 py-2 text-xs font-bold uppercase tracking-[0.18em] text-[#ff6b00]">Jojo HQ</p>
          <nav className="flex gap-1 overflow-x-auto lg:block" aria-label="Analytics sections">
            {pages.map((item, index) => (
              <div key={item.id} className="shrink-0 lg:shrink">
                {(index === 0 || pages[index - 1]?.group !== item.group) ? (
                  <p className="hidden px-3 pb-1 pt-4 text-[10px] font-bold uppercase tracking-widest text-white/40 lg:block">{item.group}</p>
                ) : null}
                <button type="button" onClick={() => navigate(item.id)} aria-current={page === item.id ? "page" : undefined}
                  className={`w-full whitespace-nowrap rounded-xl px-3 py-2.5 text-left text-sm font-semibold transition-colors lg:whitespace-normal ${page === item.id ? "bg-[#ff6b00] text-black" : "text-white/60 hover:bg-white/5 hover:text-white"}`}>
                  {item.label}
                </button>
              </div>
            ))}
          </nav>
        </div>
      </aside>
      <main className="min-w-0 space-y-5">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-[#ff6b00]">Production insights · {selectedPage.group}</p>
          <h1 className="mt-2 text-3xl font-semibold tracking-tight text-white">{selectedPage.label}</h1>
          <p className="mt-2 max-w-2xl text-sm text-white/55">{selectedPage.description}</p>
        </div>
        <div className="flex gap-2">
          <button type="button" onClick={() => setTheme(theme === "dark" ? "light" : "dark")}
            className="rounded-full border border-white/10 px-4 py-2.5 text-sm font-semibold">
            {theme === "dark" ? "Light mode" : "Dark mode"}
          </button>
          {page !== "reviews" ? <button
            type="button"
            onClick={() => page === "pipeline" || page === "categories" ? setPipelineRefresh(n => n+1) : void load()}
            className="rounded-full bg-[#ff6b00] px-5 py-2.5 text-sm font-bold text-black disabled:opacity-60"
            disabled={loading}
          >
            {loading ? "Loading…" : "Refresh"}
          </button> : null}
        </div>
      </div>

      {showsDateRange ? <section className="rounded-2xl border border-white/10 bg-[#171a21] p-4">
        <p className="text-sm font-semibold">Analytics date and time · {range.label}</p>
        <p className="mt-1 text-xs text-white/50">Presets use your local time. Reports use UTC boundaries; production feedback stays recent.</p>
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
      </section> : null}

      {error ? (
        <p className="rounded-xl border border-red-500/30 bg-red-500/10 px-4 py-3 text-sm text-red-200">{error}</p>
      ) : null}

      {data?.metrics_error ? (
        <p className="rounded-xl border border-amber-500/30 bg-amber-500/10 px-4 py-3 text-sm text-amber-100">
          Product analytics could not load: {data.metrics_error}
        </p>
      ) : null}

      {page === "pipeline" ? <CatalogPipeline from={range.from} to={range.to} refreshKey={pipelineRefresh} /> : null}
      {page === "categories" ? <CategoryPerformance from={range.from} to={range.to} refreshKey={pipelineRefresh} rangeLabel={range.label} /> : null}

      {page === "overview" ? <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <Stat label="Active users · selected range" value={data?.metrics?.active_users ?? "—"} />
        <Stat label="First-seen users · selected range" value={data?.metrics?.new_installs ?? "—"} />
        <Stat label="Sessions" value={data?.metrics?.sessions.count ?? "—"} />
        <Stat label="Average active minutes" value={data?.metrics ? Math.round(data.metrics.sessions.avg_active_seconds / 60) : "—"} />
      </div> : null}

      {page === "overview" && data?.metrics ? (
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

      {page === "overview" ? (
        <section aria-label="Explore detailed reports" className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
          {([
            ["learning", "Learning", `${data?.metrics?.learning.clip_views ?? "—"} clip views`],
            ["categories", "Categories", "Most and least watched categories"],
            ["acquisition", "Acquisition", `${data?.metrics?.acquisition.total ?? "—"} source answers`],
            ["playback", "Playback", `${data?.metrics?.playback.failure_reports ?? "—"} failure reports`],
            ["messages", "Messages", `${threads.length} conversations`],
            ["feedback", "Feedback", `${data?.feedback.total ?? "—"} recent items`],
            ["reviews", "App Store", "Read and reply to reviews"],
          ] as const).map(([destination, title, detail]) => (
            <button key={destination} type="button" onClick={() => navigate(destination)}
              className="rounded-2xl border border-white/10 bg-[#171a21] p-4 text-left transition-colors hover:bg-white/5">
              <span className="flex items-center justify-between gap-2 text-sm font-semibold text-white">
                {title}<span aria-hidden="true" className="text-[#ff6b00]">↗</span>
              </span>
              <span className="mt-2 block text-xs text-white/50">{detail}</span>
            </button>
          ))}
        </section>
      ) : null}

      {page === "learning" && data?.metrics ? (
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
        </section>
      ) : null}

      {page === "playback" ? (
        <section className="rounded-2xl border border-white/10 bg-[#171a21] p-5">
          <h2 className="text-lg font-semibold text-white">Playback health · {range.label}</h2>
          <p className="mt-1 text-sm text-white/50">Reports from real production sessions in the selected time range.</p>
          <div className="mt-4 grid gap-3 sm:grid-cols-2">
            <Stat label="Failure reports" value={data?.metrics?.playback.failure_reports ?? "—"} />
            <Stat label="Affected videos" value={data?.metrics?.playback.affected_videos ?? "—"} />
          </div>
          <h3 className="mt-6 text-sm font-semibold text-white">Videos with the most reports</h3>
          <div className="mt-2 flex flex-wrap gap-2 text-sm">
            {data?.metrics?.playback.top_videos.length ? data.metrics.playback.top_videos.map((item) => (
              <a key={item.video_id} href={`https://www.youtube.com/watch?v=${encodeURIComponent(item.video_id)}`}
                target="_blank" rel="noopener noreferrer"
                className="rounded-full border border-white/10 bg-white/5 px-3 py-1.5 hover:bg-white/10">
                {item.video_id} · {item.reports} reports
              </a>
            )) : <p className="text-white/50">No video failures reported.</p>}
          </div>
          <h3 className="mt-6 text-sm font-semibold text-white">App errors</h3>
          <div className="mt-2 space-y-2 text-sm">
            {data?.metrics?.errors.length ? data.metrics.errors.map((item) => (
              <div key={`${item.name}:${item.code}`} className="flex justify-between gap-3 rounded-lg bg-white/5 px-3 py-2">
                <span className="break-all text-white/80">{item.name}{item.code ? ` · ${item.code}` : ""}</span>
                <span className="font-semibold text-white">{item.n}</span>
              </div>
            )) : <p className="text-white/50">No app errors reported.</p>}
          </div>
        </section>
      ) : null}

      {page === "acquisition" ? <div className="grid gap-3 sm:grid-cols-2">
        <Stat label={`Acquisition answers · ${range.label}`} value={data?.metrics?.acquisition?.total ?? "—"} />
        <Stat label="Distinct sources" value={bySource.length} />
      </div> : null}

      {page === "acquisition" ? <section className="rounded-2xl border border-white/10 bg-[#171a21] p-5">
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
      </section> : null}

      {page === "messages" ? <section className="rounded-2xl border border-white/10 bg-[#171a21] p-5">
        <h2 className="text-lg font-semibold text-white">Messages</h2>
        <p className="mt-1 text-sm text-white/50">
          Your private board. A reply shows up only in that learner&apos;s app, under Feedback → Messages with Jojo.
        </p>
        <div className="mt-4 flex flex-wrap gap-2">
          <input aria-label="Search conversations" value={messageQuery} onChange={(event) => setMessageQuery(event.target.value)}
            placeholder="Search conversations" className="min-w-0 flex-1 rounded-lg border border-white/10 bg-[#0c0e13] px-3 py-2 text-sm text-white" />
          <select aria-label="Filter conversations" value={messageReplyFilter}
            onChange={(event) => setMessageReplyFilter(event.target.value as "all" | "needs-reply")}
            className="rounded-lg border border-white/10 bg-[#0c0e13] px-3 py-2 text-sm text-white">
            <option value="all">All conversations</option><option value="needs-reply">Needs reply</option>
          </select>
        </div>
        <div className="mt-4 space-y-4">
          {visibleThreads.length === 0 ? (
            <p className="text-sm text-white/45">No matching conversations.</p>
          ) : (
            visibleThreads.map((thread) => (
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
      </section> : null}

      {page === "feedback" ? <div className="grid gap-3 sm:grid-cols-3">
        <Stat label="Recent feedback" value={data?.feedback.total ?? "—"} />
        <Stat label="Enjoying · Yes" value={data?.feedback.enjoyed_yes ?? "—"} />
        <Stat label="Enjoying · No" value={data?.feedback.enjoyed_no ?? "—"} />
      </div> : null}

      {page === "feedback" ? <section className="rounded-2xl border border-white/10 bg-[#171a21] p-5">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h2 className="text-lg font-semibold text-white">Feedback</h2>
          <input aria-label="Search feedback" value={feedbackQuery} onChange={(event) => setFeedbackQuery(event.target.value)}
            placeholder="Search feedback" className="min-w-0 rounded-lg border border-white/10 bg-[#0c0e13] px-3 py-2 text-sm text-white" />
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
            <p className="text-sm text-white/45">No matching feedback.</p>
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
      </section> : null}
      {page === "reviews" ? <AppStoreReviews /> : null}
      </main>
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
