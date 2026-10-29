-- Keep non-embeddable videos out of the Japanese and Korean client catalogs.
-- Reuses the project_url, catalog_bearer, and admin_token secrets set by the
-- existing catalog cron setup.

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

do $$
declare
  existing bigint;
begin
  select jobid into existing from cron.job where jobname = 'audit-youtube-embeds';
  if existing is not null then
    perform cron.unschedule(existing);
  end if;
end $$;

select cron.schedule(
  'audit-youtube-embeds',
  '*/30 * * * *',
  $cron$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
      || '/functions/v1/audit-embeds',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'catalog_bearer'),
      'x-admin-token', (select decrypted_secret from vault.decrypted_secrets where name = 'admin_token')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 150000
  );
  $cron$
);
