-- Public request board and private one-to-one messages. Service role only.

create table if not exists public.feedback_posts (
  id bigint generated always as identity primary key,
  app_user_id text not null,
  category text not null check (category in ('bug','feature','general')),
  title text not null check (char_length(title) between 1 and 80),
  body text not null check (char_length(body) between 1 and 1000),
  status text not null default 'open' check (status in ('open','planned','done','hidden')),
  vote_count int not null default 0 check (vote_count >= 0),
  comment_count int not null default 0 check (comment_count >= 0),
  created_at timestamptz not null default now()
);
alter table public.feedback_posts enable row level security;
create index if not exists feedback_posts_board_idx on public.feedback_posts (vote_count desc, created_at desc);
create index if not exists feedback_posts_category_idx on public.feedback_posts (category, vote_count desc);

create table if not exists public.feedback_votes (
  post_id bigint not null references public.feedback_posts (id) on delete cascade,
  app_user_id text not null,
  created_at timestamptz not null default now(),
  primary key (post_id, app_user_id)
);
alter table public.feedback_votes enable row level security;
create index if not exists feedback_votes_post_idx on public.feedback_votes (post_id);

create table if not exists public.feedback_comments (
  id bigint generated always as identity primary key,
  post_id bigint not null references public.feedback_posts (id) on delete cascade,
  app_user_id text not null,
  body text not null check (char_length(body) between 1 and 500),
  created_at timestamptz not null default now()
);
alter table public.feedback_comments enable row level security;
create index if not exists feedback_comments_post_idx on public.feedback_comments (post_id, created_at);

alter table public.insight_rate_buckets drop constraint if exists insight_rate_buckets_kind_check;
alter table public.insight_rate_buckets
  add constraint insight_rate_buckets_kind_check
  check (kind in ('acquisition','feedback','board','inbox'));

create table if not exists public.direct_messages (
  id bigint generated always as identity primary key,
  app_user_id text not null,
  sender text not null check (sender in ('user','jojo')),
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);
alter table public.direct_messages enable row level security;
create index if not exists direct_messages_user_idx on public.direct_messages (app_user_id, created_at);

revoke all on table public.direct_messages from anon, authenticated;
grant all on table public.direct_messages to service_role;
revoke all on table public.feedback_posts from anon, authenticated;
revoke all on table public.feedback_votes from anon, authenticated;
revoke all on table public.feedback_comments from anon, authenticated;
grant all on table public.feedback_posts to service_role;
grant all on table public.feedback_votes to service_role;
grant all on table public.feedback_comments to service_role;
grant usage, select on all sequences in schema public to service_role;;
