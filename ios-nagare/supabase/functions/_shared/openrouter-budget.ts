/** Server-only budget reservations. Credentials never leave the configured Supabase API. */
export type BudgetReservation = { id: string; amount: number };

async function rpc(name: string, body: Record<string, unknown>): Promise<unknown> {
  const base = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!base || !key) throw new Error("AI budget unavailable");
  const response = await fetch(base + "/rest/v1/rpc/" + name, {
    method: "POST",
    headers: { "Content-Type": "application/json", apikey: key, Authorization: "Bearer " + key },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(5000),
  });
  if (!response.ok) throw new Error("AI budget unavailable");
  return await response.json();
}

export async function reserveOpenRouterBudget(amount: number, purpose: "catalog" | "lookup" = "catalog"): Promise<BudgetReservation | null> {
  const id = await rpc(purpose === "lookup" ? "openrouter_reserve_lookup_budget" : "openrouter_reserve_budget", { p_amount: amount });
  return typeof id === "string" && /^[0-9a-f-]{36}$/i.test(id) ? { id, amount } : null;
}

/** Settlement is idempotent. If accounting is unavailable the reservation stays held. */
export async function settleOpenRouterBudget(reservation: BudgetReservation, cost: number): Promise<boolean> {
  try {
    const result = await rpc("openrouter_settle_budget", {
      p_reservation: reservation.id,
      p_cost: Number.isFinite(cost) && cost >= 0 ? cost : reservation.amount,
    });
    return (typeof result === "number" || typeof result === "string") && Number.isFinite(Number(result));
  } catch {
    console.warn(JSON.stringify({ event: "openrouter_budget_settlement_pending" }));
    return false;
  }
}
