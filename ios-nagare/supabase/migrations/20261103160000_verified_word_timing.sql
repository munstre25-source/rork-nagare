-- Word alignment is a publication requirement. Existing live rows are repaired
-- through the service-only compare-and-swap below; no catalog rows are deleted.
create function public.catalog_word_timing_ok(p_lines jsonb)
returns boolean language sql immutable security invoker set search_path='' as $body$
 select case when jsonb_typeof(p_lines)='array' and jsonb_array_length(p_lines)>0 then
  not exists(select 1 from jsonb_array_elements(p_lines) l
   where l->>'timing' is distinct from 'word'
      or l->'translationReview'->'wordTimingVerified' is distinct from 'true'::jsonb)
 else false end;
$body$;
revoke all on function public.catalog_word_timing_ok(jsonb) from public,anon,authenticated;
grant execute on function public.catalog_word_timing_ok(jsonb) to service_role;

-- Preserve source bounds, line slots, Japanese, readings and meanings. Only verified
-- timing and independently reviewed English/receipts may change. No network call holds a lock.
create function public.apply_catalog_word_timing(
 p_id text,p_expected_lines jsonb,p_video_id text,p_source_start numeric,p_duration numeric,p_lines jsonb
) returns boolean language plpgsql security invoker set search_path='' as $body$
declare changed integer;
begin
 if jsonb_typeof(p_lines) is distinct from 'array'
 or jsonb_typeof(p_expected_lines) is distinct from 'array'
 or jsonb_array_length(p_lines)=0
 or jsonb_array_length(p_lines)<>jsonb_array_length(p_expected_lines) then
  raise exception 'Timing repair must preserve original line slots';
 end if;
 if not public.catalog_word_timing_ok(p_lines)
 or not public.catalog_review_receipt_ok(p_video_id,p_source_start,p_duration,p_lines) then
  raise exception 'Timing repair requires signed independent audio verification';
 end if;
 if exists(
  select 1 from jsonb_array_elements(p_lines) with ordinality n(line,i)
  join jsonb_array_elements(p_expected_lines) with ordinality o(line,i) using(i)
  where (n.line-'tokens'-'timing'-'translation'-'translationReview')
     is distinct from (o.line-'tokens'-'timing'-'translation'-'translationReview')
     or jsonb_typeof(n.line->'tokens') is distinct from 'array'
     or jsonb_typeof(o.line->'tokens') is distinct from 'array'
     or jsonb_array_length(n.line->'tokens')<>jsonb_array_length(o.line->'tokens')
 ) then raise exception 'Timing repair must preserve sentences and token slots'; end if;
 if exists(
  select 1 from jsonb_array_elements(p_lines) with ordinality n(line,i)
  join jsonb_array_elements(p_expected_lines) with ordinality o(line,i) using(i)
  cross join lateral jsonb_array_elements(n.line->'tokens') with ordinality nt(token,j)
  join lateral jsonb_array_elements(o.line->'tokens') with ordinality ot(token,j) using(j)
  where (nt.token-'start'-'end') is distinct from (ot.token-'start'-'end')
 ) then raise exception 'Timing repair may not change Japanese, readings or meanings'; end if;
 update public.clips set lines=p_lines,timing_mode='word',
  category=p_lines->0->'translationReview'->'contentClassification'->>'category'
 where id=p_id and lines=p_expected_lines and video_id=p_video_id
   and coalesce(source_start_sec,0)=p_source_start and duration_sec=p_duration;
 get diagnostics changed=row_count;
 return changed=1;
end;
$body$;
revoke all on function public.apply_catalog_word_timing(text,jsonb,text,numeric,numeric,jsonb) from public,anon,authenticated;
grant execute on function public.apply_catalog_word_timing(text,jsonb,text,numeric,numeric,jsonb) to service_role;

create or replace function public.guard_catalog_publication()
returns trigger language plpgsql security invoker set search_path='' as $body$
begin
 if new.published and (
  not public.catalog_review_receipt_ok(new.video_id,new.source_start_sec,new.duration_sec,new.lines)
  or not public.catalog_word_timing_ok(new.lines)
  or exists(select 1 from jsonb_array_elements(new.lines) l
   where l->'translationReview'->'contentClassification'->>'category' is distinct from new.category)
 ) then
  raise exception 'Publication blocked: independently audio-verified word timing, translation and source review required'
   using errcode='23514';
 end if;
 if new.published then new.review_tier := 'ai_v3'; end if;
 return new;
end;
$body$;
