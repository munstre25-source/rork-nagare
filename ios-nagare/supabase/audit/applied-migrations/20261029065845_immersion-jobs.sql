-- Immersion engine: a durable queue for turning a YouTube video into a timed lesson.
-- Additive only.

create table if not exists public.immersion_jobs (
  id uuid primary key default gen_random_uuid(),
  video_id text not null check (video_id ~ '^[A-Za-z0-9_-]{11}$'),
  language text not null default 'ja' check (language in ('ja')),
  status text not null default 'queued'
    check (status in ('queued', 'processing', 'succeeded', 'failed', 'unprocessable')),
  stage text not null default 'queued'
    check (stage in ('queued', 'checking', 'transcribing', 'validating', 'enriching', 'publishing', 'done')),
  scan_offset_sec numeric not null default 0 check (scan_offset_sec >= 0),
  windows_scanned int not null default 0 check (windows_scanned >= 0),
  attempts int not null default 0 check (attempts >= 0),
  max_attempts int not null default 3 check (max_attempts between 1 and 10),
  next_attempt_at timestamptz not null default now(),
  locked_at timestamptz,
  locked_by text,
  error_code text,
  error_message text,
  title text,
  channel_name text,
  video_duration_sec numeric,
  clip_id text references public.clips (id) on delete set null,
  model text,
  prompt_version text,
  timing_mode text check (timing_mode in ('word', 'line', 'mixed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  finished_at timestamptz,
  constraint immersion_jobs_video_language_key unique (video_id, language)
);

create index if not exists immersion_jobs_ready_idx
  on public.immersion_jobs (next_attempt_at)
  where status = 'queued';
create index if not exists immersion_jobs_processing_idx
  on public.immersion_jobs (locked_at)
  where status = 'processing';
create index if not exists immersion_jobs_clip_id_idx on public.immersion_jobs (clip_id);

create table if not exists public.immersion_job_requests (
  job_id uuid not null references public.immersion_jobs (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (job_id, user_id)
);

create index if not exists immersion_job_requests_user_idx
  on public.immersion_job_requests (user_id, created_at desc);

alter table public.immersion_jobs enable row level security;
alter table public.immersion_job_requests enable row level security;

revoke all on table public.immersion_jobs from public, anon, authenticated;
revoke all on table public.immersion_job_requests from public, anon, authenticated;
grant select on table public.immersion_jobs to authenticated;
grant select on table public.immersion_job_requests to authenticated;

drop policy if exists "requesters read their requests" on public.immersion_job_requests;
create policy "requesters read their requests" on public.immersion_job_requests
  for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "requesters read their jobs" on public.immersion_jobs;
create policy "requesters read their jobs" on public.immersion_jobs
  for select to authenticated
  using (exists (
    select 1 from public.immersion_job_requests r
    where r.job_id = immersion_jobs.id and r.user_id = (select auth.uid())
  ));

alter table public.clips add column if not exists timing_mode text
  check (timing_mode in ('word', 'line', 'mixed'));
alter table public.clips add column if not exists model text;
alter table public.clips add column if not exists prompt_version text;

drop policy if exists "requesters read their clips" on public.clips;
create policy "requesters read their clips" on public.clips
  for select to authenticated
  using (exists (
    select 1
    from public.immersion_jobs j
    join public.immersion_job_requests r on r.job_id = j.id
    where j.clip_id = clips.id and r.user_id = (select auth.uid())
  ));
;
