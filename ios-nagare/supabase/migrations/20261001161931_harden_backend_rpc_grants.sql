-- Harden service-role-only RPCs and internal tables.
-- Clients must not call rate/quota helpers or read cache/quota tables.

revoke all on function public.increment_explain_rate(text, date, text, int) from public, anon, authenticated;
revoke all on function public.increment_gemini_usage(date, int) from public, anon, authenticated;
revoke all on function public.consume_youtube_quota(date, int, int) from public, anon, authenticated;
grant execute on function public.increment_explain_rate(text, date, text, int) to service_role;
grant execute on function public.increment_gemini_usage(date, int) to service_role;
grant execute on function public.consume_youtube_quota(date, int, int) to service_role;

revoke all on table public.word_explanations from public, anon, authenticated;
revoke all on table public.explain_rate_buckets from public, anon, authenticated;
revoke all on table public.gemini_daily_usage from public, anon, authenticated;
revoke all on table public.revenuecat_entitlement_cache from public, anon, authenticated;
revoke all on table public.youtube_quota_usage from public, anon, authenticated;

-- App reads published clips via anon key + RLS policy; no client writes.
revoke all on table public.clips from public, anon, authenticated;
grant select on table public.clips to anon, authenticated;
