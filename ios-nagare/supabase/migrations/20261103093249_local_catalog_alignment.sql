-- Free local alignment only changes timing on content that is already live.
-- It never manufactures an independent translation/visual/audio-review receipt,
-- publishes a draft, or changes source bounds, category, Japanese or dictionary data.
create function public.catalog_timing_content(p_lines jsonb)
returns jsonb language sql immutable security invoker set search_path='' as $body$
 select jsonb_agg((l-'start'-'end'-'timing'-'tokens'-'translationReview') || jsonb_build_object(
  'tokens',(select jsonb_agg(t-'start'-'end' order by j)
            from jsonb_array_elements(l->'tokens') with ordinality tt(t,j)),
  'translationReview',coalesce(l->'translationReview','{}'::jsonb)-'localAlignment'
 ) order by i) from jsonb_array_elements(p_lines) with ordinality ll(l,i);
$body$;
revoke all on function public.catalog_timing_content(jsonb) from public,anon,authenticated;
grant execute on function public.catalog_timing_content(jsonb) to service_role;

create function public.catalog_local_alignment_ok(p_video_id text,p_start numeric,p_duration numeric,p_lines jsonb)
returns boolean language plpgsql immutable security invoker set search_path='' as $body$
declare expected_hash text;
begin
 if p_start is null or p_start<0 or p_duration is null or p_duration<=0 or p_duration>120 then return false; end if;
 if jsonb_typeof(p_lines) is distinct from 'array' then return false; end if;
 if jsonb_array_length(p_lines)=0 or jsonb_array_length(p_lines)>100 then return false; end if;
 expected_hash := public.catalog_review_hash(p_video_id,p_start,p_duration,p_lines);
 if exists(select 1 from jsonb_array_elements(p_lines) l where
  l->>'timing' is distinct from 'word'
  or l->'translationReview'->'localAlignment'->>'version' is distinct from '1'
  or l->'translationReview'->'localAlignment'->>'method' is distinct from 'local-forced-alignment'
  or l->'translationReview'->'localAlignment'->>'model' is distinct from 'Qwen/Qwen3-ForcedAligner-0.6B'
  or l->'translationReview'->'localAlignment'->>'revision' is distinct from 'c7cbfc2048c462b0d63a45797104fc9db3ad62b7'
  or coalesce(l->'translationReview'->'localAlignment'->>'audioSha256','') !~ '^[a-f0-9]{64}$'
  or coalesce(l->'translationReview'->'localAlignment'->>'sourceLinesHash','') !~ '^[a-f0-9]{64}$'
  or l->'translationReview'->'localAlignment'->>'databaseHash' is distinct from expected_hash
  or l->'translationReview'->'localAlignment'->>'videoId' is distinct from p_video_id
  or l->'translationReview'->'localAlignment'->'sourceStartSec' is distinct from to_jsonb(p_start)
  or l->'translationReview'->'localAlignment'->'durationSec' is distinct from to_jsonb(p_duration)
  or jsonb_typeof(l->'start') is distinct from 'number'
  or jsonb_typeof(l->'end') is distinct from 'number'
  or jsonb_typeof(l->'tokens') is distinct from 'array'
 ) then return false; end if;
 if exists(select 1 from (
   select l,(l->>'start')::numeric s,(l->>'end')::numeric e,
    lag((l->>'end')::numeric) over(order by i) previous_end
   from jsonb_array_elements(p_lines) with ordinality ll(l,i)
  ) q where s<0 or e<=s or e>p_duration+.001 or s<previous_end
   or jsonb_array_length(l->'tokens')=0
 ) then return false; end if;
 if exists(select 1 from jsonb_array_elements(p_lines) l
  cross join lateral jsonb_array_elements(l->'tokens') t
  where jsonb_typeof(t->'start') is distinct from 'number'
   or jsonb_typeof(t->'end') is distinct from 'number'
 ) then return false; end if;
 return not exists(select 1 from jsonb_array_elements(p_lines) l
  cross join lateral (
   select t,(t->>'start')::numeric s,(t->>'end')::numeric e,
    lag((t->>'end')::numeric) over(order by j) previous_end
   from jsonb_array_elements(l->'tokens') with ordinality tt(t,j)
  ) q where s<(l->>'start')::numeric-.001 or e>(l->>'end')::numeric+.001
    or e<s or s<previous_end-.001
    or (coalesce(t->>'surface','') !~ '^[[:space:][:punct:]ー〜]+$' and e<=s)
 );
exception when invalid_text_representation or numeric_value_out_of_range then return false;
end;
$body$;
revoke all on function public.catalog_local_alignment_ok(text,numeric,numeric,jsonb) from public,anon,authenticated;
grant execute on function public.catalog_local_alignment_ok(text,numeric,numeric,jsonb) to service_role;

create function public.apply_catalog_local_alignment(
 p_id text,p_expected_lines jsonb,p_video_id text,p_source_start numeric,p_duration numeric,p_lines jsonb
) returns boolean language plpgsql security invoker set search_path='' as $body$
declare changed integer; original_hash text;
begin
 if not public.catalog_local_alignment_ok(p_video_id,p_source_start,p_duration,p_lines) then
  raise exception 'Local alignment requires complete bounded word intervals and a matching integrity seal';
 end if;
 if public.catalog_timing_content(p_lines) is distinct from public.catalog_timing_content(p_expected_lines) then
  raise exception 'Local alignment may only replace timing and its own receipt';
 end if;
 original_hash := public.catalog_review_hash(p_video_id,p_source_start,p_duration,p_expected_lines);
 if exists(select 1 from jsonb_array_elements(p_lines) l where
  l->'translationReview'->'localAlignment'->>'sourceLinesHash' is distinct from original_hash
 ) then raise exception 'Local alignment does not match the original subtitle snapshot'; end if;
 update public.clips set lines=p_lines,timing_mode='word'
 where id=p_id and published and lines=p_expected_lines and video_id=p_video_id
  and coalesce(source_start_sec,0)=p_source_start and duration_sec=p_duration;
 get diagnostics changed=row_count;
 return changed=1;
end;
$body$;
revoke all on function public.apply_catalog_local_alignment(text,jsonb,text,numeric,numeric,jsonb) from public,anon,authenticated;
grant execute on function public.apply_catalog_local_alignment(text,jsonb,text,numeric,numeric,jsonb) to service_role;

create or replace function public.guard_catalog_publication()
returns trigger language plpgsql security invoker set search_path='' as $body$
begin
 if not new.published then return new; end if;
 -- Existing live content can receive locally aligned timings without buying a new
 -- translation/visual review. This exception cannot publish or recategorize a clip.
 if tg_op='UPDATE' then
  if old.published and new.video_id=old.video_id
   and new.source_start_sec is not distinct from old.source_start_sec
   and new.duration_sec=old.duration_sec and new.category=old.category
   and new.review_tier=old.review_tier
   and public.catalog_timing_content(new.lines)=public.catalog_timing_content(old.lines)
   and public.catalog_local_alignment_ok(new.video_id,coalesce(new.source_start_sec,0),new.duration_sec,new.lines)
  then return new; end if;
 end if;
 if not public.catalog_review_receipt_ok(new.video_id,new.source_start_sec,new.duration_sec,new.lines)
  or not public.catalog_word_timing_ok(new.lines)
  or exists(select 1 from jsonb_array_elements(new.lines) l
   where l->'translationReview'->'contentClassification'->>'category' is distinct from new.category)
 then raise exception 'Publication blocked: independently audio-verified word timing, translation and source review required'
  using errcode='23514'; end if;
 new.review_tier := 'ai_v3';
 return new;
end;
$body$;
