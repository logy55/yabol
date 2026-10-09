-- Apply after migration 006. Add game attendance photos to the gallery.
begin;
alter table public.posts drop constraint posts_category_check;
alter table public.posts add constraint posts_category_check check (
  (board='free' and category is not null and category in ('humor','info','chat','question'))
  or (board='gallery' and (category is null or category in ('meetup','flash','meme','attendance')))
  or (board not in ('free','gallery') and category is null)
);
commit;
