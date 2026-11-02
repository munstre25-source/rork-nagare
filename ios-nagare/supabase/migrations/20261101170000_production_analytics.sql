-- Keep production analytics separate from simulator, debug and TestFlight activity.
-- Legacy rows remain available for audit but are unclassified and excluded from product KPIs.
alter table public.analytics_events add column if not exists environment text not null default 'legacy'
  check (environment in ('legacy', 'test', 'production'));
alter table public.analytics_sessions add column if not exists environment text not null default 'legacy'
  check (environment in ('legacy', 'test', 'production'));
alter table public.acquisition_events add column if not exists environment text not null default 'legacy'
  check (environment in ('legacy', 'test', 'production'));
alter table public.feedback_items add column if not exists environment text not null default 'legacy'
  check (environment in ('legacy', 'test', 'production'));
alter table public.direct_messages add column if not exists environment text not null default 'legacy'
  check (environment in ('legacy', 'test', 'production'));
alter table public.clip_playback_failures add column if not exists environment text not null default 'legacy'
  check (environment in ('legacy', 'test', 'production'));

create or replace function public.analytics_ingest_classified(
  p_install uuid, p_user uuid, p_events jsonb, p_sessions jsonb, p_environment text
) returns int
language plpgsql security invoker set search_path = '' as $$
declare inserted int;
begin
  if p_environment not in ('production', 'test') then
    raise exception 'Invalid analytics environment';
  end if;
  inserted := public.analytics_ingest(p_install, p_user, p_events, p_sessions);
  update public.analytics_events e set environment = p_environment
    where e.install_id = p_install and e.environment = 'legacy'
      and e.id in (select (x->>'id')::uuid from jsonb_array_elements(p_events) x);
  update public.analytics_sessions s set environment = p_environment
    where s.install_id = p_install and s.environment = 'legacy'
      and s.id in (select (x->>'id')::uuid from jsonb_array_elements(p_sessions) x);
  return inserted;
end;
$$;
revoke all on function public.analytics_ingest_classified(uuid, uuid, jsonb, jsonb, text)
  from public, anon, authenticated;
grant execute on function public.analytics_ingest_classified(uuid, uuid, jsonb, jsonb, text)
  to service_role;

create or replace function public.report_clip_playback_failure(
  p_video_id text,
  p_reporter text,
  p_clip_id text,
  p_error_code integer
) returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  removed_reports int;
  embed_reports int;
  total_reports int;
  reporter_recent int;
  should_hide boolean;
begin
  if p_video_id !~ '^[A-Za-z0-9_-]{11}$' then
    return false;
  end if;

  -- Circuit breaker: a reporter who sees several different videos fail in a day is more
  -- likely broken (blocked network, WebKit bug, simulator) or abusive than right.
  -- Record, but don't unpublish.
  select count(distinct video_id) into reporter_recent
    from public.clip_playback_failures
   where reporter = left(p_reporter, 128)
     and environment = 'production' and reported_at > now() - interval '1 day'
     and video_id <> p_video_id;

  insert into public.clip_playback_failures (video_id, reporter, clip_id, error_code, environment)
  values (p_video_id, left(p_reporter, 128), left(p_clip_id, 128), p_error_code, 'production')
  on conflict (video_id, reporter) do update
    set error_code = excluded.error_code, clip_id = excluded.clip_id, environment = 'production', reported_at = now();

  -- Only recent evidence counts; a video that played fine for months should not be
  -- retired because of a stale storm row.
  select
    count(*) filter (where error_code = 100),
    count(*) filter (where error_code in (101, 150)),
    count(*)
  into removed_reports, embed_reports, total_reports
  from public.clip_playback_failures
  where video_id = p_video_id
    and environment = 'production' and reported_at > now() - interval '7 days';

  should_hide := reporter_recent < 3
    and (
      removed_reports >= 1        -- 100: removed/private, one witness is enough
      or embed_reports >= 2       -- 101/150: two devices must agree
      or total_reports >= 3       -- soft codes: three devices must agree
    );
  if should_hide then
    update public.clips set published = false where video_id = p_video_id and published;
    update public.sori_clips set published = false where video_id = p_video_id and published;
  end if;
  return should_hide;
end;
$$;

revoke all on function public.report_clip_playback_failure(text,text,text,integer) from public,anon,authenticated;
grant execute on function public.report_clip_playback_failure(text,text,text,integer) to service_role;

create or replace function public.admin_dashboard_metrics_range(
  p_start timestamptz,
  p_end timestamptz
) returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  result jsonb;
begin
  if p_start is null or p_end is null or p_start >= p_end
     or p_end - p_start > interval '366 days' then
    raise exception 'Invalid analytics range';
  end if;

  with
  sess as (
    select install_id, started_at, active_seconds
    from public.analytics_sessions
    where started_at >= p_start and started_at < p_end and environment = 'production'
  ),
  ev as (
    select install_id, name, props
    from public.analytics_events
    where occurred_at >= p_start and occurred_at < p_end and environment = 'production'
  ),
  daily as (
    select (started_at at time zone 'UTC')::date as day,
           count(distinct install_id) as users
    from sess group by 1
  ),
  viewed_pairs as (
    select distinct install_id, props->>'clip' as clip
    from ev where name = 'clip_view' and props ? 'clip'
  ),
  completed_pairs as (
    select distinct install_id, props->>'clip' as clip
    from ev where name = 'clip_completed' and props ? 'clip'
  ),
  candidate_first as (
    select install_id, min(started_at) as first_at
    from sess group by install_id
  ),
  cohorts as (
    select c.install_id, (c.first_at at time zone 'UTC')::date as first_day
    from candidate_first c
    where not exists (select 1 from public.analytics_sessions older
      where older.install_id = c.install_id and older.environment = 'production' and older.started_at < c.first_at)
  ),
  retention as (
    select
      count(*) filter (where first_day + 2 <= (least(p_end, now()) at time zone 'UTC')::date) as d1_eligible,
      count(*) filter (where first_day + 2 <= (least(p_end, now()) at time zone 'UTC')::date
        and exists (select 1 from public.analytics_sessions later
          where later.install_id = c.install_id and later.environment = 'production'
            and (later.started_at at time zone 'UTC')::date = first_day + 1)) as d1_returned,
      count(*) filter (where first_day + 8 <= (least(p_end, now()) at time zone 'UTC')::date) as d7_eligible,
      count(*) filter (where first_day + 8 <= (least(p_end, now()) at time zone 'UTC')::date
        and exists (select 1 from public.analytics_sessions later
          where later.install_id = c.install_id and later.environment = 'production'
            and (later.started_at at time zone 'UTC')::date = first_day + 7)) as d7_returned
    from cohorts c
  ),
  paywall_viewers as (
    select distinct install_id from ev where name = 'onboarding_paywall_view'
  ),
  purchasers as (
    select distinct install_id from ev
    where name = 'onboarding_payment_success'
       or (name = 'remote_paywall_purchase' and props->>'active' = '1')
  ),
  activity as (
    select
      (select count(*) from viewed_pairs) as clip_views,
      (select count(*) from completed_pairs) as clip_completions,
      (select count(*) from viewed_pairs v join completed_pairs c
        using (install_id, clip)) as matched_completions,
      count(*) filter (where name = 'clip_liked') as likes,
      count(*) filter (where name = 'vocab_saved') as vocab_saves,
      count(*) filter (where name = 'review_completed') as reviews_completed,
      count(*) filter (where name = 'clip_quiz_shown') as quizzes_shown,
      count(*) filter (where name = 'clip_quiz_done') as quizzes_completed
    from ev
  ),
  funnel as (
    select names.name, names.ord,
           (select count(distinct install_id) from ev where ev.name = names.name) as users
    from (values ('session_start', 1), ('clip_view', 2),
                 ('clip_completed', 3), ('word_tapped', 4),
                 ('vocab_saved', 5), ('review_started', 6),
                 ('review_completed', 7), ('clip_liked', 8)) as names(name, ord)
  ),
  errors as (
    select name, coalesce(props->>'code', props->>'reason', '') as code,
           count(*) as n
    from ev
    where name = 'app_error' or name like '%\_failed'
    group by 1, 2 order by n desc limit 12
  ),
  failed_videos as (
    select video_id, count(*) as reports
    from public.clip_playback_failures
    where reported_at >= p_start and reported_at < p_end and environment = 'production'
    group by video_id order by reports desc limit 5
  ),
  fb as (
    select enjoyed from public.feedback_items
    where environment = 'production' and created_at >= p_start and created_at < p_end
  ),
  acq_counts as (
    select source, count(*) as n from public.acquisition_events
    where environment = 'production' and created_at >= p_start and created_at < p_end
    group by source
  )
  select jsonb_build_object(
    'from', p_start, 'to', p_end,
    'active_users', (select count(distinct install_id) from sess),
    'new_installs', (select count(*) from cohorts),
    'retention', (select jsonb_build_object(
      'd1_eligible', d1_eligible, 'd1_returned', d1_returned,
      'd7_eligible', d7_eligible, 'd7_returned', d7_returned,
      'd1_percent', case when d1_eligible = 0 then null else round(d1_returned * 100.0 / d1_eligible, 1) end,
      'd7_percent', case when d7_eligible = 0 then null else round(d7_returned * 100.0 / d7_eligible, 1) end
    ) from retention),
    'conversion', jsonb_build_object(
      'paywall_viewers', (select count(*) from paywall_viewers),
      'purchasers', (select count(*) from purchasers),
      'view_to_purchase_percent', (select case when count(*) = 0 then null
        else round((select count(*) from paywall_viewers v join purchasers p using (install_id))
          * 100.0 / count(*), 1) end from paywall_viewers)
    ),
    'acquisition', jsonb_build_object(
      'total', (select coalesce(sum(n), 0) from acq_counts),
      'by_source', coalesce((select jsonb_object_agg(source, n) from acq_counts), '{}'::jsonb)
    ),
    'dau_series', coalesce((select jsonb_agg(jsonb_build_object('day', day, 'users', users)
      order by day) from daily), '[]'::jsonb),
    'sessions', jsonb_build_object(
      'count', (select count(*) from sess),
      'avg_active_seconds', (select coalesce(round(avg(active_seconds)), 0)
        from sess where active_seconds > 0)
    ),
    'core_funnel', coalesce((select jsonb_agg(jsonb_build_object('name', name, 'users', users)
      order by ord) from funnel), '[]'::jsonb),
    'learning', (select jsonb_build_object(
      'clip_views', clip_views,
      'clip_completions', clip_completions,
      'completion_percent', case when clip_views = 0 then 0
        else round(matched_completions * 100.0 / clip_views, 1) end,
      'likes', likes,
      'vocab_saves', vocab_saves,
      'reviews_completed', reviews_completed,
      'quiz_completion_percent', case when quizzes_shown = 0 then 0
        else round(least(100, quizzes_completed * 100.0 / quizzes_shown), 1) end
    ) from activity),
    'playback', jsonb_build_object(
      'failure_reports', (select count(*) from public.clip_playback_failures
        where reported_at >= p_start and reported_at < p_end and environment = 'production'),
      'affected_videos', (select count(distinct video_id) from public.clip_playback_failures
        where reported_at >= p_start and reported_at < p_end and environment = 'production'),
      'top_videos', coalesce((select jsonb_agg(jsonb_build_object(
        'video_id', video_id, 'reports', reports) order by reports desc)
        from failed_videos), '[]'::jsonb)
    ),
    'feedback', jsonb_build_object(
      'total', (select count(*) from fb),
      'positive', (select count(*) from fb where enjoyed is true),
      'negative', (select count(*) from fb where enjoyed is false)
    ),
    'errors', coalesce((select jsonb_agg(row_to_json(e)) from errors e), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;

revoke all on function public.admin_dashboard_metrics_range(timestamptz, timestamptz)
  from public, anon, authenticated;
grant execute on function public.admin_dashboard_metrics_range(timestamptz, timestamptz)
  to service_role;
