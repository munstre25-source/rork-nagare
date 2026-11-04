-- Roll back this entire test transaction. Fixtures never remain in the catalog.
do $qa$
declare lines jsonb; h text; alignment jsonb; proof jsonb;
begin
 if has_function_privilege('anon','public.catalog_local_publication_ok(text,numeric,numeric,jsonb,text)','execute')
 or has_function_privilege('authenticated','public.catalog_local_publication_ok(text,numeric,numeric,jsonb,text)','execute') then raise exception 'Public local-publication function access'; end if;
 lines := '[{"start":0.1,"end":1,"timing":"word","translation":"Thank you!","tokens":[{"surface":"ありがとう","start":0.1,"end":1,"tappable":true,"definitions":["thank you"]}]}]'::jsonb;
 h := public.catalog_review_hash('abcdefghijk',0,124,lines);
 alignment := jsonb_build_object('version',1,'method','local-forced-alignment','model','Qwen/Qwen3-ForcedAligner-0.6B','revision','c7cbfc2048c462b0d63a45797104fc9db3ad62b7','audioSha256',repeat('a',64),'sourceLinesHash',h,'databaseHash',h,'videoId','abcdefghijk','sourceStartSec',0,'durationSec',124);
 proof := jsonb_build_object('version',1,'method','local-asr-translation','language','Japanese','asrModel','Qwen/Qwen3-ASR-0.6B','asrRevision','5eb144179a02acc5e5ba31e748d22b0cf3e303b0','translationModel','Helsinki-NLP/opus-mt-ja-en','translationRevision','0770961a39ba6bd66305b149c3f4110bcafca2e6','channelId','UC' || repeat('z',22),'category','variety','videoId','abcdefghijk','sourceStartSec',0,'durationSec',124,'databaseHash',h);
 lines := jsonb_set(lines,'{0,translationReview}',jsonb_build_object('version','local-1','localAlignment',alignment,'localPublication',proof));
 if not public.catalog_local_publication_ok('abcdefghijk',0,124,lines,'variety') then raise exception 'Complete 124-second local Short rejected'; end if;
 if public.catalog_local_publication_ok('abcdefghijk',0,124,lines,'anime') then raise exception 'Wrong category accepted'; end if;
 lines := jsonb_set(jsonb_set(lines,'{0,translationReview,localPublication,asrModel}','"dropbox-dash/faster-whisper-large-v3-turbo"'),'{0,translationReview,localPublication,asrRevision}','"0a363e9161cbc7ed1431c9597a8ceaf0c4f78fcf"');
 if not public.catalog_local_publication_ok('abcdefghijk',0,124,lines,'variety') then raise exception 'Pinned free Whisper rejected'; end if;
 if public.catalog_local_publication_ok('abcdefghijk',0,124,jsonb_set(lines,'{0,translationReview,localPublication,asrRevision}','"5eb144179a02acc5e5ba31e748d22b0cf3e303b0"'),'variety') then raise exception 'Mixed model/revision accepted'; end if;
 lines := jsonb_set(lines,'{0,translationReview,localAlignment,method}','"local-attention-dtw"');
 lines := jsonb_set(lines,'{0,translationReview,localAlignment,model}','"dropbox-dash/faster-whisper-large-v3-turbo"');
 lines := jsonb_set(lines,'{0,translationReview,localAlignment,revision}','"0a363e9161cbc7ed1431c9597a8ceaf0c4f78fcf"');
 if not public.catalog_local_publication_ok('abcdefghijk',0,124,lines,'variety') then raise exception 'Pinned attention timing rejected'; end if;
 if public.catalog_local_publication_ok('abcdefghijk',0,124,jsonb_set(lines,'{0,translationReview,localAlignment,method}','"local-forced-alignment"'),'variety') then raise exception 'Mixed alignment method/model accepted'; end if;
 if public.catalog_review_receipt_ok('abcdefghijk',0,124,lines) then raise exception 'Local publication pretended to be paid independent review'; end if;
 insert into public.catalog_sources(handle,channel_id,title,discovery_status,local_pipeline_ok,local_category)
 values('__local_publication_qa__','UC'||repeat('z',22),'Local QA','test',false,'variety');
 insert into public.catalog_video_sources(video_id,channel_id,channel_title) values('abcdefghijk','UC'||repeat('z',22),'Local QA');
 begin
  insert into public.clips(id,video_id,title,channel_name,category,difficulty,source_start_sec,duration_sec,lines,published,review_tier,timing_mode,video_orientation)
  values('__local_publication_qa__','abcdefghijk','Local QA','Local QA','variety','Beginner',0,124,lines,true,'local','word','portrait');
  raise exception 'Unapproved source was published';
 exception when check_violation then null; end;
 update public.catalog_sources set local_pipeline_ok=true where handle='__local_publication_qa__';
 insert into public.clips(id,video_id,title,channel_name,category,difficulty,source_start_sec,duration_sec,lines,published,review_tier,timing_mode,video_orientation)
 values('__local_publication_qa__','abcdefghijk','Local QA','Local QA','variety','Beginner',0,124,lines,true,'local','word','portrait');
 begin
  update public.clips c set lines=jsonb_set(c.lines,'{0,tokens,0,surface}','"changed"') where id='__local_publication_qa__';
  raise exception 'Post-seal subtitle mutation accepted';
 exception when check_violation then null; end;
end;
$qa$;
