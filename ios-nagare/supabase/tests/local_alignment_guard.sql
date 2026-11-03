-- Run in a rollback-only transaction after the local alignment migration.
do $qa$
declare old_lines jsonb; new_lines jsonb; receipt jsonb; h text; did_change boolean;
begin
 if has_function_privilege('anon','public.apply_catalog_local_alignment(text,jsonb,text,numeric,numeric,jsonb)','execute')
 or has_function_privilege('authenticated','public.apply_catalog_local_alignment(text,jsonb,text,numeric,numeric,jsonb)','execute')
 or not has_function_privilege('service_role','public.apply_catalog_local_alignment(text,jsonb,text,numeric,numeric,jsonb)','execute')
 then raise exception 'Local timing RPC privilege failure'; end if;
 old_lines := '[{"start":0,"end":3,"translation":"Hello there!","tokens":[{"surface":"hello","start":0,"end":3,"definitions":["greeting"]},{"surface":"!","start":0,"end":3},{"surface":"there","start":0,"end":3}]}]'::jsonb;
 new_lines := '[{"start":0.1,"end":2.5,"timing":"word","translation":"Hello there!","tokens":[{"surface":"hello","start":0.1,"end":0.6,"definitions":["greeting"]},{"surface":"!","start":0.6,"end":0.6},{"surface":"there","start":2,"end":2.5}]}]'::jsonb;
 receipt := jsonb_build_object('version',1,'method','local-forced-alignment','model','Qwen/Qwen3-ForcedAligner-0.6B',
  'revision','c7cbfc2048c462b0d63a45797104fc9db3ad62b7','videoId','abcdefghijk','sourceStartSec',8,'durationSec',3,
  'audioSha256',repeat('a',64),'sourceLinesHash',public.catalog_review_hash('abcdefghijk',8,3,old_lines));
 new_lines := jsonb_set(new_lines,'{0,translationReview}',jsonb_build_object('localAlignment',receipt));
 h := public.catalog_review_hash('abcdefghijk',8,3,new_lines);
 new_lines := jsonb_set(new_lines,'{0,translationReview,localAlignment,databaseHash}',to_jsonb(h));
 if not public.catalog_local_alignment_ok('abcdefghijk',8,3,new_lines) then raise exception 'Valid local timing rejected'; end if;
 if public.catalog_timing_content(old_lines) is distinct from public.catalog_timing_content(new_lines) then raise exception 'Timing-only normalization failed'; end if;
 if public.catalog_review_receipt_ok('abcdefghijk',8,3,new_lines) then raise exception 'Local timing pretended to be independent AI review'; end if;
 if public.catalog_local_alignment_ok('abcdefghijk',9,3,new_lines) then raise exception 'Source mismatch accepted'; end if;
 if public.catalog_local_alignment_ok('abcdefghijk',8,3,jsonb_set(new_lines,'{0,tokens,0,end}','0.1')) then raise exception 'Collapsed timing accepted'; end if;
 did_change := public.apply_catalog_local_alignment('__local_timing_qa_nonexistent__',old_lines,'abcdefghijk',8,3,new_lines);
 if did_change then raise exception 'Nonexistent CAS reported success'; end if;
 begin
  perform public.apply_catalog_local_alignment('__local_timing_qa_nonexistent__',jsonb_set(old_lines,'{0,tokens,0,surface}','"changed"'),'abcdefghijk',8,3,new_lines);
  raise exception 'Content mutation accepted';
 exception when raise_exception then
  if sqlerrm='Content mutation accepted' then raise; end if;
 end;
end;
$qa$;
