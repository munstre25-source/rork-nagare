alter table public.catalog_candidate_queue drop constraint if exists catalog_candidate_queue_pkey;
alter table public.catalog_candidate_queue add primary key (video_id);
alter table public.catalog_candidate_queue drop column if exists window_start_sec;
alter table public.sori_candidate_queue drop constraint if exists sori_candidate_queue_pkey;
alter table public.sori_candidate_queue add primary key (video_id);
alter table public.sori_candidate_queue drop column if exists window_start_sec;
drop index if exists public.catalog_candidate_queue_added_idx;
drop index if exists public.sori_candidate_queue_added_idx;
drop index if exists public.catalog_rejections_video_idx;
