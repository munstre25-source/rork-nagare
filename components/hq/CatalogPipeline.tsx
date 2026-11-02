"use client";
import { useCallback, useEffect, useRef, useState } from "react";

type Row = { id: string; video_id: string; title: string; channel_name: string; status: string; stage: string; reason?: string; detail?: string; at: string; source: string };
type Channel = { title: string; handle?: string; live: number; verified: number; queued_videos: number; queued_windows: number; discovery_status?: string; checked_at?: string };
type Summary = {
 current_failed: number; current_held: number; current_excluded: number; current_queued_retries: number;
 live: number; drafts: number; policy_passed_live: number; needs_policy_review: number;
 queued_videos: number; queued_windows: number; processing: number; stalled: number;
 published_in_range: number; unpublished_in_range: number; rejected_in_range: number; failed_in_range: number; held_in_range: number; reviewed_in_range: number; legacy_rejections_in_range: number;
 history_started_at?: string; last_attempt_at?: string;
 budget?: { spent_usd: number; reserved_usd?: number; cap_usd: number; lookup_allowance_usd?: number; lookup_spent_usd?: number; lookup_reserved_usd?: number }; publisher?: { paused_until?: string; pause_reason?: string };
 learner_jobs?: Record<string, number>;
};
type Payload = { generated_at: string; summary: Summary; channels: Channel[]; reasons: { reason: string; status: string; n: number }[]; items: Row[]; total: number; page: number; page_size: number; policy_version: number };
type View = "current" | "live" | "drafts" | "queued" | "attempts" | "publications" | "rejections" | "jobs";
const views: { id: View; label: string }[] = [
 { id: "current", label: "Current pipeline" },
 { id: "live", label: "Live catalog" }, { id: "drafts", label: "Unpublished" }, { id: "queued", label: "Candidate queue" },
 { id: "attempts", label: "Processing & outcomes" }, { id: "publications", label: "Publication history" },
 { id: "rejections", label: "Legacy rejections" }, { id: "jobs", label: "Learner imports" },
];
const statuses: Record<View, string[]> = {
 current: ["queued","processing","stalled","published","excluded","held","failed"],
 live: ["policy_passed","needs_review"], drafts: ["policy_passed","needs_review"], queued: [],
 attempts: ["processing","stalled","published","reviewed","rejected","held","failed"],
 publications: ["published","unpublished"], rejections: [], jobs: ["queued","processing","succeeded","failed"],
};
const time = (value?: string) => value ? new Date(value).toLocaleString() : "—";
const money = (value?: number) => value == null ? "—" : new Intl.NumberFormat(undefined, { style: "currency", currency: "USD", maximumFractionDigits: 3 }).format(Number(value));
const panel = "rounded-2xl border border-white/10 bg-[#171a21] p-5";
const control = "rounded-xl border border-white/10 bg-[#0c0e13] px-3 py-2 text-sm";
function Badge({ status }: { status: string }) {
 const tone = ["published","policy_passed","reviewed","succeeded"].includes(status) ? "text-emerald-300 bg-emerald-500/10" :
  ["failed","rejected"].includes(status) ? "text-red-300 bg-red-500/10" : "text-amber-200 bg-amber-500/10";
 return <span className={`inline-block rounded-full px-2 py-1 text-xs ${tone}`}>{status.replaceAll("_", " ")}</span>;
}
export function CatalogPipeline({ from, to, refreshKey }: { from: string; to: string; refreshKey: number }) {
 const [data, setData] = useState<Payload | null>(null);
 const [view, setView] = useState<View>("current");
 const [status, setStatus] = useState("");
 const [search, setSearch] = useState("");
 const [query, setQuery] = useState("");
 const [page, setPage] = useState(0);
 const [error, setError] = useState("");
 const [loading, setLoading] = useState(false);
 const [auto, setAuto] = useState(true);
 const sequence = useRef(0);
 const pending = useRef<AbortController | null>(null);
 useEffect(() => { const id = window.setTimeout(() => { setQuery(search.trim()); setPage(0); }, 300); return () => clearTimeout(id); }, [search]);
 useEffect(() => setPage(0), [from,to]);
 const load = useCallback(async () => {
  const id = ++sequence.current;
  pending.current?.abort();
  const controller = new AbortController(); pending.current = controller;
  setLoading(true); setError("");
  try {
   const params = new URLSearchParams({ pipeline: "1", view, status, search: query, page: String(page) });
   if (from && to) { params.set("from",from); params.set("to",to); }
   const response = await fetch(`/hq/jojo-insights/api?${params}`, { cache: "no-store", signal: controller.signal });
   const payload = await response.json();
   if (!response.ok) throw new Error(payload.error || `HTTP ${response.status}`);
   if (id === sequence.current) setData(payload);
  } catch (e) {
   if (id === sequence.current && !controller.signal.aborted) setError(e instanceof Error ? e.message : "Pipeline request failed");
  } finally { if (id === sequence.current) setLoading(false); }
 }, [from,to,view,status,query,page]);
 useEffect(() => { void load(); return () => pending.current?.abort(); }, [load,refreshKey]);
 useEffect(() => {
  if (!auto) return;
  const timer = window.setInterval(() => { if (document.visibilityState === "visible") void load(); }, 30000);
  return () => clearInterval(timer);
 }, [auto,load]);
 function select(next: View, filter = "") { setView(next); setStatus(filter); setPage(0); }
 const s = data?.summary;
 const b = s?.budget;
 const catalogRemaining = b ? Math.max(0, Number(b.cap_usd)-Number(b.spent_usd)-Number(b.reserved_usd ?? 0)) : undefined;
 const lookupRemaining = b?.lookup_allowance_usd == null ? undefined : Math.max(0, Number(b.lookup_allowance_usd)-Number(b.lookup_spent_usd ?? 0)-Number(b.lookup_reserved_usd ?? 0));
 const metric = (label: string, value: number | undefined, note: string, next: View, filter = "") =>
  <button key={label} type="button" onClick={() => select(next,filter)} className={`${panel} text-left hover:border-[#ff6b00]/50`}>
   <p className="text-xs text-white/55">{label}</p><p className="mt-2 text-3xl font-semibold">{value ?? "—"}</p><p className="mt-1 text-xs text-white/45">{note}</p>
  </button>;
 return <div className="space-y-5">
  <section className={panel}>
   <div className="flex flex-wrap items-center justify-between gap-3">
    <div><h2 className="text-lg font-semibold">Japanese catalog pipeline</h2><p className="mt-1 text-xs text-white/50">Updated {time(data?.generated_at)} · current inventory and queue health; dated outcomes remain in history</p></div>
    <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={auto} onChange={e=>setAuto(e.target.checked)} /> Refresh every 30 seconds</label>
   </div>
   <p className="mt-3 text-sm text-white/60">Queued → source and embed check → transcription and timing → English meaning, grammar and visual subtitle review → publication.</p>
   <p className="mt-2 text-xs text-white/45">Queue inventory includes in-flight windows until their attempts finish; processing is also shown separately. One video can contain multiple candidate windows. Publication history records actual transitions from this deployment onward; older creation dates are not counted as publication events.</p>
   <div className="mt-4 flex flex-wrap gap-3 text-sm">
    <span>Catalog allowance remaining <b>{money(catalogRemaining)}</b> · reserved {money(b?.reserved_usd)}</span>
    <span>User definition reserve <b>{money(lookupRemaining)}</b> · video calls cannot use it</span>
    <span>Last attempt {time(s?.last_attempt_at)}</span>
    <span>{s?.publisher?.paused_until && new Date(s.publisher.paused_until)>new Date() ? `Paused until ${time(s.publisher.paused_until)} · ${s.publisher.pause_reason}` : "Publisher: every 10 minutes · source ≤4 min"}</span>
   </div>
   {s?.needs_policy_review ? <p className="mt-3 rounded-xl border border-amber-500/30 bg-amber-500/10 p-3 text-sm text-amber-100">{s.needs_policy_review} existing live clips still need policy v{data?.policy_version} review. Their publication state is unchanged; older receipts do not certify the current checks.</p> : null}
   {error ? <p role="alert" className="mt-3 text-sm text-red-200">Pipeline refresh failed: {error}. {data ? "The displayed snapshot is stale." : "Counts are unavailable."}</p> : null}
  </section>
  <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
   {metric("Live lessons",s?.live,"Current published inventory","live")}
   {metric("Passed current policy · live",s?.policy_passed_live,"Audio, timing, English and source visual check","live","policy_passed")}
   {metric("Queued source videos",s?.queued_videos,`${s?.queued_windows ?? "—"} candidate windows`,"queued")}
   {metric("Processing now",s?.processing,`${s?.stalled ?? "—"} stalled over 10 minutes`,"attempts","processing")}
   {metric("Successful publications · range",s?.published_in_range,"Actual publish transitions; republishing is another event","publications","published")}
   {metric("Excluded sources",s?.current_excluded,"Quality or eligibility did not pass; kept out of the queue","current","excluded")}
   {metric("Held now",s?.current_held,"Latest unresolved publishing holds","current","held")}
   {metric("Failed now",s?.current_failed,"Recoverable processing errors; queued retries are counted separately","current","failed")}
  </div>
  <section className={panel}>
   <div className="flex flex-wrap gap-2">{views.map(v=><button key={v.id} type="button" onClick={()=>select(v.id)} aria-pressed={view===v.id} className={`${control} ${view===v.id ? "border-[#ff6b00] text-[#ff6b00]" : ""}`}>{v.label}</button>)}</div>
   <div className="mt-4 flex flex-wrap items-center gap-2">
    <input aria-label="Search pipeline" placeholder="Video ID, title, channel or failure reason" value={search} onChange={e=>setSearch(e.target.value)} className={`${control} min-w-0 flex-1`} />
    <select aria-label="Pipeline status" value={status} onChange={e=>{setStatus(e.target.value);setPage(0);}} className={control}><option value="">All statuses</option>{statuses[view].map(v=><option key={v} value={v}>{v.replaceAll("_"," ")}</option>)}</select>
    <button type="button" onClick={()=>void load()} disabled={loading} className={control}>{loading ? "Refreshing…" : "Refresh pipeline"}</button>
   </div>
   <p className="mt-2 text-xs text-white/45">{view==="rejections" ? "Historical rejection records are separate from the new attempt ledger and are not added to its failure counts." : view==="jobs" ? "Learner imports are shown separately from automatic catalog processing." : view==="current" ? "Latest automatic/manual outcome per source window. A queued retry replaces the old failure here; the original attempt stays in history. Legacy live reviews are tracked separately." : view==="live" || view==="drafts" || view==="queued" ? "This is current inventory; the date range applies to outcomes and publication history." : "Includes attempts and outcomes in the selected range, plus processing attempts that still need an outcome."}</p>
   <div className="mt-4 max-h-[520px] overflow-auto"><table className="w-full text-left text-sm">
    <thead className="sticky top-0 z-10 border-b border-white/10 bg-[#171a21] text-xs text-white/45"><tr>{["Clip / source video","Status","Stage / category","Reason and detail","Updated"].map(h=><th key={h} className="px-2 py-3 font-medium">{h}</th>)}</tr></thead>
    <tbody>{(data?.items ?? []).map(row=><tr key={row.id} className="border-b border-white/5">
     <td className="max-w-xs px-2 py-3"><a href={`https://www.youtube.com/watch?v=${row.video_id}`} target="_blank" rel="noreferrer" className="font-medium text-[#ff6b00] hover:underline">{row.title || row.video_id}</a><p className="mt-1 text-xs text-white/50">{row.channel_name}</p><p className="mt-1 break-all font-mono text-[10px] text-white/35">{row.id}</p></td>
     <td className="px-2 py-3"><Badge status={row.status} /></td><td className="px-2 py-3 text-xs text-white/55">{row.stage === "awaiting_retry" && !row.reason ? "ready" : row.stage}<p>{row.source}</p></td>
     <td className="max-w-md px-2 py-3 text-xs"><p className="font-medium">{row.reason?.replaceAll("_"," ") || "—"}</p><p className="mt-1 whitespace-pre-wrap break-words text-white/50">{row.detail}</p></td>
     <td className="whitespace-nowrap px-2 py-3 text-xs text-white/45">{time(row.at)}</td>
    </tr>)}</tbody>
   </table>{data && data.items.length===0 ? <p className="py-8 text-center text-sm text-white/45">No matching records.</p> : null}</div>
   <div className="mt-4 flex items-center justify-between gap-3 text-xs text-white/50"><span>{data ? `${data.total} matching records · page ${data.page+1} / ${Math.max(1,Math.ceil(data.total/data.page_size))}` : "Loading records…"}</span><div className="flex gap-2"><button type="button" disabled={page===0 || loading} onClick={()=>setPage(p=>Math.max(0,p-1))} className={control}>Previous</button><button type="button" disabled={!data || (page+1)*data.page_size>=data.total || loading} onClick={()=>setPage(p=>p+1)} className={control}>Next</button></div></div>
  </section>
  <section className={panel}><h2 className="text-lg font-semibold">Source channels</h2><p className="mt-1 text-xs text-white/50">All registered requested channels and channels with inventory. Zero queued uploads can mean no eligible recent source under the four-minute policy.</p>
   <div className="mt-4 max-h-96 overflow-auto"><table className="w-full text-left text-sm"><thead className="sticky top-0 bg-[#171a21] text-xs text-white/45"><tr>{["Channel","Live","Policy passed","Queued videos / windows","Discovery"].map(h=><th key={h} className="px-2 py-2">{h}</th>)}</tr></thead><tbody>{(data?.channels ?? []).map((c,i)=><tr key={c.handle || c.title || i} className="border-t border-white/5"><td className="px-2 py-3">{c.title || "Unknown channel"}<p className="text-xs text-white/45">{c.handle ? `@${c.handle}` : ""}</p></td><td className="px-2 py-3">{c.live}</td><td className="px-2 py-3">{c.verified}</td><td className="px-2 py-3">{c.queued_videos} / {c.queued_windows}</td><td className="px-2 py-3 text-xs text-white/50">{c.discovery_status?.replaceAll("_"," ") || "Catalog discovery"}<p>{time(c.checked_at)}</p></td></tr>)}</tbody></table></div>
  </section>
  <div className="grid gap-5 lg:grid-cols-2">
   <section className={panel}><h2 className="text-lg font-semibold">Outcome history · selected range</h2><p className="mt-2 text-xs text-white/45">Historical attempts remain here after a successful retry. Excluded sources are completed screening decisions, not active technical errors.</p>{data?.reasons.length ? <ul className="mt-3 space-y-3">{data.reasons.map(r=><li key={r.status+":"+r.reason} className="flex items-center justify-between gap-3 text-sm"><span>{r.reason?.replaceAll("_"," ") || "Unspecified"} <Badge status={r.status} /></span><b>{r.n}</b></li>)}</ul> : <p className="mt-3 text-sm text-white/45">No held, rejected or failed attempts in this range.</p>}</section>
   <section className={panel}><h2 className="text-lg font-semibold">Other inventory and activity</h2><dl className="mt-3 grid grid-cols-2 gap-3 text-sm"><dt>Unpublished lessons</dt><dd>{s?.drafts ?? "—"}</dd><dt>Stalled attempts</dt><dd>{s?.stalled ?? "—"}</dd><dt>Reviews passed · range</dt><dd>{s?.reviewed_in_range ?? "—"}</dd><dt>Unpublish events · range</dt><dd>{s?.unpublished_in_range ?? "—"}</dd><dt>Queued retries</dt><dd>{s?.current_queued_retries ?? "—"}</dd><dt>Failed attempts · range</dt><dd>{s?.failed_in_range ?? "—"}</dd><dt>Held attempts · range</dt><dd>{s?.held_in_range ?? "—"}</dd><dt>Rejected attempts · range</dt><dd>{s?.rejected_in_range ?? "—"}</dd><dt>Legacy rejection records · range</dt><dd>{s?.legacy_rejections_in_range ?? "—"}</dd></dl><p className="mt-4 text-xs text-white/45">Learner imports: {Object.entries(s?.learner_jobs ?? {}).map(([k,v])=>`${k}: ${v}`).join(" · ") || "none"}</p><p className="mt-3 text-xs text-white/45">Unknown or incomplete visual/audio checks are held from new publication. App-controlled English help remains available; English burned into source video is rejected. YouTube CC is kept off.</p></section>
  </div>
 </div>;
}
