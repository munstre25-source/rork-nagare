-- Keep transient failures visible in the queue without starving new candidates.
alter table public.catalog_candidate_queue
 add column next_attempt_at timestamptz not null default now();
create index catalog_candidate_queue_ready_idx
 on public.catalog_candidate_queue(next_attempt_at,added_at);
CREATE OR REPLACE FUNCTION public.catalog_current_pipeline()
 RETURNS TABLE(id text, video_id text, title text, channel_name text, status text, stage text, reason text, detail text, at timestamp with time zone, source text)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 with latest as (
  select distinct on (a.video_id,a.window_start_sec) a.*
  from public.catalog_pipeline_attempts a where a.source in ('automatic','manual')
  order by a.video_id,a.window_start_sec,a.started_at desc,a.id desc
 )
 select coalesce(a.id::text,q.video_id||':'||q.window_start_sec),coalesce(a.video_id,q.video_id),
 coalesce(nullif(a.title,''),q.title,''),coalesce(nullif(a.channel_name,''),q.channel_title,''),
 case when a.status='processing' then
   case when a.updated_at<=now()-interval '10 minutes' then 'stalled' else 'processing' end
  when q.video_id is not null then 'queued'
  when a.status='rejected' then 'excluded'
  else a.status end,
 case when q.video_id is not null and a.status is distinct from 'processing' then 'awaiting_retry' else coalesce(a.stage,'discovery') end,
 a.reason,case when q.next_attempt_at>now() then concat_ws(' ',a.detail,'Retry after '||q.next_attempt_at::text) else a.detail end,coalesce(a.updated_at,q.added_at),coalesce(a.source,'automatic')
 from latest a full join public.catalog_candidate_queue q
 on q.video_id=a.video_id and q.window_start_sec=a.window_start_sec;
$function$
