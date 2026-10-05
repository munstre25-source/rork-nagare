-- Publish one new YouTube clip every 3 hours.
-- The video file stays on YouTube. This job only stores the id and the transcript.
--
-- Before the job can authenticate, store these once in Vault (SQL editor):
--   select vault.create_secret('https://<project-ref>.supabase.co', 'project_url');
--   select vault.create_secret('<ADMIN_TOKEN>', 'admin_token');
-- The token is the same value as the Edge Function secret ADMIN_TOKEN.
-- Do not commit either value.

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

do $$
declare
  existing bigint;
begin
  select jobid into existing from cron.job where jobname = 'fill-jojo-catalog';
  if existing is not null then
    perform cron.unschedule(existing);
  end if;
end $$;

select cron.schedule(
  'fill-jojo-catalog',
  '0 */3 * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
      || '/functions/v1/fill-catalog',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-admin-token', (select decrypted_secret from vault.decrypted_secrets where name = 'admin_token')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 150000
  );
  $$
);
