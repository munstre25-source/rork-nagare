-- Acquisition + in-app feedback (service-role writes only via Edge Functions).

create table if not exists public.acquisition_events (
  id bigint generated always as identity primary key,
  app_user_id text not null,
  source text not null check (source in ('instagram','tiktok','web_search','app_store','friend','youtube','other')),
  source_detail text,
  created_at timestamptz not null default now(),
  constraint acquisition_events_app_user_unique unique (app_user_id)
);
alter table public.acquisition_events enable row level security;
create index if not exists acquisition_events_source_idx on public.acquisition_events (source);
create index if not exists acquisition_events_created_at_idx on public.acquisition_events (created_at desc);

create table if not exists public.feedback_items (
  id bigint generated always as identity primary key,
  app_user_id text not null,
  enjoyed boolean,
  category text check (category is null or category in ('bug','feature','general')),
  message text not null default '',
  status text not null default 'new' check (status in ('new','reviewed','done')),
  created_at timestamptz not null default now()
);
alter table public.feedback_items enable row level security;
create index if not exists feedback_items_status_created_idx on public.feedback_items (status, created_at desc);
create index if not exists feedback_items_app_user_idx on public.feedback_items (app_user_id);
create index if not exists feedback_items_category_idx on public.feedback_items (category);

create table if not exists public.insight_rate_buckets (
  app_user_id text not null,
  day_utc date not null,
  kind text not null check (kind in ('acquisition','feedback')),
  count int not null default 0,
  primary key (app_user_id, day_utc, kind)
);
alter table public.insight_rate_buckets enable row level security;

create or replace function public.increment_insight_rate(
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
  insert into public.insight_rate_buckets (app_user_id, day_utc, kind, count)
  values (p_app_user_id, p_day_utc, p_kind, 1)
  on conflict (app_user_id, day_utc, kind)
  do update set count = public.insight_rate_buckets.count + 1
  where public.insight_rate_buckets.count < p_limit
  returning count into new_count;
  if new_count is null then
    return false;
  end if;
  return true;
end;
$$;

revoke all on function public.increment_insight_rate(text, date, text, int) from public, anon, authenticated;
grant execute on function public.increment_insight_rate(text, date, text, int) to service_role;

revoke all on table public.acquisition_events from anon, authenticated;
revoke all on table public.feedback_items from anon, authenticated;
revoke all on table public.insight_rate_buckets from anon, authenticated;
grant all on table public.acquisition_events to service_role;
grant all on table public.feedback_items to service_role;
grant all on table public.insight_rate_buckets to service_role;
grant usage, select on all sequences in schema public to service_role;;
