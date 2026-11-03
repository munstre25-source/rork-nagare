-- Per-category supply (live clips) and demand (views, completions, saves, likes, onboarding interest)
-- for the HQ "Categories" report. Service role only.
create or replace function public.admin_category_performance(
  p_start timestamptz,
  p_end timestamptz,
  p_include_test boolean default false
) returns jsonb
language plpgsql
stable
set search_path to ''
as $$
declare
  result jsonb;
begin
  if p_start is null or p_end is null or p_start >= p_end or p_end - p_start > interval '366 days' then
    raise exception 'Invalid analytics range';
  end if;

  with
  ev as (
    select e.install_id, e.name, e.props
    from public.analytics_events e
    where e.occurred_at >= p_start and e.occurred_at < p_end
      and (e.environment = 'production' or (p_include_test and e.environment in ('test', 'legacy')))
      and e.name in ('clip_view', 'clip_completed', 'clip_liked', 'vocab_saved', 'line_saved', 'onboarding_taste_swiped')
  ),
  clip_ev as (
    select ev.install_id, ev.name, ev.props->>'clip' as clip_id, coalesce(c.category, 'personal') as category
    from ev
    left join public.clips c on c.id = ev.props->>'clip'
    where ev.props ? 'clip'
  ),
  supply as (
    select category,
           count(*) filter (where published) as live_clips,
           count(*) filter (where published and review_tier = 'caption') as caption_live
    from public.clips group by category
  ),
  demand as (
    select category,
           count(distinct (install_id, clip_id)) filter (where name = 'clip_view') as views,
           count(*) filter (where name = 'clip_view') as raw_views,
           count(distinct install_id) filter (where name = 'clip_view') as viewers,
           count(distinct clip_id) filter (where name = 'clip_view') as viewed_clips,
           count(distinct (install_id, clip_id)) filter (where name = 'clip_completed') as completions,
           count(*) filter (where name in ('vocab_saved', 'line_saved')) as saves,
           count(*) filter (where name = 'clip_liked') as likes
    from clip_ev group by category
  ),
  taste as (
    select cat as category,
           count(*) as swipes,
           count(*) filter (where ev.props->>'liked' = '1') as liked
    from ev
    cross join lateral unnest(case ev.props->>'taste'
      when 'vtuberGaming' then array['vtuber', 'gaming']
      when 'interviews' then array['interview']
      when 'podcasts' then array['podcast']
      else array[ev.props->>'taste'] end) as cat
    where ev.name = 'onboarding_taste_swiped'
    group by cat
  ),
  per_clip as (
    select category, clip_id,
           count(distinct install_id) filter (where name = 'clip_view') as views,
           count(distinct install_id) filter (where name = 'clip_completed') as completions
    from clip_ev where category <> 'personal'
    group by category, clip_id
  ),
  ranked as (
    select p.*, c.title, c.channel_name,
           row_number() over (partition by p.category order by p.views desc, p.completions desc) as rn
    from per_clip p join public.clips c on c.id = p.clip_id
    where p.views > 0
  ),
  cats as (
    select category from supply where live_clips > 0
    union select category from demand
    union select category from taste
  )
  select jsonb_build_object(
    'include_test', p_include_test,
    'categories', coalesce(jsonb_agg(jsonb_build_object(
      'category', k.category,
      'live_clips', coalesce(s.live_clips, 0),
      'caption_live', coalesce(s.caption_live, 0),
      'views', coalesce(d.views, 0),
      'raw_views', coalesce(d.raw_views, 0),
      'viewers', coalesce(d.viewers, 0),
      'viewed_clips', coalesce(d.viewed_clips, 0),
      'completions', coalesce(d.completions, 0),
      'saves', coalesce(d.saves, 0),
      'likes', coalesce(d.likes, 0),
      'taste_swipes', coalesce(t.swipes, 0),
      'taste_liked', coalesce(t.liked, 0),
      'top_clips', coalesce((
        select jsonb_agg(jsonb_build_object('id', r.clip_id, 'title', r.title, 'channel', r.channel_name,
                                            'views', r.views, 'completions', r.completions) order by r.rn)
        from ranked r where r.category = k.category and r.rn <= 3), '[]'::jsonb)
    ) order by coalesce(d.views, 0) desc, coalesce(s.live_clips, 0) desc), '[]'::jsonb)
  ) into result
  from cats k
  left join supply s on s.category = k.category
  left join demand d on d.category = k.category
  left join taste t on t.category = k.category;

  return result;
end;
$$;

revoke all on function public.admin_category_performance(timestamptz, timestamptz, boolean) from public, anon, authenticated;
grant execute on function public.admin_category_performance(timestamptz, timestamptz, boolean) to service_role;
