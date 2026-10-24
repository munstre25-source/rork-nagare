create table if not exists public.sori_clips (
  id text primary key,
  video_id text not null,
  title text not null,
  channel_name text not null,
  category text not null check (category in ('anime','drama','variety','vtuber','interview','kids','gaming')),
  difficulty text not null check (difficulty in ('Beginner','Intermediate','Advanced')),
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
grant select on table public.sori_clips to anon, authenticated;;
