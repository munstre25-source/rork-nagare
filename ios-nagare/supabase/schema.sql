-- Nagare clip library. The app reads: GET /rest/v1/clips?published=eq.true&select=*
create table if not exists public.clips (
  id text primary key,
  video_id text not null,            -- 11-char YouTube ID (never re-host video)
  title text not null,
  channel_name text not null,
  category text not null check (category in ('anime','drama','variety','vtuber','interview','kids','gaming')),
  difficulty text not null check (difficulty in ('Beginner','Intermediate','Advanced')),
  duration_sec numeric not null,
  lines jsonb not null,              -- [{ tokens:[Token], translation, start, end }]
  published boolean not null default false,
  channel_avatar_color text,         -- optional "#RRGGBB"
  thumbnail_gradient jsonb,          -- optional ["#hex","#hex","#hex"]
  created_at timestamptz not null default now()
);

alter table public.clips enable row level security;
create policy "public read published clips" on public.clips
  for select using (published = true);

-- Example row (one line). Token fields match Nagare/Models/Clip.swift.
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
