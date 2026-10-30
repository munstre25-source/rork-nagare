-- Hard OpenRouter spend cap (owner budget: $3 from the 2026-10-30 top-up).
create table if not exists public.openrouter_budget (
  id int primary key default 1 check (id = 1),
  spent_usd numeric not null default 0,
  cap_usd numeric not null default 3,
  updated_at timestamptz not null default now()
);
alter table public.openrouter_budget enable row level security;
insert into public.openrouter_budget (id) values (1) on conflict do nothing;

create or replace function public.openrouter_budget_ok(reserve numeric default 0.05)
returns boolean language sql security definer set search_path = public as $$
  select spent_usd + reserve < cap_usd from public.openrouter_budget where id = 1
$$;

create or replace function public.openrouter_add_spend(cost numeric)
returns numeric language sql security definer set search_path = public as $$
  update public.openrouter_budget set spent_usd = spent_usd + greatest(cost, 0), updated_at = now()
  where id = 1 returning spent_usd
$$;

revoke all on function public.openrouter_budget_ok(numeric) from public, anon, authenticated;
revoke all on function public.openrouter_add_spend(numeric) from public, anon, authenticated;
