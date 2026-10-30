-- Rollback of 20261030150000_line_search_and_grammar.sql
drop function if exists public.search_clip_lines(text, integer, integer);
drop function if exists public.search_grammar_lines(text, integer, integer);
drop function if exists public.line_kana(jsonb);
drop function if exists public.line_romaji(jsonb);
drop function if exists public.ja_to_hiragana(text);
drop table if exists public.grammar_patterns;
