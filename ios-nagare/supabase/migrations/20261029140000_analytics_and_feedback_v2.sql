-- First-party product analytics + feedback v2 (private inbox fields, public board moderation).
-- Additive only. Every table is service-role only; the app talks to Edge Functions.
-- Rollback: supabase/rollbacks/20261029140000_analytics_and_feedback_v2.down.sql (manual, destructive to analytics data).

-- ── Analytics ────────────────────────────────────────────────────────────────

create table if not exists public.analytics_sessions (
  id uuid primary key,
  install_id uuid not null,
  user_id uuid,
  started_at timestamptz not null,
  last_seen_at timestamptz not null,
  active_seconds int not null default 0 check (active_seconds between 0 and 86400),
  app_version text check (char_length(app_version) <= 24),
  build text check (char_length(build) <= 16),
  os_version text check (char_length(os_version) <= 16),
  device_class text check (char_length(device_class) <= 16),
  received_at timestamptz not null default now()
);
alter table public.analytics_sessions enable row level security;
create index if not exists analytics_sessions_started_idx on public.analytics_sessions (started_at desc);
create index if not exists analytics_sessions_install_idx on public.analytics_sessions (install_id, started_at);
create index if not exists analytics_sessions_user_idx on public.analytics_sessions (user_id) where user_id is not null;

create table if not exists public.analytics_events (
  -- Client-generated UUID: retries of the same batch are idempotent.
  id uuid primary key,
  install_id uuid not null,
  user_id uuid,
  session_id uuid,
  name text not null check (name ~ '^[a-z][a-z0-9_]{1,63}$'),
  props jsonb not null default '{}'::jsonb
    check (jsonb_typeof(props) = 'object' and pg_column_size(props) <= 2048),
  occurred_at timestamptz not null,
  app_version text check (char_length(app_version) <= 24),
  os_version text check (char_length(os_version) <= 16),
  received_at timestamptz not null default now()
);
alter table public.analytics_events enable row level security;
create index if not exists analytics_events_occurred_idx on public.analytics_events (occurred_at desc);
create index if not exists analytics_events_name_idx on public.analytics_events (name, occurred_at desc);
create index if not exists analytics_events_install_idx on public.analytics_events (install_id, occurred_at);
create index if not exists analytics_events_user_idx on public.analytics_events (user_id) where user_id is not null;

revoke all on table public.analytics_sessions from anon, authenticated;
revoke all on table public.analytics_events from anon, authenticated;
grant all on table public.analytics_sessions to service_role;
grant all on table public.analytics_events to service_role;

-- Rate buckets gain analytics + per-IP board kinds.
alter table public.insight_rate_buckets drop constraint if exists insight_rate_buckets_kind_check;
alter table public.insight_rate_buckets
  add constraint insight_rate_buckets_kind_check
  check (kind in ('acquisition','feedback','board','inbox','analytics','analytics_ip','board_ip','report'));

/** Batch ingest. Validated JSON comes from the analytics-ingest Edge Function. */
create or replace function public.analytics_ingest(
  p_install uuid,
  p_user uuid,
  p_events jsonb,
  p_sessions jsonb
) returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  inserted int := 0;
begin
  if jsonb_typeof(p_sessions) = 'array' then
    insert into public.analytics_sessions as s
      (id, install_id, user_id, started_at, last_seen_at, active_seconds, app_version, build, os_version, device_class)
    select
      (x->>'id')::uuid, p_install, p_user,
      (x->>'started_at')::timestamptz, (x->>'last_seen_at')::timestamptz,
      least(greatest(coalesce((x->>'active_seconds')::int, 0), 0), 86400),
      x->>'app_version', x->>'build', x->>'os_version', x->>'device_class'
    from jsonb_array_elements(p_sessions) as x
    on conflict (id) do update set
      last_seen_at = greatest(s.last_seen_at, excluded.last_seen_at),
      active_seconds = greatest(s.active_seconds, excluded.active_seconds),
      user_id = coalesce(s.user_id, excluded.user_id),
      received_at = now()
    where s.install_id = excluded.install_id;
  end if;

  if jsonb_typeof(p_events) = 'array' then
    with rows as (
      insert into public.analytics_events
        (id, install_id, user_id, session_id, name, props, occurred_at, app_version, os_version)
      select
        (x->>'id')::uuid, p_install, p_user, nullif(x->>'session_id', '')::uuid,
        x->>'name', coalesce(x->'props', '{}'::jsonb), (x->>'occurred_at')::timestamptz,
        x->>'app_version', x->>'os_version'
      from jsonb_array_elements(p_events) as x
      on conflict (id) do nothing
      returning 1
    )
    select count(*) into inserted from rows;
  end if;
  return inserted;
end;
$$;
revoke all on function public.analytics_ingest(uuid, uuid, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.analytics_ingest(uuid, uuid, jsonb, jsonb) to service_role;

-- ── Private inbox (feedback_items) ───────────────────────────────────────────

alter table public.feedback_items add column if not exists user_id uuid;
alter table public.feedback_items add column if not exists source text
  check (source is null or source in ('experience_prompt','manual','cancellation','board'));
alter table public.feedback_items add column if not exists is_anonymous boolean not null default false;
alter table public.feedback_items add column if not exists app_version text check (char_length(app_version) <= 24);
alter table public.feedback_items add column if not exists build text check (char_length(build) <= 16);
alter table public.feedback_items add column if not exists os_version text check (char_length(os_version) <= 16);
alter table public.feedback_items add column if not exists device_class text check (char_length(device_class) <= 16);

alter table public.feedback_items drop constraint if exists feedback_items_category_check;
alter table public.feedback_items add constraint feedback_items_category_check check (
  category is null or category in (
    'bug','feature','general','content','learning','performance',
    'cancel_price','cancel_time','cancel_content','cancel_hard','cancel_curious','cancel_other'
  )
);
create index if not exists feedback_items_created_idx on public.feedback_items (created_at desc);

-- ── Public board ─────────────────────────────────────────────────────────────

alter table public.feedback_posts drop constraint if exists feedback_posts_status_check;
alter table public.feedback_posts add constraint feedback_posts_status_check
  check (status in ('open','under_review','planned','in_progress','done','declined','hidden'));
alter table public.feedback_posts add column if not exists report_count int not null default 0 check (report_count >= 0);
alter table public.feedback_posts add column if not exists held boolean not null default false;
alter table public.feedback_posts add column if not exists moderated_at timestamptz;
alter table public.feedback_posts add column if not exists updated_at timestamptz not null default now();
create index if not exists feedback_posts_created_idx on public.feedback_posts (created_at desc);
create index if not exists feedback_votes_recent_idx on public.feedback_votes (post_id, created_at);

create table if not exists public.feedback_reports (
  post_id bigint not null references public.feedback_posts (id) on delete cascade,
  reporter text not null,
  reason text not null default 'other' check (reason in ('spam','offensive','personal_info','other')),
  created_at timestamptz not null default now(),
  primary key (post_id, reporter)
);
alter table public.feedback_reports enable row level security;
revoke all on table public.feedback_reports from anon, authenticated;
grant all on table public.feedback_reports to service_role;

/** One page of the public board. Never returns author identifiers. */
create or replace function public.feedback_board_page(
  p_viewer text,
  p_sort text,
  p_search text,
  p_limit int,
  p_offset int
) returns table (
  id bigint, category text, title text, body text, status text,
  vote_count int, comment_count int, created_at timestamptz, voted boolean, recent_votes int
)
language sql
stable
security definer
set search_path = ''
as $$
  with visible as (
    select p.*
    from public.feedback_posts p
    where p.status <> 'hidden' and not p.held
      and (
        coalesce(p_search, '') = ''
        or p.title ilike '%' || replace(replace(replace(p_search, '\', '\\'), '%', '\%'), '_', '\_') || '%'
        or p.body ilike '%' || replace(replace(replace(p_search, '\', '\\'), '%', '\%'), '_', '\_') || '%'
      )
  ),
  scored as (
    select v.*,
      (select count(*)::int from public.feedback_votes fv
        where fv.post_id = v.id and fv.created_at > now() - interval '7 days') as recent,
      exists (select 1 from public.feedback_votes fv
        where fv.post_id = v.id and fv.app_user_id = p_viewer) as mine
    from visible v
  )
  select s.id, s.category, s.title, s.body, s.status, s.vote_count, s.comment_count, s.created_at,
         s.mine, s.recent
  from scored s
  order by
    case when p_sort = 'newest' then extract(epoch from s.created_at) end desc nulls last,
    case when p_sort = 'trending' then
      (s.recent * 3 + s.vote_count)::float
        / power(extract(epoch from (now() - s.created_at)) / 3600.0 + 2, 0.6)
    end desc nulls last,
    s.vote_count desc,
    s.created_at desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50)
  offset greatest(coalesce(p_offset, 0), 0);
$$;
revoke all on function public.feedback_board_page(text, text, text, int, int) from public, anon, authenticated;
grant execute on function public.feedback_board_page(text, text, text, int, int) to service_role;

/** Atomic one-vote-per-identity toggle. The counter is recomputed, never trusted from the client. */
create or replace function public.feedback_toggle_vote(p_post bigint, p_voter text)
returns table (vote_count int, voted boolean)
language plpgsql
security definer
set search_path = ''
as $$
declare
  removed int;
  total int;
begin
  perform 1 from public.feedback_posts p
    where p.id = p_post and p.status <> 'hidden' and not p.held
    for update;
  if not found then
    raise exception 'post not found' using errcode = 'P0002';
  end if;
  delete from public.feedback_votes v where v.post_id = p_post and v.app_user_id = p_voter;
  get diagnostics removed = row_count;
  if removed = 0 then
    insert into public.feedback_votes (post_id, app_user_id) values (p_post, p_voter)
    on conflict do nothing;
  end if;
  select count(*)::int into total from public.feedback_votes v where v.post_id = p_post;
  update public.feedback_posts p set vote_count = total, updated_at = now() where p.id = p_post;
  return query select total, removed = 0;
end;
$$;
revoke all on function public.feedback_toggle_vote(bigint, text) from public, anon, authenticated;
grant execute on function public.feedback_toggle_vote(bigint, text) to service_role;

/** One report per identity. Three reports hold a post for review unless a moderator already cleared it. */
create or replace function public.feedback_report_post(p_post bigint, p_reporter text, p_reason text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  added int;
begin
  insert into public.feedback_reports (post_id, reporter, reason)
  values (p_post, p_reporter, coalesce(p_reason, 'other'))
  on conflict do nothing;
  get diagnostics added = row_count;
  if added > 0 then
    update public.feedback_posts p
      set report_count = p.report_count + 1,
          held = case when p.moderated_at is null and p.report_count + 1 >= 3 then true else p.held end,
          updated_at = now()
      where p.id = p_post;
  end if;
  return added > 0;
end;
$$;
revoke all on function public.feedback_report_post(bigint, text, text) from public, anon, authenticated;
grant execute on function public.feedback_report_post(bigint, text, text) to service_role;

-- ── Developer dashboard aggregates ───────────────────────────────────────────

create or replace function public.admin_dashboard_metrics(p_days int default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  since timestamptz := now() - make_interval(days => least(greatest(p_days, 1), 365));
  result jsonb;
begin
  with
  sess as (select * from public.analytics_sessions where started_at >= since),
  ev as (select * from public.analytics_events where occurred_at >= since),
  first_seen as (
    select install_id, min(started_at) as first_at
    from public.analytics_sessions group by install_id
  ),
  daily as (
    select date_trunc('day', started_at)::date as day, count(distinct install_id) as users
    from sess group by 1
  ),
  cohorts as (
    select date_trunc('week', f.first_at)::date as cohort,
      count(*) as size,
      count(*) filter (where exists (select 1 from public.analytics_sessions s
        where s.install_id = f.install_id and s.started_at >= f.first_at + interval '1 day'
          and s.started_at < f.first_at + interval '2 days')) as d1,
      count(*) filter (where exists (select 1 from public.analytics_sessions s
        where s.install_id = f.install_id and s.started_at >= f.first_at + interval '7 days'
          and s.started_at < f.first_at + interval '14 days')) as w2,
      count(*) filter (where exists (select 1 from public.analytics_sessions s
        where s.install_id = f.install_id and s.started_at >= f.first_at + interval '30 days')) as d30
    from first_seen f
    where f.first_at >= now() - interval '10 weeks'
    group by 1
  ),
  onboarding as (
    select (props->>'step')::int as step, name, count(distinct install_id) as users
    from ev
    where name like 'onboarding\_%\_view' and (props->>'step') ~ '^[0-9]+$'
    group by 1, 2
  ),
  core as (
    select n.name, n.ord, (select count(distinct install_id) from ev where ev.name = n.name) as users
    from (values ('session_start',1),('clip_view',2),('word_tapped',3),('vocab_saved',4),
                 ('review_started',5),('review_completed',6)) as n(name, ord)
  ),
  guide as (
    select coalesce(props->>'step', name) as step, name, count(distinct install_id) as users
    from ev where name in ('guide_step_viewed','guide_completed','guide_skipped')
    group by 1, 2
  ),
  errors as (
    select name, coalesce(props->>'code', props->>'reason', '') as code, count(*) as n,
           max(occurred_at) as last_at
    from ev where name = 'app_error' or name like '%\_failed'
    group by 1, 2 order by n desc limit 25
  ),
  versions as (
    select coalesce(app_version, '?') as v, count(distinct install_id) as users
    from sess group by 1 order by users desc limit 12
  ),
  oses as (
    select coalesce(split_part(os_version, '.', 1) || '.' || nullif(split_part(os_version, '.', 2), ''), os_version, '?') as v,
           count(distinct install_id) as users
    from sess group by 1 order by users desc limit 12
  ),
  fb as (select * from public.feedback_items where created_at >= since)
  select jsonb_build_object(
    'window_days', least(greatest(p_days, 1), 365),
    'generated_at', now(),
    'dau', (select count(distinct install_id) from public.analytics_sessions where started_at >= now() - interval '1 day'),
    'wau', (select count(distinct install_id) from public.analytics_sessions where started_at >= now() - interval '7 days'),
    'mau', (select count(distinct install_id) from public.analytics_sessions where started_at >= now() - interval '30 days'),
    'new_installs', (select count(*) from first_seen where first_at >= since),
    'dau_series', coalesce((select jsonb_agg(jsonb_build_object('day', day, 'users', users) order by day) from daily), '[]'::jsonb),
    'sessions', jsonb_build_object(
      'count', (select count(*) from sess),
      'avg_active_seconds', (select coalesce(round(avg(active_seconds)), 0) from sess where active_seconds > 0),
      'median_active_seconds', (select coalesce(percentile_cont(0.5) within group (order by active_seconds), 0) from sess where active_seconds > 0),
      'per_user', (select case when count(distinct install_id) = 0 then 0 else round(count(*)::numeric / count(distinct install_id), 2) end from sess)
    ),
    'retention', coalesce((select jsonb_agg(jsonb_build_object('cohort', cohort, 'size', size, 'd1', d1, 'w2', w2, 'd30', d30) order by cohort desc) from cohorts), '[]'::jsonb),
    'onboarding_funnel', coalesce((select jsonb_agg(jsonb_build_object('step', step, 'name', name, 'users', users) order by step) from onboarding), '[]'::jsonb),
    'onboarding_completed', (select count(distinct install_id) from ev where name = 'onboarding_completed'),
    'core_funnel', coalesce((select jsonb_agg(jsonb_build_object('name', name, 'users', users) order by ord) from core), '[]'::jsonb),
    'guide_funnel', coalesce((select jsonb_agg(jsonb_build_object('step', step, 'name', name, 'users', users)) from guide), '[]'::jsonb),
    'feedback', jsonb_build_object(
      'total', (select count(*) from fb),
      'positive', (select count(*) from fb where enjoyed is true),
      'negative', (select count(*) from fb where enjoyed is false),
      'by_category', coalesce((select jsonb_object_agg(c, n) from (select coalesce(category, 'none') c, count(*) n from fb group by 1) x), '{}'::jsonb),
      'prompt_shown', (select count(distinct install_id) from ev where name = 'feedback_prompt_shown'),
      'prompt_positive', (select count(distinct install_id) from ev where name = 'feedback_prompt_positive'),
      'prompt_negative', (select count(distinct install_id) from ev where name = 'feedback_prompt_negative'),
      'review_requested', (select count(distinct install_id) from ev where name = 'review_request_tapped')
    ),
    'top_requests', coalesce((select jsonb_agg(row_to_json(t)) from (
      select id, title, category, status, vote_count, comment_count, report_count, held, created_at
      from public.feedback_posts where status <> 'hidden' order by vote_count desc, created_at desc limit 15) t), '[]'::jsonb),
    'errors', coalesce((select jsonb_agg(row_to_json(e)) from errors e), '[]'::jsonb),
    'versions', coalesce((select jsonb_agg(jsonb_build_object('v', v, 'users', users)) from versions), '[]'::jsonb),
    'os', coalesce((select jsonb_agg(jsonb_build_object('v', v, 'users', users)) from oses), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;
revoke all on function public.admin_dashboard_metrics(int) from public, anon, authenticated;
grant execute on function public.admin_dashboard_metrics(int) to service_role;

-- ── Retention: analytics older than 13 months is deleted nightly ─────────────

do $$
begin
  if exists (select 1 from cron.job where jobname = 'analytics-retention') then
    perform cron.unschedule('analytics-retention');
  end if;
  perform cron.schedule(
    'analytics-retention',
    '17 3 * * *',
    $job$
      delete from public.analytics_events where occurred_at < now() - interval '395 days';
      delete from public.analytics_sessions where started_at < now() - interval '395 days';
    $job$
  );
end;
$$;
