-- One owner per candidate window, shared by scheduled/manual publisher calls.
create table public.catalog_candidate_leases (
 video_id text not null,
 window_start_sec integer not null,
 lease_token uuid not null default gen_random_uuid(),
 expires_at timestamptz not null,
 primary key(video_id,window_start_sec),
 foreign key(video_id,window_start_sec) references public.catalog_candidate_queue(video_id,window_start_sec) on delete cascade
);
alter table public.catalog_candidate_leases enable row level security;
revoke all on public.catalog_candidate_leases from public,anon,authenticated;
grant select,insert,update,delete on public.catalog_candidate_leases to service_role;

create function public.claim_catalog_candidate(p_video_id text,p_window_start_sec integer)
returns uuid language plpgsql security invoker set search_path='' as $body$
declare claimed uuid;
begin
 insert into public.catalog_candidate_leases(video_id,window_start_sec,expires_at)
 select q.video_id,q.window_start_sec,now()+interval '5 minutes'
 from public.catalog_candidate_queue q
 where q.video_id=p_video_id and q.window_start_sec=p_window_start_sec and q.next_attempt_at<=now()
 on conflict(video_id,window_start_sec) do update
 set lease_token=excluded.lease_token,expires_at=excluded.expires_at
 where public.catalog_candidate_leases.expires_at<=now()
 returning lease_token into claimed;
 if claimed is not null then
  update public.catalog_pipeline_attempts set status='failed',stage='error',reason='worker_timeout',
   detail='Previous worker lease expired; candidate reclaimed for retry',updated_at=now(),finished_at=now()
  where video_id=p_video_id and window_start_sec=p_window_start_sec and source='automatic'
   and status='processing' and updated_at<now()-interval '5 minutes';
 end if;
 return claimed;
end;
$body$;
create function public.release_catalog_candidate(p_video_id text,p_window_start_sec integer,p_lease_token uuid)
returns void language sql security invoker set search_path='' as $body$
 delete from public.catalog_candidate_leases
 where video_id=p_video_id and window_start_sec=p_window_start_sec and lease_token=p_lease_token;
$body$;
revoke all on function public.claim_catalog_candidate(text,integer) from public,anon,authenticated;
revoke all on function public.release_catalog_candidate(text,integer,uuid) from public,anon,authenticated;
grant execute on function public.claim_catalog_candidate(text,integer) to service_role;
grant execute on function public.release_catalog_candidate(text,integer,uuid) to service_role;
