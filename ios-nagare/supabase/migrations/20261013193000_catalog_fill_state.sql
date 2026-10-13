-- Pauses catalog search when Gemini video billing rejects the call,
-- so the timer does not spend the daily YouTube quota on retries.

create table if not exists public.catalog_fill_state (
  id int primary key check (id = 1),
  paused_until timestamptz,
  pause_reason text,
  updated_at timestamptz not null default now()
);

alter table public.catalog_fill_state enable row level security;
revoke all on table public.catalog_fill_state from public, anon, authenticated;
