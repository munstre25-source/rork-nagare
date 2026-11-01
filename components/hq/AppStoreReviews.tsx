"use client";

import { useCallback, useEffect, useState } from "react";

type Review = {
  id: string;
  title: string;
  body: string;
  rating: number;
  nickname: string;
  territory: string;
  createdAt: string;
  response: string | null;
  responseState: string | null;
};

const endpoint = "/hq/jojo-insights/api/app-store-reviews";

export function AppStoreReviews() {
  const [reviews, setReviews] = useState<Review[]>([]);
  const [drafts, setDrafts] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState<string | null>(null);
  const [error, setError] = useState("");

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const response = await fetch(endpoint, { cache: "no-store" });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? `HTTP ${response.status}`);
      setReviews(body.reviews ?? []);
      setError("");
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not load reviews");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void load(); }, [load]);

  async function publish(review: Review) {
    const message = drafts[review.id]?.trim();
    if (!message) return;
    if (!window.confirm("Publish this reply publicly on the App Store?")) return;
    setSending(review.id);
    setError("");
    try {
      const response = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ reviewId: review.id, message }),
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? `HTTP ${response.status}`);
      setDrafts((current) => ({ ...current, [review.id]: "" }));
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not publish reply");
    } finally {
      setSending(null);
    }
  }

  return (
    <section className="rounded-2xl border border-white/10 bg-[#171a21] p-5">
      <div className="flex items-center justify-between gap-3">
        <div>
          <h2 className="text-lg font-semibold text-white">App Store reviews</h2>
          <p className="mt-1 text-sm text-white/50">Replies here are public on the App Store. The latest 100 reviews are shown.</p>
        </div>
        <button type="button" onClick={() => void load()} disabled={loading} className="text-sm text-[#ff8a3d] disabled:opacity-50">
          Refresh
        </button>
      </div>
      {error ? <p className="mt-4 rounded-lg border border-amber-500/30 bg-amber-500/10 p-3 text-sm text-amber-100">{error}</p> : null}
      {loading && reviews.length === 0 ? <p className="mt-4 text-sm text-white/50">Loading reviews…</p> : null}
      {!loading && !error && reviews.length === 0 ? <p className="mt-4 text-sm text-white/50">No App Store reviews yet.</p> : null}
      <div className="mt-4 space-y-3">
        {reviews.map((review) => (
          <article key={review.id} className="rounded-xl border border-white/10 bg-[#12151c] p-4">
            <div className="flex flex-wrap justify-between gap-2 text-xs text-white/50">
              <span>{"★".repeat(Math.max(0, Math.min(5, review.rating)))} · {review.nickname || "Customer"} · {review.territory}</span>
              <span>{review.createdAt ? new Date(review.createdAt).toLocaleDateString() : ""}</span>
            </div>
            <h3 className="mt-2 font-semibold text-white">{review.title}</h3>
            <p className="mt-1 whitespace-pre-wrap text-sm text-white/80">{review.body}</p>
            {review.response ? (
              <p className="mt-3 rounded-lg bg-white/5 p-3 text-sm text-white/70">
                Your reply ({review.responseState ?? "submitted"}): {review.response}
              </p>
            ) : null}
            <textarea
              value={drafts[review.id] ?? ""}
              onChange={(event) => setDrafts((current) => ({ ...current, [review.id]: event.target.value }))}
              maxLength={2000}
              placeholder={review.response ? "Replace your public reply" : "Write a public reply"}
              className="mt-3 min-h-20 w-full rounded-lg border border-white/10 bg-[#0c0e13] p-3 text-sm text-white"
            />
            <button
              type="button"
              onClick={() => void publish(review)}
              disabled={sending === review.id || !drafts[review.id]?.trim()}
              className="mt-2 rounded-full bg-[#ff6b00] px-4 py-2 text-sm font-bold text-black disabled:opacity-50"
            >
              {sending === review.id ? "Publishing…" : review.response ? "Update public reply" : "Publish public reply"}
            </button>
          </article>
        ))}
      </div>
    </section>
  );
}
