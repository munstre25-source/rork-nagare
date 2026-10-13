-- YouTube search position for each catalog lane. Service role only.
-- Lets fill-catalog walk past videos it has already published.

create table if not exists public.catalog_search_cursors (
  lane_key text primary key,
  page_token text,
  variant int not null default 0,
  updated_at timestamptz not null default now()
);

alter table public.catalog_search_cursors enable row level security;
revoke all on table public.catalog_search_cursors from public, anon, authenticated;
