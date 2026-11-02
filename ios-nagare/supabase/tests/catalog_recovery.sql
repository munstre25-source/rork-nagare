-- Run with a privileged test connection against a seeded catalog; all writes roll back.
begin;
set local role service_role;
do $test$
declare c record; applied boolean; blocked boolean:=false;
begin
 select * into c from public.clips where published
 and public.catalog_review_receipt_ok(video_id,source_start_sec,duration_sec,lines) limit 1;
 if c.id is null then raise exception 'An approved clip fixture is required'; end if;
 applied:=public.apply_catalog_review(c.id,c.lines,c.category,c.lines,c.category);
 if not applied then raise exception 'Unchanged approved payload should apply'; end if;
 applied:=public.apply_catalog_review(c.id,c.lines||'[{}]'::jsonb,c.category,c.lines||'[{}]'::jsonb,c.category);
 if applied then raise exception 'Stale expected payload must not apply'; end if;
 begin
  perform public.apply_catalog_review(c.id,c.lines,c.category,
   jsonb_set(c.lines,'{0,start}',to_jsonb(999)),c.category);
 exception when raise_exception then blocked:=true;
 end;
 if not blocked then raise exception 'Timing mutation was not blocked'; end if;
 blocked:=false;
 begin
  perform public.apply_catalog_review(c.id,c.lines,c.category,
   jsonb_set(c.lines,'{0,tokens,0,surface}','"Invented"'::jsonb),c.category);
 exception when raise_exception then blocked:=true;
 end;
 if not blocked then raise exception 'Japanese mutation was not blocked'; end if;
 blocked:=false;
 begin
  perform public.apply_catalog_review(c.id,c.lines,c.category,
   jsonb_set(c.lines,'{0,translation}','"An unreviewed edit."'::jsonb),c.category);
 exception when check_violation then blocked:=true;
 end;
 if not blocked then raise exception 'Invalid review seal was not blocked'; end if;
 if exists(select 1 from public.catalog_current_pipeline() group by video_id,id having count(*)>1)
 then raise exception 'Current pipeline contains duplicate work'; end if;
end;
$test$;
select 'catalog recovery safety checks passed' result;
rollback;
