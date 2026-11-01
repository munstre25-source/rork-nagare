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
APP_STORE_CONNECT_ISSUER_ID=...
APP_STORE_CONNECT_KEY_ID=...
APP_STORE_CONNECT_PRIVATE_KEY=...  # full .p8 contents; escaped newlines also work
APP_STORE_CONNECT_APP_ID=...       # numeric app resource ID from App Store Connect
```

The four App Store Connect variables enable public review reading and replies in
the private Vercel dashboard. Use an App Store Connect team API key with access to
the app and customer reviews. Without them, private in-app feedback and product
analytics still work; the App Store reviews section explains what is missing.

Deploy the Supabase `analytics-ingest`, `admin-dashboard`, `admin-insights`,
`submit-feedback`, and `direct-messages` functions and apply the analytics and
feedback migrations before relying on the dashboard. The Vercel page proxies
private Supabase requests server-side; no admin token is sent to the browser.

## Local static fallback

```bash
cd tools/insights-dashboard
python3 -m http.server 8787
```

Open http://localhost:8787 — enter URL, anon key, and admin token in the page.
