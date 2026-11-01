alter table public.clips drop constraint if exists clips_category_check;
alter table public.clips add constraint clips_category_check
  check (category in ('anime', 'drama', 'variety', 'vtuber', 'interview', 'kids', 'gaming'));
alter table public.sori_clips drop constraint if exists sori_clips_category_check;
alter table public.sori_clips add constraint sori_clips_category_check
  check (category in ('anime', 'drama', 'variety', 'vtuber', 'interview', 'kids', 'gaming'));
