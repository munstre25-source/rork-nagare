begin;
set local role service_role;
insert into public.catalog_candidate_queue(video_id,window_start_sec,title,channel_title,duration_sec,category,difficulty)
values('LEASE_TEST1',0,'lease fixture','test',20,'learning','Beginner');
do $test$
declare first_token uuid; second_token uuid;
begin
 first_token:=public.claim_catalog_candidate('LEASE_TEST1',0);
 if first_token is null then raise exception 'First claim failed';end if;
 if public.claim_catalog_candidate('LEASE_TEST1',0) is not null then raise exception 'Duplicate ownership allowed';end if;
 perform public.release_catalog_candidate('LEASE_TEST1',0,gen_random_uuid());
 if public.claim_catalog_candidate('LEASE_TEST1',0) is not null then raise exception 'Foreign token released ownership';end if;
 update public.catalog_candidate_leases set expires_at=now()-interval '1 second' where video_id='LEASE_TEST1';
 second_token:=public.claim_catalog_candidate('LEASE_TEST1',0);
 if second_token is null or second_token=first_token then raise exception 'Expired ownership was not renewed';end if;
 perform public.release_catalog_candidate('LEASE_TEST1',0,first_token);
 if public.claim_catalog_candidate('LEASE_TEST1',0) is not null then raise exception 'Stale owner released renewed claim';end if;
 perform public.release_catalog_candidate('LEASE_TEST1',0,second_token);
 if public.claim_catalog_candidate('LEASE_TEST1',0) is null then raise exception 'Correct release failed';end if;
 delete from public.catalog_candidate_queue where video_id='LEASE_TEST1';
 if exists(select 1 from public.catalog_candidate_leases where video_id='LEASE_TEST1') then raise exception 'Deleted queue retained claim';end if;
 if public.claim_catalog_candidate('LEASE_TEST1',0) is not null then raise exception 'Missing candidate was claimed';end if;
end;
$test$;
select 'publisher lease safety passed' result;
rollback;
