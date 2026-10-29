-- Nagare clip library + backend cache/quota.
-- Prefer applying migrations from ios-nagare/: supabase db push
-- The app reads: GET /rest/v1/clips?published=eq.true&select=*
--
-- Immersion engine (source of truth: migrations/20261029120000..120200):
--   immersion_jobs       shared per-video pipeline job (queued/processing/succeeded/failed/unprocessable),
--                        stage, attempts, lease, next_attempt_at, error_code, timing_mode, clip_id -> clips.id
--   immersion_job_requests (user_id, job_id) link; RLS: a learner sees only jobs they requested
--   user_vocab           anonymous user's mirrored deck; unique (user_id, term, reading); RLS owner-only
--   practice_attempts    speaking tries; scoring_method = 'recognition_similarity' (text match, not
--                        pronunciation); RLS owner-only; user_id defaults to auth.uid()
--   clips                + timing_mode, model, prompt_version; learner clips stay published=false
--                        and are readable only by requesters (policy "requesters read their clips")
--   claim_immersion_jobs(text,int,int) RPC (service_role only) + pg_cron 'immersion-worker' every minute
-- All user rows cascade on auth.users delete (delete-my-data function).
--
-- Analytics + feedback v2 (source of truth: migrations/20261029140000_analytics_and_feedback_v2.sql):
--   analytics_events     first-party events keyed by install_id (+ user_id when signed in); unique
--                        (install_id, event_id) dedupe; no client access (RLS, no policies); 395-day cron purge
--   analytics_sessions   per-install session summaries (active seconds only)
--   analytics_ingest(jsonb) RPC (service_role) used by the analytics-ingest function
--   feedback_items       private inbox (+ user_id, source, is_anonymous, app/os version, build, device_class)
--   feedback_posts       public board (+ held, report_count, moderated_at); feedback_reports one per identity
--   feedback_board_page / feedback_toggle_vote / feedback_report_post RPCs (service_role)
--   admin_dashboard_metrics(int) RPC read by the token-gated admin-dashboard function

create table if not exists public.clips (
  id text primary key,
  video_id text not null,            -- 11-char YouTube ID (never re-host video)
  title text not null,
  channel_name text not null,
  category text not null check (category in ('anime','drama','variety','vtuber','interview','kids','gaming')),
  difficulty text not null check (difficulty in ('Beginner','Intermediate','Advanced')),
  source_start_sec numeric not null default 0,
  duration_sec numeric not null,
  lines jsonb not null,              -- [{ tokens:[Token], translation, start, end }]
  published boolean not null default false,
  channel_avatar_color text,         -- optional "#RRGGBB"
  thumbnail_gradient jsonb,          -- optional ["#hex","#hex","#hex"]
  created_at timestamptz not null default now()
);

alter table public.clips enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'clips' and policyname = 'public read published clips'
  ) then
    create policy "public read published clips" on public.clips
      for select using (published = true);
  end if;
end $$;

create index if not exists clips_video_id_idx on public.clips (video_id);

-- Korean catalog. Sori reads this table. Jojo keeps reading public.clips.
create table if not exists public.sori_clips (
  id text primary key,
  video_id text not null,
  title text not null,
  channel_name text not null,
  category text not null check (category in ('anime','drama','variety','vtuber','interview','kids','gaming')),
  difficulty text not null check (difficulty in ('Beginner','Intermediate','Advanced')),
  source_start_sec numeric not null default 0,
  duration_sec numeric not null,
  lines jsonb not null,
  published boolean not null default false,
  channel_avatar_color text,
  thumbnail_gradient jsonb,
  created_at timestamptz not null default now()
);

alter table public.sori_clips enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'sori_clips' and policyname = 'public read published sori clips'
  ) then
    create policy "public read published sori clips" on public.sori_clips
      for select
      to anon, authenticated
      using (published = true);
  end if;
end $$;

create index if not exists sori_clips_video_id_idx on public.sori_clips (video_id);
revoke all on table public.sori_clips from public, anon, authenticated;
grant select on table public.sori_clips to anon, authenticated;

-- Remembers which YouTube search page each catalog lane is on, so fill-catalog
-- walks past videos it already published.
create table if not exists public.catalog_search_cursors (
  lane_key text primary key,
  page_token text,
  variant int not null default 0,
  updated_at timestamptz not null default now()
);

create table if not exists public.catalog_fill_state (
  id int primary key check (id = 1),
  paused_until timestamptz,
  pause_reason text,
  updated_at timestamptz not null default now()
);

alter table public.catalog_fill_state enable row level security;
revoke all on table public.catalog_fill_state from public, anon, authenticated;

alter table public.catalog_search_cursors enable row level security;
revoke all on table public.catalog_search_cursors from public, anon, authenticated;

-- Service role stores the catalog cron URL and token. The function never returns them.
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

-- Shared explanation cache (service role only; no anon policies)
create table if not exists public.word_explanations (
  cache_key text primary key,
  kind text not null check (kind in ('lookup', 'context')),
  word text not null,
  sentence_hash text,
  payload jsonb not null,
  model text not null,
  prompt_version text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.word_explanations enable row level security;

create table if not exists public.explain_rate_buckets (
  app_user_id text not null,
  day_utc date not null,
  kind text not null check (kind in ('lookup', 'context')),
  count int not null default 0,
  primary key (app_user_id, day_utc, kind)
);
alter table public.explain_rate_buckets enable row level security;

create table if not exists public.gemini_daily_usage (
  day_utc date primary key,
  count int not null default 0
);
alter table public.gemini_daily_usage enable row level security;

create table if not exists public.revenuecat_entitlement_cache (
  app_user_id text primary key,
  entitled boolean not null,
  checked_at timestamptz not null default now()
);
alter table public.revenuecat_entitlement_cache enable row level security;

create table if not exists public.youtube_quota_usage (
  day_utc date primary key,
  units int not null default 0
);
alter table public.youtube_quota_usage enable row level security;

-- Atomic limit RPCs (service_role only)
create or replace function public.increment_explain_rate(
  p_app_user_id text,
  p_day_utc date,
  p_kind text,
  p_limit int
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  new_count int;
begin
  insert into public.explain_rate_buckets (app_user_id, day_utc, kind, count)
  values (p_app_user_id, p_day_utc, p_kind, 1)
  on conflict (app_user_id, day_utc, kind)
  do update set count = public.explain_rate_buckets.count + 1
  where public.explain_rate_buckets.count < p_limit
  returning count into new_count;
  if new_count is null then
    return false;
  end if;
  return true;
end;
$$;

create or replace function public.increment_gemini_usage(
  p_day_utc date,
  p_limit int
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  new_count int;
begin
  insert into public.gemini_daily_usage (day_utc, count)
  values (p_day_utc, 1)
  on conflict (day_utc)
  do update set count = public.gemini_daily_usage.count + 1
  where public.gemini_daily_usage.count < p_limit
  returning count into new_count;
  if new_count is null then
    return false;
  end if;
  return true;
end;
$$;

create or replace function public.consume_youtube_quota(
  p_day_utc date,
  p_units int,
  p_limit int
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  new_units int;
begin
  if p_units <= 0 then
    return true;
  end if;
  if p_units > p_limit then
    return false;
  end if;
  insert into public.youtube_quota_usage (day_utc, units)
  values (p_day_utc, p_units)
  on conflict (day_utc)
  do update set units = public.youtube_quota_usage.units + excluded.units
  where public.youtube_quota_usage.units + excluded.units <= p_limit
  returning units into new_units;
  if new_units is null then
    return false;
  end if;
  return true;
end;
$$;

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

-- Acquisition + feedback (service role via Edge Functions only)
create table if not exists public.acquisition_events (
  id bigint generated always as identity primary key,
  app_user_id text not null,
  source text not null check (source in ('instagram','tiktok','web_search','app_store','friend','youtube','other')),
  source_detail text,
  created_at timestamptz not null default now(),
  constraint acquisition_events_app_user_unique unique (app_user_id)
);
alter table public.acquisition_events enable row level security;

create table if not exists public.feedback_items (
  id bigint generated always as identity primary key,
  app_user_id text not null,
  enjoyed boolean,
  category text check (category is null or category in (
    'bug','feature','general',
    'cancel_price','cancel_time','cancel_content','cancel_hard','cancel_curious','cancel_other'
  )),
  message text not null default '',
  status text not null default 'new' check (status in ('new','reviewed','done')),
  created_at timestamptz not null default now()
);
alter table public.feedback_items enable row level security;

-- Public request board. app_user_id stays server-side; clients read through the feedback-board function.
create table if not exists public.feedback_posts (
  id bigint generated always as identity primary key,
  app_user_id text not null,
  category text not null check (category in ('bug','feature','general')),
  title text not null check (char_length(title) between 1 and 80),
  body text not null check (char_length(body) between 1 and 1000),
  status text not null default 'open' check (status in ('open','planned','done','hidden')),
  vote_count int not null default 0 check (vote_count >= 0),
  comment_count int not null default 0 check (comment_count >= 0),
  created_at timestamptz not null default now()
);
alter table public.feedback_posts enable row level security;
create index if not exists feedback_posts_board_idx on public.feedback_posts (vote_count desc, created_at desc);
create index if not exists feedback_posts_category_idx on public.feedback_posts (category, vote_count desc);

create table if not exists public.feedback_votes (
  post_id bigint not null references public.feedback_posts (id) on delete cascade,
  app_user_id text not null,
  created_at timestamptz not null default now(),
  primary key (post_id, app_user_id)
);
alter table public.feedback_votes enable row level security;
create index if not exists feedback_votes_post_idx on public.feedback_votes (post_id);

create table if not exists public.feedback_comments (
  id bigint generated always as identity primary key,
  post_id bigint not null references public.feedback_posts (id) on delete cascade,
  app_user_id text not null,
  body text not null check (char_length(body) between 1 and 500),
  created_at timestamptz not null default now()
);
alter table public.feedback_comments enable row level security;
create index if not exists feedback_comments_post_idx on public.feedback_comments (post_id, created_at);
revoke all on table public.feedback_posts from anon, authenticated;
revoke all on table public.feedback_votes from anon, authenticated;
revoke all on table public.feedback_comments from anon, authenticated;
grant all on table public.feedback_posts to service_role;
grant all on table public.feedback_votes to service_role;
grant all on table public.feedback_comments to service_role;

create table if not exists public.direct_messages (
  id bigint generated always as identity primary key,
  app_user_id text not null,
  sender text not null check (sender in ('user','jojo')),
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);
alter table public.direct_messages enable row level security;
create index if not exists direct_messages_user_idx on public.direct_messages (app_user_id, created_at);
revoke all on table public.direct_messages from anon, authenticated;
grant all on table public.direct_messages to service_role;

create table if not exists public.insight_rate_buckets (
  app_user_id text not null,
  day_utc date not null,
  kind text not null check (kind in ('acquisition','feedback','board','inbox')),
  count int not null default 0,
  primary key (app_user_id, day_utc, kind)
);
alter table public.insight_rate_buckets enable row level security;

revoke all on table public.clips from public, anon, authenticated;
grant select on table public.clips to anon, authenticated;

-- Example row (one line). Token fields match Jojo/Models/Clip.swift.
insert into public.clips (id, video_id, title, channel_name, category, difficulty, duration_sec, lines, published)
values ('example-01', 'dQw4w9WgXcQ', 'Example clip', 'Example Channel', 'drama', 'Beginner', 12,
 '[{"translation":"The weather''s nice today, isn''t it?","start":1.0,"end":4.2,"tokens":[
   {"surface":"今日","reading":"きょう","altReadings":["こんにち"],"romaji":"kyou","start":1.0,"end":1.6,"pos":"noun","jlpt":"N5","definitions":["today"],"tappable":true},
   {"surface":"は","romaji":"wa","start":1.6,"end":1.8,"pos":"particle","jlpt":"N5","definitions":["topic marker"],"tappable":true},
   {"surface":"天気","reading":"てんき","romaji":"tenki","start":1.8,"end":2.5,"pos":"noun","jlpt":"N5","definitions":["weather; the elements"],"tappable":true},
   {"surface":"が","romaji":"ga","start":2.5,"end":2.7,"pos":"particle","jlpt":"N5","definitions":["subject marker"],"tappable":true},
   {"surface":"いい","romaji":"ii","start":2.7,"end":3.2,"pos":"i-adjective","jlpt":"N5","definitions":["good; nice"],"tappable":true},
   {"surface":"です","romaji":"desu","start":3.2,"end":3.8,"pos":"copula","jlpt":"N5","definitions":["to be (polite)"],"formality":"polite","tappable":true},
   {"surface":"ね","romaji":"ne","start":3.8,"end":4.2,"pos":"particle","jlpt":"N5","definitions":["right?; isn''t it?"],"tappable":true}
 ]}]'::jsonb, false)
on conflict (id) do nothing;
