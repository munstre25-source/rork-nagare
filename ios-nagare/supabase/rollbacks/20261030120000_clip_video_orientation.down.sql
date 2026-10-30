-- Rollback for 20261030120000_clip_video_orientation.sql
alter table public.clips drop column if exists video_orientation;
alter table public.sori_clips drop column if exists video_orientation;
delete from supabase_migrations.schema_migrations where version = '20261030120000';
