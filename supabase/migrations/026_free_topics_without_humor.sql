-- Humor has its own board. Existing free-board posts retain their IDs and content.
begin;
create temporary table old_humor_topic_times on commit drop as
select id,updated_at from public.posts where board='free' and category='humor';
update public.posts set category='chat' where board='free' and category='humor';
update public.posts p set updated_at=t.updated_at from old_humor_topic_times t where p.id=t.id;
alter table public.posts drop constraint posts_category_check;
alter table public.posts add constraint posts_category_check check (
  (board='free' and category is not null and category in ('chat','info','question'))
  or (board='gallery' and (category is null or category in ('meetup','flash','meme','attendance')))
  or (board='staff' and category is not null and category in ('plot','minutes'))
  or (board not in ('free','gallery','staff') and category is null)
);
commit;
