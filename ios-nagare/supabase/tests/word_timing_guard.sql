-- Run after the word-timing migration inside a rollback-only QA transaction.
do $qa$
declare original jsonb; candidate jsonb; signature text; applied boolean;
begin
 if has_function_privilege('anon','public.apply_catalog_word_timing(text,jsonb,text,numeric,numeric,jsonb)','execute')
 or has_function_privilege('authenticated','public.apply_catalog_word_timing(text,jsonb,text,numeric,numeric,jsonb)','execute')
 or not has_function_privilege('service_role','public.apply_catalog_word_timing(text,jsonb,text,numeric,numeric,jsonb)','execute') then
  raise exception 'Timing repair privileges are incorrect';
 end if;
 if public.catalog_word_timing_ok('[]'::jsonb) or public.catalog_word_timing_ok('[{"timing":"line"}]'::jsonb) then
  raise exception 'Sentence timing passed publication guard';
 end if;
 original := '[{"start":0,"end":2,"timing":"line","translation":"Today.","tokens":[{"surface":"今日","start":0,"end":2,"definitions":["today"]}]}]'::jsonb;
 candidate := jsonb_set(original,'{0,timing}','"word"'::jsonb);
 candidate := jsonb_set(candidate,'{0,tokens,0,end}','1.8'::jsonb);
 candidate := jsonb_set(candidate,'{0,translationReview}',jsonb_build_object(
  'version',3,'sourceHash',repeat('a',64),'model','rollback-qa','videoId','qa-video',
  'sourceStartSec',0,'durationSec',8,'visualCheckComplete',true,'englishSubtitlesVisible',false,
  'timingVerified',true,'wordTimingVerified',true,'contentClassification',jsonb_build_object(
   'category','learning','contentFormat','language_lesson','childDirected',false,
   'classificationClear',true,'classificationEvidence','Rollback-only quality assurance fixture'
  )
 ));
 signature := public.catalog_review_hash('qa-video',0,8,candidate);
 candidate := jsonb_set(candidate,'{0,translationReview,databaseHash}',to_jsonb(signature));
 applied := public.apply_catalog_word_timing('__qa_nonexistent_clip__',original,'qa-video',0,8,candidate);
 if applied then raise exception 'Compare-and-swap unexpectedly wrote a nonexistent clip'; end if;
 candidate := jsonb_set(candidate,'{0,tokens,0,surface}','"改変"'::jsonb);
 signature := public.catalog_review_hash('qa-video',0,8,candidate);
 candidate := jsonb_set(candidate,'{0,translationReview,databaseHash}',to_jsonb(signature));
 begin
  perform public.apply_catalog_word_timing('__qa_nonexistent_clip__',original,'qa-video',0,8,candidate);
  raise exception 'QA failed: Japanese mutation was accepted';
 exception when raise_exception then
  if sqlerrm <> 'Timing repair may not change Japanese, readings or meanings' then raise; end if;
 end;
end;
$qa$;
