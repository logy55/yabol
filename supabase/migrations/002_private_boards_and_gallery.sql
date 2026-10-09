-- For a project initialized with the original schema.sql, run this once instead
-- of rerunning schema.sql. Fresh projects already include these changes.
begin;

create table private.board_memberships (
  user_id uuid not null references auth.users(id) on delete cascade,
  board text not null check(board in ('staff','yb')),
  primary key(user_id,board)
);
alter table private.board_memberships enable row level security;
alter table private.admins enable row level security;
revoke all on private.board_memberships,private.admins from public,anon,authenticated;
grant usage on schema private to anon,authenticated;

create function private.member_can_access_board(p_user uuid,p_board text)
returns boolean language sql stable security definer set search_path='' as $$
  select case
    when p_board in ('free','info','gallery','question','notice') then true
    when p_board in ('staff','yb') then p_user is not null and (
      exists(select 1 from private.admins where user_id=p_user)
      or exists(select 1 from private.board_memberships where user_id=p_user and board=p_board)
    )
    else false end;
$$;
revoke all on function private.member_can_access_board(uuid,text) from public,anon,authenticated;

create function private.can_access_board(p_board text)
returns boolean language sql stable security definer set search_path='' as $$
  select private.member_can_access_board((select auth.uid()),p_board);
$$;
revoke all on function private.can_access_board(text) from public,anon,authenticated;
grant execute on function private.can_access_board(text) to anon,authenticated;

create function public.get_board_access() returns text[]
language sql stable security definer set search_path='' as $$
  select coalesce(array_agg(board),'{}'::text[])
  from unnest(array['free','info','gallery','question','notice','staff','yb']) board
  where private.can_access_board(board);
$$;
revoke all on function public.get_board_access() from public,anon,authenticated;
grant execute on function public.get_board_access() to anon,authenticated;

-- Only the trusted media service may query access for an explicitly verified user.
create function public.member_can_access_board(p_user uuid,p_board text)
returns boolean language sql stable security definer set search_path='' as $$
  select private.member_can_access_board(p_user,p_board);
$$;
revoke all on function public.member_can_access_board(uuid,text) from public,anon,authenticated;
grant execute on function public.member_can_access_board(uuid,text) to service_role;

alter table public.posts drop constraint posts_board_check;
alter table public.posts add constraint posts_board_check
check(board in ('free','info','gallery','question','notice','staff','yb'));
alter table public.posts add column category text;
alter table public.posts add constraint posts_category_check check (
  (board='gallery' and (category is null or category in ('meetup','flash','meme')))
  or (board<>'gallery' and category is null)
);
grant insert(category),update(category) on public.posts to authenticated;

drop policy posts_read on public.posts;
create policy posts_read on public.posts for select to anon,authenticated
using(private.can_access_board(board));
drop policy posts_write on public.posts;
create policy posts_write on public.posts for insert to authenticated with check (
  author_id=(select auth.uid()) and private.can_access_board(board)
  and ((board<>'notice' and not is_notice) or (select private.is_admin()))
);
drop policy posts_edit on public.posts;
create policy posts_edit on public.posts for update to authenticated
using(author_id=(select auth.uid()) and private.can_access_board(board)) with check (
  author_id=(select auth.uid()) and private.can_access_board(board)
  and ((board<>'notice' and not is_notice) or (select private.is_admin()))
);
drop policy comments_read on public.comments;
create policy comments_read on public.comments for select to anon,authenticated
using(exists(select 1 from public.posts p where p.id=post_id));
drop policy comments_write on public.comments;
create policy comments_write on public.comments for insert to authenticated with check (
  author_id=(select auth.uid()) and exists(select 1 from public.posts p where p.id=post_id)
);
drop policy likes_read on public.likes;
create policy likes_read on public.likes for select to anon,authenticated
using(exists(select 1 from public.posts p where p.id=post_id));
drop policy likes_write on public.likes;
create policy likes_write on public.likes for insert to authenticated with check (
  user_id=(select auth.uid()) and exists(select 1 from public.posts p where p.id=post_id)
);
drop policy likes_remove on public.likes;
create policy likes_remove on public.likes for delete to authenticated using (
  user_id=(select auth.uid()) and exists(select 1 from public.posts p where p.id=post_id)
);

alter table public.upload_tickets add column board text not null default 'free'
  check(board in ('free','info','gallery','question','notice','staff','yb'));
alter table public.upload_tickets add column delivery_type text not null default 'upload'
  check(delivery_type in ('upload','authenticated'));
alter table public.upload_tickets add column format text check(format in ('jpg','png','webp'));
alter table public.upload_tickets add constraint upload_delivery_check check (
  (board in ('staff','yb') and delivery_type='authenticated')
  or (board not in ('staff','yb') and delivery_type='upload')
);

drop function public.reserve_upload(uuid,text);
create function public.reserve_upload(p_owner uuid,p_public_id text,p_board text) returns void
language plpgsql security definer set search_path='' as $$
begin
  if not private.member_can_access_board(p_owner,p_board) then raise exception 'Board access denied'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_owner::text,0));
  if (select count(*) from public.upload_tickets where owner_id=p_owner and created_at>now()-interval '1 hour')>=30
     or (select count(*) from public.upload_tickets where owner_id=p_owner and created_at>now()-interval '1 day')>=100 then
    raise exception 'Upload quota exceeded';
  end if;
  insert into public.upload_tickets(public_id,owner_id,board,delivery_type)
  values(p_public_id,p_owner,p_board,case when p_board in ('staff','yb') then 'authenticated' else 'upload' end);
end; $$;
revoke all on function public.reserve_upload(uuid,text,text) from public,anon,authenticated;
grant execute on function public.reserve_upload(uuid,text,text) to service_role;

create or replace function private.validate_post_images() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if exists(select 1 from unnest(new.images) image(url) where not exists(
    select 1 from public.upload_tickets t where t.owner_id=new.author_id
    and t.secure_url=image.url and t.verified_at is not null and (
      (new.board in ('staff','yb') and t.board=new.board and t.delivery_type='authenticated')
      or (new.board not in ('staff','yb') and t.delivery_type='upload')
    )
  )) then raise exception 'Unverified or incorrectly protected attachment'; end if;
  new.updated_at:=now();
  return new;
end; $$;

-- Append the category column without changing the existing view's column order.
create or replace view public.post_feed with(security_invoker=true) as
select p.id,p.author_id,p.board,p.title,p.body,p.images,p.is_notice,p.created_at,p.updated_at,r.nickname,
  (select count(*) from public.likes l where l.post_id=p.id) as like_count,
  (select count(*) from public.comments c where c.post_id=p.id) as comment_count,p.category
from public.posts p join public.profiles r on r.id=p.author_id;
commit;
