/** Constant-time admin token check. Never log the token. */

function encode(s: string): Uint8Array {
  return new TextEncoder().encode(s);
}

/** Constant-time equality for equal-length byte arrays. */
function timingSafeEqualBytes(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a[i]! ^ b[i]!;
  }
  return diff === 0;
}

/**
 * Compare two strings in constant time for a given max length.
 * Length mismatch still walks a fixed buffer so timing does not leak the secret length exactly,
 * but unequal lengths always return false.
 */
export function timingSafeEqualString(a: string, b: string): boolean {
  const ae = encode(a);
  const be = encode(b);
  const len = Math.max(ae.length, be.length, 1);
  const ap = new Uint8Array(len);
  const bp = new Uint8Array(len);
  ap.set(ae);
  bp.set(be);
  const equal = timingSafeEqualBytes(ap, bp);
  return equal && ae.length === be.length;
}

export function requireAdmin(req: Request, adminToken: string): boolean {
  const provided = req.headers.get("x-admin-token") ?? "";
  return timingSafeEqualString(provided, adminToken);
}

/**
 * Admin or scheduled caller. pg_cron sends CRON_FILL_TOKEN (stored in Vault as admin_token);
 * operators send ADMIN_TOKEN. Both arrive in x-admin-token.
 */
export function isAdminOrCron(req: Request): boolean {
  const adminToken = Deno.env.get("ADMIN_TOKEN")?.trim() ?? "";
  if (adminToken.length > 0 && requireAdmin(req, adminToken)) return true;
  const cronToken = Deno.env.get("CRON_FILL_TOKEN")?.trim() ?? "";
  if (cronToken.length < 16) return false;
  return requireAdmin(req, cronToken);
}
