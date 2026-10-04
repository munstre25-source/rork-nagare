"use client";

import { useCallback, useEffect, useState } from "react";

type FeedbackItem = {
  id: number;
  app_user_id: string;
  enjoyed: boolean | null;
  category: string | null;
  message: string;
  status: string;
  created_at: string;
};

type InsightsPayload = {
  acquisition: { total: number; by_source: Record<string, number> };
  feedback: {
    total: number;
    enjoyed_yes: number;
    enjoyed_no: number;
    items: FeedbackItem[];
  };
};

export function JojoInsightsDashboard() {
  const [data, setData] = useState<InsightsPayload | null>(null);
  const [status, setStatus] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const qs = status ? `?status=${encodeURIComponent(status)}` : "";
      const res = await fetch(`/hq/jojo-insights/api${qs}`, { cache: "no-store" });
      const json = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(json.error || `HTTP ${res.status}`);
      setData(json as InsightsPayload);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to load");
      setData(null);
    } finally {
      setLoading(false);
    }
  }, [status]);

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

  const bySource = Object.entries(data?.acquisition.by_source ?? {}).sort((a, b) => b[1] - a[1]);
  const maxSource = Math.max(1, ...bySource.map(([, n]) => n));

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-[#ff6b00]">Jojo · noindex</p>
          <h1 className="mt-2 text-3xl font-semibold tracking-tight text-white">Insights</h1>
          <p className="mt-2 max-w-2xl text-sm text-white/55">
            Acquisition answers and enjoy/feedback prompts, read from Supabase. Gated by the HQ token.
          </p>
        </div>
        <button
          type="button"
          onClick={() => void load()}
          className="rounded-full bg-[#ff6b00] px-5 py-2.5 text-sm font-bold text-black disabled:opacity-60"
          disabled={loading}
        >
          {loading ? "Loading…" : "Refresh"}
        </button>
      </div>

      {error ? (
        <p className="rounded-xl border border-red-500/30 bg-red-500/10 px-4 py-3 text-sm text-red-200">{error}</p>
      ) : null}

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <Stat label="Acquisition answers" value={data?.acquisition.total ?? "—"} />
        <Stat label="Feedback items" value={data?.feedback.total ?? "—"} />
        <Stat label="Enjoying · Yes" value={data?.feedback.enjoyed_yes ?? "—"} />
        <Stat label="Enjoying · No" value={data?.feedback.enjoyed_no ?? "—"} />
      </div>

      <section className="rounded-2xl border border-white/10 bg-[#171a21] p-5">
        <h2 className="text-lg font-semibold text-white">Where users found Jojo</h2>
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
          {(data?.feedback.items ?? []).length === 0 ? (
            <p className="text-sm text-white/45">No feedback yet.</p>
          ) : (
            data!.feedback.items.map((item) => (
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
