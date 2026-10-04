# Jojo Insights

## Live

This repo hosts the private dashboard for the Vercel project (`/hq` and `/hq/jojo-insights`).
The public Jojo marketing pages stay on SocialReportHQ.

The same dashboard also remains at **https://socialreporthq.com/hq/jojo-insights**.

(Use your real site host if different.)

Requires host env:

```bash
HQ_ACCESS_TOKEN=...
JOJO_SUPABASE_URL=https://jacpmygzmsfiyltdsiyu.supabase.co
JOJO_SUPABASE_ANON_KEY=...
JOJO_ADMIN_TOKEN=...   # same as Supabase Edge ADMIN_TOKEN
```

## Local static fallback

```bash
cd tools/insights-dashboard
python3 -m http.server 8787
```

Open http://localhost:8787 — enter URL, anon key, and admin token in the page.
