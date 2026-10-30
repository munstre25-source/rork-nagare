-- Candidate queues for the catalog fill.
--
-- One YouTube search costs 101 quota units (10,000/day hard limit), and a pass can only
-- analyze a few candidates before its time budget ends. Queuing every embeddable result
-- means each search serves many passes: publish from the queue with no quota, and only
-- search again when the queue runs low. One queue per catalog language.
-- Reversible: see supabase/rollbacks/20261030160000_candidate_queues.down.sql

create table if not exists public.catalog_candidate_queue (
  video_id text primary key,
  title text not null,
  channel_title text not null,
  duration_sec numeric not null,
  category text not null,
  difficulty text not null,
  added_at timestamptz not null default now()
);

create table if not exists public.sori_candidate_queue (
  video_id text primary key,
  title text not null,
  channel_title text not null,
  duration_sec numeric not null,
  category text not null,
  difficulty text not null,
  added_at timestamptz not null default now()
);

alter table public.catalog_candidate_queue enable row level security;
alter table public.sori_candidate_queue enable row level security;
revoke all on table public.catalog_candidate_queue from anon, authenticated;
revoke all on table public.sori_candidate_queue from anon, authenticated;
grant all on table public.catalog_candidate_queue to service_role;
grant all on table public.sori_candidate_queue to service_role;
