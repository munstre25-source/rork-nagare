import { createPrivateKey, sign } from "node:crypto";
import { NextResponse } from "next/server";
import { hasHQAccess } from "@/lib/hq-access";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

const APPLE_API = "https://api.appstoreconnect.apple.com/v1";

function credentials() {
  const issuer = process.env.APP_STORE_CONNECT_ISSUER_ID?.trim();
  const keyId = process.env.APP_STORE_CONNECT_KEY_ID?.trim();
  const privateKey = process.env.APP_STORE_CONNECT_PRIVATE_KEY?.replace(/\\n/g, "\n").trim();
  const appId = process.env.APP_STORE_CONNECT_APP_ID?.trim();
  return issuer && keyId && privateKey && appId ? { issuer, keyId, privateKey, appId } : null;
}

function bearer(config: NonNullable<ReturnType<typeof credentials>>): string {
  const now = Math.floor(Date.now() / 1000);
  const header = Buffer.from(JSON.stringify({ alg: "ES256", kid: config.keyId, typ: "JWT" })).toString("base64url");
  const payload = Buffer.from(JSON.stringify({ iss: config.issuer, iat: now, exp: now + 600, aud: "appstoreconnect-v1" })).toString("base64url");
  const content = `${header}.${payload}`;
  const signature = sign("sha256", Buffer.from(content), {
    key: createPrivateKey(config.privateKey), dsaEncoding: "ieee-p1363",
  }).toString("base64url");
  return `${content}.${signature}`;
}

async function authorizedConfig() {
  if (!(await hasHQAccess())) return { error: NextResponse.json({ error: "Unauthorized" }, { status: 401 }) };
  const config = credentials();
  if (!config) return { error: NextResponse.json({
    error: "Set APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_PRIVATE_KEY, and APP_STORE_CONNECT_APP_ID in Vercel.",
  }, { status: 503 }) };
  return { config };
}

export async function GET() {
  const access = await authorizedConfig();
  if (access.error) return access.error;
  const config = access.config!;
  try {
    const url = new URL(`${APPLE_API}/apps/${encodeURIComponent(config.appId)}/customerReviews`);
    url.searchParams.set("sort", "-createdDate");
    url.searchParams.set("limit", "100");
    url.searchParams.set("include", "response");
    const response = await fetch(url, { headers: { Authorization: `Bearer ${bearer(config)}` }, cache: "no-store" });
    if (!response.ok) return NextResponse.json({ error: `App Store Connect returned HTTP ${response.status}` }, { status: 502 });
    const body = await response.json() as {
      data?: { id: string; attributes?: Record<string, unknown>; relationships?: { response?: { data?: { id: string } | null } } }[];
      included?: { id: string; attributes?: { responseBody?: string; state?: string } }[];
    };
    const responses = new Map((body.included ?? []).map((item) => [item.id, item.attributes]));
    return NextResponse.json({ reviews: (body.data ?? []).map((review) => ({
      id: review.id,
      title: review.attributes?.title ?? "",
      body: review.attributes?.body ?? "",
      rating: review.attributes?.rating ?? 0,
      nickname: review.attributes?.reviewerNickname ?? "",
      territory: review.attributes?.territory ?? "",
      createdAt: review.attributes?.createdDate ?? "",
      response: responses.get(review.relationships?.response?.data?.id ?? "")?.responseBody ?? null,
      responseState: responses.get(review.relationships?.response?.data?.id ?? "")?.state ?? null,
    })) });
  } catch {
    return NextResponse.json({ error: "Could not load App Store reviews" }, { status: 502 });
  }
}

export async function POST(req: Request) {
  const access = await authorizedConfig();
  if (access.error) return access.error;
  const config = access.config!;
  let input: { reviewId?: unknown; message?: unknown };
  try { input = await req.json(); } catch { return NextResponse.json({ error: "Invalid request" }, { status: 400 }); }
  const reviewId = typeof input.reviewId === "string" ? input.reviewId.trim() : "";
  const message = typeof input.message === "string" ? input.message.trim() : "";
  if (!/^[A-Za-z0-9-]{8,100}$/.test(reviewId) || !message || message.length > 2000) {
    return NextResponse.json({ error: "Choose a review and write a reply of at most 2,000 characters" }, { status: 400 });
  }
  try {
    const response = await fetch(`${APPLE_API}/customerReviewResponses`, {
      method: "POST",
      headers: { Authorization: `Bearer ${bearer(config)}`, "Content-Type": "application/json" },
      body: JSON.stringify({ data: {
        type: "customerReviewResponses",
        attributes: { responseBody: message },
        relationships: { review: { data: { type: "customerReviews", id: reviewId } } },
      } }),
      cache: "no-store",
    });
    if (!response.ok) return NextResponse.json({ error: `App Store Connect rejected the reply (HTTP ${response.status})` }, { status: 502 });
    return NextResponse.json({ ok: true });
  } catch {
    return NextResponse.json({ error: "Could not publish the App Store reply" }, { status: 502 });
  }
}
