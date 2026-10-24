alter table public.feedback_items drop constraint if exists feedback_items_category_check;

alter table public.feedback_items add constraint feedback_items_category_check check (
  category is null
  or category in (
    'bug',
    'feature',
    'general',
    'cancel_price',
    'cancel_time',
    'cancel_content',
    'cancel_hard',
    'cancel_curious',
    'cancel_other'
  )
);;
