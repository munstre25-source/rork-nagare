-- Learner-owned data, keyed to the app's anonymous Supabase Auth session.
-- Additive only. Rollback: drop table public.practice_attempts, public.user_vocab;

create table if not exists public.user_vocab (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  term text not null check (char_length(term) between 1 and 64),
  reading text not null default '' check (char_length(reading) <= 64),
  surface text check (char_length(surface) <= 64),
  romaji text check (char_length(romaji) <= 128),
  pos text check (char_length(pos) <= 40),
  jlpt text check (jlpt is null or jlpt in ('N5', 'N4', 'N3', 'N2', 'N1')),
  definitions jsonb not null default '[]'::jsonb check (jsonb_typeof(definitions) = 'array'),
  context_sentence text check (char_length(context_sentence) <= 400),
  context_translation text check (char_length(context_translation) <= 400),
  context_note text check (char_length(context_note) <= 600),
  clip_id text check (char_length(clip_id) <= 120),
  line_index int check (line_index >= 0),
  encounter_count int not null default 1 check (encounter_count >= 0),
  srs_state text not null default 'new' check (srs_state in ('new', 'learning', 'familiar', 'easy', 'known')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_vocab_user_term_reading_key unique (user_id, term, reading)
);

create index if not exists user_vocab_user_updated_idx on public.user_vocab (user_id, updated_at desc);

alter table public.user_vocab enable row level security;
revoke all on table public.user_vocab from public, anon, authenticated;
grant select, insert, update, delete on table public.user_vocab to authenticated;

drop policy if exists "own vocab select" on public.user_vocab;
create policy "own vocab select" on public.user_vocab
  for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "own vocab insert" on public.user_vocab;
create policy "own vocab insert" on public.user_vocab
  for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists "own vocab update" on public.user_vocab;
create policy "own vocab update" on public.user_vocab
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
drop policy if exists "own vocab delete" on public.user_vocab;
create policy "own vocab delete" on public.user_vocab
  for delete to authenticated using (user_id = (select auth.uid()));

-- Speaking practice. `similarity` is how closely on-device speech recognition's text
-- matched the target line (0-100). It is not a phonetic pronunciation score.
create table if not exists public.practice_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  clip_id text not null check (char_length(clip_id) between 1 and 120),
  line_index int not null check (line_index >= 0),
  target_text text not null check (char_length(target_text) between 1 and 400),
  recognized_text text not null check (char_length(recognized_text) <= 400),
  similarity int not null check (similarity between 0 and 100),
  scoring_method text not null default 'recognition_similarity'
    check (scoring_method in ('recognition_similarity')),
  locale text not null default 'ja-JP' check (char_length(locale) <= 16),
  on_device boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists practice_attempts_user_created_idx
  on public.practice_attempts (user_id, created_at desc);
create index if not exists practice_attempts_user_clip_line_idx
  on public.practice_attempts (user_id, clip_id, line_index);

alter table public.practice_attempts enable row level security;
revoke all on table public.practice_attempts from public, anon, authenticated;
grant select, insert, delete on table public.practice_attempts to authenticated;

drop policy if exists "own practice select" on public.practice_attempts;
create policy "own practice select" on public.practice_attempts
  for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "own practice insert" on public.practice_attempts;
create policy "own practice insert" on public.practice_attempts
  for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists "own practice delete" on public.practice_attempts;
create policy "own practice delete" on public.practice_attempts
  for delete to authenticated using (user_id = (select auth.uid()));
