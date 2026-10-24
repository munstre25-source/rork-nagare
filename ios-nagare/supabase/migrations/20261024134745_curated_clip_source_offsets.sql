-- Store where a curated excerpt begins in its original YouTube source.
-- Existing rows represent playback from the beginning of the source.
alter table public.clips
  add column if not exists source_start_sec numeric not null default 0;

alter table public.sori_clips
  add column if not exists source_start_sec numeric not null default 0;
