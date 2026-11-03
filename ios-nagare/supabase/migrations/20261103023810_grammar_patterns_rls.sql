-- grammar_patterns is a public seed table: clients may read, never write.
-- Without RLS the SELECT grant alone still left the table open to writes via the anon key.
alter table public.grammar_patterns enable row level security;

drop policy if exists grammar_patterns_read on public.grammar_patterns;
create policy grammar_patterns_read on public.grammar_patterns
  for select to anon, authenticated
  using (true);

revoke insert, update, delete on table public.grammar_patterns from anon, authenticated;
grant select on table public.grammar_patterns to anon, authenticated;
