-- Revoke client access to service-role-only helpers and internal tables.
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

-- App needs to read published clips via anon key + RLS policy.
grant select on table public.clips to anon, authenticated;;
