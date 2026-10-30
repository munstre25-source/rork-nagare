-- Store the actual YouTube player frame orientation so feed layouts can match it.
-- Landscape uploads that contain portrait footage remain landscape and are not cropped.
alter table public.clips
  add column if not exists video_orientation text not null default 'landscape'
  check (video_orientation in ('portrait', 'landscape'));

alter table public.sori_clips
  add column if not exists video_orientation text not null default 'landscape'
  check (video_orientation in ('portrait', 'landscape'));
