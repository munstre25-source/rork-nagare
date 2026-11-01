-- OpenRouter calls remain metered in openrouter_budget.spent_usd, but no longer
-- stop when the legacy cap_usd value is reached. Keep this RPC for deployed
-- Edge Function versions that still call it before each analysis.
create or replace function public.openrouter_budget_ok(reserve numeric default 0.05)
returns boolean
language sql
security definer
set search_path = public
as $$
  select true
$$;

revoke all on function public.openrouter_budget_ok(numeric) from public, anon, authenticated;
comment on function public.openrouter_budget_ok(numeric) is
  'Compatibility gate: OpenRouter spending is recorded, not capped.';
