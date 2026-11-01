-- A source video may yield several independently checked 90-second lesson windows.
alter table public.catalog_candidate_queue
  add column if not exists window_start_sec integer not null default 0
  check (window_start_sec >= 0);
alter table public.catalog_candidate_queue
  drop constraint if exists catalog_candidate_queue_pkey;
alter table public.catalog_candidate_queue
  add primary key (video_id, window_start_sec);

alter table public.sori_candidate_queue
  add column if not exists window_start_sec integer not null default 0
  check (window_start_sec >= 0);
alter table public.sori_candidate_queue
  drop constraint if exists sori_candidate_queue_pkey;
alter table public.sori_candidate_queue
  add primary key (video_id, window_start_sec);

create index if not exists catalog_candidate_queue_added_idx
  on public.catalog_candidate_queue (added_at);
create index if not exists sori_candidate_queue_added_idx
  on public.sori_candidate_queue (added_at);
create index if not exists catalog_rejections_video_idx
  on public.catalog_rejections (video_id);
