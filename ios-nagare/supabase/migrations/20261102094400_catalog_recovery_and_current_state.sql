
-- Apply approved review JSON in the request body, avoiding oversized REST URL filters.
-- Preserve publication state, source bounds, line order, Japanese and every token time.
create function public.apply_catalog_review(
 p_id text,p_expected_lines jsonb,p_expected_category text,p_lines jsonb,p_category text
) returns boolean language plpgsql security invoker set search_path='' as $body$
declare changed integer;
begin
 if jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines)=0
 or jsonb_array_length(p_lines)<>jsonb_array_length(p_expected_lines) then
  raise exception 'Review must preserve original line slots';
 end if;
 if exists (
  select 1 from jsonb_array_elements(p_lines) with ordinality n(line,i)
  join jsonb_array_elements(p_expected_lines) with ordinality o(line,i) using(i)
  where n.line->'start' is distinct from o.line->'start'
     or n.line->'end' is distinct from o.line->'end'
     or n.line->'timing' is distinct from o.line->'timing'
     or n.line->'tokens' is distinct from o.line->'tokens'
 ) then raise exception 'Review must preserve Japanese and subtitle timing'; end if;
 update public.clips set lines=p_lines,category=p_category
 where id=p_id and lines=p_expected_lines and category=p_expected_category;
 get diagnostics changed=row_count;
 return changed=1;
end;
$body$;
revoke all on function public.apply_catalog_review(text,jsonb,text,jsonb,text) from public,anon,authenticated;
grant execute on function public.apply_catalog_review(text,jsonb,text,jsonb,text) to service_role;

-- Current automatic/manual work, one row per source window. Review history stays separate.
create function public.catalog_current_pipeline()
returns table(id text,video_id text,title text,channel_name text,status text,stage text,
 reason text,detail text,at timestamptz,source text)
language sql stable security invoker set search_path='' as $body$
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
 a.reason,a.detail,coalesce(a.updated_at,q.added_at),coalesce(a.source,'automatic')
 from latest a full join public.catalog_candidate_queue q
 on q.video_id=a.video_id and q.window_start_sec=a.window_start_sec;
$body$;
revoke all on function public.catalog_current_pipeline() from public,anon,authenticated;
grant execute on function public.catalog_current_pipeline() to service_role;

CREATE OR REPLACE FUNCTION public.admin_catalog_pipeline(p_from timestamp with time zone, p_to timestamp with time zone, p_view text DEFAULT 'live'::text, p_status text DEFAULT ''::text, p_search text DEFAULT ''::text, p_page integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare summary jsonb; items jsonb; total bigint; channels jsonb; reasons jsonb;
begin
 if p_from>=p_to or p_to-p_from>interval '366 days' or p_page<0 or p_page>100000
 or p_view not in ('live','drafts','queued','current','attempts','publications','rejections','jobs') then
  raise exception 'Invalid pipeline filters';
 end if;
 select jsonb_build_object(
  'current_failed',(select count(*) from public.catalog_current_pipeline() where status='failed'),
  'current_held',(select count(*) from public.catalog_current_pipeline() where status='held'),
  'current_excluded',(select count(*) from public.catalog_current_pipeline() where status='excluded'),
  'current_queued_retries',(select count(*) from public.catalog_current_pipeline() where status='queued' and reason is not null),
  'live',(select count(*) from public.clips where published),
  'drafts',(select count(*) from public.clips where not published),
  'policy_passed_live',(select count(*) from public.clips where published and public.catalog_review_receipt_ok(video_id,source_start_sec,duration_sec,lines)),
  'needs_policy_review',(select count(*) from public.clips where published and not public.catalog_review_receipt_ok(video_id,source_start_sec,duration_sec,lines)),
  'queued_videos',(select count(distinct video_id) from public.catalog_candidate_queue),
  'queued_windows',(select count(*) from public.catalog_candidate_queue),
  'processing',(select count(*) from public.catalog_pipeline_attempts where status='processing' and updated_at>now()-interval '10 minutes'),
  'stalled',(select count(*) from public.catalog_pipeline_attempts where status='processing' and updated_at<=now()-interval '10 minutes'),
  'published_in_range',(select count(*) from public.catalog_publication_events where status='published' and occurred_at>=p_from and occurred_at<p_to),
  'unpublished_in_range',(select count(*) from public.catalog_publication_events where status='unpublished' and occurred_at>=p_from and occurred_at<p_to),
  'failed_in_range',(select count(*) from public.catalog_pipeline_attempts where status='failed' and updated_at>=p_from and updated_at<p_to),
  'rejected_in_range',(select count(*) from public.catalog_pipeline_attempts where status='rejected' and updated_at>=p_from and updated_at<p_to),
  'held_in_range',(select count(*) from public.catalog_pipeline_attempts where status='held' and updated_at>=p_from and updated_at<p_to),
  'reviewed_in_range',(select count(*) from public.catalog_pipeline_attempts where status='reviewed' and updated_at>=p_from and updated_at<p_to),
  'legacy_rejections_in_range',(select count(*) from public.catalog_rejections where rejected_at>=p_from and rejected_at<p_to),
  'history_started_at',(select min(occurred_at) from public.catalog_publication_events),
  'last_attempt_at',(select max(started_at) from public.catalog_pipeline_attempts),
  'budget',(select jsonb_build_object('spent_usd',spent_usd,'reserved_usd',reserved_usd,'cap_usd',cap_usd) from public.openrouter_budget where id=1),
  'publisher',(select jsonb_build_object('paused_until',paused_until,'pause_reason',pause_reason) from public.catalog_fill_state where id=1),
  'learner_jobs',(select coalesce(jsonb_object_agg(status,n),'{}'::jsonb) from (select status,count(*) n from public.immersion_jobs where language='ja' group by status) j)
 ) into summary;
 with c as (select coalesce(m.channel_title,c.channel_name) title,count(*) live,count(*) filter(where public.catalog_review_receipt_ok(c.video_id,c.source_start_sec,c.duration_sec,c.lines)) verified from public.clips c left join public.catalog_video_sources m on m.video_id=c.video_id where c.published group by coalesce(m.channel_title,c.channel_name)),
 q as (select channel_title title,count(*) windows,count(distinct video_id) videos from public.catalog_candidate_queue group by channel_title),
 combined as (select coalesce(c.title,q.title,s.title) title,s.handle,s.channel_id,s.discovery_status,s.checked_at,coalesce(c.live,0) live,coalesce(c.verified,0) verified,coalesce(q.videos,0) queued_videos,coalesce(q.windows,0) queued_windows from c full join q using(title) full join public.catalog_sources s on s.title=coalesce(c.title,q.title))
 select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) into channels from (select * from combined order by live desc,queued_videos desc,title) t;
 select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) into reasons from (
  select reason,status,count(*) n from public.catalog_pipeline_attempts
  where status in ('rejected','failed','held') and updated_at>=p_from and updated_at<p_to
  group by reason,status order by count(*) desc,reason limit 50
 ) t;
 with rows as (
  select id,video_id,title,channel_name,case when public.catalog_review_receipt_ok(video_id,source_start_sec,duration_sec,lines) then 'policy_passed' else 'needs_review' end status,
   category stage,
   case when public.catalog_review_receipt_ok(video_id,source_start_sec,duration_sec,lines) then null else coalesce((select a.reason from public.catalog_pipeline_attempts a where a.clip_id=c.id and a.review_version=3 order by a.updated_at desc limit 1),'needs_current_review') end reason,
   case when public.catalog_review_receipt_ok(video_id,source_start_sec,duration_sec,lines) then null else coalesce((select a.detail from public.catalog_pipeline_attempts a where a.clip_id=c.id and a.review_version=3 order by a.updated_at desc limit 1),'Current content classification policy has not been approved') end detail,
   coalesce((select max(a.updated_at) from public.catalog_pipeline_attempts a where a.clip_id=c.id),created_at) at,'catalog' source from public.clips c where p_view='live' and published or p_view='drafts' and not published
  union all
  select video_id||':'||window_start_sec,video_id,title,channel_title,'queued','discovery',null,null,added_at,'automatic' from public.catalog_candidate_queue where p_view='queued'
  union all
  select * from public.catalog_current_pipeline() where p_view='current'
  union all
  select id::text,video_id,title,channel_name,case when status='processing' and updated_at<=now()-interval '10 minutes' then 'stalled' else status end,stage,reason,detail,updated_at,source
   from public.catalog_pipeline_attempts where p_view='attempts' and (status='processing' or updated_at>=p_from and updated_at<p_to)
  union all
  select id::text,video_id,title,channel_name,status,'publication',null,null,occurred_at,'publication' from public.catalog_publication_events where p_view='publications' and occurred_at>=p_from and occurred_at<p_to
  union all
  select video_id,video_id,'','', 'legacy_rejection','legacy',reason,detail,rejected_at,'legacy' from public.catalog_rejections where p_view='rejections' and rejected_at>=p_from and rejected_at<p_to
  union all
  select id::text,video_id,coalesce(title,''),coalesce(channel_name,''),status,stage,error_code,error_message,updated_at,'learner_import' from public.immersion_jobs where p_view='jobs' and language='ja' and (status in ('queued','processing') or updated_at>=p_from and updated_at<p_to)
 ), filtered as (
  select * from rows where (p_status='' or status=p_status) and (p_search='' or concat_ws(' ',id,video_id,title,channel_name,reason,detail) ilike '%'||p_search||'%')
 )
 select (select count(*) from filtered),coalesce((select jsonb_agg(to_jsonb(t)) from (select * from filtered order by at desc,id limit 50 offset p_page*50) t),'[]'::jsonb)
 into total,items;
 return jsonb_build_object('generated_at',now(),'from',p_from,'to',p_to,'summary',summary,'channels',channels,'reasons',reasons,'items',items,'total',total,'page',p_page,'page_size',50,'policy_version',3);
end;
$function$
