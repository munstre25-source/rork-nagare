import { NextResponse } from "next/server";
import { hasHQAccess, jojoInsightsConfig } from "@/lib/hq-access";

export const dynamic = "force-dynamic";

async function proxyInsights(req: Request) {
  if (!(await hasHQAccess())) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const cfg = jojoInsightsConfig();
  if (!cfg.configured) {
    return NextResponse.json(
      { error: "Jojo insights env not configured (JOJO_SUPABASE_URL, JOJO_SUPABASE_ANON_KEY, JOJO_ADMIN_TOKEN)." },
      { status: 503 },
    );
  }

  const incoming = new URL(req.url);
  const pipeline = req.method === "GET" && incoming.searchParams.get("pipeline") === "1";
  const target = new URL(`${cfg.supabaseUrl}/functions/v1/${pipeline ? "admin-pipeline" : "admin-insights"}`);
  incoming.searchParams.forEach((value, key) => target.searchParams.set(key, value));

  const init: RequestInit = {
    method: req.method,
    headers: {
      "Content-Type": "application/json",
      apikey: cfg.anonKey,
      Authorization: `Bearer ${cfg.anonKey}`,
      "x-admin-token": cfg.adminToken,
    },
    cache: "no-store",
  };

  if (req.method === "PATCH" || req.method === "POST") {
    init.body = await req.text();
  }

  const res = await fetch(target, init);
  if (req.method === "GET" && res.ok && !pipeline) {
    const insights = await res.json() as Record<string, unknown>;
    try {
      const metricsTarget = new URL(`${cfg.supabaseUrl}/functions/v1/admin-dashboard`);
      const from = incoming.searchParams.get("from");
      const to = incoming.searchParams.get("to");
      if (from && to) {
        metricsTarget.searchParams.set("from", from);
        metricsTarget.searchParams.set("to", to);
      } else {
        metricsTarget.searchParams.set("days", "30");
      }
      const metricsRes = await fetch(metricsTarget, init);
      if (!metricsRes.ok) {
        return NextResponse.json({ ...insights, metrics: null, metrics_error: `HTTP ${metricsRes.status}` });
      }
      const dashboard = await metricsRes.json() as { metrics?: unknown };
      return NextResponse.json({ ...insights, metrics: dashboard.metrics ?? null });
    } catch {
      return NextResponse.json({ ...insights, metrics: null, metrics_error: "Request failed" });
    }
  }
  const text = await res.text();
  return new NextResponse(text, {
    status: res.status,
    headers: { "Content-Type": res.headers.get("Content-Type") ?? "application/json" },
  });
}

export async function GET(req: Request) {
  return proxyInsights(req);
}

export async function PATCH(req: Request) {
  return proxyInsights(req);
}

export async function POST(req: Request) {
  return proxyInsights(req);
}
