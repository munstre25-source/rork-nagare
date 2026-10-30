-- Kiku-style search across the whole catalog, on the server.
--
-- The phone only downloads published clips it has seen, so its local search misses
-- most of the library. These RPCs scan every published clip's transcript lines and
-- return matching lines together with the clip row, so the app can open the clip
-- directly at the matching line. Grammar patterns are matched with surface suffixes
-- (〜たい, 〜てしまう, …) over the same index.
--
-- Matches are computed on the fly from clips.lines (jsonb). At a few thousand clips
-- this is a fast sequential scan; pg_trgm indexes can be added when it grows past that.
-- Reversible: see supabase/rollbacks/20261030150000_line_search_and_grammar.down.sql

create table if not exists public.grammar_patterns (
  id text primary key,
  title text not null,
  meaning text not null,
  jlpt text,
  -- Any of these substrings in the spoken line counts as a match (e.g. てしまう, ちゃう).
  surface_match text[] not null default '{}',
  -- Any of these substrings in the line's kana reading counts as a match.
  kana_match text[] not null default '{}',
  sort integer not null default 100
);

comment on table public.grammar_patterns is 'Grammar points searchable by pattern; rows seeded in this migration, edited only by new migrations.';

-- Katakana → hiragana so readings match the learner's hiragana query.
create or replace function public.ja_to_hiragana(t text) returns text
language sql immutable parallel safe
as $$
  select translate(
    t,
    'ァアィイゥウェエォオカガキギクグケゲコゴサザシジスズセゼソゾタダチヂツヅテデトドナニヌネノハバパヒビピフブプヘベペホボポマミムメモャヤュユョヨラリルレロヮワヰヱヲンヴヵヶ',
    'ぁあぃいうゔえぉおかがきぎくぐけげこごさざしじすずせぜそぞただちぢつづてでとどなにぬねのはばぱひびぴふぶへべぺほぼぽまみむめもゃやゅゆょよらりるれろゎわゐゑをんゔゕゖ'
  );
$$;

-- The line's kana: each token's reading, else its base reading, else the surface itself.
create or replace function public.line_kana(line jsonb) returns text
language sql immutable parallel safe
as $$
  select public.ja_to_hiragana(string_agg(
    coalesce(token->>'reading', token->>'baseReading', token->>'surface', ''),
    ''
  ) )
  from jsonb_array_elements(coalesce(line->'tokens', '[]'::jsonb)) as token;
$$;

-- The line's romaji, lowercased and without spaces, for romaji queries.
create or replace function public.line_romaji(line jsonb) returns text
language sql immutable parallel safe
as $$
  select lower(string_agg(coalesce(token->>'romaji', ''), ''))
  from jsonb_array_elements(coalesce(line->'tokens', '[]'::jsonb)) as token;
$$;

-- Word / phrase search: kanji or kana inside the spoken text or its reading; ASCII
-- queries match the romaji (spaces ignored). Returns the matching line with its clip.
create or replace function public.search_clip_lines(
  p_query text,
  p_max_results integer default 24,
  p_offset integer default 0
) returns table (clip_row jsonb, line_index integer)
language sql
security definer
set search_path = public, pg_catalog
stable
as $$
  with q as (
    select
      lower(trim(p_query)) as raw,
      regexp_replace(lower(trim(p_query)), '\s+', '', 'g') as packed,
      public.ja_to_hiragana(trim(p_query)) as hq
  ),
  lines as (
    select c.id as clip_id, to_jsonb(c) as row, ordinality - 1 as line_index, line.value as line, q.*
    from public.clips c
    cross join lateral jsonb_array_elements(c.lines) with ordinality as line
    cross join q
    where c.published and jsonb_typeof(c.lines) = 'array'
  )
  select distinct on (l.clip_id, l.line_index)
    l.row, l.line_index
  from lines l
  where (
    (l.hq <> '' and l.raw !~ '^[\x00-\x7F]+$' and (
      coalesce(l.line->>'text', '') like '%' || l.raw || '%'
      or coalesce(public.line_kana(l.line), '') like '%' || l.hq || '%'
    ))
    or
    (l.raw !~ '^[\x00-\x7F]+$' and coalesce(l.line->>'translation', '') ilike '%' || l.raw || '%')
    or
    (l.packed ~ '^[\x00-\x7F]+$' and length(l.packed) >= 2 and
      coalesce(public.line_romaji(l.line), '') like '%' || l.packed || '%')
  )
  order by l.clip_id, l.line_index, length(coalesce(l.line->>'text', ''))
  limit greatest(1, least(p_max_results, 50))
  offset greatest(0, p_offset);
$$;

-- Grammar search: every line whose spoken text or reading contains one of the
-- pattern's substrings, newest clip first.
create or replace function public.search_grammar_lines(
  p_pattern_id text,
  p_max_results integer default 24,
  p_offset integer default 0
) returns table (clip_row jsonb, line_index integer, pattern_id text)
language sql
security definer
set search_path = public, pg_catalog
stable
as $$
  with p as (select * from public.grammar_patterns where id = p_pattern_id),
  lines as (
    select c.id as clip_id, to_jsonb(c) as row, ordinality - 1 as line_index, line.value as line
    from public.clips c
    cross join lateral jsonb_array_elements(c.lines) with ordinality as line
    cross join p
    where c.published and jsonb_typeof(c.lines) = 'array'
  )
  select distinct on (l.clip_id, l.line_index)
    l.row, l.line_index, p.id
  from lines l cross join p
  where exists (
    select 1 from unnest(p.surface_match) s
    where coalesce(l.line->>'text', '') like '%' || s || '%'
  ) or exists (
    select 1 from unnest(p.kana_match) k
    where coalesce(public.line_kana(l.line), '') like '%' || k || '%'
  )
  order by l.clip_id, l.line_index
  limit greatest(1, least(p_max_results, 50))
  offset greatest(0, p_offset);
$$;

-- Public read: these RPCs only ever return published clips.
revoke all on function public.search_clip_lines(text, integer, integer) from public;
grant execute on function public.search_clip_lines(text, integer, integer) to anon, authenticated;
revoke all on function public.search_grammar_lines(text, integer, integer) from public;
grant execute on function public.search_grammar_lines(text, integer, integer) to anon, authenticated;

revoke all on table public.grammar_patterns from anon, authenticated;
grant select on table public.grammar_patterns to anon, authenticated;

-- Grammar points a learner actually looks for, roughly JLPT order.
insert into public.grammar_patterns (id, title, meaning, jlpt, surface_match, kana_match, sort) values
  ('tai',        '〜たい',              'want to do',                       'N5', '{たい}', '{たい}', 10),
  ('temoii',     '〜てもいい',          'may, is okay to',                  'N5', '{てもいい}', '{てもいい}', 11),
  ('tekudasai',  '〜てください',        'please do',                        'N5', '{てください}', '{てください}', 12),
  ('nakereba',   '〜なければならない',  'must, have to',                    'N5', '{なければならない,なきゃ,ないと}', '{なければならない,なきゃ,ないと}', 13),
  ('tari',       '〜たり〜たり',        'doing things like',                'N5', '{たり}', '{たり}', 14),
  ('nagara',     '〜ながら',            'while doing',                      'N5', '{ながら}', '{ながら}', 15),
  ('tara',       '〜たら',              'if / when',                        'N5', '{たら}', '{たら}', 16),
  ('tokoro',     '〜ところ',            'about to / just did',              'N4', '{ところ}', '{ところ}', 20),
  ('teshimau',   '〜てしまう / 〜ちゃう', 'finish doing; do by accident',    'N4', '{てしまう,ちゃう,ちまう,てしまった}', '{てしまう,ちゃう,ちまう}', 21),
  ('teoku',      '〜ておく',            'do in advance',                    'N4', '{ておく,とく}', '{ておく,とく}', 22),
  ('temiru',     '〜てみる',            'try doing',                        'N4', '{てみる,てみて,てみた}', '{てみる,てみて,てみた}', 23),
  ('teiku',      '〜ていく / 〜てくる', 'change over time; come and do',    'N4', '{ていく,てくる,ていった,てきた}', '{ていく,てくる,ていった,てきた}', 24),
  ('rashii',     '〜らしい / 〜そうだ', 'hearsay, appearance',              'N4', '{らしい,そうだ,って}', '{らしい,そうだ}', 25),
  ('hazudesu',   '〜はず',              'supposed to, expected',            'N4', '{はず}', '{はず}', 26),
  ('kamoshirenai','〜かもしれない',     'might, maybe',                     'N4', '{かもしれない,かも}', '{かもしれない,かも}', 27),
  ('tsumori',    '〜つもり',            'intend to',                        'N4', '{つもり}', '{つもり}', 28),
  ('sugiru',     '〜すぎる',            'too much',                         'N4', '{すぎる,すぎた,すぎて}', '{すぎる,すぎた,すぎて}', 29),
  ('yasui',      '〜やすい / 〜にくい', 'easy to / hard to do',             'N4', '{やすい,にくい}', '{やすい,にくい}', 30),
  ('saseru',     '〜させる / 〜られる', 'causative and passive',            'N4', '{させる,られる,された,させた}', '{させる,られる,された,させた}', 31),
  ('tekureru',   '〜てくれる / 〜てもらう', 'do for someone',               'N4', '{てくれる,てもらう,てあげる,てくれた}', '{てくれる,てもらう,てあげる,てくれた}', 32),
  ('youtoomou',  '〜ようと思う',        'think I will',                     'N3', '{ようと思う,ようと思って,ようと思った}', '{ようとおもう,ようとおもって,ようとおもった}', 40),
  ('younisuru',  '〜ようにする',        'make a habit of; arrange to',      'N3', '{ようにする,ようにして,ようにした}', '{ようにする,ようにして,ようにした}', 41),
  ('tame',       '〜ため(に)',          'for the sake of; because',         'N3', '{ため}', '{ため}', 42),
  ('tabini',     '〜たび(に)',          'every time',                       'N3', '{たびに}', '{たびに}', 43),
  ('kotonisuru', '〜ことにする / 〜ことにしている', 'decide to; make a rule of', 'N3', '{ことにする,ことにして,ことにしている}', '{ことにする,ことにして,ことにしている}', 44),
  ('wake',       '〜わけ',              'reason; no wonder',                'N3', '{わけ}', '{わけ}', 45),
  ('bayoroshii', '〜ばよかった',        'should have (regret)',             'N3', '{ばよかった}', '{ばよかった}', 46),
  ('sae',        '〜さえ',              'even',                             'N2', '{さえ}', '{さえ}', 50),
  ('ue',         '〜上(に)',            'on top of, moreover',              'N2', '{上に}', '{うえに}', 51),
  ('kka',        '〜っけ',              'was it again? (recall)',           'N2', '{っけ}', '{っけ}', 52)
on conflict (id) do nothing;
