-- Caption-tier publication: creator-uploaded YouTube captions + local tokenization,
-- no Gemini. The existing v3 AI review path stays untouched.

alter table public.clips
  add column if not exists review_tier text not null default 'ai_v3'
  check (review_tier in ('ai_v3', 'caption'));

create index if not exists clips_review_tier_idx on public.clips (review_tier)
  where published;

alter table public.catalog_sources
  add column if not exists caption_tier_ok boolean not null default false;

-- Caption receipt: every line carries translationReview.version = 'caption-1' with
-- matching hashes, category, and source bounds. No visual/audio Gemini fields required.
-- databaseHash reuses catalog_review_hash so the seal matches the stored lines payload.
create or replace function public.catalog_caption_receipt_ok(
  p_video_id text,
  p_start numeric,
  p_duration numeric,
  p_lines jsonb,
  p_category text
) returns boolean
language plpgsql
immutable
security invoker
set search_path = ''
as $body$
declare
  expected_hash text;
begin
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' then return false; end if;
  if jsonb_array_length(p_lines) < 4 then return false; end if;
  if p_duration is null or p_duration < 6 or p_duration > 120 then return false; end if;
  if coalesce(p_category, '') not in (
    'anime','drama','variety','vtuber','interview','kids','gaming','learning','podcast'
  ) then
    return false;
  end if;

  expected_hash := public.catalog_review_hash(p_video_id, p_start, p_duration, p_lines);

  return not exists (
    select 1 from jsonb_array_elements(p_lines) l where
      coalesce(l->'translationReview'->>'version', '') <> 'caption-1'
      or coalesce(l->'translationReview'->>'sourceTrack', '') <> 'creator-manual'
      or coalesce(l->'translationReview'->>'sourceHash', '') !~ '^[a-f0-9]{64}$'
      or coalesce(l->'translationReview'->>'databaseHash', '') <> expected_hash
      or coalesce(l->'translationReview'->>'videoId', '') <> p_video_id
      or l->'translationReview'->'sourceStartSec' is distinct from to_jsonb(p_start)
      or l->'translationReview'->'durationSec' is distinct from to_jsonb(p_duration)
      or coalesce(l->'translationReview'->>'category', '') <> p_category
      or coalesce(btrim(l->>'translation'), '') = ''
      or coalesce(l->>'timing', '') <> 'line'
  );
end;
$body$;

create or replace function public.guard_catalog_publication()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $body$
declare
  source_ok boolean := false;
begin
  if not new.published then
    return new;
  end if;

  -- AI v3 path (unchanged).
  if public.catalog_review_receipt_ok(
       new.video_id, new.source_start_sec, new.duration_sec, new.lines
     )
     and not exists (
       select 1 from jsonb_array_elements(new.lines) l
       where l->'translationReview'->'contentClassification'->>'category'
             is distinct from new.category
     )
  then
    new.review_tier := 'ai_v3';
    return new;
  end if;

  -- Caption tier: channel must be flagged caption_tier_ok.
  select coalesce(s.caption_tier_ok, false) into source_ok
  from public.catalog_video_sources v
  join public.catalog_sources s on s.channel_id = v.channel_id
  where v.video_id = new.video_id
  limit 1;

  if not coalesce(source_ok, false) then
    -- Allow caption-tier when the channel_name matches a flagged source title/handle.
    select coalesce(bool_or(s.caption_tier_ok), false) into source_ok
    from public.catalog_sources s
    where s.title = new.channel_name or s.handle = new.channel_name;
  end if;

  if coalesce(source_ok, false)
     and public.catalog_caption_receipt_ok(
           new.video_id, new.source_start_sec, new.duration_sec, new.lines, new.category
         )
  then
    new.review_tier := 'caption';
    return new;
  end if;

  raise exception
    'Publication blocked: current audio, timing, translation and source visual and content classification review required'
    using errcode = '23514';
end;
$body$;

drop trigger if exists catalog_publication_guard on public.clips;
create trigger catalog_publication_guard
  before insert or update of published, lines, video_id, source_start_sec, duration_sec, category, review_tier
  on public.clips
  for each row execute function public.guard_catalog_publication();

grant execute on function public.catalog_caption_receipt_ok(text, numeric, numeric, jsonb, text)
  to service_role;
