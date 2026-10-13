-- Lets fill-catalog store the cron URL and token in Vault.
-- Callable only by the service role. Values are never returned.

create or replace function public.upsert_vault_secret(secret_name text, secret_value text)
returns void
language plpgsql
security definer
set search_path = vault, public
as $$
declare
  existing uuid;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'forbidden';
  end if;
  if secret_name is null or secret_name !~ '^[a-z_]{3,40}$' then
    raise exception 'invalid name';
  end if;
  if secret_value is null or length(secret_value) < 8 or length(secret_value) > 4000 then
    raise exception 'invalid value';
  end if;
  select id into existing from vault.secrets where name = secret_name limit 1;
  if existing is null then
    perform vault.create_secret(secret_value, secret_name);
  else
    perform vault.update_secret(existing, secret_value, secret_name);
  end if;
end;
$$;

revoke all on function public.upsert_vault_secret(text, text) from public, anon, authenticated;
grant execute on function public.upsert_vault_secret(text, text) to service_role;
