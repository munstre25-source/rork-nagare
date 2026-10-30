-- Rollback of 20261030180000_playback_failure_quorum.sql: restore the original quorum.
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
