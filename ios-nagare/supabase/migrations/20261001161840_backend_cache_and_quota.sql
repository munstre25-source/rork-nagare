-- Backend cache, rate limits, quota, and entitlement cache.
-- Safe to re-run: IF NOT EXISTS throughout. clips may already exist in live projects.

create table if not exists public.clips (
  id text primary key,
  video_id text not null,
  title text not null,
  channel_name text not null,
  category text not null check (category in ('anime','drama','variety','vtuber','interview','kids','gaming')),
  difficulty text not null check (difficulty in ('Beginner','Intermediate','Advanced')),
  duration_sec numeric not null,
  lines jsonb not null,
  published boolean not null default false,
  channel_avatar_color text,
  thumbnail_gradient jsonb,
  created_at timestamptz not null default now()
);

alter table public.clips enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'clips' and policyname = 'public read published clips'
  ) then
    create policy "public read published clips" on public.clips
      for select using (published = true);
  end if;
end $$;

create index if not exists clips_video_id_idx on public.clips (video_id);
create index if not exists clips_published_idx on public.clips (published) where published = true;

create table if not exists public.word_explanations (
  cache_key text primary key,
  kind text not null check (kind in ('lookup', 'context')),
  word text not null,
  sentence_hash text,
  payload jsonb not null,
  model text not null,
  prompt_version text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.word_explanations enable row level security;

create index if not exists word_explanations_word_idx on public.word_explanations (word);

create table if not exists public.explain_rate_buckets (
  app_user_id text not null,
  day_utc date not null,
  kind text not null check (kind in ('lookup', 'context')),
  count int not null default 0,
  primary key (app_user_id, day_utc, kind)
);

alter table public.explain_rate_buckets enable row level security;

create table if not exists public.gemini_daily_usage (
  day_utc date primary key,
  count int not null default 0
);

alter table public.gemini_daily_usage enable row level security;

create table if not exists public.revenuecat_entitlement_cache (
  app_user_id text primary key,
  entitled boolean not null,
  checked_at timestamptz not null default now()
);

alter table public.revenuecat_entitlement_cache enable row level security;

create table if not exists public.youtube_quota_usage (
  day_utc date primary key,
  units int not null default 0
);

alter table public.youtube_quota_usage enable row level security;

create or replace function public.increment_explain_rate(
  p_app_user_id text,
  p_day_utc date,
  p_kind text,
  p_limit int
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  new_count int;
begin
  insert into public.explain_rate_buckets (app_user_id, day_utc, kind, count)
  values (p_app_user_id, p_day_utc, p_kind, 1)
  on conflict (app_user_id, day_utc, kind)
  do update set count = public.explain_rate_buckets.count + 1
  where public.explain_rate_buckets.count < p_limit
  returning count into new_count;

  if new_count is null then
    return false;
  end if;
  return true;
end;
$$;

create or replace function public.increment_gemini_usage(
  p_day_utc date,
  p_limit int
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  new_count int;
begin
  insert into public.gemini_daily_usage (day_utc, count)
  values (p_day_utc, 1)
  on conflict (day_utc)
  do update set count = public.gemini_daily_usage.count + 1
  where public.gemini_daily_usage.count < p_limit
  returning count into new_count;

  if new_count is null then
    return false;
  end if;
  return true;
end;
$$;

create or replace function public.consume_youtube_quota(
  p_day_utc date,
  p_units int,
  p_limit int
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  new_units int;
begin
  if p_units <= 0 then
    return true;
  end if;
  if p_units > p_limit then
    return false;
  end if;

  insert into public.youtube_quota_usage (day_utc, units)
  values (p_day_utc, p_units)
  on conflict (day_utc)
  do update set units = public.youtube_quota_usage.units + excluded.units
  where public.youtube_quota_usage.units + excluded.units <= p_limit
  returning units into new_units;

  if new_units is null then
    return false;
  end if;
  return true;
end;
$$;

revoke all on function public.increment_explain_rate(text, date, text, int) from public;
revoke all on function public.increment_gemini_usage(date, int) from public;
revoke all on function public.consume_youtube_quota(date, int, int) from public;
grant execute on function public.increment_explain_rate(text, date, text, int) to service_role;
grant execute on function public.increment_gemini_usage(date, int) to service_role;
grant execute on function public.consume_youtube_quota(date, int, int) to service_role;;
