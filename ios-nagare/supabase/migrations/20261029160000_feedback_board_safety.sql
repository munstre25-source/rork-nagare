-- Feedback board safety (App Review 1.2): per-viewer author blocking, comment reports
-- with automatic hiding, all reachable only through the service role (edge function).
-- Reversible:
--   drop function if exists public.feedback_report_comment(bigint, text, text);
--   drop table if exists public.feedback_comment_reports;
--   drop table if exists public.feedback_blocks;
--   alter table public.feedback_comments drop column if exists hidden, drop column if exists report_count;

create table if not exists public.feedback_blocks (
  blocker text not null,
  blocked_author text not null,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked_author)
);
alter table public.feedback_blocks enable row level security;
revoke all on table public.feedback_blocks from anon, authenticated;
grant all on table public.feedback_blocks to service_role;

alter table public.feedback_comments add column if not exists hidden boolean not null default false;
alter table public.feedback_comments add column if not exists report_count integer not null default 0;

create table if not exists public.feedback_comment_reports (
  comment_id bigint not null references public.feedback_comments (id) on delete cascade,
  reporter text not null,
  reason text not null default 'other',
  created_at timestamptz not null default now(),
  primary key (comment_id, reporter)
);
alter table public.feedback_comment_reports enable row level security;
revoke all on table public.feedback_comment_reports from anon, authenticated;
grant all on table public.feedback_comment_reports to service_role;

-- One report per reporter; a comment hides itself after 2 distinct reports.
create or replace function public.feedback_report_comment(p_comment bigint, p_reporter text, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  inserted integer;
begin
  insert into public.feedback_comment_reports (comment_id, reporter, reason)
  values (p_comment, p_reporter, coalesce(p_reason, 'other'))
  on conflict do nothing;
  get diagnostics inserted = row_count;
  if inserted > 0 then
    update public.feedback_comments c
       set report_count = c.report_count + 1,
           hidden = case when c.report_count + 1 >= 2 then true else c.hidden end
     where c.id = p_comment;
  end if;
end;
$$;
revoke all on function public.feedback_report_comment(bigint, text, text) from public, anon, authenticated;
grant execute on function public.feedback_report_comment(bigint, text, text) to service_role;
