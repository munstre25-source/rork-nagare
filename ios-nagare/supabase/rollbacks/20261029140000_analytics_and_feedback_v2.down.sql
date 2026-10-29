-- Manual rollback for 20261029140000_analytics_and_feedback_v2.sql.
-- DESTRUCTIVE: drops analytics data and board reports. Run only with explicit sign-off.

select cron.unschedule('analytics-retention') where exists (select 1 from cron.job where jobname = 'analytics-retention');

drop function if exists public.admin_dashboard_metrics(int);
drop function if exists public.feedback_report_post(bigint, text, text);
drop function if exists public.feedback_toggle_vote(bigint, text);
drop function if exists public.feedback_board_page(text, text, text, int, int);
drop function if exists public.analytics_ingest(uuid, uuid, jsonb, jsonb);

drop table if exists public.feedback_reports;
drop table if exists public.analytics_events;
drop table if exists public.analytics_sessions;

alter table public.feedback_posts drop column if exists report_count;
alter table public.feedback_posts drop column if exists held;
alter table public.feedback_posts drop column if exists moderated_at;
alter table public.feedback_posts drop column if exists updated_at;
update public.feedback_posts set status = 'open' where status in ('under_review','in_progress','declined');
alter table public.feedback_posts drop constraint if exists feedback_posts_status_check;
alter table public.feedback_posts add constraint feedback_posts_status_check
  check (status in ('open','planned','done','hidden'));

alter table public.feedback_items drop column if exists user_id;
alter table public.feedback_items drop column if exists source;
alter table public.feedback_items drop column if exists is_anonymous;
alter table public.feedback_items drop column if exists app_version;
alter table public.feedback_items drop column if exists build;
alter table public.feedback_items drop column if exists os_version;
alter table public.feedback_items drop column if exists device_class;
update public.feedback_items set category = 'general' where category in ('content','learning','performance');
alter table public.feedback_items drop constraint if exists feedback_items_category_check;
alter table public.feedback_items add constraint feedback_items_category_check check (
  category is null or category in ('bug','feature','general','cancel_price','cancel_time','cancel_content','cancel_hard','cancel_curious','cancel_other')
);

delete from public.insight_rate_buckets where kind in ('analytics','analytics_ip','board_ip','report');
alter table public.insight_rate_buckets drop constraint if exists insight_rate_buckets_kind_check;
alter table public.insight_rate_buckets
  add constraint insight_rate_buckets_kind_check
  check (kind in ('acquisition','feedback','board','inbox'));
