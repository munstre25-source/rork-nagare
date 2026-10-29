-- Real-device playback verification.
-- YouTube's Data API reports `embeddable=true` for videos that rights holders still block
-- in app players (Content ID policies → IFrame error 150/101) or that never become ready.
-- Only a learner's phone can see that, so the app reports failures here and the catalog
-- unpublishes the video for everyone. Rows are kept for audit; reachable only via service role.
-- Reversible: see supabase/rollbacks/20261029190000_clip_playback_failures.down.sql

create table if not exists public.clip_playback_failures (
  video_id text not null,
  reporter text not null,
  clip_id text,
  error_code integer not null,
  reported_at timestamptz not null default now(),
  primary key (video_id, reporter)
);
create index if not exists clip_playback_failures_video_idx on public.clip_playback_failures (video_id);
alter table public.clip_playback_failures enable row level security;
revoke all on table public.clip_playback_failures from anon, authenticated;
grant all on table public.clip_playback_failures to service_role;

-- Records one report per reporter and video, then unpublishes the video when the evidence is
-- strong enough. Definitive IFrame codes (100 removed, 101/150 embed blocked) unpublish on the
-- first report; softer signals (timeouts/stalls, negative codes) need 2 distinct reporters.
-- Returns true when the video is now unpublished.
create or replace function public.report_clip_playback_failure(
  p_video_id text,
  p_reporter text,
  p_clip_id text,
  p_error_code integer
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  definitive_reports int;
  any_reports int;
  reporter_recent int;
  should_hide boolean;
begin
  if p_video_id !~ '^[A-Za-z0-9_-]{11}$' then
    return false;
  end if;

  -- Circuit breaker: a reporter who sees many different videos fail in a day is more likely
  -- broken (blocked network, app bug) or abusive than right. Record, but don't unpublish.
  select count(distinct video_id) into reporter_recent
    from public.clip_playback_failures
   where reporter = left(p_reporter, 128)
     and reported_at > now() - interval '1 day'
     and video_id <> p_video_id;

  insert into public.clip_playback_failures (video_id, reporter, clip_id, error_code)
  values (p_video_id, left(p_reporter, 128), left(p_clip_id, 128), p_error_code)
  on conflict (video_id, reporter) do update
    set error_code = excluded.error_code, clip_id = excluded.clip_id, reported_at = now();

  select count(*) filter (where error_code in (100, 101, 150)), count(*)
    into definitive_reports, any_reports
    from public.clip_playback_failures
   where video_id = p_video_id;

  should_hide := reporter_recent < 5 and (definitive_reports >= 1 or any_reports >= 2);
  if should_hide then
    update public.clips set published = false where video_id = p_video_id and published;
    update public.sori_clips set published = false where video_id = p_video_id and published;
  end if;
  return should_hide;
end;
$$;

revoke all on function public.report_clip_playback_failure(text, text, text, integer) from public, anon, authenticated;
grant execute on function public.report_clip_playback_failure(text, text, text, integer) to service_role;

-- Allow a per-reporter daily rate bucket for playback reports.
do $$
declare
  c text;
begin
  select conname into c from pg_constraint
   where conrelid = 'public.insight_rate_buckets'::regclass and contype = 'c'
   limit 1;
  if c is not null then
    execute format('alter table public.insight_rate_buckets drop constraint %I', c);
  end if;
end $$;
alter table public.insight_rate_buckets add constraint insight_rate_buckets_kind_check check (kind in (
  'acquisition', 'feedback', 'board', 'inbox', 'analytics', 'analytics_ip', 'board_ip', 'report', 'playback_report'
));

-- Known failures observed on a real iPhone (2026-10-29): error 150 and a player that never loaded.
insert into public.clip_playback_failures (video_id, reporter, clip_id, error_code) values
  ('kE23CnwTzKI', 'seed:device-test-2026-10-29', 'immersion-kE23CnwTzKI-0-35', 150),
  ('ca0H6E2Ritw', 'seed:device-test-2026-10-29', 'immersion-ca0H6E2Ritw-0-30', -1)
on conflict do nothing;
update public.clips set published = false where video_id in ('kE23CnwTzKI', 'ca0H6E2Ritw');
