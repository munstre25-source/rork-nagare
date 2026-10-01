-- Cheap ingress rate limit for explain-word (before RevenueCat calls).
-- Buckets are per-minute; keys are opaque (ip hash or jwt sub).

create table if not exists public.explain_ingress_buckets (
  bucket_key text not null,
  window_start timestamptz not null,
  count int not null default 0,
  primary key (bucket_key, window_start)
);

alter table public.explain_ingress_buckets enable row level security;

revoke all on table public.explain_ingress_buckets from public, anon, authenticated;

create or replace function public.increment_explain_ingress(
  p_bucket_key text,
  p_window_start timestamptz,
  p_limit int
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  new_count int;
begin
  insert into public.explain_ingress_buckets (bucket_key, window_start, count)
  values (p_bucket_key, p_window_start, 1)
  on conflict (bucket_key, window_start)
  do update set count = public.explain_ingress_buckets.count + 1
  where public.explain_ingress_buckets.count < p_limit
  returning count into new_count;

  if new_count is null then
    return false;
  end if;
  return true;
end;
$$;

revoke all on function public.increment_explain_ingress(text, timestamptz, int) from public, anon, authenticated;
grant execute on function public.increment_explain_ingress(text, timestamptz, int) to service_role;
