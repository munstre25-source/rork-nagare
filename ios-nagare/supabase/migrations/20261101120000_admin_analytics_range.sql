-- Private, range-filtered product metrics for the Vercel command centre.
-- Exclusive upper bound keeps adjacent daily or weekly reports from double counting.
create index if not exists clip_playback_failures_reported_idx
  on public.clip_playback_failures (reported_at desc);

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
    where started_at >= p_start and started_at < p_end
  ),
  ev as (
    select install_id, name, props
    from public.analytics_events
    where occurred_at >= p_start and occurred_at < p_end
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
      where older.install_id = c.install_id and older.started_at < c.first_at)
  ),
  retention as (
    select
      count(*) filter (where first_day + 2 <= (least(p_end, now()) at time zone 'UTC')::date) as d1_eligible,
      count(*) filter (where first_day + 2 <= (least(p_end, now()) at time zone 'UTC')::date
        and exists (select 1 from public.analytics_sessions later
          where later.install_id = c.install_id
            and (later.started_at at time zone 'UTC')::date = first_day + 1)) as d1_returned,
      count(*) filter (where first_day + 8 <= (least(p_end, now()) at time zone 'UTC')::date) as d7_eligible,
      count(*) filter (where first_day + 8 <= (least(p_end, now()) at time zone 'UTC')::date
        and exists (select 1 from public.analytics_sessions later
          where later.install_id = c.install_id
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
    where reported_at >= p_start and reported_at < p_end
    group by video_id order by reports desc limit 5
  ),
  fb as (
    select enjoyed from public.feedback_items
    where created_at >= p_start and created_at < p_end
  ),
  acq_counts as (
    select source, count(*) as n from public.acquisition_events
    where created_at >= p_start and created_at < p_end
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
        where reported_at >= p_start and reported_at < p_end),
      'affected_videos', (select count(distinct video_id) from public.clip_playback_failures
        where reported_at >= p_start and reported_at < p_end),
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
