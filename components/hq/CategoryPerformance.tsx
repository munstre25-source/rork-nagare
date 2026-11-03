"use client";
import { useCallback, useEffect, useRef, useState } from "react";

type TopClip = { id: string; title: string; channel: string; views: number; completions: number };
type CategoryRow = {
  category: string; live_clips: number; caption_live: number;
  views: number; raw_views: number; viewers: number; viewed_clips: number; completions: number;
  saves: number; likes: number; taste_swipes: number; taste_liked: number; top_clips: TopClip[];
};
type Payload = { include_test: boolean; categories: CategoryRow[] };

type Derived = CategoryRow & {
  catalogShare: number; viewShare: number; demandIndex: number | null;
  completionRate: number | null; savesPer100: number | null; coverage: number | null; interest: number | null;
};
type Insight = { tone: "good" | "warn" | "info"; title: string; body: string };

const panel = "rounded-2xl border border-white/10 bg-[#171a21] p-5";
const MIN_VIEWS = 10;
const pct = (value: number | null, digits = 0) => value == null ? "—" : `${value.toFixed(digits)}%`;
const label = (category: string) => category === "personal" ? "Learner imports" : category.charAt(0).toUpperCase() + category.slice(1);

function derive(rows: CategoryRow[]): Derived[] {
  const catalog = rows.filter((r) => r.category !== "personal");
  const totalLive = catalog.reduce((n, r) => n + r.live_clips, 0);
  const totalViews = catalog.reduce((n, r) => n + r.views, 0);
  return rows.map((r) => {
    const catalogShare = totalLive ? r.live_clips / totalLive * 100 : 0;
    const viewShare = totalViews && r.category !== "personal" ? r.views / totalViews * 100 : 0;
    return {
      ...r,
      catalogShare,
      viewShare,
      demandIndex: catalogShare > 0 && totalViews > 0 ? viewShare / catalogShare * 100 : null,
      completionRate: r.views ? Math.min(100, r.completions / r.views * 100) : null,
      savesPer100: r.views ? r.saves / r.views * 100 : null,
      coverage: r.live_clips ? Math.min(100, r.viewed_clips / r.live_clips * 100) : null,
      interest: r.taste_swipes ? r.taste_liked / r.taste_swipes * 100 : null,
    };
  });
}

/** Plain-language recommendations from supply vs demand. Thresholds avoid reacting to a handful of views. */
function insightsFor(rows: Derived[]): Insight[] {
  const catalog = rows.filter((r) => r.category !== "personal" && r.live_clips > 0);
  const totalViews = catalog.reduce((n, r) => n + r.views, 0);
  if (totalViews < 30) {
    return [{ tone: "info", title: "Not enough viewing yet", body: `${totalViews} unique clip views in this range. Recommendations appear after about 30.` }];
  }
  const out: Insight[] = [];
  const byViews = [...catalog].sort((a, b) => b.views - a.views);
  const most = byViews[0];
  const least = byViews.at(-1)!;
  out.push({ tone: "good", title: `Most watched: ${label(most.category)}`, body: `${pct(most.viewShare)} of all views from ${pct(most.catalogShare)} of the catalog.` });
  out.push({ tone: "warn", title: `Least watched: ${label(least.category)}`, body: `${pct(least.viewShare)} of views from ${least.live_clips} live clips (${pct(least.catalogShare)} of the catalog).` });

  const measured = catalog.filter((r) => r.views >= MIN_VIEWS && r.demandIndex != null);
  const hungry = measured.filter((r) => r.demandIndex! >= 150).sort((a, b) => b.demandIndex! - a.demandIndex!);
  for (const r of hungry.slice(0, 2)) {
    out.push({ tone: "good", title: `Add more ${label(r.category)}`, body: `Watched ${(r.demandIndex! / 100).toFixed(1)}× more than its catalog share. Only ${r.live_clips} live clips; learners have already opened ${pct(r.coverage)} of them.` });
  }
  const crowded = measured.filter((r) => r.demandIndex! <= 50 && r.live_clips >= 20).sort((a, b) => a.demandIndex! - b.demandIndex!);
  for (const r of crowded.slice(0, 2)) {
    out.push({ tone: "warn", title: `${label(r.category)} is over-supplied`, body: `${r.live_clips} live clips but only ${(r.demandIndex! / 100).toFixed(1)}× its catalog share in views. Slow new additions or surface the best ones.` });
  }
  const completion = measured.filter((r) => r.completionRate != null).sort((a, b) => b.completionRate! - a.completionRate!);
  if (completion.length >= 2) {
    const best = completion[0];
    const worst = completion.at(-1)!;
    out.push({ tone: "good", title: `Best finished: ${label(best.category)}`, body: `${pct(best.completionRate)} of views reach the end.` });
    if (worst.category !== best.category && worst.completionRate! < 40) {
      out.push({ tone: "warn", title: `Often abandoned: ${label(worst.category)}`, body: `Only ${pct(worst.completionRate)} finished. Check clip length, audio and difficulty.` });
    }
  }
  const studied = measured.filter((r) => r.savesPer100 != null).sort((a, b) => b.savesPer100! - a.savesPer100!)[0];
  if (studied) out.push({ tone: "info", title: `Most words saved: ${label(studied.category)}`, body: `${studied.savesPer100!.toFixed(0)} saves per 100 views.` });
  const gap = catalog.filter((r) => (r.interest ?? 0) >= 70 && r.taste_swipes >= 5 && r.catalogShare < 8);
  for (const r of gap.slice(0, 2)) {
    out.push({ tone: "good", title: `Interest gap: ${label(r.category)}`, body: `${pct(r.interest)} liked it during onboarding, but it is only ${pct(r.catalogShare)} of the catalog.` });
  }
  return out;
}

function ShareBars({ row, maxShare }: { row: Derived; maxShare: number }) {
  return (
    <div className="space-y-1" aria-label={`${label(row.category)}: ${pct(row.viewShare)} of views, ${pct(row.catalogShare)} of catalog`}>
      <div className="h-2 overflow-hidden rounded-full bg-black/40">
        <div className="h-full rounded-full bg-[#ff6b00]" style={{ width: `${row.viewShare / maxShare * 100}%` }} />
      </div>
      <div className="h-2 overflow-hidden rounded-full bg-black/40">
        <div className="h-full rounded-full bg-white/35" style={{ width: `${row.catalogShare / maxShare * 100}%` }} />
      </div>
    </div>
  );
}

export function CategoryPerformance({ from, to, refreshKey, rangeLabel }: { from: string; to: string; refreshKey: number; rangeLabel: string }) {
  const [data, setData] = useState<Payload | null>(null);
  const [includeTest, setIncludeTest] = useState(false);
  const [open, setOpen] = useState<string | null>(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const sequence = useRef(0);

  const load = useCallback(async () => {
    const id = ++sequence.current;
    setLoading(true);
    setError("");
    try {
      const params = new URLSearchParams({ report: "categories" });
      if (from && to) { params.set("from", from); params.set("to", to); }
      if (includeTest) params.set("include_test", "1");
      const res = await fetch(`/hq/jojo-insights/api?${params}`, { cache: "no-store" });
      const json = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(json.error || `HTTP ${res.status}`);
      if (id === sequence.current) setData(json as Payload);
    } catch (e) {
      if (id === sequence.current) setError(e instanceof Error ? e.message : "Failed to load");
    } finally {
      if (id === sequence.current) setLoading(false);
    }
  }, [from, to, includeTest]);

  useEffect(() => { void load(); }, [load, refreshKey]);

  const rows = derive(data?.categories ?? []);
  const catalogRows = rows.filter((r) => r.category !== "personal");
  const personal = rows.find((r) => r.category === "personal");
  const insights = insightsFor(rows);
  const maxShare = Math.max(1, ...catalogRows.flatMap((r) => [r.viewShare, r.catalogShare]));
  const totals = catalogRows.reduce((t, r) => ({ live: t.live + r.live_clips, views: t.views + r.views, done: t.done + r.completions }), { live: 0, views: 0, done: 0 });

  return (
    <div className="space-y-5">
      <section className={panel}>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h2 className="text-lg font-semibold">What learners watch · {rangeLabel}</h2>
            <p className="mt-1 text-xs text-white/50">Live clips are current inventory. Views, completions and saves are unique learner–clip pairs in the selected range.</p>
          </div>
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={includeTest} onChange={(e) => setIncludeTest(e.target.checked)} />
            Include test and pre-launch data
          </label>
        </div>
        {error ? <p role="alert" className="mt-3 text-sm text-red-200">Could not load categories: {error}</p> : null}
        <div className="mt-4 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <Metric label="Live clips" value={totals.live} />
          <Metric label="Unique clip views" value={totals.views} />
          <Metric label="Completion rate" value={totals.views ? pct(Math.min(100, totals.done / totals.views * 100)) : "—"} />
          <Metric label="Categories with views" value={`${catalogRows.filter((r) => r.views > 0).length} / ${catalogRows.length}`} />
        </div>
      </section>

      <section className={panel}>
        <h2 className="text-lg font-semibold">Recommendations</h2>
        <div className="mt-3 grid gap-3 md:grid-cols-2">
          {loading && !data ? <p className="text-sm text-white/45">Loading…</p> : insights.map((item) => (
            <article key={item.title} className={`rounded-xl border p-4 ${item.tone === "good" ? "border-emerald-500/30 bg-emerald-500/5" : item.tone === "warn" ? "border-amber-500/30 bg-amber-500/5" : "border-white/10 bg-white/5"}`}>
              <p className="text-sm font-semibold">{item.title}</p>
              <p className="mt-1 text-xs text-white/60">{item.body}</p>
            </article>
          ))}
        </div>
      </section>

      <section className={panel}>
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h2 className="text-lg font-semibold">Categories</h2>
          <p className="flex items-center gap-3 text-xs text-white/50">
            <span className="flex items-center gap-1"><span className="inline-block h-2 w-4 rounded bg-[#ff6b00]" /> share of views</span>
            <span className="flex items-center gap-1"><span className="inline-block h-2 w-4 rounded bg-white/35" /> share of catalog</span>
          </p>
        </div>
        <p className="mt-1 text-xs text-white/45">Demand index 100 means a category is watched exactly in proportion to its catalog size; above 100 learners want more of it. Rates with fewer than {MIN_VIEWS} views are dimmed.</p>
        <div className="mt-4 overflow-x-auto">
          <table className="w-full min-w-[920px] text-left text-sm">
            <thead className="border-b border-white/10 text-xs text-white/45">
              <tr>{["Category", "Live clips", "Views vs catalog", "Views", "Demand index", "Viewers", "Clips opened", "Completed", "Saves / 100 views", "Likes", "Onboarding interest"].map((h) => <th key={h} className="px-2 py-3 font-medium">{h}</th>)}</tr>
            </thead>
            <tbody>
              {catalogRows.map((r) => {
                const thin = r.views < MIN_VIEWS ? "text-white/35" : "";
                return [
                  <tr key={r.category} className="cursor-pointer border-b border-white/5 hover:bg-white/5" onClick={() => setOpen(open === r.category ? null : r.category)}>
                    <td className="px-2 py-3 font-semibold">{label(r.category)} <span className="text-[#ff6b00]">{open === r.category ? "▾" : "▸"}</span></td>
                    <td className="px-2 py-3">{r.live_clips}<p className="text-[11px] text-white/40">{r.caption_live ? `${r.caption_live} caption` : ""}</p></td>
                    <td className="w-40 px-2 py-3"><ShareBars row={r} maxShare={maxShare} /></td>
                    <td className="px-2 py-3">{r.views}<p className="text-[11px] text-white/40">{pct(r.viewShare)}</p></td>
                    <td className={`px-2 py-3 font-semibold ${thin || (r.demandIndex == null ? "" : r.demandIndex >= 150 ? "text-emerald-300" : r.demandIndex <= 50 ? "text-amber-300" : "")}`}>{r.demandIndex == null ? "—" : Math.round(r.demandIndex)}</td>
                    <td className="px-2 py-3">{r.viewers}</td>
                    <td className="px-2 py-3">{pct(r.coverage)}<p className="text-[11px] text-white/40">{r.viewed_clips} of {r.live_clips}</p></td>
                    <td className={`px-2 py-3 ${thin}`}>{pct(r.completionRate)}</td>
                    <td className={`px-2 py-3 ${thin}`}>{r.savesPer100 == null ? "—" : r.savesPer100.toFixed(0)}</td>
                    <td className="px-2 py-3">{r.likes}</td>
                    <td className="px-2 py-3">{pct(r.interest)}<p className="text-[11px] text-white/40">{r.taste_swipes ? `${r.taste_liked}/${r.taste_swipes} liked` : ""}</p></td>
                  </tr>,
                  open === r.category ? (
                    <tr key={`${r.category}-top`} className="border-b border-white/5 bg-black/20">
                      <td colSpan={11} className="px-4 py-3">
                        <p className="text-xs font-semibold text-white/60">Most watched {label(r.category).toLowerCase()} clips</p>
                        {r.top_clips.length ? (
                          <ol className="mt-2 space-y-1 text-xs">
                            {r.top_clips.map((clip) => (
                              <li key={clip.id} className="flex flex-wrap justify-between gap-2">
                                <span className="text-white/80">{clip.title} <span className="text-white/40">· {clip.channel}</span></span>
                                <span className="text-white/50">{clip.views} viewers · {clip.views ? Math.round(Math.min(100, clip.completions / clip.views * 100)) : 0}% finished</span>
                              </li>
                            ))}
                          </ol>
                        ) : <p className="mt-2 text-xs text-white/45">No views in this range.</p>}
                      </td>
                    </tr>
                  ) : null,
                ];
              })}
            </tbody>
          </table>
          {data && catalogRows.length === 0 ? <p className="py-8 text-center text-sm text-white/45">No categories yet.</p> : null}
        </div>
        {personal && personal.views ? (
          <p className="mt-3 text-xs text-white/45">Learner imports (personal YouTube links): {personal.views} views · {pct(personal.completionRate)} completed · not counted in catalog shares.</p>
        ) : null}
      </section>
    </div>
  );
}

function Metric({ label: title, value }: { label: string; value: string | number }) {
  return (
    <article className="rounded-xl bg-white/5 p-4">
      <p className="text-xs text-white/45">{title}</p>
      <p className="mt-2 text-2xl font-extrabold">{value}</p>
    </article>
  );
}
