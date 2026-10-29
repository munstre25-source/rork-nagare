-- Claims queued immersion jobs for one worker run, with a global concurrency cap,
-- stale-lock recovery, and SKIP LOCKED so overlapping runs never take the same job.
-- Rollback: select cron.unschedule('immersion-worker'); drop function public.claim_immersion_jobs(text, int, int);

create or replace function public.claim_immersion_jobs(
  p_worker text,
  p_max_concurrency int default 2,
  p_stale_seconds int default 300
)
returns setof public.immersion_jobs
language plpgsql
security definer
set search_path = public
as $$
declare
  running int;
  free_slots int;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'forbidden';
  end if;
  -- One claimer at a time so the concurrency cap holds across overlapping runs.
  perform pg_advisory_xact_lock(hashtext('immersion_jobs_claim'));

  -- A worker that died mid-run leaves its lock behind. Requeue it, or fail it when out of attempts.
  update public.immersion_jobs
     set status = case when attempts >= max_attempts then 'failed' else 'queued' end,
         stage = 'queued',
         error_code = 'worker_timeout',
         error_message = 'Processing stopped before it finished.',
         locked_at = null,
         locked_by = null,
         next_attempt_at = now(),
         finished_at = case when attempts >= max_attempts then now() else null end,
         updated_at = now()
   where status = 'processing'
     and locked_at < now() - make_interval(secs => greatest(p_stale_seconds, 60));

  select count(*) into running from public.immersion_jobs where status = 'processing';
  free_slots := greatest(0, least(greatest(p_max_concurrency, 1), 10) - running);
  if free_slots = 0 then
    return;
  end if;

  return query
  update public.immersion_jobs j
     set status = 'processing',
         stage = 'checking',
         attempts = j.attempts + 1,
         locked_at = now(),
         locked_by = left(p_worker, 64),
         updated_at = now()
   where j.id in (
     select q.id
       from public.immersion_jobs q
      where q.status = 'queued' and q.next_attempt_at <= now()
      order by q.next_attempt_at, q.created_at
      limit free_slots
      for update skip locked
   )
  returning j.*;
end;
$$;

revoke all on function public.claim_immersion_jobs(text, int, int) from public, anon, authenticated;
grant execute on function public.claim_immersion_jobs(text, int, int) to service_role;

-- Drain the queue every minute. Same Vault secrets as fill-catalog (project_url, catalog_bearer, admin_token).
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

do $$
declare
  existing bigint;
begin
  select jobid into existing from cron.job where jobname = 'immersion-worker';
  if existing is not null then
    perform cron.unschedule(existing);
  end if;
end $$;

select cron.schedule(
  'immersion-worker',
  '* * * * *',
  $cron$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
      || '/functions/v1/immersion-worker',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'catalog_bearer'),
      'x-admin-token', (select decrypted_secret from vault.decrypted_secrets where name = 'admin_token')
    ),
    body := '{"source":"cron"}'::jsonb,
    timeout_milliseconds := 150000
  )
  where exists (
    select 1 from public.immersion_jobs
    where (status = 'queued' and next_attempt_at <= now()) or status = 'processing'
  );
  $cron$
);
