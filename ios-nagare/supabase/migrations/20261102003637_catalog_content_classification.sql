alter table public.clips drop constraint clips_category_check;
alter table public.clips add constraint clips_category_check check(category in ('anime','drama','variety','vtuber','interview','kids','gaming','learning','podcast'));
create table public.catalog_video_sources (
 video_id text primary key,channel_id text not null,channel_title text not null,checked_at timestamptz not null default now()
);
alter table public.catalog_video_sources enable row level security;
revoke all on public.catalog_video_sources from public,anon,authenticated;
grant select,insert,update on public.catalog_video_sources to service_role;
create index catalog_video_sources_channel_idx on public.catalog_video_sources(channel_id);
create index catalog_pipeline_attempts_clip_idx on public.catalog_pipeline_attempts(clip_id,updated_at desc) where clip_id is not null;
create or replace function public.catalog_review_receipt_ok(p_video_id text,p_start numeric,p_duration numeric,p_lines jsonb)
returns boolean language plpgsql immutable security invoker set search_path='' as $body$
declare expected_hash text;
begin
 if p_lines is null or jsonb_typeof(p_lines)<>'array' then return false; end if;
 if jsonb_array_length(p_lines)=0 then return false; end if;
 expected_hash:=public.catalog_review_hash(p_video_id,p_start,p_duration,p_lines);
 return not exists (
  select 1 from jsonb_array_elements(p_lines) l where
   coalesce(l->'translationReview'->>'version','')<>'3'
   or coalesce(l->'translationReview'->>'databaseHash','')<>expected_hash
   or coalesce(l->'translationReview'->>'sourceHash','') !~ '^[a-f0-9]{64}$'
   or coalesce(l->'translationReview'->>'model','')=''
   or l->'translationReview'->'visualCheckComplete' is distinct from 'true'::jsonb
   or l->'translationReview'->'englishSubtitlesVisible' is distinct from 'false'::jsonb
   or l->'translationReview'->'timingVerified' is distinct from 'true'::jsonb
   or coalesce(l->'translationReview'->>'videoId','')<>p_video_id
   or l->'translationReview'->'sourceStartSec' is distinct from to_jsonb(p_start)
   or l->'translationReview'->'durationSec' is distinct from to_jsonb(p_duration)
   or l->'translationReview'->'contentClassification'->'classificationClear' is distinct from 'true'::jsonb
   or length(coalesce(l->'translationReview'->'contentClassification'->>'classificationEvidence',''))<12
   or coalesce(l->'translationReview'->'contentClassification'->>'category','') not in ('anime','drama','variety','vtuber','interview','kids','gaming','learning','podcast')
   or l->'translationReview'->'contentClassification'->>'category' is distinct from
    case l->'translationReview'->'contentClassification'->>'contentFormat'
     when 'anime' then 'anime' when 'scripted_drama' then 'drama' when 'variety' then 'variety'
     when 'vtuber_stream' then 'vtuber' when 'street_interview' then 'interview'
     when 'children_program' then 'kids' when 'gameplay' then 'gaming'
     when 'language_lesson' then 'learning' when 'podcast' then 'podcast' else null end
   or l->'translationReview'->'contentClassification'->'childDirected' is distinct from
    case when l->'translationReview'->'contentClassification'->>'category'='kids' then 'true'::jsonb else 'false'::jsonb end
   or coalesce(btrim(l->>'translation'),'')=''
 );
end;
$body$;
create or replace function public.guard_catalog_publication()
returns trigger language plpgsql security invoker set search_path='' as $body$
begin
 if new.published and (
  not public.catalog_review_receipt_ok(new.video_id,new.source_start_sec,new.duration_sec,new.lines) or
  exists(select 1 from jsonb_array_elements(new.lines) l where l->'translationReview'->'contentClassification'->>'category' is distinct from new.category)
 ) then
  raise exception 'Publication blocked: current audio, timing, translation and source visual and content classification review required'
   using errcode='23514';
 end if;
 return new;
end;
$body$;

drop trigger catalog_publication_guard on public.clips;
create trigger catalog_publication_guard before insert or update of published,lines,video_id,source_start_sec,duration_sec,category
 on public.clips for each row execute function public.guard_catalog_publication();
create or replace function public.publish_reviewed_catalog_clip(p_id text,p_expected_lines jsonb,p_reviewed_lines jsonb)
returns setof public.clips language plpgsql security invoker set search_path='' as $body$
begin
 if (select jsonb_agg(v-'translation'-'translationReview' order by n) from jsonb_array_elements(p_expected_lines) with ordinality t(v,n))
 is distinct from
 (select jsonb_agg(v-'translation'-'translationReview' order by n) from jsonb_array_elements(p_reviewed_lines) with ordinality t(v,n)) then
  raise exception 'Review may only replace English and receipts' using errcode='23514';
 end if;
 return query update public.clips set lines=p_reviewed_lines,published=true,category=p_reviewed_lines->0->'translationReview'->'contentClassification'->>'category'
  where id=p_id and lines=p_expected_lines returning *;
end;
$body$;
create or replace function public.admin_catalog_pipeline(
 p_from timestamptz,p_to timestamptz,p_view text default 'live',
 p_status text default '',p_search text default '',p_page integer default 0
) returns jsonb language plpgsql stable security invoker set search_path='' as $body$
declare summary jsonb; items jsonb; total bigint; channels jsonb; reasons jsonb;
begin
 if p_from>=p_to or p_to-p_from>interval '366 days' or p_page<0 or p_page>100000
 or p_view not in ('live','drafts','queued','attempts','publications','rejections','jobs') then
  raise exception 'Invalid pipeline filters';
 end if;
 select jsonb_build_object(
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
  'budget',(select jsonb_build_object('spent_usd',spent_usd,'cap_usd',cap_usd) from public.openrouter_budget where id=1),
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
$body$;
create or replace function public.record_catalog_publication()
returns trigger language plpgsql security invoker set search_path='' as $body$
begin
 if tg_op='INSERT' then
  if not new.published then return new; end if;
 elsif new.published is not distinct from old.published then return new;
 end if;
 insert into public.catalog_publication_events(clip_id,video_id,title,channel_name,status,review_version)
 values(new.id,new.video_id,coalesce(new.title,''),coalesce(new.channel_name,''),
 case when new.published then 'published' else 'unpublished' end,
 case when new.lines->0->'translationReview'->>'version'='3' then 3 else null end);
 return new;
end;
$body$;
