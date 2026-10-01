-- Clients may only read published clips (RLS). Writes go through service-role Edge Functions.
revoke all on table public.clips from public, anon, authenticated;
grant select on table public.clips to anon, authenticated;
