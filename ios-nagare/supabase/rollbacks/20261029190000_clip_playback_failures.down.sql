-- Rollback for 20261029190000_clip_playback_failures.sql
-- Clips unpublished by reports stay unpublished; republish them with publish-clip if needed.
drop function if exists public.report_clip_playback_failure(text, text, text, integer);
drop table if exists public.clip_playback_failures;

delete from public.insight_rate_buckets where kind = 'playback_report';
alter table public.insight_rate_buckets drop constraint if exists insight_rate_buckets_kind_check;
alter table public.insight_rate_buckets add constraint insight_rate_buckets_kind_check check (kind in (
  'acquisition', 'feedback', 'board', 'inbox', 'analytics', 'analytics_ip', 'board_ip', 'report'
));
