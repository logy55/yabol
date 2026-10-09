-- Apply after migration 005. Consolidate public discussions into free-board topics.
begin;
alter table public.posts drop constraint posts_category_check;

-- Keep post IDs, attached images, replies, likes and original timestamps.
create temporary table free_topic_timestamps on commit drop as
select id,updated_at from public.posts where board in ('info','question');
update public.posts set category=case board when 'info' then 'info' else 'question' end,board='free'
where board in ('info','question');
update public.posts set category='chat' where board='free' and category is null;
update public.posts p set updated_at=t.updated_at from free_topic_timestamps t where p.id=t.id;

alter table public.posts drop constraint posts_board_check;
alter table public.posts add constraint posts_board_check check(board in ('free','gallery','notice','staff','yb'));
alter table public.posts add constraint posts_category_check check (
  (board='free' and category is not null and category in ('humor','info','chat','question'))
  or (board='gallery' and (category is null or category in ('meetup','flash','meme')))
  or (board not in ('free','gallery') and category is null)
);

create function private.default_free_topic() returns trigger
language plpgsql set search_path='' as $$
begin
  if new.board='free' and new.category is null then new.category:='chat'; end if;
  return new;
end; $$;
revoke all on function private.default_free_topic() from public,anon,authenticated;
create trigger default_free_topic before insert or update of board,category on public.posts
for each row execute function private.default_free_topic();

update public.upload_tickets set board='free' where board in ('info','question');
alter table public.upload_tickets drop constraint upload_tickets_board_check;
alter table public.upload_tickets add constraint upload_tickets_board_check
check(board in ('free','gallery','notice','staff','yb'));

create or replace function private.member_can_access_board(p_user uuid,p_board text) returns boolean
language sql stable security definer set search_path='' as $$
  select case
    when p_board in ('free','gallery','notice') then true
    when p_board in ('staff','yb') then private.member_approved(p_user) and (
      exists(select 1 from private.admins where user_id=p_user)
      or exists(select 1 from private.board_memberships where user_id=p_user and board=p_board)
    ) else false end;
$$;
create or replace function public.get_board_access() returns text[]
language sql stable security definer set search_path='' as $$
  select coalesce(array_agg(board),'{}'::text[])
  from unnest(array['free','gallery','notice','staff','yb']) board
  where private.can_access_board(board);
$$;
commit;
