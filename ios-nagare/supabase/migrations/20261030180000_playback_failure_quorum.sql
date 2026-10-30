-- Harden playback-failure retirement against environmental storms.
--
-- Incident (2026-10-30): an iOS 26.4 WebKit/simulator session flakily failed every embed
-- (IFrame 150 → direct-embed never ready → code -1). Each preview session presented a fresh
-- reporter identity, so the old "2 distinct reporters" quorum for soft codes was met by one
-- person's consecutive sessions, and 39 of 41 clips were unpublished within minutes. The feed
-- was left with nothing to play.
--
-- Rules after this migration:
--   * Evidence counts only reports from the last 7 days (a video can recover after an
--     incident without old rows re-retiring it).
--   * Code 100 (video removed/private) still retires on 1 reporter.
--   * Codes 101/150 (embed blocked) need 2 distinct reporters — one device's WebKit quirk
--     is not proof about a video.
--   * Soft signals (-1 never ready, -2 stalled, other) need 3 distinct reporters.
--   * Circuit breaker tightens: a reporter who saw 2+ other videos fail in a day is in a
--     broken environment and contributes evidence, never a verdict.
--
-- Reversible: see supabase/rollbacks/20261030180000_playback_failure_quorum.down.sql

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
     and reported_at > now() - interval '1 day'
     and video_id <> p_video_id;

  insert into public.clip_playback_failures (video_id, reporter, clip_id, error_code)
  values (p_video_id, left(p_reporter, 128), left(p_clip_id, 128), p_error_code)
  on conflict (video_id, reporter) do update
    set error_code = excluded.error_code, clip_id = excluded.clip_id, reported_at = now();

  -- Only recent evidence counts; a video that played fine for months should not be
  -- retired because of a stale storm row.
  select
    count(*) filter (where error_code = 100),
    count(*) filter (where error_code in (101, 150)),
    count(*)
  into removed_reports, embed_reports, total_reports
  from public.clip_playback_failures
  where video_id = p_video_id
    and reported_at > now() - interval '7 days';

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
