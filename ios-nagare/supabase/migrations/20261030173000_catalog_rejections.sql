-- Persist catalog candidate rejections so fill-catalog diagnosis does not depend on
-- edge-log access (edge_logs was unavailable during the 2026-10-30 catalog incident).
-- Service-role only; rows older than 14 days are pruned by fill-catalog passes.
create table if not exists public.catalog_rejections (
  video_id text not null,
  reason text not null,
  detail text,
  rejected_at timestamptz not null default now()
);
create index if not exists catalog_rejections_recent_idx on public.catalog_rejections (rejected_at desc);
alter table public.catalog_rejections enable row level security;
revoke all on table public.catalog_rejections from anon, authenticated;
grant all on table public.catalog_rejections to service_role;
