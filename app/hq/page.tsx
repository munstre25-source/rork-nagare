import type { Metadata } from "next";
import Link from "next/link";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { JojoInsightsDashboard } from "@/components/hq/JojoInsightsDashboard";
import { HQ_ACCESS_COOKIE, getHQAccessToken, jojoInsightsConfig } from "@/lib/hq-access";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export const metadata: Metadata = {
  title: "Command Centre | Jojo",
  robots: { index: false, follow: false, nocache: true },
};

async function unlockHQ(formData: FormData) {
  "use server";
  const configuredToken = getHQAccessToken();
  const submittedToken = String(formData.get("accessToken") ?? "").trim();
  if (!configuredToken || submittedToken !== configuredToken) {
    redirect("/hq?error=1");
  }
  const cookieStore = await cookies();
  cookieStore.set(HQ_ACCESS_COOKIE, configuredToken, {
    httpOnly: true,
    sameSite: "strict",
    secure: process.env.NODE_ENV === "production",
    path: "/hq",
    maxAge: 60 * 60 * 12,
  });
  redirect("/hq");
}

async function lockHQ() {
  "use server";
  const cookieStore = await cookies();
  cookieStore.delete(HQ_ACCESS_COOKIE);
  redirect("/hq");
}

export default async function HQPage({
  searchParams,
}: {
  searchParams?: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const cookieStore = await cookies();
  const configuredToken = getHQAccessToken();
  const cookieToken = cookieStore.get(HQ_ACCESS_COOKIE)?.value;
  const hasAccess = Boolean(configuredToken && cookieToken === configuredToken);

  if (!hasAccess) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-[#0f1115] px-5 text-white">
        <form action={unlockHQ} className="w-full max-w-md rounded-2xl border border-white/10 bg-[#171a21] p-6">
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-[#ff6b00]">Private · noindex</p>
          <h1 className="mt-2 text-2xl font-semibold">Unlock Command Centre</h1>
          <p className="mt-2 text-sm text-white/55">
            Private analytics for Jojo, plus a one-to-one message board with learners.
          </p>
          {!configuredToken ? (
            <p className="mt-4 rounded-lg border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-sm text-amber-100">
              Set <code className="font-mono">HQ_ACCESS_TOKEN1</code> in the Vercel environment first.
            </p>
          ) : null}
          {params?.error === "1" ? (
            <p className="mt-4 rounded-lg border border-red-500/30 bg-red-500/10 px-3 py-2 text-sm text-red-200">
              That access token was not accepted.
            </p>
          ) : null}
          <label className="mt-5 block text-sm text-white/60">
            Access token
            <input
              name="accessToken"
              type="password"
              autoComplete="current-password"
              className="mt-2 w-full rounded-lg border border-white/10 bg-[#0c0e13] px-3 py-2.5 text-white"
              required
            />
          </label>
          <button type="submit" className="mt-5 w-full rounded-full bg-[#ff6b00] px-4 py-3 text-sm font-bold text-black">
            Open HQ
          </button>
        </form>
      </div>
    );
  }

  const insightsReady = jojoInsightsConfig().configured;

  return (
    <div className="min-h-screen bg-[#0f1115] px-5 py-8 text-white sm:px-8">
      <div className="mx-auto mb-6 flex max-w-7xl flex-wrap items-center justify-between gap-3 text-sm">
        <p className="text-xs font-semibold uppercase tracking-[0.18em] text-white/40">Jojo · private HQ</p>
        <div className="flex items-center gap-3">
          <Link href="/hq/jojo-insights" className="text-white/55 hover:text-white">
            Jojo Insights
          </Link>
          <form action={lockHQ}>
            <button type="submit" className="rounded-full border border-white/10 px-3 py-1 text-xs text-white/55 hover:text-white">
              Lock HQ
            </button>
          </form>
        </div>
      </div>
      <div className="mx-auto max-w-7xl">
        {!insightsReady ? (
          <div className="rounded-2xl border border-amber-500/30 bg-amber-500/10 p-5 text-sm text-amber-50">
            <p className="font-semibold">Supabase env missing</p>
            <p className="mt-2 text-amber-100/80">
              Add <code className="font-mono">JOJO_SUPABASE_URL</code>,{" "}
              <code className="font-mono">JOJO_SUPABASE_ANON_KEY</code>, and{" "}
              <code className="font-mono">JOJO_ADMIN_TOKEN</code> on Vercel, then redeploy.
            </p>
          </div>
        ) : (
          <JojoInsightsDashboard />
        )}
      </div>
    </div>
  );
}
