/** HTTP helpers. Never log secrets or tokens. */

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-app-user-id, x-admin-token",
  "Access-Control-Allow-Methods": "GET, POST, PATCH, OPTIONS",
};

export function corsPreflight(): Response {
  return new Response(null, { status: 204, headers: CORS });
}

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

export function errorResponse(status: number, message: string): Response {
  return jsonResponse({ error: message }, status);
}

export async function readJson<T>(req: Request): Promise<T> {
  return await req.json() as T;
}
