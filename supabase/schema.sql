-- Run once in a NEW Supabase project. Do not apply to an existing community database.
begin;
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null check (char_length(nickname) between 2 and 20),
  created_at timestamptz not null default now()
);
create table private.admins (user_id uuid primary key references auth.users(id) on delete cascade);
create function private.is_admin() returns boolean language sql stable security definer
set search_path = '' as $$ select exists(select 1 from private.admins where user_id = (select auth.uid())); $$;
revoke all on function private.is_admin() from public, anon;
grant execute on function private.is_admin() to authenticated;

create function private.new_profile() returns trigger language plpgsql security definer set search_path = '' as $$
declare chosen text;
begin
  chosen := trim(coalesce(new.raw_user_meta_data->>'nickname',''));
  if char_length(chosen) not between 2 and 20 then
    chosen := '회원_' || substring(new.id::text,1,8);
  end if;
  insert into public.profiles(id,nickname) values(new.id,chosen);
  return new;
end; $$;
revoke all on function private.new_profile() from public, anon, authenticated;
create trigger create_profile after insert on auth.users for each row execute function private.new_profile();

create table public.upload_tickets (
  public_id text primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  verified_at timestamptz,
  secure_url text unique
);
create index upload_tickets_owner_created on public.upload_tickets(owner_id,created_at);
alter table public.upload_tickets enable row level security;
revoke all on public.upload_tickets from public, anon, authenticated;
grant select, insert, update on public.upload_tickets to service_role;

create function public.reserve_upload(p_owner uuid, p_public_id text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(p_owner::text,0));
  if (select count(*) from public.upload_tickets where owner_id=p_owner and created_at>now()-interval '1 hour') >= 30
     or (select count(*) from public.upload_tickets where owner_id=p_owner and created_at>now()-interval '1 day') >= 100 then
    raise exception 'Upload quota exceeded';
  end if;
  insert into public.upload_tickets(public_id,owner_id) values(p_public_id,p_owner);
end; $$;
revoke all on function public.reserve_upload(uuid,text) from public, anon, authenticated;
grant execute on function public.reserve_upload(uuid,text) to service_role;

create table public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  board text not null check (board in ('free','info','gallery','question','notice')),
  title text not null check (char_length(trim(title)) between 1 and 120),
  body text not null check (char_length(trim(body)) between 1 and 10000),
  images text[] not null default '{}' check (cardinality(images)<=5),
  is_notice boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index posts_board_created on public.posts(board,created_at desc);
create table public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index comments_post_created on public.comments(post_id,created_at);
create table public.likes (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(post_id,user_id)
);

create function private.validate_post_images() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if exists(select 1 from unnest(new.images) as image(url)
    where not exists(select 1 from public.upload_tickets t where t.owner_id=new.author_id
      and t.secure_url=image.url and t.verified_at is not null)) then
    raise exception 'Unverified attachment';
  end if;
  new.updated_at := now();
  return new;
end; $$;
revoke all on function private.validate_post_images() from public, anon, authenticated;
create trigger verify_post_images before insert or update of images,body,title,board on public.posts
for each row execute function private.validate_post_images();

alter table public.profiles enable row level security;
alter table public.posts enable row level security;
alter table public.comments enable row level security;
alter table public.likes enable row level security;
revoke all on public.profiles,public.posts,public.comments,public.likes from public,anon,authenticated;
grant select on public.profiles,public.posts,public.comments,public.likes to anon,authenticated;
grant insert(author_id,board,title,body,images) on public.posts to authenticated;
grant update(board,title,body,images) on public.posts to authenticated;
grant insert(post_id,author_id,body) on public.comments to authenticated;
grant insert(post_id,user_id) on public.likes to authenticated;
grant delete on public.likes to authenticated;
grant all on public.profiles,public.posts,public.comments,public.likes to service_role;

create policy profiles_read on public.profiles for select to anon,authenticated using(true);
create policy posts_read on public.posts for select to anon,authenticated using(true);
create policy posts_write on public.posts for insert to authenticated with check (
  author_id=(select auth.uid()) and ((board<>'notice' and not is_notice) or (select private.is_admin()))
);
create policy posts_edit on public.posts for update to authenticated
using(author_id=(select auth.uid())) with check (
  author_id=(select auth.uid()) and ((board<>'notice' and not is_notice) or (select private.is_admin()))
);
create policy comments_read on public.comments for select to anon,authenticated using(true);
create policy comments_write on public.comments for insert to authenticated with check(author_id=(select auth.uid()));
create policy likes_read on public.likes for select to anon,authenticated using(true);
create policy likes_write on public.likes for insert to authenticated with check(user_id=(select auth.uid()));
create policy likes_remove on public.likes for delete to authenticated using(user_id=(select auth.uid()));

create view public.post_feed with(security_invoker=true) as
select p.*,r.nickname,
  (select count(*) from public.likes l where l.post_id=p.id) as like_count,
  (select count(*) from public.comments c where c.post_id=p.id) as comment_count
from public.posts p join public.profiles r on r.id=p.author_id;
create view public.comment_feed with(security_invoker=true) as
select c.*,r.nickname from public.comments c join public.profiles r on r.id=c.author_id;
revoke all on public.post_feed,public.comment_feed from public,anon,authenticated;
grant select on public.post_feed,public.comment_feed to anon,authenticated;

-- For a project initialized with the original schema.sql, run this once instead
-- of rerunning schema.sql. Fresh projects already include these changes.

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


-- Apply after migration 002. Existing members remain approved.
begin;
alter table public.profiles add column team text check(team is null or team in ('kia','samsung','lg','doosan','kt','ssg','lotte','hanwha','nc','kiwoom'));
alter table public.profiles add column region text check(region is null or char_length(trim(region)) between 1 and 20);

create table private.member_accounts (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  username text unique not null check(username ~ '^[a-z0-9_]{3,40}$'),
  status text not null default 'pending' check(status in ('pending','approved')),
  approved_at timestamptz,
  approved_by uuid references auth.users(id) on delete set null
);
alter table private.member_accounts enable row level security;
revoke all on private.member_accounts from public,anon,authenticated;
grant select on private.member_accounts to service_role;
insert into private.member_accounts(user_id,username,status,approved_at)
select id,'legacy_'||replace(id::text,'-',''),'approved',created_at from public.profiles;

create or replace function private.new_profile() returns trigger language plpgsql security definer set search_path='' as $$
declare chosen text; login_id text; chosen_team text; chosen_region text;
begin
  chosen:=trim(coalesce(new.raw_user_meta_data->>'nickname',''));
  if char_length(chosen) not between 2 and 20 then chosen:='회원_'||substring(new.id::text,1,8); end if;
  login_id:=lower(trim(coalesce(new.raw_user_meta_data->>'username','')));
  if login_id !~ '^[a-z0-9_]{3,24}$' then login_id:='legacy_'||replace(new.id::text,'-',''); end if;
  chosen_team:=new.raw_user_meta_data->>'team';
  if chosen_team not in ('kia','samsung','lg','doosan','kt','ssg','lotte','hanwha','nc','kiwoom') then chosen_team:=null; end if;
  chosen_region:=trim(new.raw_user_meta_data->>'region');
  if char_length(chosen_region) not between 1 and 20 then chosen_region:=null; end if;
  insert into public.profiles(id,nickname,team,region) values(new.id,chosen,chosen_team,chosen_region);
  -- Approval is held in a private table, never in editable user metadata.
  insert into private.member_accounts(user_id,username) values(new.id,login_id);
  return new;
end; $$;

create function private.member_approved(p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from private.member_accounts where user_id=p_user and status='approved')
    or exists(select 1 from private.admins where user_id=p_user);
$$;
revoke all on function private.member_approved(uuid) from public,anon,authenticated;
grant execute on function private.member_approved(uuid) to authenticated;

create or replace function private.member_can_access_board(p_user uuid,p_board text) returns boolean language sql stable security definer set search_path='' as $$
  select case
    when p_board in ('free','info','gallery','question','notice') then true
    when p_board in ('staff','yb') then private.member_approved(p_user) and (
      exists(select 1 from private.admins where user_id=p_user)
      or exists(select 1 from private.board_memberships where user_id=p_user and board=p_board)
    ) else false end;
$$;

create policy posts_approved_insert on public.posts as restrictive for insert to authenticated with check(private.member_approved((select auth.uid())));
create policy posts_approved_update on public.posts as restrictive for update to authenticated using(private.member_approved((select auth.uid()))) with check(private.member_approved((select auth.uid())));
create policy comments_approved_insert on public.comments as restrictive for insert to authenticated with check(private.member_approved((select auth.uid())));
create policy likes_approved_insert on public.likes as restrictive for insert to authenticated with check(private.member_approved((select auth.uid())));
create policy likes_approved_delete on public.likes as restrictive for delete to authenticated using(private.member_approved((select auth.uid())));

-- The trusted upload service must also require an approved account.
create or replace function public.member_can_access_board(p_user uuid,p_board text) returns boolean language sql stable security definer set search_path='' as $$
  select private.member_approved(p_user) and private.member_can_access_board(p_user,p_board);
$$;

create function public.get_my_membership() returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('username',a.username,'nickname',p.nickname,'team',p.team,'region',p.region,
    'status',case when private.member_approved(p.id) then 'approved' else 'pending' end,'created_at',p.created_at)
  from public.profiles p join private.member_accounts a on a.user_id=p.id where p.id=(select auth.uid());
$$;
revoke all on function public.get_my_membership() from public,anon,authenticated;
grant execute on function public.get_my_membership() to authenticated;

create function public.member_is_approved(p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
  select private.member_approved(p_user);
$$;
revoke all on function public.member_is_approved(uuid) from public,anon,authenticated;
grant execute on function public.member_is_approved(uuid) to service_role;

create function public.approve_member(p_user uuid) returns void language plpgsql security definer set search_path='' as $$
begin
  if not private.is_admin() then raise exception 'Administrator required'; end if;
  update private.member_accounts set status='approved',approved_at=now(),approved_by=(select auth.uid()) where user_id=p_user;
  if not found then raise exception 'Member not found'; end if;
end; $$;
revoke all on function public.approve_member(uuid) from public,anon,authenticated;
grant execute on function public.approve_member(uuid) to authenticated;

-- Bound anonymous signup/login attempts before using privileged Auth APIs.
create table private.membership_attempts(attempt_key text not null,created_at timestamptz not null default now());
create index membership_attempts_key_time on private.membership_attempts(attempt_key,created_at);
alter table private.membership_attempts enable row level security;
revoke all on private.membership_attempts from public,anon,authenticated;
create function public.membership_rate_limit(p_key text,p_limit integer,p_seconds integer) returns boolean language plpgsql security definer set search_path='' as $$
begin
  if p_limit<1 or p_seconds<1 or p_seconds>86400 then raise exception 'Invalid limit'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_key,1));
  delete from private.membership_attempts where created_at<now()-interval '1 day';
  if (select count(*) from private.membership_attempts where attempt_key=p_key and created_at>now()-make_interval(secs=>p_seconds))>=p_limit then return false; end if;
  insert into private.membership_attempts(attempt_key) values(p_key);
  return true;
end; $$;
revoke all on function public.membership_rate_limit(text,integer,integer) from public,anon,authenticated;
grant execute on function public.membership_rate_limit(text,integer,integer) to service_role;

create or replace view public.post_feed with(security_invoker=true) as
select p.id,p.author_id,p.board,p.title,p.body,p.images,p.is_notice,p.created_at,p.updated_at,r.nickname,
  (select count(*) from public.likes l where l.post_id=p.id) as like_count,
  (select count(*) from public.comments c where c.post_id=p.id) as comment_count,p.category,r.team,r.region
from public.posts p join public.profiles r on r.id=p.author_id;
create or replace view public.comment_feed with(security_invoker=true) as
select c.*,r.nickname,r.team,r.region from public.comments c join public.profiles r on r.id=c.author_id;
commit;

-- Apply after migration 003. Staff badges are server-managed presentation roles.
begin;
alter table public.profiles add column staff_role text not null default 'member'
  check(staff_role in ('member','staff','vice_staff'));
update public.profiles p set staff_role='staff'
where exists(select 1 from private.admins a where a.user_id=p.id);

-- The existing profile grants allow clients to read, but never write this field.
-- Editable Auth metadata is deliberately not used for staff roles.
create or replace function public.get_my_membership() returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('username',a.username,'nickname',p.nickname,'team',p.team,'region',p.region,
    'status',case when private.member_approved(p.id) then 'approved' else 'pending' end,
    'created_at',p.created_at,'staff_role',p.staff_role)
  from public.profiles p join private.member_accounts a on a.user_id=p.id where p.id=(select auth.uid());
$$;

create or replace view public.post_feed with(security_invoker=true) as
select p.id,p.author_id,p.board,p.title,p.body,p.images,p.is_notice,p.created_at,p.updated_at,r.nickname,
  (select count(*) from public.likes l where l.post_id=p.id) as like_count,
  (select count(*) from public.comments c where c.post_id=p.id) as comment_count,p.category,r.team,r.region,r.staff_role
from public.posts p join public.profiles r on r.id=p.author_id;
create or replace view public.comment_feed with(security_invoker=true) as
select c.*,r.nickname,r.team,r.region,r.staff_role from public.comments c join public.profiles r on r.id=c.author_id;
commit;

-- Apply after migration 004. YB affiliation uses the existing trusted membership.
begin;
create function private.is_yb_member(p_user uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from private.board_memberships where user_id=p_user and board='yb');
$$;
revoke all on function private.is_yb_member(uuid) from public,anon,authenticated;
grant execute on function private.is_yb_member(uuid) to anon,authenticated,service_role;

-- Administrators' general board access is not itself YB affiliation.
-- Client-editable Auth metadata is never used for this badge.
create or replace function public.get_my_membership() returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('username',a.username,'nickname',p.nickname,'team',p.team,'region',p.region,
    'status',case when private.member_approved(p.id) then 'approved' else 'pending' end,
    'created_at',p.created_at,'staff_role',p.staff_role,'is_yb_member',private.is_yb_member(p.id))
  from public.profiles p join private.member_accounts a on a.user_id=p.id where p.id=(select auth.uid());
$$;
create or replace view public.post_feed with(security_invoker=true) as
select p.id,p.author_id,p.board,p.title,p.body,p.images,p.is_notice,p.created_at,p.updated_at,r.nickname,
  (select count(*) from public.likes l where l.post_id=p.id) as like_count,
  (select count(*) from public.comments c where c.post_id=p.id) as comment_count,
  p.category,r.team,r.region,r.staff_role,private.is_yb_member(r.id) as is_yb_member
from public.posts p join public.profiles r on r.id=p.author_id;
create or replace view public.comment_feed with(security_invoker=true) as
select c.*,r.nickname,r.team,r.region,r.staff_role,private.is_yb_member(r.id) as is_yb_member
from public.comments c join public.profiles r on r.id=c.author_id;
commit;

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

-- Apply after migration 006. Add game attendance photos to the gallery.
begin;
alter table public.posts drop constraint posts_category_check;
alter table public.posts add constraint posts_category_check check (
  (board='free' and category is not null and category in ('humor','info','chat','question'))
  or (board='gallery' and (category is null or category in ('meetup','flash','meme','attendance')))
  or (board not in ('free','gallery') and category is null)
);
commit;

-- Apply after migration 007. Rich bodies reference verified post images by index.
begin;
alter table public.posts add column body_doc jsonb;
grant insert(body_doc),update(body_doc) on public.posts to authenticated;

create function private.rich_document_valid(p_doc jsonb,p_image_count integer) returns boolean
language plpgsql immutable set search_path='' as $$
declare item record; node jsonb; attrs jsonb; kind text; allowed text[]; child_types text[];
  mark jsonb; total_nodes integer:=0; total_text integer:=0;
begin
  if p_doc is null then return true; end if;
  if jsonb_typeof(p_doc)<>'object' or p_doc->>'type'<>'doc' or char_length(p_doc::text)>200000 then return false; end if;
  for item in
    with recursive walk(node,parent,depth) as (
      select p_doc,'ROOT'::text,0
      union all
      select child.value,w.node->>'type',w.depth+1 from walk w
      cross join lateral jsonb_array_elements(case when jsonb_typeof(w.node->'content')='array' then w.node->'content' else '[]'::jsonb end) child
      where w.depth<=10
    ) select * from walk
  loop
    node:=item.node; kind:=node->>'type'; total_nodes:=total_nodes+1;
    if total_nodes>2000 or item.depth>10 or jsonb_typeof(node)<>'object' or kind is null then return false; end if;
    child_types:=case item.parent
      when 'ROOT' then array['doc']
      when 'doc' then array['paragraph','heading','blockquote','bulletList','orderedList','codeBlock','horizontalRule','table','image']
      when 'paragraph' then array['text','hardBreak','yabolticon']
      when 'heading' then array['text','hardBreak','yabolticon']
      when 'codeBlock' then array['text']
      when 'blockquote' then array['paragraph','heading','blockquote','bulletList','orderedList','codeBlock','horizontalRule','table','image']
      when 'listItem' then array['paragraph','heading','blockquote','bulletList','orderedList','codeBlock','horizontalRule','table','image']
      when 'bulletList' then array['listItem']
      when 'orderedList' then array['listItem']
      when 'table' then array['tableRow']
      when 'tableRow' then array['tableCell','tableHeader']
      when 'tableCell' then array['paragraph','heading','blockquote','bulletList','orderedList','codeBlock','horizontalRule','image']
      when 'tableHeader' then array['paragraph','heading','blockquote','bulletList','orderedList','codeBlock','horizontalRule','image']
      else array[]::text[] end;
    if not(kind=any(child_types)) then return false; end if;
    allowed:=case
      when kind='text' then array['type','text','marks']
      when kind in ('image','yabolticon') then array['type','attrs']
      when kind in ('hardBreak','horizontalRule') then array['type']
      when kind in ('heading','orderedList','tableCell','tableHeader') then array['type','attrs','content']
      else array['type','content'] end;
    if exists(select 1 from jsonb_object_keys(node) key where not(key=any(allowed))) then return false; end if;
    if kind='text' then
      if jsonb_typeof(node->'text') is distinct from 'string' then return false; end if;
      total_text:=total_text+char_length(node->>'text'); if total_text>10000 then return false; end if;
      if node ? 'marks' then
        if jsonb_typeof(node->'marks')<>'array' or jsonb_array_length(node->'marks')>5 then return false; end if;
        for mark in select value from jsonb_array_elements(node->'marks') loop
          if jsonb_typeof(mark)<>'object' or (mark-'type')<>'{}'::jsonb or (mark->>'type') is null
            or not(mark->>'type'=any(array['bold','italic','underline','strike','code'])) then return false; end if;
        end loop;
      end if;
    elsif kind not in ('image','yabolticon','hardBreak','horizontalRule') then
      if jsonb_typeof(node->'content') is distinct from 'array' then return false; end if;
      if kind='table' and jsonb_array_length(node->'content') not between 1 and 20 then return false; end if;
      if kind='tableRow' and jsonb_array_length(node->'content') not between 1 and 10 then return false; end if;
    end if;
    if kind in ('image','yabolticon','heading','orderedList','tableCell','tableHeader') then
      attrs:=node->'attrs'; if jsonb_typeof(attrs) is distinct from 'object' then return false; end if;
      if kind='image' then
        if (attrs-array['index','alt'])<>'{}'::jsonb or jsonb_typeof(attrs->'index') is distinct from 'number'
          or coalesce(attrs->>'index','') !~ '^[0-4]$' or (attrs->>'index')::integer>=p_image_count
          or jsonb_typeof(attrs->'alt') is distinct from 'string' or char_length(attrs->>'alt')>200 then return false; end if;
      elsif kind='yabolticon' then
        if (attrs-'id')<>'{}'::jsonb or (attrs->>'id') is null
          or not(attrs->>'id'=any(array['hello','laugh','cheer','homerun','cry','angry','clap','thanks'])) then return false; end if;
      elsif kind='heading' then
        if (attrs-'level')<>'{}'::jsonb or jsonb_typeof(attrs->'level') is distinct from 'number' or coalesce(attrs->>'level','') !~ '^[23]$' then return false; end if;
      elsif kind='orderedList' then
        if (attrs-'start')<>'{}'::jsonb or jsonb_typeof(attrs->'start') is distinct from 'number'
          or coalesce(attrs->>'start','') !~ '^[1-9][0-9]{0,2}$' then return false; end if;
      else
        if (attrs-array['colspan','rowspan'])<>'{}'::jsonb or jsonb_typeof(attrs->'colspan') is distinct from 'number'
          or jsonb_typeof(attrs->'rowspan') is distinct from 'number' or coalesce(attrs->>'colspan','') !~ '^[1-9][0-9]?$'
          or coalesce(attrs->>'rowspan','') !~ '^[1-9][0-9]?$'
          or (attrs->>'colspan')::integer>10 or (attrs->>'rowspan')::integer>20 then return false; end if;
      end if;
    end if;
  end loop;
  return true;
exception when others then return false;
end; $$;
revoke all on function private.rich_document_valid(jsonb,integer) from public,anon,authenticated;

create function private.validate_rich_post() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if not private.rich_document_valid(new.body_doc,cardinality(new.images)) then raise exception 'Invalid rich body document'; end if;
  return new;
end; $$;
revoke all on function private.validate_rich_post() from public,anon,authenticated;
create trigger validate_rich_post before insert or update of body_doc,images on public.posts
for each row execute function private.validate_rich_post();

create or replace view public.post_feed with(security_invoker=true) as
select p.id,p.author_id,p.board,p.title,p.body,p.images,p.is_notice,p.created_at,p.updated_at,r.nickname,
  (select count(*) from public.likes l where l.post_id=p.id) as like_count,
  (select count(*) from public.comments c where c.post_id=p.id) as comment_count,
  p.category,r.team,r.region,r.staff_role,private.is_yb_member(r.id) as is_yb_member,p.body_doc
from public.posts p join public.profiles r on r.id=p.author_id;
commit;

-- Apply after 008. Admin-only approval, grades and per-member board permissions.
begin;
alter table private.member_accounts drop constraint member_accounts_status_check;
alter table private.member_accounts add constraint member_accounts_status_check
  check(status in ('pending','approved','rejected','suspended'));
alter table private.member_accounts add column revision bigint not null default 0;
-- Preserve previously effective approval for existing bootstrap administrators.
update private.member_accounts a set status='approved',approved_at=coalesce(approved_at,now())
where exists(select 1 from private.admins d where d.user_id=a.user_id) and status='pending';

create table private.member_permissions (
  user_id uuid not null references public.profiles(id) on delete cascade,
  board text not null check(board in ('free','gallery','notice','staff','yb')),
  access text not null check(access in ('deny','read','write')),
  primary key(user_id,board)
);
create table private.admin_audit (
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users(id) on delete set null,
  target_id uuid references public.profiles(id) on delete set null,
  detail jsonb not null,
  created_at timestamptz not null default now()
);
alter table private.member_permissions enable row level security;
alter table private.admin_audit enable row level security;
revoke all on private.member_permissions,private.admin_audit from public,anon,authenticated;
-- Preserve older manually granted staff access as a visible explicit override.
insert into private.member_permissions(user_id,board,access)
select user_id,'staff','write' from private.board_memberships where board='staff';

create or replace function private.member_approved(p_user uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from private.member_accounts where user_id=p_user and status='approved');
$$;
create or replace function private.is_admin() returns boolean
language sql stable security definer set search_path='' as $$
  select private.member_approved((select auth.uid()))
    and exists(select 1 from private.admins where user_id=(select auth.uid()));
$$;

create function private.board_permission(p_user uuid,p_board text) returns text
language plpgsql stable security definer set search_path='' as $$
declare override_access text; member_role text;
begin
  if p_board is null or p_board not in ('free','gallery','notice','staff','yb') then return 'deny'; end if;
  if p_user is null then return case when p_board in ('free','gallery','notice') then 'read' else 'deny' end; end if;
  if not private.member_approved(p_user) then return 'deny'; end if;
  if exists(select 1 from private.admins where user_id=p_user) then return 'write'; end if;
  select access into override_access from private.member_permissions where user_id=p_user and board=p_board;
  if found then return override_access; end if;
  select staff_role into member_role from public.profiles where id=p_user;
  if p_board in ('free','gallery') then return 'write'; end if;
  if p_board='notice' then return case when member_role in ('staff','vice_staff') then 'write' else 'read' end; end if;
  if p_board='staff' and member_role in ('staff','vice_staff') then return 'write'; end if;
  if p_board='yb' and private.is_yb_member(p_user) then return 'write'; end if;
  return 'deny';
end; $$;
revoke all on function private.board_permission(uuid,text) from public,anon,authenticated;

create or replace function private.member_can_access_board(p_user uuid,p_board text) returns boolean
language sql stable security definer set search_path='' as $$
  select private.board_permission(p_user,p_board) in ('read','write');
$$;
create function private.can_write_board(p_board text) returns boolean
language sql stable security definer set search_path='' as $$
  select private.board_permission((select auth.uid()),p_board)='write';
$$;
revoke all on function private.can_write_board(text) from public,anon,authenticated;
grant execute on function private.can_write_board(text) to authenticated;

create or replace function public.member_can_access_board(p_user uuid,p_board text) returns boolean
language sql stable security definer set search_path='' as $$
  select private.member_approved(p_user) and private.member_can_access_board(p_user,p_board);
$$;
create function public.member_can_write_board(p_user uuid,p_board text) returns boolean
language sql stable security definer set search_path='' as $$
  select private.board_permission(p_user,p_board)='write';
$$;
revoke all on function public.member_can_write_board(uuid,text) from public,anon,authenticated;
grant execute on function public.member_can_write_board(uuid,text) to service_role;

create function public.get_member_status(p_user uuid) returns text
language sql stable security definer set search_path='' as $$
  select status from private.member_accounts where user_id=p_user;
$$;
revoke all on function public.get_member_status(uuid) from public,anon,authenticated;
grant execute on function public.get_member_status(uuid) to service_role;

create function public.get_board_permissions() returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_object_agg(board,jsonb_build_object('read',access in ('read','write'),'write',access='write'))
  from (select board,private.board_permission((select auth.uid()),board) access
    from unnest(array['free','gallery','notice','staff','yb']) board) permissions;
$$;
revoke all on function public.get_board_permissions() from public,anon,authenticated;
grant execute on function public.get_board_permissions() to anon,authenticated;

create or replace function public.get_my_membership() returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('username',a.username,'nickname',p.nickname,'team',p.team,'region',p.region,
    'status',a.status,'created_at',p.created_at,'staff_role',p.staff_role,
    'is_yb_member',private.is_yb_member(p.id),'is_admin',private.is_admin())
  from public.profiles p join private.member_accounts a on a.user_id=p.id where p.id=(select auth.uid());
$$;

drop policy posts_write on public.posts;
create policy posts_write on public.posts for insert to authenticated with check (
  author_id=(select auth.uid()) and private.can_write_board(board)
);
drop policy posts_edit on public.posts;
create policy posts_edit on public.posts for update to authenticated
using(author_id=(select auth.uid()) and private.can_write_board(board))
with check(author_id=(select auth.uid()) and private.can_write_board(board));
drop policy comments_write on public.comments;
create policy comments_write on public.comments for insert to authenticated with check (
  author_id=(select auth.uid()) and exists(select 1 from public.posts p where p.id=post_id and private.can_write_board(p.board))
);
-- Notice status is derived from its board, not a writable client role flag.
create function private.set_notice_flag() returns trigger
language plpgsql set search_path='' as $$ begin new.is_notice:=(new.board='notice'); return new; end; $$;
revoke all on function private.set_notice_flag() from public,anon,authenticated;
create trigger set_notice_flag before insert or update of board on public.posts
for each row execute function private.set_notice_flag();

create or replace function public.reserve_upload(p_owner uuid,p_public_id text,p_board text) returns void
language plpgsql security definer set search_path='' as $$
begin
  if private.board_permission(p_owner,p_board)<>'write' then raise exception 'Board write denied'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_owner::text,0));
  if (select count(*) from public.upload_tickets where owner_id=p_owner and created_at>now()-interval '1 hour')>=30
     or (select count(*) from public.upload_tickets where owner_id=p_owner and created_at>now()-interval '1 day')>=100 then raise exception 'Upload quota exceeded'; end if;
  insert into public.upload_tickets(public_id,owner_id,board,delivery_type)
  values(p_public_id,p_owner,p_board,case when p_board in ('staff','yb') then 'authenticated' else 'upload' end);
end; $$;

create function private.admin_member_snapshot(p_user uuid) returns jsonb
language sql stable set search_path='' as $$
  select jsonb_build_object('id',p.id,'username',a.username,'nickname',p.nickname,'region',p.region,'team',p.team,
    'staff_role',p.staff_role,'status',a.status,'revision',a.revision,'created_at',p.created_at,
    'is_admin',exists(select 1 from private.admins where user_id=p.id),'is_yb_member',private.is_yb_member(p.id),
    'permissions',coalesce((select jsonb_object_agg(board,access) from private.member_permissions where user_id=p.id),'{}'::jsonb),
    'effective', (select jsonb_object_agg(board,private.board_permission(p.id,board)) from unnest(array['free','gallery','notice','staff','yb']) board))
  from public.profiles p join private.member_accounts a on a.user_id=p.id where p.id=p_user;
$$;
revoke all on function private.admin_member_snapshot(uuid) from public,anon,authenticated;

create function public.admin_list_members(p_query text default '',p_status text default null,p_limit integer default 20,p_offset integer default 0) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare query_text text; result jsonb;
begin
  if not private.is_admin() then raise exception 'Administrator required'; end if;
  if p_query is null or char_length(p_query)>100 or p_limit is null or p_limit not between 1 and 50 or p_offset is null or p_offset not between 0 and 1000000
    or (p_status is not null and p_status not in ('pending','approved','rejected','suspended')) then raise exception 'Invalid filter'; end if;
  query_text:=lower(trim(p_query));
  with filtered as (
    select p.id,p.created_at,a.status from public.profiles p join private.member_accounts a on a.user_id=p.id
    where (p_status is null or a.status=p_status) and (query_text='' or strpos(lower(a.username||' '||p.nickname||' '||coalesce(p.region,'')),query_text)>0)
  ), page as (select * from filtered order by created_at desc,id limit p_limit offset p_offset)
  select jsonb_build_object('members',coalesce((select jsonb_agg(private.admin_member_snapshot(id) order by created_at desc,id) from page),'[]'::jsonb),
    'total',(select count(*) from filtered),'stats', (select jsonb_build_object('pending',count(*) filter(where status='pending'),'approved',count(*) filter(where status='approved'),
      'rejected',count(*) filter(where status='rejected'),'suspended',count(*) filter(where status='suspended')) from private.member_accounts)) into result;
  return result;
end; $$;
revoke all on function public.admin_list_members(text,text,integer,integer) from public,anon,authenticated;
grant execute on function public.admin_list_members(text,text,integer,integer) to authenticated;

create function public.admin_update_member(p_user uuid,p_status text,p_staff_role text,p_is_yb boolean,p_is_admin boolean,p_permissions jsonb,p_revision bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare current_revision bigint; previous jsonb; updated jsonb; board_key text; mode text; actor uuid:=(select auth.uid());
begin
  -- Serialize administrator membership mutations and protect the final administrator.
  perform pg_advisory_xact_lock(hashtextextended('community-member-administration',0));
  if not private.is_admin() then raise exception 'Administrator required'; end if;
  if p_user is null or p_status is null or p_status not in ('pending','approved','rejected','suspended')
    or p_staff_role is null or p_staff_role not in ('member','staff','vice_staff') or p_is_yb is null or p_is_admin is null
    or p_revision is null or jsonb_typeof(p_permissions) is distinct from 'object' then raise exception 'Invalid member settings'; end if;
  if (select count(*) from jsonb_object_keys(p_permissions))<>5
    or exists(select 1 from jsonb_each_text(p_permissions) entry where entry.key not in ('free','gallery','notice','staff','yb') or entry.value not in ('default','deny','read','write') or entry.value is null)
    then raise exception 'Invalid board permissions'; end if;
  select revision into current_revision from private.member_accounts where user_id=p_user for update;
  if not found then raise exception 'Member not found'; end if;
  if current_revision<>p_revision then raise exception 'Member settings changed; reload required'; end if;
  if p_is_admin and p_status<>'approved' then raise exception 'Administrator must remain approved'; end if;
  if p_user=actor and (not p_is_admin or p_status<>'approved') then raise exception 'Cannot remove your own administrator access'; end if;
  if exists(select 1 from private.admins where user_id=p_user) and not p_is_admin
    and (select count(*) from private.admins d join private.member_accounts a on a.user_id=d.user_id where a.status='approved')<=1
    then raise exception 'Cannot remove final administrator'; end if;
  previous:=private.admin_member_snapshot(p_user);
  update private.member_accounts set status=p_status,revision=revision+1,
    approved_at=case when p_status='approved' and status<>'approved' then now() else approved_at end,
    approved_by=case when p_status='approved' and status<>'approved' then actor else approved_by end where user_id=p_user;
  update public.profiles set staff_role=p_staff_role where id=p_user;
  if p_is_admin then insert into private.admins(user_id) values(p_user) on conflict do nothing;
  else delete from private.admins where user_id=p_user; end if;
  if p_is_yb then insert into private.board_memberships(user_id,board) values(p_user,'yb') on conflict do nothing;
  else delete from private.board_memberships where user_id=p_user and board='yb'; end if;
  delete from private.member_permissions where user_id=p_user;
  for board_key,mode in select key,value from jsonb_each_text(p_permissions) loop
    if mode<>'default' then insert into private.member_permissions(user_id,board,access) values(p_user,board_key,mode); end if;
  end loop;
  updated:=private.admin_member_snapshot(p_user);
  insert into private.admin_audit(actor_id,target_id,detail) values(actor,p_user,jsonb_build_object('before',previous,'after',updated));
  return updated;
end; $$;
revoke all on function public.admin_update_member(uuid,text,text,boolean,boolean,jsonb,bigint) from public,anon,authenticated;
grant execute on function public.admin_update_member(uuid,text,text,boolean,boolean,jsonb,bigint) to authenticated;

-- Compatibility approval RPC shares the same validation and audit path.
create or replace function public.approve_member(p_user uuid) returns void
language plpgsql security definer set search_path='' as $$
declare member_settings jsonb; full_permissions jsonb;
begin
  if not private.is_admin() then raise exception 'Administrator required'; end if;
  member_settings:=private.admin_member_snapshot(p_user);
  if member_settings is null then raise exception 'Member not found'; end if;
  select jsonb_object_agg(board,coalesce(member_settings->'permissions'->>board,'default')) into full_permissions
  from unnest(array['free','gallery','notice','staff','yb']) board;
  perform public.admin_update_member(p_user,'approved',member_settings->>'staff_role',(member_settings->>'is_yb_member')::boolean,
    (member_settings->>'is_admin')::boolean,full_permissions,(member_settings->>'revision')::bigint);
end; $$;

create function public.admin_list_audit() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  if not private.is_admin() then raise exception 'Administrator required'; end if;
  select coalesce(jsonb_agg(entry order by id desc),'[]'::jsonb) into result from (
    select l.id,jsonb_build_object('id',l.id,'created_at',l.created_at,'actor',coalesce(p.nickname,'삭제된 회원'),'detail',l.detail) entry
    from private.admin_audit l left join public.profiles p on p.id=l.actor_id order by l.id desc limit 30
  ) recent;
  return result;
end; $$;
revoke all on function public.admin_list_audit() from public,anon,authenticated;
grant execute on function public.admin_list_audit() to authenticated;
commit;

-- Apply after 009. Approved staff and vice-staff can manage members; administrator accounts remain administrator-only.
begin;
create or replace function private.can_manage_members() returns boolean
language sql stable security definer set search_path='' as $$
  select private.member_approved((select auth.uid())) and (
    private.is_admin() or exists(select 1 from public.profiles where id=(select auth.uid()) and staff_role in ('staff','vice_staff'))
  );
$$;
revoke all on function private.can_manage_members() from public,anon,authenticated;

create or replace function public.get_my_membership() returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('username',a.username,'nickname',p.nickname,'team',p.team,'region',p.region,
    'status',a.status,'created_at',p.created_at,'staff_role',p.staff_role,
    'is_yb_member',private.is_yb_member(p.id),'is_admin',private.is_admin(),'can_manage_members',private.can_manage_members())
  from public.profiles p join private.member_accounts a on a.user_id=p.id where p.id=(select auth.uid());
$$;

create or replace function public.admin_list_members(p_query text default '',p_status text default null,p_limit integer default 20,p_offset integer default 0) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare query_text text; result jsonb;
begin
  if not private.can_manage_members() then raise exception 'Administrator required'; end if;
  if p_query is null or char_length(p_query)>100 or p_limit is null or p_limit not between 1 and 50 or p_offset is null or p_offset not between 0 and 1000000
    or (p_status is not null and p_status not in ('pending','approved','rejected','suspended')) then raise exception 'Invalid filter'; end if;
  query_text:=lower(trim(p_query));
  with filtered as (
    select p.id,p.created_at,a.status from public.profiles p join private.member_accounts a on a.user_id=p.id
    where (p_status is null or a.status=p_status) and (query_text='' or strpos(lower(a.username||' '||p.nickname||' '||coalesce(p.region,'')),query_text)>0)
  ), page as (select * from filtered order by created_at desc,id limit p_limit offset p_offset)
  select jsonb_build_object('members',coalesce((select jsonb_agg(private.admin_member_snapshot(id) order by created_at desc,id) from page),'[]'::jsonb),
    'total',(select count(*) from filtered),'stats', (select jsonb_build_object('pending',count(*) filter(where status='pending'),'approved',count(*) filter(where status='approved'),
      'rejected',count(*) filter(where status='rejected'),'suspended',count(*) filter(where status='suspended')) from private.member_accounts)) into result;
  return result;
end; $$;

create or replace function public.admin_update_member(p_user uuid,p_status text,p_staff_role text,p_is_yb boolean,p_is_admin boolean,p_permissions jsonb,p_revision bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor_admin boolean; current_revision bigint; previous jsonb; updated jsonb; board_key text; mode text; actor uuid:=(select auth.uid());
begin
  -- Serialize administrator membership mutations and protect the final administrator.
  perform pg_advisory_xact_lock(hashtextextended('community-member-administration',0));
  if not private.can_manage_members() then raise exception 'Administrator required'; end if;
  actor_admin:=private.is_admin();
  if p_user is null or p_status is null or p_status not in ('pending','approved','rejected','suspended')
    or p_staff_role is null or p_staff_role not in ('member','staff','vice_staff') or p_is_yb is null or p_is_admin is null
    or p_revision is null or jsonb_typeof(p_permissions) is distinct from 'object' then raise exception 'Invalid member settings'; end if;
  if (select count(*) from jsonb_object_keys(p_permissions))<>5
    or exists(select 1 from jsonb_each_text(p_permissions) entry where entry.key not in ('free','gallery','notice','staff','yb') or entry.value not in ('default','deny','read','write') or entry.value is null)
    then raise exception 'Invalid board permissions'; end if;
  select revision into current_revision from private.member_accounts where user_id=p_user for update;
  if not found then raise exception 'Member not found'; end if;
  if current_revision<>p_revision then raise exception 'Member settings changed; reload required'; end if;
  if not actor_admin and (p_is_admin or exists(select 1 from private.admins where user_id=p_user)) then
    raise exception 'Only administrators may manage administrator accounts';
  end if;
  if p_is_admin and p_status<>'approved' then raise exception 'Administrator must remain approved'; end if;
  if p_user=actor and (p_status<>'approved' or (actor_admin and not p_is_admin) or (not actor_admin and p_staff_role not in ('staff','vice_staff'))) then raise exception 'Cannot remove your own administrator access'; end if;
  if exists(select 1 from private.admins where user_id=p_user) and not p_is_admin
    and (select count(*) from private.admins d join private.member_accounts a on a.user_id=d.user_id where a.status='approved')<=1
    then raise exception 'Cannot remove final administrator'; end if;
  previous:=private.admin_member_snapshot(p_user);
  update private.member_accounts set status=p_status,revision=revision+1,
    approved_at=case when p_status='approved' and status<>'approved' then now() else approved_at end,
    approved_by=case when p_status='approved' and status<>'approved' then actor else approved_by end where user_id=p_user;
  update public.profiles set staff_role=p_staff_role where id=p_user;
  if p_is_admin then insert into private.admins(user_id) values(p_user) on conflict do nothing;
  else delete from private.admins where user_id=p_user; end if;
  if p_is_yb then insert into private.board_memberships(user_id,board) values(p_user,'yb') on conflict do nothing;
  else delete from private.board_memberships where user_id=p_user and board='yb'; end if;
  delete from private.member_permissions where user_id=p_user;
  for board_key,mode in select key,value from jsonb_each_text(p_permissions) loop
    if mode<>'default' then insert into private.member_permissions(user_id,board,access) values(p_user,board_key,mode); end if;
  end loop;
  updated:=private.admin_member_snapshot(p_user);
  insert into private.admin_audit(actor_id,target_id,detail) values(actor,p_user,jsonb_build_object('before',previous,'after',updated));
  return updated;
end; $$;

create or replace function public.approve_member(p_user uuid) returns void
language plpgsql security definer set search_path='' as $$
declare member_settings jsonb; full_permissions jsonb;
begin
  if not private.can_manage_members() then raise exception 'Administrator required'; end if;
  member_settings:=private.admin_member_snapshot(p_user);
  if member_settings is null then raise exception 'Member not found'; end if;
  select jsonb_object_agg(board,coalesce(member_settings->'permissions'->>board,'default')) into full_permissions
  from unnest(array['free','gallery','notice','staff','yb']) board;
  perform public.admin_update_member(p_user,'approved',member_settings->>'staff_role',(member_settings->>'is_yb_member')::boolean,
    (member_settings->>'is_admin')::boolean,full_permissions,(member_settings->>'revision')::bigint);
end; $$;

create or replace function public.admin_list_audit() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  if not private.can_manage_members() then raise exception 'Administrator required'; end if;
  select coalesce(jsonb_agg(entry order by id desc),'[]'::jsonb) into result from (
    select l.id,jsonb_build_object('id',l.id,'created_at',l.created_at,'actor',coalesce(p.nickname,'삭제된 회원'),'detail',l.detail) entry
    from private.admin_audit l left join public.profiles p on p.id=l.actor_id order by l.id desc limit 30
  ) recent;
  return result;
end; $$;
commit;

-- Apply after 010. Staff subboards share staff permission; roster shares YB permission.
begin;
alter table public.posts drop constraint posts_category_check;
create temporary table staff_subboard_timestamps on commit drop as select id,updated_at from public.posts where board='staff' and category is null;
update public.posts set category='plot' where board='staff' and category is null;
update public.posts p set updated_at=t.updated_at from staff_subboard_timestamps t where p.id=t.id;
alter table public.posts add constraint posts_category_check check (
  (board='free' and category is not null and category in ('humor','info','chat','question'))
  or (board='gallery' and (category is null or category in ('meetup','flash','meme','attendance')))
  or (board='staff' and category is not null and category in ('plot','minutes'))
  or (board in ('notice','yb') and category is null)
);
create or replace function private.default_free_topic() returns trigger
language plpgsql set search_path='' as $$
begin
  if new.board='free' and new.category is null then new.category:='chat'; end if;
  if new.board='staff' and new.category is null then new.category:='plot'; end if;
  return new;
end; $$;

create table private.team_roster (
  id uuid primary key default gen_random_uuid(),
  role text not null check(role in ('manager','coach','team_manager','pitcher','catcher','infielder','outfielder')),
  name text not null check(char_length(trim(name)) between 1 and 50),
  jersey_number integer check(jersey_number between 0 and 999),
  sort_order integer not null default 0 check(sort_order>=0),
  photo_post_id uuid references public.posts(id) on delete set null,
  photo_index integer not null default 0 check(photo_index between 0 and 4)
);
alter table private.team_roster enable row level security;
revoke all on private.team_roster from public,anon,authenticated;
create function public.get_team_roster() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  if not private.member_approved((select auth.uid())) or not private.can_access_board('yb') then raise exception 'YB membership required'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'role',r.role,'name',r.name,'jersey_number',r.jersey_number,
    'photo_post_id',p.id,'photo',p.images[r.photo_index+1]) order by array_position(array['manager','coach','team_manager','pitcher','catcher','infielder','outfielder'],r.role),r.sort_order,r.name,r.id),'[]'::jsonb)
  into result from private.team_roster r left join public.posts p on p.id=r.photo_post_id and p.board='yb';
  return result;
end; $$;
revoke all on function public.get_team_roster() from public,anon,authenticated;
grant execute on function public.get_team_roster() to authenticated;
commit;

-- Apply after 011. Public humor board and a permission-controlled YB calendar.
begin;
alter table public.posts drop constraint posts_board_check;
alter table public.posts add constraint posts_board_check check(board in ('free','humor','gallery','notice','staff','yb'));
alter table public.posts drop constraint posts_category_check;
alter table public.posts add constraint posts_category_check check (
  (board='free' and category is not null and category in ('humor','info','chat','question'))
  or (board='gallery' and (category is null or category in ('meetup','flash','meme','attendance')))
  or (board='staff' and category is not null and category in ('plot','minutes'))
  or (board in ('humor','notice','yb') and category is null)
);
alter table public.upload_tickets drop constraint upload_tickets_board_check;
alter table public.upload_tickets add constraint upload_tickets_board_check check(board in ('free','humor','gallery','notice','staff','yb'));
alter table private.member_permissions drop constraint member_permissions_board_check;
alter table private.member_permissions add constraint member_permissions_board_check check(board in ('free','humor','gallery','notice','staff','yb'));

create or replace function private.board_permission(p_user uuid,p_board text) returns text
language plpgsql stable security definer set search_path='' as $$
declare override_access text; member_role text;
begin
  if p_board is null or p_board not in ('free','humor','gallery','notice','staff','yb') then return 'deny'; end if;
  if p_user is null then return case when p_board in ('free','humor','gallery','notice') then 'read' else 'deny' end; end if;
  if not private.member_approved(p_user) then return 'deny'; end if;
  if exists(select 1 from private.admins where user_id=p_user) then return 'write'; end if;
  select access into override_access from private.member_permissions where user_id=p_user and board=p_board;
  if found then return override_access; end if;
  select staff_role into member_role from public.profiles where id=p_user;
  if p_board in ('free','humor','gallery') then return 'write'; end if;
  if p_board='notice' then return case when member_role in ('staff','vice_staff') then 'write' else 'read' end; end if;
  if p_board='staff' and member_role in ('staff','vice_staff') then return 'write'; end if;
  if p_board='yb' and private.is_yb_member(p_user) then return 'write'; end if;
  return 'deny';
end; $$;

create or replace function public.get_board_permissions() returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_object_agg(board,jsonb_build_object('read',access in ('read','write'),'write',access='write'))
  from (select board,private.board_permission((select auth.uid()),board) access
    from unnest(array['free','humor','gallery','notice','staff','yb']) board) permissions;
$$;

create or replace function private.admin_member_snapshot(p_user uuid) returns jsonb
language sql stable set search_path='' as $$
  select jsonb_build_object('id',p.id,'username',a.username,'nickname',p.nickname,'region',p.region,'team',p.team,
    'staff_role',p.staff_role,'status',a.status,'revision',a.revision,'created_at',p.created_at,
    'is_admin',exists(select 1 from private.admins where user_id=p.id),'is_yb_member',private.is_yb_member(p.id),
    'permissions',coalesce((select jsonb_object_agg(board,access) from private.member_permissions where user_id=p.id),'{}'::jsonb),
    'effective', (select jsonb_object_agg(board,private.board_permission(p.id,board)) from unnest(array['free','humor','gallery','notice','staff','yb']) board))
  from public.profiles p join private.member_accounts a on a.user_id=p.id where p.id=p_user;
$$;

create or replace function public.admin_update_member(p_user uuid,p_status text,p_staff_role text,p_is_yb boolean,p_is_admin boolean,p_permissions jsonb,p_revision bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor_admin boolean; current_revision bigint; previous jsonb; updated jsonb; board_key text; mode text; actor uuid:=(select auth.uid());
begin
  -- Serialize administrator membership mutations and protect the final administrator.
  perform pg_advisory_xact_lock(hashtextextended('community-member-administration',0));
  if not private.can_manage_members() then raise exception 'Administrator required'; end if;
  actor_admin:=private.is_admin();
  if p_user is null or p_status is null or p_status not in ('pending','approved','rejected','suspended')
    or p_staff_role is null or p_staff_role not in ('member','staff','vice_staff') or p_is_yb is null or p_is_admin is null
    or p_revision is null or jsonb_typeof(p_permissions) is distinct from 'object' then raise exception 'Invalid member settings'; end if;
  if (select count(*) from jsonb_object_keys(p_permissions))<>6
    or exists(select 1 from jsonb_each_text(p_permissions) entry where entry.key not in ('free','humor','gallery','notice','staff','yb') or entry.value not in ('default','deny','read','write') or entry.value is null)
    then raise exception 'Invalid board permissions'; end if;
  select revision into current_revision from private.member_accounts where user_id=p_user for update;
  if not found then raise exception 'Member not found'; end if;
  if current_revision<>p_revision then raise exception 'Member settings changed; reload required'; end if;
  if not actor_admin and (p_is_admin or exists(select 1 from private.admins where user_id=p_user)) then
    raise exception 'Only administrators may manage administrator accounts';
  end if;
  if p_is_admin and p_status<>'approved' then raise exception 'Administrator must remain approved'; end if;
  if p_user=actor and (p_status<>'approved' or (actor_admin and not p_is_admin) or (not actor_admin and p_staff_role not in ('staff','vice_staff'))) then raise exception 'Cannot remove your own administrator access'; end if;
  if exists(select 1 from private.admins where user_id=p_user) and not p_is_admin
    and (select count(*) from private.admins d join private.member_accounts a on a.user_id=d.user_id where a.status='approved')<=1
    then raise exception 'Cannot remove final administrator'; end if;
  previous:=private.admin_member_snapshot(p_user);
  update private.member_accounts set status=p_status,revision=revision+1,
    approved_at=case when p_status='approved' and status<>'approved' then now() else approved_at end,
    approved_by=case when p_status='approved' and status<>'approved' then actor else approved_by end where user_id=p_user;
  update public.profiles set staff_role=p_staff_role where id=p_user;
  if p_is_admin then insert into private.admins(user_id) values(p_user) on conflict do nothing;
  else delete from private.admins where user_id=p_user; end if;
  if p_is_yb then insert into private.board_memberships(user_id,board) values(p_user,'yb') on conflict do nothing;
  else delete from private.board_memberships where user_id=p_user and board='yb'; end if;
  delete from private.member_permissions where user_id=p_user;
  for board_key,mode in select key,value from jsonb_each_text(p_permissions) loop
    if mode<>'default' then insert into private.member_permissions(user_id,board,access) values(p_user,board_key,mode); end if;
  end loop;
  updated:=private.admin_member_snapshot(p_user);
  insert into private.admin_audit(actor_id,target_id,detail) values(actor,p_user,jsonb_build_object('before',previous,'after',updated));
  return updated;
end; $$;

create or replace function public.approve_member(p_user uuid) returns void
language plpgsql security definer set search_path='' as $$
declare member_settings jsonb; full_permissions jsonb;
begin
  if not private.can_manage_members() then raise exception 'Administrator required'; end if;
  member_settings:=private.admin_member_snapshot(p_user);
  if member_settings is null then raise exception 'Member not found'; end if;
  select jsonb_object_agg(board,coalesce(member_settings->'permissions'->>board,'default')) into full_permissions
  from unnest(array['free','humor','gallery','notice','staff','yb']) board;
  perform public.admin_update_member(p_user,'approved',member_settings->>'staff_role',(member_settings->>'is_yb_member')::boolean,
    (member_settings->>'is_admin')::boolean,full_permissions,(member_settings->>'revision')::bigint);
end; $$;

create or replace function public.get_board_access() returns text[]
language sql stable security definer set search_path='' as $$
  select coalesce(array_agg(board),'{}'::text[]) from unnest(array['free','humor','gallery','notice','staff','yb']) board where private.can_access_board(board);
$$;

create table private.team_events (
  id uuid primary key default gen_random_uuid(),
  title text not null check(char_length(trim(title)) between 1 and 80),
  event_date date not null,
  event_time time,
  opponent text not null default '' check(char_length(opponent)<=50),
  location text not null default '' check(char_length(location)<=100),
  memo text not null default '' check(char_length(memo)<=1000),
  revision bigint not null default 1,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index team_events_date on private.team_events(event_date) where deleted_at is null;
alter table private.team_events enable row level security;
revoke all on private.team_events from public,anon,authenticated;

create function public.get_team_events(p_from date,p_to date) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  if not private.member_approved((select auth.uid())) or not private.can_access_board('yb') then raise exception 'YB membership required'; end if;
  if p_from is null or p_to is null or p_to<p_from or p_to-p_from>370 then raise exception 'Invalid date range'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'title',title,'event_date',event_date,'event_time',event_time,
    'opponent',opponent,'location',location,'memo',memo,'revision',revision) order by event_date,event_time nulls last,id),'[]'::jsonb)
  into result from private.team_events where deleted_at is null and event_date between p_from and p_to;
  return result;
end; $$;
revoke all on function public.get_team_events(date,date) from public,anon,authenticated;
grant execute on function public.get_team_events(date,date) to authenticated;

create function public.save_team_event(p_id uuid,p_revision bigint,p_title text,p_date date,p_time time,p_opponent text,p_location text,p_memo text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare saved private.team_events; actor uuid:=(select auth.uid());
begin
  if not private.can_manage_members() or not private.can_write_board('yb') then raise exception 'Calendar management required'; end if;
  if p_date is null or p_title is null or char_length(trim(p_title)) not between 1 and 80
    or p_opponent is null or char_length(p_opponent)>50 or p_location is null or char_length(p_location)>100
    or p_memo is null or char_length(p_memo)>1000 or p_revision is null then raise exception 'Invalid event'; end if;
  if p_id is null then
    if p_revision<>0 then raise exception 'Invalid event revision'; end if;
    insert into private.team_events(title,event_date,event_time,opponent,location,memo,created_by,updated_by)
    values(trim(p_title),p_date,p_time,trim(p_opponent),trim(p_location),trim(p_memo),actor,actor) returning * into saved;
  else
    select * into saved from private.team_events where id=p_id and deleted_at is null for update;
    if not found then raise exception 'Event not found'; end if;
    if saved.revision<>p_revision then raise exception 'Event changed; reload required'; end if;
    update private.team_events set title=trim(p_title),event_date=p_date,event_time=p_time,opponent=trim(p_opponent),location=trim(p_location),memo=trim(p_memo),
      revision=revision+1,updated_at=now(),updated_by=actor where id=p_id returning * into saved;
  end if;
  return jsonb_build_object('id',saved.id,'title',saved.title,'event_date',saved.event_date,'event_time',saved.event_time,'opponent',saved.opponent,'location',saved.location,'memo',saved.memo,'revision',saved.revision);
end; $$;
revoke all on function public.save_team_event(uuid,bigint,text,date,time,text,text,text) from public,anon,authenticated;
grant execute on function public.save_team_event(uuid,bigint,text,date,time,text,text,text) to authenticated;

create function public.delete_team_event(p_id uuid,p_revision bigint) returns void
language plpgsql security definer set search_path='' as $$
declare current_revision bigint;
begin
  if not private.can_manage_members() or not private.can_write_board('yb') then raise exception 'Calendar management required'; end if;
  select revision into current_revision from private.team_events where id=p_id and deleted_at is null for update;
  if not found then raise exception 'Event not found'; end if;
  if p_revision is null or current_revision<>p_revision then raise exception 'Event changed; reload required'; end if;
  update private.team_events set deleted_at=now(),updated_at=now(),updated_by=(select auth.uid()),revision=revision+1 where id=p_id;
end; $$;
revoke all on function public.delete_team_event(uuid,bigint) from public,anon,authenticated;
grant execute on function public.delete_team_event(uuid,bigint) to authenticated;
commit;

-- Apply after 012. Each submenu has an independent permission; roster is publicly readable.
begin;
alter table private.member_permissions drop constraint member_permissions_board_check;
alter table private.member_permissions add constraint member_permissions_board_check check(board in ('free','humor','gallery','notice','staff','yb','gallery_flash','gallery_attendance','gallery_meetup','staff_plot','staff_minutes','yb_roster','yb_calendar','yb_holics'));
insert into private.member_permissions(user_id,board,access)
select user_id,menu,access from private.member_permissions p cross join lateral unnest(case p.board when 'gallery' then array['gallery_flash','gallery_attendance','gallery_meetup'] when 'staff' then array['staff_plot','staff_minutes'] when 'yb' then array['yb_holics','yb_calendar'] else array[]::text[] end) menu on conflict do nothing;
delete from private.member_permissions where board in ('gallery','staff','yb');

create function private.post_menu(p_board text,p_category text) returns text
language sql immutable set search_path='' as $$
  select case when p_board='gallery' then case p_category when 'flash' then 'gallery_flash' when 'attendance' then 'gallery_attendance' when 'meme' then 'gallery_flash' when 'meetup' then 'gallery_meetup' else case when p_category is null then 'gallery_meetup' end end
    when p_board='staff' then case when p_category='minutes' then 'staff_minutes' when p_category='plot' or p_category is null then 'staff_plot' end
    when p_board='yb' then 'yb_holics' when p_board in ('free','humor','notice') then p_board end;
$$;
revoke all on function private.post_menu(text,text) from public,anon,authenticated;

create function private.menu_permission(p_user uuid,p_menu text) returns text
language plpgsql stable security definer set search_path='' as $$
declare override_access text; member_role text;
begin
  if p_menu is null or p_menu not in ('free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','staff_plot','staff_minutes','yb_roster','yb_calendar','yb_holics') then return 'deny'; end if;
  if p_user is null then return case when p_menu in ('free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','yb_roster') then 'read' else 'deny' end; end if;
  if not private.member_approved(p_user) then return 'deny'; end if;
  if exists(select 1 from private.admins where user_id=p_user) then return 'write'; end if;
  select access into override_access from private.member_permissions where user_id=p_user and board=p_menu;
  if found then return override_access; end if;
  select staff_role into member_role from public.profiles where id=p_user;
  if p_menu in ('free','humor','gallery_flash','gallery_attendance','gallery_meetup') then return 'write'; end if;
  if p_menu='notice' then return case when member_role in ('staff','vice_staff') then 'write' else 'read' end; end if;
  if p_menu in ('staff_plot','staff_minutes') then return case when member_role in ('staff','vice_staff') then 'write' else 'deny' end; end if;
  if p_menu='yb_roster' then return case when member_role in ('staff','vice_staff') then 'write' else 'read' end; end if;
  if p_menu='yb_calendar' then return case when private.is_yb_member(p_user) then case when member_role in ('staff','vice_staff') then 'write' else 'read' end else 'deny' end; end if;
  if private.is_yb_member(p_user) then return 'write'; end if;
  return 'deny';
end; $$;
revoke all on function private.menu_permission(uuid,text) from public,anon,authenticated;

create or replace function private.board_permission(p_user uuid,p_board text) returns text
language plpgsql stable security definer set search_path='' as $$
declare modes text[];
begin
  if p_board='gallery' then select array_agg(private.menu_permission(p_user,menu)) into modes from unnest(array['gallery_flash','gallery_attendance','gallery_meetup']) menu;
  elsif p_board='staff' then select array_agg(private.menu_permission(p_user,menu)) into modes from unnest(array['staff_plot','staff_minutes']) menu;
  else return private.menu_permission(p_user,case when p_board='yb' then 'yb_holics' else p_board end); end if;
  return case when 'write'=any(modes) then 'write' when 'read'=any(modes) then 'read' else 'deny' end;
end; $$;

create function private.can_read_post_menu(p_board text,p_category text) returns boolean
language sql stable security definer set search_path='' as $$ select private.menu_permission((select auth.uid()),private.post_menu(p_board,p_category)) in ('read','write'); $$;
create function private.can_write_post_menu(p_board text,p_category text) returns boolean
language sql stable security definer set search_path='' as $$ select private.menu_permission((select auth.uid()),private.post_menu(p_board,p_category))='write'; $$;
revoke all on function private.can_read_post_menu(text,text),private.can_write_post_menu(text,text) from public,anon,authenticated;
grant execute on function private.can_read_post_menu(text,text) to anon,authenticated;
grant execute on function private.can_write_post_menu(text,text) to authenticated;

create function public.get_menu_permissions() returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_object_agg(menu,jsonb_build_object('read',mode in ('read','write'),'write',mode='write')) from
    (select menu,private.menu_permission((select auth.uid()),menu) mode from unnest(array['free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','staff_plot','staff_minutes','yb_roster','yb_calendar','yb_holics']) menu) permissions;
$$;
revoke all on function public.get_menu_permissions() from public,anon,authenticated;
grant execute on function public.get_menu_permissions() to anon,authenticated;

drop policy posts_read on public.posts;
create policy posts_read on public.posts for select to anon,authenticated using(private.can_read_post_menu(board,category));
drop policy posts_write on public.posts;
create policy posts_write on public.posts for insert to authenticated with check(author_id=(select auth.uid()) and private.can_write_post_menu(board,category));
drop policy posts_edit on public.posts;
create policy posts_edit on public.posts for update to authenticated using(author_id=(select auth.uid()) and private.can_write_post_menu(board,category)) with check(author_id=(select auth.uid()) and private.can_write_post_menu(board,category));
drop policy comments_write on public.comments;
create policy comments_write on public.comments for insert to authenticated with check(author_id=(select auth.uid()) and exists(select 1 from public.posts p where p.id=post_id and private.can_write_post_menu(p.board,p.category)));

create function public.member_can_read_post_menu(p_user uuid,p_board text,p_category text) returns boolean
language sql stable security definer set search_path='' as $$ select private.menu_permission(p_user,private.post_menu(p_board,p_category)) in ('read','write'); $$;
create function public.member_can_write_post_menu(p_user uuid,p_board text,p_category text) returns boolean
language sql stable security definer set search_path='' as $$ select private.menu_permission(p_user,private.post_menu(p_board,p_category))='write'; $$;
revoke all on function public.member_can_read_post_menu(uuid,text,text),public.member_can_write_post_menu(uuid,text,text) from public,anon,authenticated;
grant execute on function public.member_can_read_post_menu(uuid,text,text),public.member_can_write_post_menu(uuid,text,text) to service_role;

alter table public.upload_tickets add column category text;
create function public.reserve_menu_upload(p_owner uuid,p_public_id text,p_board text,p_category text) returns void
language plpgsql security definer set search_path='' as $$
begin
  if private.menu_permission(p_owner,private.post_menu(p_board,p_category))<>'write' then raise exception 'Board write denied'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_owner::text,0));
  if (select count(*) from public.upload_tickets where owner_id=p_owner and created_at>now()-interval '1 hour')>=30 or
    (select count(*) from public.upload_tickets where owner_id=p_owner and created_at>now()-interval '1 day')>=100 then raise exception 'Upload quota exceeded'; end if;
  insert into public.upload_tickets(public_id,owner_id,board,category,delivery_type) values(p_public_id,p_owner,p_board,p_category,case when p_board in ('staff','yb') then 'authenticated' else 'upload' end);
end; $$;
revoke all on function public.reserve_menu_upload(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.reserve_menu_upload(uuid,text,text,text) to service_role;

create or replace function public.get_team_roster() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  if private.menu_permission((select auth.uid()),'yb_roster') not in ('read','write') then raise exception 'Roster access required'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'role',r.role,'name',r.name,'jersey_number',r.jersey_number,
    'photo_post_id',p.id,'photo_private',p.board in ('staff','yb'),'photo',p.images[r.photo_index+1]) order by array_position(array['manager','coach','team_manager','pitcher','catcher','infielder','outfielder'],r.role),r.sort_order,r.name,r.id),'[]'::jsonb)
  into result from private.team_roster r left join public.posts p on p.id=r.photo_post_id and private.can_read_post_menu(p.board,p.category);
  return result;
end; $$;
grant execute on function public.get_team_roster() to anon,authenticated;

create or replace function private.admin_member_snapshot(p_user uuid) returns jsonb
language sql stable set search_path='' as $$
  select jsonb_build_object('id',p.id,'username',a.username,'nickname',p.nickname,'region',p.region,'team',p.team,
    'staff_role',p.staff_role,'status',a.status,'revision',a.revision,'created_at',p.created_at,
    'is_admin',exists(select 1 from private.admins where user_id=p.id),'is_yb_member',private.is_yb_member(p.id),
    'permissions',coalesce((select jsonb_object_agg(board,access) from private.member_permissions where user_id=p.id),'{}'::jsonb),
    'effective', (select jsonb_object_agg(board,private.menu_permission(p.id,board)) from unnest(array['free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','staff_plot','staff_minutes','yb_roster','yb_calendar','yb_holics']) board))
  from public.profiles p join private.member_accounts a on a.user_id=p.id where p.id=p_user;
$$;

create or replace function public.admin_update_member(p_user uuid,p_status text,p_staff_role text,p_is_yb boolean,p_is_admin boolean,p_permissions jsonb,p_revision bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor_admin boolean; current_revision bigint; previous jsonb; updated jsonb; board_key text; mode text; actor uuid:=(select auth.uid());
begin
  -- Serialize administrator membership mutations and protect the final administrator.
  perform pg_advisory_xact_lock(hashtextextended('community-member-administration',0));
  if not private.can_manage_members() then raise exception 'Administrator required'; end if;
  actor_admin:=private.is_admin();
  if p_user is null or p_status is null or p_status not in ('pending','approved','rejected','suspended')
    or p_staff_role is null or p_staff_role not in ('member','staff','vice_staff') or p_is_yb is null or p_is_admin is null
    or p_revision is null or jsonb_typeof(p_permissions) is distinct from 'object' then raise exception 'Invalid member settings'; end if;
  if (select count(*) from jsonb_object_keys(p_permissions))<>11
    or exists(select 1 from jsonb_each_text(p_permissions) entry where entry.key not in ('free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','staff_plot','staff_minutes','yb_roster','yb_calendar','yb_holics') or entry.value not in ('default','deny','read','write') or entry.value is null)
    then raise exception 'Invalid board permissions'; end if;
  select revision into current_revision from private.member_accounts where user_id=p_user for update;
  if not found then raise exception 'Member not found'; end if;
  if current_revision<>p_revision then raise exception 'Member settings changed; reload required'; end if;
  if not actor_admin and (p_is_admin or exists(select 1 from private.admins where user_id=p_user)) then
    raise exception 'Only administrators may manage administrator accounts';
  end if;
  if p_is_admin and p_status<>'approved' then raise exception 'Administrator must remain approved'; end if;
  if p_user=actor and (p_status<>'approved' or (actor_admin and not p_is_admin) or (not actor_admin and p_staff_role not in ('staff','vice_staff'))) then raise exception 'Cannot remove your own administrator access'; end if;
  if exists(select 1 from private.admins where user_id=p_user) and not p_is_admin
    and (select count(*) from private.admins d join private.member_accounts a on a.user_id=d.user_id where a.status='approved')<=1
    then raise exception 'Cannot remove final administrator'; end if;
  previous:=private.admin_member_snapshot(p_user);
  update private.member_accounts set status=p_status,revision=revision+1,
    approved_at=case when p_status='approved' and status<>'approved' then now() else approved_at end,
    approved_by=case when p_status='approved' and status<>'approved' then actor else approved_by end where user_id=p_user;
  update public.profiles set staff_role=p_staff_role where id=p_user;
  if p_is_admin then insert into private.admins(user_id) values(p_user) on conflict do nothing;
  else delete from private.admins where user_id=p_user; end if;
  if p_is_yb then insert into private.board_memberships(user_id,board) values(p_user,'yb') on conflict do nothing;
  else delete from private.board_memberships where user_id=p_user and board='yb'; end if;
  delete from private.member_permissions where user_id=p_user;
  for board_key,mode in select key,value from jsonb_each_text(p_permissions) loop
    if mode<>'default' then insert into private.member_permissions(user_id,board,access) values(p_user,board_key,mode); end if;
  end loop;
  updated:=private.admin_member_snapshot(p_user);
  insert into private.admin_audit(actor_id,target_id,detail) values(actor,p_user,jsonb_build_object('before',previous,'after',updated));
  return updated;
end; $$;

create or replace function public.approve_member(p_user uuid) returns void
language plpgsql security definer set search_path='' as $$
declare member_settings jsonb; full_permissions jsonb;
begin
  if not private.can_manage_members() then raise exception 'Administrator required'; end if;
  member_settings:=private.admin_member_snapshot(p_user);
  if member_settings is null then raise exception 'Member not found'; end if;
  select jsonb_object_agg(board,coalesce(member_settings->'permissions'->>board,'default')) into full_permissions
  from unnest(array['free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','staff_plot','staff_minutes','yb_roster','yb_calendar','yb_holics']) board;
  perform public.admin_update_member(p_user,'approved',member_settings->>'staff_role',(member_settings->>'is_yb_member')::boolean,
    (member_settings->>'is_admin')::boolean,full_permissions,(member_settings->>'revision')::bigint);
end; $$;

create or replace function public.get_team_events(p_from date,p_to date) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  if private.menu_permission((select auth.uid()),'yb_calendar') not in ('read','write') then raise exception 'YB membership required'; end if;
  if p_from is null or p_to is null or p_to<p_from or p_to-p_from>370 then raise exception 'Invalid date range'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'title',title,'event_date',event_date,'event_time',event_time,
    'opponent',opponent,'location',location,'memo',memo,'revision',revision) order by event_date,event_time nulls last,id),'[]'::jsonb)
  into result from private.team_events where deleted_at is null and event_date between p_from and p_to;
  return result;
end; $$;

create or replace function public.save_team_event(p_id uuid,p_revision bigint,p_title text,p_date date,p_time time,p_opponent text,p_location text,p_memo text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare saved private.team_events; actor uuid:=(select auth.uid());
begin
  if private.menu_permission((select auth.uid()),'yb_calendar')<>'write' then raise exception 'Calendar management required'; end if;
  if p_date is null or p_title is null or char_length(trim(p_title)) not between 1 and 80
    or p_opponent is null or char_length(p_opponent)>50 or p_location is null or char_length(p_location)>100
    or p_memo is null or char_length(p_memo)>1000 or p_revision is null then raise exception 'Invalid event'; end if;
  if p_id is null then
    if p_revision<>0 then raise exception 'Invalid event revision'; end if;
    insert into private.team_events(title,event_date,event_time,opponent,location,memo,created_by,updated_by)
    values(trim(p_title),p_date,p_time,trim(p_opponent),trim(p_location),trim(p_memo),actor,actor) returning * into saved;
  else
    select * into saved from private.team_events where id=p_id and deleted_at is null for update;
    if not found then raise exception 'Event not found'; end if;
    if saved.revision<>p_revision then raise exception 'Event changed; reload required'; end if;
    update private.team_events set title=trim(p_title),event_date=p_date,event_time=p_time,opponent=trim(p_opponent),location=trim(p_location),memo=trim(p_memo),
      revision=revision+1,updated_at=now(),updated_by=actor where id=p_id returning * into saved;
  end if;
  return jsonb_build_object('id',saved.id,'title',saved.title,'event_date',saved.event_date,'event_time',saved.event_time,'opponent',saved.opponent,'location',saved.location,'memo',saved.memo,'revision',saved.revision);
end; $$;

create or replace function public.delete_team_event(p_id uuid,p_revision bigint) returns void
language plpgsql security definer set search_path='' as $$
declare current_revision bigint;
begin
  if private.menu_permission((select auth.uid()),'yb_calendar')<>'write' then raise exception 'Calendar management required'; end if;
  select revision into current_revision from private.team_events where id=p_id and deleted_at is null for update;
  if not found then raise exception 'Event not found'; end if;
  if p_revision is null or current_revision<>p_revision then raise exception 'Event changed; reload required'; end if;
  update private.team_events set deleted_at=now(),updated_at=now(),updated_by=(select auth.uid()),revision=revision+1 where id=p_id;
end; $$;
commit;

-- Apply after 013. Roster writing is controlled by the yb_roster submenu permission.
begin;
alter table private.team_roster
  add column photo_url text,
  add column revision bigint not null default 1 check(revision>0),
  add column updated_at timestamptz not null default now(),
  add column updated_by uuid references auth.users(id) on delete set null,
  add column deleted_at timestamptz;
alter table public.upload_tickets drop constraint upload_tickets_board_check;
alter table public.upload_tickets add constraint upload_tickets_board_check check(board in ('free','humor','gallery','notice','staff','yb','yb_roster'));

create function public.member_can_write_menu(p_user uuid,p_menu text) returns boolean
language sql stable security definer set search_path='' as $$ select private.menu_permission(p_user,p_menu)='write'; $$;
revoke all on function public.member_can_write_menu(uuid,text) from public,anon,authenticated;
grant execute on function public.member_can_write_menu(uuid,text) to service_role;

create function public.reserve_roster_upload(p_owner uuid,p_public_id text) returns void
language plpgsql security definer set search_path='' as $$
begin
  if private.menu_permission(p_owner,'yb_roster')<>'write' then raise exception 'Roster management required'; end if;
  if p_public_id is null or p_public_id not like 'community/'||p_owner::text||'/%' then raise exception 'Invalid asset'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_owner::text,0));
  if (select count(*) from public.upload_tickets where owner_id=p_owner and created_at>now()-interval '1 hour')>=30 or
    (select count(*) from public.upload_tickets where owner_id=p_owner and created_at>now()-interval '1 day')>=100 then raise exception 'Upload quota exceeded'; end if;
  insert into public.upload_tickets(public_id,owner_id,board,delivery_type) values(p_public_id,p_owner,'yb_roster','upload');
end; $$;
revoke all on function public.reserve_roster_upload(uuid,text) from public,anon,authenticated;
grant execute on function public.reserve_roster_upload(uuid,text) to service_role;

create function public.save_team_roster(p_id uuid,p_revision bigint,p_role text,p_name text,p_number integer,p_sort_order integer,p_photo_url text,p_remove_photo boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); current_row private.team_roster; saved private.team_roster; next_photo text;
begin
  if private.menu_permission(actor,'yb_roster')<>'write' then raise exception 'Roster management required'; end if;
  if p_role is null or p_role not in ('manager','coach','team_manager','pitcher','catcher','infielder','outfielder') or
    p_name is null or char_length(trim(p_name)) not between 1 and 50 or
    (p_number is not null and p_number not between 0 and 999) or p_sort_order is null or p_sort_order<0 or
    p_remove_photo is null or p_revision is null then raise exception 'Invalid roster values'; end if;
  if p_id is not null then
    select * into current_row from private.team_roster where id=p_id and deleted_at is null for update;
    if not found or current_row.revision<>p_revision then raise exception 'Roster changed'; end if;
  elsif p_revision<>0 then raise exception 'Roster changed'; end if;
  next_photo:=case when p_remove_photo then null else coalesce(nullif(p_photo_url,''),current_row.photo_url) end;
  if next_photo is not null and next_photo is distinct from current_row.photo_url and not exists(
    select 1 from public.upload_tickets where owner_id=actor and board='yb_roster' and delivery_type='upload'
      and secure_url=next_photo and verified_at is not null and format in ('jpg','png','webp')
  ) then raise exception 'Verified roster photo required'; end if;
  if p_id is null then
    insert into private.team_roster(role,name,jersey_number,sort_order,photo_url,updated_by)
    values(p_role,trim(p_name),p_number,p_sort_order,next_photo,actor) returning * into saved;
  else
    update private.team_roster set role=p_role,name=trim(p_name),jersey_number=p_number,sort_order=p_sort_order,
      photo_url=next_photo,
      photo_post_id=case when p_remove_photo or next_photo is not null then null else photo_post_id end,
      photo_index=case when p_remove_photo or next_photo is not null then 0 else photo_index end,
      revision=revision+1,updated_at=now(),updated_by=actor where id=p_id returning * into saved;
  end if;
  return jsonb_build_object('id',saved.id,'revision',saved.revision);
end; $$;
revoke all on function public.save_team_roster(uuid,bigint,text,text,integer,integer,text,boolean) from public,anon,authenticated;
grant execute on function public.save_team_roster(uuid,bigint,text,text,integer,integer,text,boolean) to authenticated;

create function public.delete_team_roster(p_id uuid,p_revision bigint) returns void
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); current_revision bigint;
begin
  if private.menu_permission(actor,'yb_roster')<>'write' then raise exception 'Roster management required'; end if;
  select revision into current_revision from private.team_roster where id=p_id and deleted_at is null for update;
  if not found or p_revision is null or current_revision<>p_revision then raise exception 'Roster changed'; end if;
  update private.team_roster set deleted_at=now(),updated_at=now(),updated_by=actor,revision=revision+1 where id=p_id;
end; $$;
revoke all on function public.delete_team_roster(uuid,bigint) from public,anon,authenticated;
grant execute on function public.delete_team_roster(uuid,bigint) to authenticated;

create or replace function public.get_team_roster() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  if private.menu_permission((select auth.uid()),'yb_roster') not in ('read','write') then raise exception 'Roster access required'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'role',r.role,'name',r.name,'jersey_number',r.jersey_number,
    'sort_order',r.sort_order,'revision',r.revision,'photo_url',r.photo_url,
    'photo_post_id',case when r.photo_url is null then p.id end,
    'photo_private',case when r.photo_url is not null then false else coalesce(p.board in ('staff','yb'),false) end,
    'photo',coalesce(r.photo_url,p.images[r.photo_index+1]))
    order by array_position(array['manager','coach','team_manager','pitcher','catcher','infielder','outfielder'],r.role),r.sort_order,r.name,r.id),'[]'::jsonb)
  into result from private.team_roster r left join public.posts p on p.id=r.photo_post_id and private.can_read_post_menu(p.board,p.category)
  where r.deleted_at is null;
  return result;
end; $$;
revoke all on function public.get_team_roster() from public,anon,authenticated;
grant execute on function public.get_team_roster() to anon,authenticated;
commit;

-- Apply after 014. Only administrators, staff, vice-staff and YB directors/managers may edit the roster.
begin;
alter table public.profiles add column yb_role text not null default 'member' check(yb_role in ('member','director','manager'));
-- Existing column-level update grants do not permit members to change yb_role.
create function private.roster_editor_role(p_user uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from private.admins where user_id=p_user)
    or exists(select 1 from public.profiles where id=p_user and (
      staff_role in ('staff','vice_staff') or (private.is_yb_member(p_user) and yb_role in ('director','manager'))
    ));
$$;
revoke all on function private.roster_editor_role(uuid) from public,anon,authenticated;
update private.member_permissions set access='read' where board='yb_roster' and access='write' and not private.roster_editor_role(user_id);

create or replace function private.menu_permission(p_user uuid,p_menu text) returns text
language plpgsql stable security definer set search_path='' as $$
declare override_access text; member_role text;
begin
  if p_menu is null or p_menu not in ('free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','staff_plot','staff_minutes','yb_roster','yb_calendar','yb_holics') then return 'deny'; end if;
  if p_user is null then return case when p_menu in ('free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','yb_roster') then 'read' else 'deny' end; end if;
  if not private.member_approved(p_user) then return 'deny'; end if;
  if exists(select 1 from private.admins where user_id=p_user) then return 'write'; end if;
  select access into override_access from private.member_permissions where user_id=p_user and board=p_menu;
  if found then return case when p_menu='yb_roster' and override_access='write' and not private.roster_editor_role(p_user) then 'read' else override_access end; end if;
  select staff_role into member_role from public.profiles where id=p_user;
  if p_menu in ('free','humor','gallery_flash','gallery_attendance','gallery_meetup') then return 'write'; end if;
  if p_menu='notice' then return case when member_role in ('staff','vice_staff') then 'write' else 'read' end; end if;
  if p_menu in ('staff_plot','staff_minutes') then return case when member_role in ('staff','vice_staff') then 'write' else 'deny' end; end if;
  if p_menu='yb_roster' then return case when private.roster_editor_role(p_user) then 'write' else 'read' end; end if;
  if p_menu='yb_calendar' then return case when private.is_yb_member(p_user) then case when member_role in ('staff','vice_staff') then 'write' else 'read' end else 'deny' end; end if;
  if private.is_yb_member(p_user) then return 'write'; end if;
  return 'deny';
end; $$;

create or replace function private.admin_member_snapshot(p_user uuid) returns jsonb
language sql stable set search_path='' as $$
  select jsonb_build_object('id',p.id,'username',a.username,'nickname',p.nickname,'region',p.region,'team',p.team,
    'staff_role',p.staff_role,'yb_role',case when private.is_yb_member(p.id) then p.yb_role else 'member' end,'status',a.status,'revision',a.revision,'created_at',p.created_at,
    'is_admin',exists(select 1 from private.admins where user_id=p.id),'is_yb_member',private.is_yb_member(p.id),
    'permissions',coalesce((select jsonb_object_agg(board,access) from private.member_permissions where user_id=p.id),'{}'::jsonb),
    'effective', (select jsonb_object_agg(board,private.menu_permission(p.id,board)) from unnest(array['free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','staff_plot','staff_minutes','yb_roster','yb_calendar','yb_holics']) board))
  from public.profiles p join private.member_accounts a on a.user_id=p.id where p.id=p_user;
$$;

create or replace function public.get_my_membership() returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('username',a.username,'nickname',p.nickname,'team',p.team,'region',p.region,
    'status',a.status,'created_at',p.created_at,'staff_role',p.staff_role,
    'yb_role',case when private.is_yb_member(p.id) then p.yb_role else 'member' end,'is_yb_member',private.is_yb_member(p.id),'is_admin',private.is_admin(),'can_manage_members',private.can_manage_members())
  from public.profiles p join private.member_accounts a on a.user_id=p.id where p.id=(select auth.uid());
$$;

drop function public.admin_update_member(uuid,text,text,boolean,boolean,jsonb,bigint);
create or replace function public.admin_update_member(p_user uuid,p_status text,p_staff_role text,p_is_yb boolean,p_yb_role text,p_is_admin boolean,p_permissions jsonb,p_revision bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor_admin boolean; current_revision bigint; previous jsonb; updated jsonb; board_key text; mode text; actor uuid:=(select auth.uid());
begin
  -- Serialize administrator membership mutations and protect the final administrator.
  perform pg_advisory_xact_lock(hashtextextended('community-member-administration',0));
  if not private.can_manage_members() then raise exception 'Administrator required'; end if;
  actor_admin:=private.is_admin();
  if p_user is null or p_status is null or p_status not in ('pending','approved','rejected','suspended')
    or p_staff_role is null or p_staff_role not in ('member','staff','vice_staff') or p_is_yb is null or p_is_admin is null
    or p_yb_role is null or p_yb_role not in ('member','director','manager')
    or p_revision is null or jsonb_typeof(p_permissions) is distinct from 'object' then raise exception 'Invalid member settings'; end if;
  if (select count(*) from jsonb_object_keys(p_permissions))<>11
    or exists(select 1 from jsonb_each_text(p_permissions) entry where entry.key not in ('free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','staff_plot','staff_minutes','yb_roster','yb_calendar','yb_holics') or entry.value not in ('default','deny','read','write') or entry.value is null)
    then raise exception 'Invalid board permissions'; end if;
  if not p_is_yb and p_yb_role<>'member' then raise exception 'YB role requires membership'; end if;
  if p_permissions->>'yb_roster'='write' and not (p_is_admin or p_staff_role in ('staff','vice_staff') or (p_is_yb and p_yb_role in ('director','manager'))) then raise exception 'Roster role required'; end if;
  select revision into current_revision from private.member_accounts where user_id=p_user for update;
  if not found then raise exception 'Member not found'; end if;
  if current_revision<>p_revision then raise exception 'Member settings changed; reload required'; end if;
  if not actor_admin and (p_is_admin or exists(select 1 from private.admins where user_id=p_user)) then
    raise exception 'Only administrators may manage administrator accounts';
  end if;
  if p_is_admin and p_status<>'approved' then raise exception 'Administrator must remain approved'; end if;
  if p_user=actor and (p_status<>'approved' or (actor_admin and not p_is_admin) or (not actor_admin and p_staff_role not in ('staff','vice_staff'))) then raise exception 'Cannot remove your own administrator access'; end if;
  if exists(select 1 from private.admins where user_id=p_user) and not p_is_admin
    and (select count(*) from private.admins d join private.member_accounts a on a.user_id=d.user_id where a.status='approved')<=1
    then raise exception 'Cannot remove final administrator'; end if;
  previous:=private.admin_member_snapshot(p_user);
  update private.member_accounts set status=p_status,revision=revision+1,
    approved_at=case when p_status='approved' and status<>'approved' then now() else approved_at end,
    approved_by=case when p_status='approved' and status<>'approved' then actor else approved_by end where user_id=p_user;
  update public.profiles set staff_role=p_staff_role,yb_role=p_yb_role where id=p_user;
  if p_is_admin then insert into private.admins(user_id) values(p_user) on conflict do nothing;
  else delete from private.admins where user_id=p_user; end if;
  if p_is_yb then insert into private.board_memberships(user_id,board) values(p_user,'yb') on conflict do nothing;
  else delete from private.board_memberships where user_id=p_user and board='yb'; end if;
  delete from private.member_permissions where user_id=p_user;
  for board_key,mode in select key,value from jsonb_each_text(p_permissions) loop
    if mode<>'default' then insert into private.member_permissions(user_id,board,access) values(p_user,board_key,mode); end if;
  end loop;
  updated:=private.admin_member_snapshot(p_user);
  insert into private.admin_audit(actor_id,target_id,detail) values(actor,p_user,jsonb_build_object('before',previous,'after',updated));
  return updated;
end; $$;

revoke all on function public.admin_update_member(uuid,text,text,boolean,text,boolean,jsonb,bigint) from public,anon,authenticated;
grant execute on function public.admin_update_member(uuid,text,text,boolean,text,boolean,jsonb,bigint) to authenticated;

create or replace function public.approve_member(p_user uuid) returns void
language plpgsql security definer set search_path='' as $$
declare member_settings jsonb; full_permissions jsonb;
begin
  if not private.can_manage_members() then raise exception 'Administrator required'; end if;
  member_settings:=private.admin_member_snapshot(p_user);
  if member_settings is null then raise exception 'Member not found'; end if;
  select jsonb_object_agg(board,coalesce(member_settings->'permissions'->>board,'default')) into full_permissions
  from unnest(array['free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','staff_plot','staff_minutes','yb_roster','yb_calendar','yb_holics']) board;
  perform public.admin_update_member(p_user,'approved',member_settings->>'staff_role',(member_settings->>'is_yb_member')::boolean,
    coalesce(member_settings->>'yb_role','member'),(member_settings->>'is_admin')::boolean,full_permissions,(member_settings->>'revision')::bigint);
end; $$;
commit;

-- Apply after 015. Timed account restrictions use [start, end) and expire without a background job.
begin;
alter table private.member_accounts add column restriction_start timestamptz,
  add column restriction_end timestamptz,
  add column restriction_reason text not null default '' check(char_length(restriction_reason)<=300),
  add constraint member_restriction_dates check(
    (restriction_start is null and restriction_end is null) or
    (restriction_start is not null and restriction_end is not null and isfinite(restriction_start) and isfinite(restriction_end) and restriction_end>restriction_start)
  );
create function private.restriction_active(p_user uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select coalesce((select status='suspended' or (status='approved' and restriction_start<=now() and now()<restriction_end)
    from private.member_accounts where user_id=p_user),false);
$$;
revoke all on function private.restriction_active(uuid) from public,anon,authenticated;
create or replace function private.member_approved(p_user uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from private.member_accounts where user_id=p_user and status='approved') and not private.restriction_active(p_user);
$$;

create or replace function private.admin_member_snapshot(p_user uuid) returns jsonb
language sql stable set search_path='' as $$
  select jsonb_build_object('id',p.id,'username',a.username,'nickname',p.nickname,'region',p.region,'team',p.team,
    'staff_role',p.staff_role,'yb_role',case when private.is_yb_member(p.id) then p.yb_role else 'member' end,'status',a.status,'revision',a.revision,'created_at',p.created_at,'restriction_start',a.restriction_start,'restriction_end',a.restriction_end,'restriction_reason',a.restriction_reason,'is_restricted',private.restriction_active(p.id),
    'is_admin',exists(select 1 from private.admins where user_id=p.id),'is_yb_member',private.is_yb_member(p.id),
    'permissions',coalesce((select jsonb_object_agg(board,access) from private.member_permissions where user_id=p.id),'{}'::jsonb),
    'effective', (select jsonb_object_agg(board,private.menu_permission(p.id,board)) from unnest(array['free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','staff_plot','staff_minutes','yb_roster','yb_calendar','yb_holics']) board))
  from public.profiles p join private.member_accounts a on a.user_id=p.id where p.id=p_user;
$$;

create or replace function public.get_my_membership() returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('username',a.username,'nickname',p.nickname,'team',p.team,'region',p.region,
    'status',a.status,'revision',a.revision,'server_time',now(),'restriction_start',a.restriction_start,'restriction_end',a.restriction_end,'restriction_reason',a.restriction_reason,'is_restricted',private.restriction_active(p.id),'created_at',p.created_at,'staff_role',p.staff_role,
    'yb_role',case when private.is_yb_member(p.id) then p.yb_role else 'member' end,'is_yb_member',private.is_yb_member(p.id),'is_admin',private.is_admin(),'can_manage_members',private.can_manage_members())
  from public.profiles p join private.member_accounts a on a.user_id=p.id where p.id=(select auth.uid());
$$;

create or replace function public.admin_list_members(p_query text default '',p_status text default null,p_limit integer default 20,p_offset integer default 0) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare query_text text; result jsonb;
begin
  if not private.can_manage_members() then raise exception 'Administrator required'; end if;
  if p_query is null or char_length(p_query)>100 or p_limit is null or p_limit not between 1 and 50 or p_offset is null or p_offset not between 0 and 1000000
    or (p_status is not null and p_status not in ('pending','approved','rejected','suspended')) then raise exception 'Invalid filter'; end if;
  query_text:=lower(trim(p_query));
  with filtered as (
    select p.id,p.created_at,a.status from public.profiles p join private.member_accounts a on a.user_id=p.id
    where (p_status is null or
      (p_status='approved' and a.status='approved' and not private.restriction_active(p.id)) or
      (p_status='suspended' and private.restriction_active(p.id)) or
      (p_status in ('pending','rejected') and a.status=p_status))
    and (query_text='' or strpos(lower(a.username||' '||p.nickname||' '||coalesce(p.region,'')),query_text)>0)
  ), page as (select * from filtered order by created_at desc,id limit p_limit offset p_offset)
  select jsonb_build_object('members',coalesce((select jsonb_agg(private.admin_member_snapshot(id) order by created_at desc,id) from page),'[]'::jsonb),
    'total',(select count(*) from filtered),'stats', (select jsonb_build_object('pending',count(*) filter(where status='pending'),
      'approved',count(*) filter(where status='approved' and not private.restriction_active(user_id)),
      'rejected',count(*) filter(where status='rejected'),'suspended',count(*) filter(where private.restriction_active(user_id))) from private.member_accounts)) into result;
  return result;
end; $$;

create function private.lock_restriction_target(p_user uuid,p_revision bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare target private.member_accounts; actor uuid:=(select auth.uid());
begin
  perform pg_advisory_xact_lock(hashtextextended('community-member-administration',0));
  if not private.can_manage_members() then raise exception 'Administrator required'; end if;
  if p_user is null or p_revision is null then raise exception 'Invalid member settings'; end if;
  select * into target from private.member_accounts where user_id=p_user for update;
  if not found then raise exception 'Member not found'; end if;
  if target.revision<>p_revision then raise exception 'Member settings changed; reload required'; end if;
  if target.status not in ('approved','suspended') then raise exception 'Approved member required'; end if;
  if actor=p_user then raise exception 'Cannot restrict your own account'; end if;
  if not private.is_admin() and exists(select 1 from private.admins where user_id=p_user) then raise exception 'Only administrators may manage administrator accounts'; end if;
  return private.admin_member_snapshot(p_user);
end; $$;
revoke all on function private.lock_restriction_target(uuid,bigint) from public,anon,authenticated;

create function public.admin_set_restriction(p_user uuid,p_start timestamptz,p_end timestamptz,p_reason text,p_revision bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare previous jsonb; updated jsonb;
begin
  previous:=private.lock_restriction_target(p_user,p_revision);
  if p_start is null or p_end is null or not isfinite(p_start) or not isfinite(p_end) or p_end<=p_start or p_end<=now()
    or p_reason is null or char_length(p_reason)>300 then raise exception 'Invalid restriction dates'; end if;
  if exists(select 1 from private.admins where user_id=p_user)
    and (select count(*) from private.admins where private.member_approved(user_id))<=1 then raise exception 'Cannot restrict final administrator'; end if;
  update private.member_accounts set status='approved',restriction_start=p_start,restriction_end=p_end,restriction_reason=trim(p_reason),revision=revision+1 where user_id=p_user;
  updated:=private.admin_member_snapshot(p_user);
  insert into private.admin_audit(actor_id,target_id,detail) values((select auth.uid()),p_user,jsonb_build_object('action','restriction_set','before',previous,'after',updated));
  return updated;
end; $$;
revoke all on function public.admin_set_restriction(uuid,timestamptz,timestamptz,text,bigint) from public,anon,authenticated;
grant execute on function public.admin_set_restriction(uuid,timestamptz,timestamptz,text,bigint) to authenticated;

create function public.admin_clear_restriction(p_user uuid,p_revision bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare previous jsonb; updated jsonb;
begin
  previous:=private.lock_restriction_target(p_user,p_revision);
  update private.member_accounts set status='approved',restriction_start=null,restriction_end=null,restriction_reason='',revision=revision+1 where user_id=p_user;
  updated:=private.admin_member_snapshot(p_user);
  insert into private.admin_audit(actor_id,target_id,detail) values((select auth.uid()),p_user,jsonb_build_object('action','restriction_clear','before',previous,'after',updated));
  return updated;
end; $$;
revoke all on function public.admin_clear_restriction(uuid,bigint) from public,anon,authenticated;
grant execute on function public.admin_clear_restriction(uuid,bigint) to authenticated;
commit;

-- Apply after 016. Staff and vice-staff may use the Holics board without YB membership.
begin;
create or replace function private.menu_permission(p_user uuid,p_menu text) returns text
language plpgsql stable security definer set search_path='' as $$
declare override_access text; member_role text;
begin
  if p_menu is null or p_menu not in ('free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','staff_plot','staff_minutes','yb_roster','yb_calendar','yb_holics') then return 'deny'; end if;
  if p_user is null then return case when p_menu in ('free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','yb_roster') then 'read' else 'deny' end; end if;
  if not private.member_approved(p_user) then return 'deny'; end if;
  if exists(select 1 from private.admins where user_id=p_user) then return 'write'; end if;
  select access into override_access from private.member_permissions where user_id=p_user and board=p_menu;
  if found then return case when p_menu='yb_roster' and override_access='write' and not private.roster_editor_role(p_user) then 'read' else override_access end; end if;
  select staff_role into member_role from public.profiles where id=p_user;
  if p_menu in ('free','humor','gallery_flash','gallery_attendance','gallery_meetup') then return 'write'; end if;
  if p_menu='notice' then return case when member_role in ('staff','vice_staff') then 'write' else 'read' end; end if;
  if p_menu in ('staff_plot','staff_minutes') then return case when member_role in ('staff','vice_staff') then 'write' else 'deny' end; end if;
  if p_menu='yb_roster' then return case when private.roster_editor_role(p_user) then 'write' else 'read' end; end if;
  if p_menu='yb_calendar' then return case when private.is_yb_member(p_user) then case when member_role in ('staff','vice_staff') then 'write' else 'read' end else 'deny' end; end if;
  if member_role in ('staff','vice_staff') or private.is_yb_member(p_user) then return 'write'; end if;
  return 'deny';
end; $$;
commit;

-- Apply after 017. Calendar reading is public; writing, restrictions and explicit overrides remain enforced.
begin;
create or replace function private.menu_permission(p_user uuid,p_menu text) returns text
language plpgsql stable security definer set search_path='' as $$
declare override_access text; member_role text;
begin
  if p_menu is null or p_menu not in ('free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','staff_plot','staff_minutes','yb_roster','yb_calendar','yb_holics') then return 'deny'; end if;
  if p_user is null then return case when p_menu in ('free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','yb_roster','yb_calendar') then 'read' else 'deny' end; end if;
  if not private.member_approved(p_user) then return 'deny'; end if;
  if exists(select 1 from private.admins where user_id=p_user) then return 'write'; end if;
  select access into override_access from private.member_permissions where user_id=p_user and board=p_menu;
  if found then return case when p_menu='yb_roster' and override_access='write' and not private.roster_editor_role(p_user) then 'read' else override_access end; end if;
  select staff_role into member_role from public.profiles where id=p_user;
  if p_menu in ('free','humor','gallery_flash','gallery_attendance','gallery_meetup') then return 'write'; end if;
  if p_menu='notice' then return case when member_role in ('staff','vice_staff') then 'write' else 'read' end; end if;
  if p_menu in ('staff_plot','staff_minutes') then return case when member_role in ('staff','vice_staff') then 'write' else 'deny' end; end if;
  if p_menu='yb_roster' then return case when private.roster_editor_role(p_user) then 'write' else 'read' end; end if;
  if p_menu='yb_calendar' then return case when private.is_yb_member(p_user) and member_role in ('staff','vice_staff') then 'write' else 'read' end; end if;
  if member_role in ('staff','vice_staff') or private.is_yb_member(p_user) then return 'write'; end if;
  return 'deny';
end; $$;

create or replace function public.get_team_events(p_from date,p_to date) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  if private.menu_permission((select auth.uid()),'yb_calendar') not in ('read','write') then raise exception 'Calendar access required'; end if;
  if p_from is null or p_to is null or p_to<p_from or p_to-p_from>370 then raise exception 'Invalid date range'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'title',title,'event_date',event_date,'event_time',event_time,
    'opponent',opponent,'location',location,'memo',memo,'revision',revision) order by event_date,event_time nulls last,id),'[]'::jsonb)
  into result from private.team_events where deleted_at is null and event_date between p_from and p_to;
  return result;
end; $$;
revoke all on function public.get_team_events(date,date) from public,anon,authenticated;
grant execute on function public.get_team_events(date,date) to anon,authenticated;
commit;

-- Apply after 018. Member managers can change the supported KBO team in the same revision-protected transaction.
begin;
drop function public.admin_update_member(uuid,text,text,boolean,text,boolean,jsonb,bigint);
create or replace function public.admin_update_member(p_user uuid,p_status text,p_staff_role text,p_is_yb boolean,p_yb_role text,p_is_admin boolean,p_team text,p_permissions jsonb,p_revision bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor_admin boolean; current_revision bigint; previous jsonb; updated jsonb; board_key text; mode text; actor uuid:=(select auth.uid());
begin
  -- Serialize administrator membership mutations and protect the final administrator.
  perform pg_advisory_xact_lock(hashtextextended('community-member-administration',0));
  if not private.can_manage_members() then raise exception 'Administrator required'; end if;
  actor_admin:=private.is_admin();
  if p_user is null or p_status is null or p_status not in ('pending','approved','rejected','suspended')
    or p_staff_role is null or p_staff_role not in ('member','staff','vice_staff') or p_is_yb is null or p_is_admin is null
    or p_yb_role is null or p_yb_role not in ('member','director','manager')
    or (p_team is not null and p_team not in ('kia','samsung','lg','doosan','kt','ssg','lotte','hanwha','nc','kiwoom'))
    or p_revision is null or jsonb_typeof(p_permissions) is distinct from 'object' then raise exception 'Invalid member settings'; end if;
  if (select count(*) from jsonb_object_keys(p_permissions))<>11
    or exists(select 1 from jsonb_each_text(p_permissions) entry where entry.key not in ('free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','staff_plot','staff_minutes','yb_roster','yb_calendar','yb_holics') or entry.value not in ('default','deny','read','write') or entry.value is null)
    then raise exception 'Invalid board permissions'; end if;
  if not p_is_yb and p_yb_role<>'member' then raise exception 'YB role requires membership'; end if;
  if p_permissions->>'yb_roster'='write' and not (p_is_admin or p_staff_role in ('staff','vice_staff') or (p_is_yb and p_yb_role in ('director','manager'))) then raise exception 'Roster role required'; end if;
  select revision into current_revision from private.member_accounts where user_id=p_user for update;
  if not found then raise exception 'Member not found'; end if;
  if current_revision<>p_revision then raise exception 'Member settings changed; reload required'; end if;
  if not actor_admin and (p_is_admin or exists(select 1 from private.admins where user_id=p_user)) then
    raise exception 'Only administrators may manage administrator accounts';
  end if;
  if p_is_admin and p_status<>'approved' then raise exception 'Administrator must remain approved'; end if;
  if p_user=actor and (p_status<>'approved' or (actor_admin and not p_is_admin) or (not actor_admin and p_staff_role not in ('staff','vice_staff'))) then raise exception 'Cannot remove your own administrator access'; end if;
  if exists(select 1 from private.admins where user_id=p_user) and not p_is_admin
    and (select count(*) from private.admins d join private.member_accounts a on a.user_id=d.user_id where a.status='approved')<=1
    then raise exception 'Cannot remove final administrator'; end if;
  previous:=private.admin_member_snapshot(p_user);
  update private.member_accounts set status=p_status,revision=revision+1,
    approved_at=case when p_status='approved' and status<>'approved' then now() else approved_at end,
    approved_by=case when p_status='approved' and status<>'approved' then actor else approved_by end where user_id=p_user;
  update public.profiles set staff_role=p_staff_role,yb_role=p_yb_role,team=p_team where id=p_user;
  if p_is_admin then insert into private.admins(user_id) values(p_user) on conflict do nothing;
  else delete from private.admins where user_id=p_user; end if;
  if p_is_yb then insert into private.board_memberships(user_id,board) values(p_user,'yb') on conflict do nothing;
  else delete from private.board_memberships where user_id=p_user and board='yb'; end if;
  delete from private.member_permissions where user_id=p_user;
  for board_key,mode in select key,value from jsonb_each_text(p_permissions) loop
    if mode<>'default' then insert into private.member_permissions(user_id,board,access) values(p_user,board_key,mode); end if;
  end loop;
  updated:=private.admin_member_snapshot(p_user);
  insert into private.admin_audit(actor_id,target_id,detail) values(actor,p_user,jsonb_build_object('before',previous,'after',updated));
  return updated;
end; $$;

revoke all on function public.admin_update_member(uuid,text,text,boolean,text,boolean,text,jsonb,bigint) from public,anon,authenticated;
grant execute on function public.admin_update_member(uuid,text,text,boolean,text,boolean,text,jsonb,bigint) to authenticated;

create or replace function public.approve_member(p_user uuid) returns void
language plpgsql security definer set search_path='' as $$
declare member_settings jsonb; full_permissions jsonb;
begin
  if not private.can_manage_members() then raise exception 'Administrator required'; end if;
  member_settings:=private.admin_member_snapshot(p_user);
  if member_settings is null then raise exception 'Member not found'; end if;
  select jsonb_object_agg(board,coalesce(member_settings->'permissions'->>board,'default')) into full_permissions
  from unnest(array['free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','staff_plot','staff_minutes','yb_roster','yb_calendar','yb_holics']) board;
  perform public.admin_update_member(p_user,'approved',member_settings->>'staff_role',(member_settings->>'is_yb_member')::boolean,
    coalesce(member_settings->>'yb_role','member'),(member_settings->>'is_admin')::boolean,member_settings->>'team',full_permissions,(member_settings->>'revision')::bigint);
end; $$;
commit;

-- Apply after 019. Moderator recruitment posts and one automatic RSVP comment per member.
begin;

alter table public.posts drop constraint posts_board_check;
alter table public.posts add constraint posts_board_check check(board in ('free','humor','gallery','notice','staff','yb','recruit'));

alter table public.upload_tickets drop constraint upload_tickets_board_check;
alter table public.upload_tickets add constraint upload_tickets_board_check check(board in ('free','humor','gallery','notice','staff','yb','yb_roster','recruit'));

alter table private.member_permissions drop constraint member_permissions_board_check;
alter table private.member_permissions add constraint member_permissions_board_check check(board in ('free','humor','gallery','notice','staff','yb','gallery_flash','gallery_attendance','gallery_meetup','staff_plot','staff_minutes','yb_roster','yb_calendar','yb_holics','recruit'));

alter table public.posts drop constraint posts_category_check;
alter table public.posts add constraint posts_category_check check (
  (board='free' and category is not null and category in ('humor','info','chat','question'))
  or (board='gallery' and (category is null or category in ('meetup','flash','meme','attendance')))
  or (board='staff' and category is not null and category in ('plot','minutes'))
  or (board in ('humor','notice','yb','recruit') and category is null));

create or replace function private.post_menu(p_board text,p_category text) returns text
language sql immutable set search_path='' as $$
  select case when p_board='gallery' then case p_category when 'flash' then 'gallery_flash' when 'attendance' then 'gallery_attendance' when 'meme' then 'gallery_flash' when 'meetup' then 'gallery_meetup' else case when p_category is null then 'gallery_meetup' end end
    when p_board='staff' then case when p_category='minutes' then 'staff_minutes' when p_category='plot' or p_category is null then 'staff_plot' end
    when p_board='yb' then 'yb_holics' when p_board in ('free','humor','notice','recruit') then p_board end;
$$;

create or replace function private.menu_permission(p_user uuid,p_menu text) returns text
language plpgsql stable security definer set search_path='' as $$
declare override_access text; member_role text;
begin
  if p_menu is null or p_menu not in ('free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','staff_plot','staff_minutes','yb_roster','yb_calendar','yb_holics','recruit') then return 'deny'; end if;
  if p_user is null then return case when p_menu in ('free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','yb_roster','yb_calendar','recruit') then 'read' else 'deny' end; end if;
  if not private.member_approved(p_user) then return 'deny'; end if;
  if exists(select 1 from private.admins where user_id=p_user) then return 'write'; end if;
  select staff_role into member_role from public.profiles where id=p_user;
  select access into override_access from private.member_permissions where user_id=p_user and board=p_menu;
  if found then return case when p_menu='yb_roster' and override_access='write' and not private.roster_editor_role(p_user) then 'read' when p_menu='recruit' and override_access='write' and member_role not in ('staff','vice_staff') then 'read' else override_access end; end if;
  select staff_role into member_role from public.profiles where id=p_user;
  if p_menu in ('free','humor','gallery_flash','gallery_attendance','gallery_meetup') then return 'write'; end if;
  if p_menu='recruit' then return case when member_role in ('staff','vice_staff') then 'write' else 'read' end; end if;
  if p_menu='notice' then return case when member_role in ('staff','vice_staff') then 'write' else 'read' end; end if;
  if p_menu in ('staff_plot','staff_minutes') then return case when member_role in ('staff','vice_staff') then 'write' else 'deny' end; end if;
  if p_menu='yb_roster' then return case when private.roster_editor_role(p_user) then 'write' else 'read' end; end if;
  if p_menu='yb_calendar' then return case when private.is_yb_member(p_user) and member_role in ('staff','vice_staff') then 'write' else 'read' end; end if;
  if member_role in ('staff','vice_staff') or private.is_yb_member(p_user) then return 'write'; end if;
  return 'deny';
end; $$;

create or replace function public.get_menu_permissions() returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_object_agg(menu,jsonb_build_object('read',mode in ('read','write'),'write',mode='write')) from
    (select menu,private.menu_permission((select auth.uid()),menu) mode from unnest(array['free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','staff_plot','staff_minutes','yb_roster','yb_calendar','yb_holics','recruit']) menu) permissions;
$$;

create or replace function private.admin_member_snapshot(p_user uuid) returns jsonb
language sql stable set search_path='' as $$
  select jsonb_build_object('id',p.id,'username',a.username,'nickname',p.nickname,'region',p.region,'team',p.team,
    'staff_role',p.staff_role,'yb_role',case when private.is_yb_member(p.id) then p.yb_role else 'member' end,'status',a.status,'revision',a.revision,'created_at',p.created_at,'restriction_start',a.restriction_start,'restriction_end',a.restriction_end,'restriction_reason',a.restriction_reason,'is_restricted',private.restriction_active(p.id),
    'is_admin',exists(select 1 from private.admins where user_id=p.id),'is_yb_member',private.is_yb_member(p.id),
    'permissions',coalesce((select jsonb_object_agg(board,access) from private.member_permissions where user_id=p.id),'{}'::jsonb),
    'effective', (select jsonb_object_agg(board,private.menu_permission(p.id,board)) from unnest(array['free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','staff_plot','staff_minutes','yb_roster','yb_calendar','yb_holics','recruit']) board))
  from public.profiles p join private.member_accounts a on a.user_id=p.id where p.id=p_user;
$$;

create or replace function public.approve_member(p_user uuid) returns void
language plpgsql security definer set search_path='' as $$
declare member_settings jsonb; full_permissions jsonb;
begin
  if not private.can_manage_members() then raise exception 'Administrator required'; end if;
  member_settings:=private.admin_member_snapshot(p_user);
  if member_settings is null then raise exception 'Member not found'; end if;
  select jsonb_object_agg(board,coalesce(member_settings->'permissions'->>board,'default')) into full_permissions
  from unnest(array['free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','staff_plot','staff_minutes','yb_roster','yb_calendar','yb_holics','recruit']) board;
  perform public.admin_update_member(p_user,'approved',member_settings->>'staff_role',(member_settings->>'is_yb_member')::boolean,
    coalesce(member_settings->>'yb_role','member'),(member_settings->>'is_admin')::boolean,member_settings->>'team',full_permissions,(member_settings->>'revision')::bigint);
end; $$;

create or replace function public.get_board_permissions() returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_object_agg(board,jsonb_build_object('read',access in ('read','write'),'write',access='write'))
  from (select board,private.board_permission((select auth.uid()),board) access
    from unnest(array['free','humor','gallery','notice','staff','yb','recruit']) board) permissions;
$$;

create or replace function public.get_board_access() returns text[]
language sql stable security definer set search_path='' as $$
  select coalesce(array_agg(board),'{}'::text[]) from unnest(array['free','humor','gallery','notice','staff','yb','recruit']) board where private.can_access_board(board);
$$;

create or replace function public.admin_update_member(p_user uuid,p_status text,p_staff_role text,p_is_yb boolean,p_yb_role text,p_is_admin boolean,p_team text,p_permissions jsonb,p_revision bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor_admin boolean; current_revision bigint; previous jsonb; updated jsonb; board_key text; mode text; actor uuid:=(select auth.uid());
begin
  -- Serialize administrator membership mutations and protect the final administrator.
  perform pg_advisory_xact_lock(hashtextextended('community-member-administration',0));
  if not private.can_manage_members() then raise exception 'Administrator required'; end if;
  actor_admin:=private.is_admin();
  if p_user is null or p_status is null or p_status not in ('pending','approved','rejected','suspended')
    or p_staff_role is null or p_staff_role not in ('member','staff','vice_staff') or p_is_yb is null or p_is_admin is null
    or p_yb_role is null or p_yb_role not in ('member','director','manager')
    or (p_team is not null and p_team not in ('kia','samsung','lg','doosan','kt','ssg','lotte','hanwha','nc','kiwoom'))
    or p_revision is null or jsonb_typeof(p_permissions) is distinct from 'object' then raise exception 'Invalid member settings'; end if;
  if (select count(*) from jsonb_object_keys(p_permissions))<>12
    or exists(select 1 from jsonb_each_text(p_permissions) entry where entry.key not in ('free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','staff_plot','staff_minutes','yb_roster','yb_calendar','yb_holics','recruit') or entry.value not in ('default','deny','read','write') or entry.value is null)
    then raise exception 'Invalid board permissions'; end if;
  if not p_is_yb and p_yb_role<>'member' then raise exception 'YB role requires membership'; end if;
  if p_permissions->>'yb_roster'='write' and not (p_is_admin or p_staff_role in ('staff','vice_staff') or (p_is_yb and p_yb_role in ('director','manager'))) then raise exception 'Roster role required'; end if;
  if p_permissions->>'recruit'='write' and not (p_is_admin or p_staff_role in ('staff','vice_staff')) then raise exception 'Recruitment moderator required'; end if;
  select revision into current_revision from private.member_accounts where user_id=p_user for update;
  if not found then raise exception 'Member not found'; end if;
  if current_revision<>p_revision then raise exception 'Member settings changed; reload required'; end if;
  if not actor_admin and (p_is_admin or exists(select 1 from private.admins where user_id=p_user)) then
    raise exception 'Only administrators may manage administrator accounts';
  end if;
  if p_is_admin and p_status<>'approved' then raise exception 'Administrator must remain approved'; end if;
  if p_user=actor and (p_status<>'approved' or (actor_admin and not p_is_admin) or (not actor_admin and p_staff_role not in ('staff','vice_staff'))) then raise exception 'Cannot remove your own administrator access'; end if;
  if exists(select 1 from private.admins where user_id=p_user) and not p_is_admin
    and (select count(*) from private.admins d join private.member_accounts a on a.user_id=d.user_id where a.status='approved')<=1
    then raise exception 'Cannot remove final administrator'; end if;
  previous:=private.admin_member_snapshot(p_user);
  update private.member_accounts set status=p_status,revision=revision+1,
    approved_at=case when p_status='approved' and status<>'approved' then now() else approved_at end,
    approved_by=case when p_status='approved' and status<>'approved' then actor else approved_by end where user_id=p_user;
  update public.profiles set staff_role=p_staff_role,yb_role=p_yb_role,team=p_team where id=p_user;
  if p_is_admin then insert into private.admins(user_id) values(p_user) on conflict do nothing;
  else delete from private.admins where user_id=p_user; end if;
  if p_is_yb then insert into private.board_memberships(user_id,board) values(p_user,'yb') on conflict do nothing;
  else delete from private.board_memberships where user_id=p_user and board='yb'; end if;
  delete from private.member_permissions where user_id=p_user;
  for board_key,mode in select key,value from jsonb_each_text(p_permissions) loop
    if mode<>'default' then insert into private.member_permissions(user_id,board,access) values(p_user,board_key,mode); end if;
  end loop;
  updated:=private.admin_member_snapshot(p_user);
  insert into private.admin_audit(actor_id,target_id,detail) values(actor,p_user,jsonb_build_object('before',previous,'after',updated));
  return updated;
end; $$;

create table private.recruitment_responses (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  comment_id uuid not null unique references public.comments(id) on delete cascade,
  response text not null check(response in ('attend','decline')),
  updated_at timestamptz not null default now(),
  primary key(post_id,user_id));
alter table private.recruitment_responses enable row level security;
revoke all on private.recruitment_responses from public,anon,authenticated;

create function public.get_recruitment_response(p_post uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  if not exists(select 1 from public.posts where id=p_post and board='recruit') then raise exception 'Recruitment post required'; end if;
  if private.menu_permission((select auth.uid()),'recruit') not in ('read','write') then raise exception 'Recruitment access required'; end if;
  select jsonb_build_object('attend',count(*) filter(where response='attend'),'decline',count(*) filter(where response='decline'),
    'mine',max(response) filter(where user_id=(select auth.uid()))) into result from private.recruitment_responses where post_id=p_post;
  return result;
end; $$;
revoke all on function public.get_recruitment_response(uuid) from public,anon,authenticated;
grant execute on function public.get_recruitment_response(uuid) to anon,authenticated;

create function public.set_recruitment_response(p_post uuid,p_response text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); existing private.recruitment_responses; comment uuid; message text;
begin
  if actor is null or not private.member_approved(actor) or private.menu_permission(actor,'recruit') not in ('read','write') then raise exception 'Approved member required'; end if;
  if p_response is null or p_response not in ('attend','decline') then raise exception 'Invalid recruitment response'; end if;
  perform 1 from public.posts where id=p_post and board='recruit' for share;
  if not found then raise exception 'Recruitment post required'; end if;
  perform pg_advisory_xact_lock(hashtextextended('recruitment:'||p_post::text||':'||actor::text,0));
  select * into existing from private.recruitment_responses where post_id=p_post and user_id=actor for update;
  message:=case p_response when 'attend' then '참석합니다.' else '불참합니다.' end;
  if found then
    if existing.response<>p_response then
      update public.comments set body=message where id=existing.comment_id and author_id=actor and post_id=p_post;
      update private.recruitment_responses set response=p_response,updated_at=now() where post_id=p_post and user_id=actor;
    end if;
  else
    insert into public.comments(post_id,author_id,body) values(p_post,actor,message) returning id into comment;
    insert into private.recruitment_responses(post_id,user_id,comment_id,response) values(p_post,actor,comment,p_response);
  end if;
  return public.get_recruitment_response(p_post);
end; $$;
revoke all on function public.set_recruitment_response(uuid,text) from public,anon,authenticated;
grant execute on function public.set_recruitment_response(uuid,text) to authenticated;
commit;

-- Apply after 020. Preserve role groups; number ascending, unnumbered members last.
begin;
create or replace function public.get_team_roster() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  if private.menu_permission((select auth.uid()),'yb_roster') not in ('read','write') then raise exception 'Roster access required'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'role',r.role,'name',r.name,'jersey_number',r.jersey_number,
    'sort_order',r.sort_order,'revision',r.revision,'photo_url',r.photo_url,
    'photo_post_id',case when r.photo_url is null then p.id end,
    'photo_private',case when r.photo_url is not null then false else coalesce(p.board in ('staff','yb'),false) end,
    'photo',coalesce(r.photo_url,p.images[r.photo_index+1]))
    order by array_position(array['manager','coach','team_manager','pitcher','catcher','infielder','outfielder'],r.role),r.jersey_number asc nulls last,r.name,r.id),'[]'::jsonb)
  into result from private.team_roster r left join public.posts p on p.id=r.photo_post_id and private.can_read_post_menu(p.board,p.category)
  where r.deleted_at is null;
  return result;
end; $$;
commit;

-- Apply after 021. Server-owned rooms, readiness, shared draw and server timestamps.
-- Ladder construction adapts Whozzie (MIT, copyright 2025 zeikar); see THIRD-PARTY-NOTICES.md.
begin;
create table private.ladder_rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  host_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check(char_length(title) between 1 and 60),
  capacity integer not null check(capacity between 2 and 12),
  outcomes jsonb not null,
  phase text not null default 'waiting' check(phase in ('waiting','countdown','closed')),
  round jsonb,
  start_at timestamptz,
  finish_at timestamptz,
  revision bigint not null default 1,
  created_at timestamptz not null default now());
create table private.ladder_players (
  room_id uuid not null references private.ladder_rooms(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  ready boolean not null default false,
  joined_at timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  primary key(room_id,user_id));
alter table private.ladder_rooms enable row level security;
alter table private.ladder_players enable row level security;
revoke all on private.ladder_rooms,private.ladder_players from public,anon,authenticated;

create function private.ladder_random_index(p_max integer) returns integer
language plpgsql volatile set search_path='' as $$
declare number bigint; ceiling bigint;
begin
  if p_max<1 then raise exception 'Invalid random range'; end if;
  ceiling:=4294967296-mod(4294967296,p_max);
  loop
    number:=('x'||substr(replace(gen_random_uuid()::text,'-',''),1,8))::bit(32)::bigint;
    exit when number<ceiling;
  end loop;
  return mod(number,p_max)::integer;
end; $$;

create function private.ladder_draw(p_players jsonb,p_outcomes jsonb) returns jsonb
language plpgsql volatile set search_path='' as $$
declare n integer:=jsonb_array_length(p_players); rows integer; rungs boolean[][]; available integer[];
  seats integer[]; slots integer[]; row_id integer; gap integer; i integer; j integer; temp integer;
  rung_json jsonb:='[]'; lane_json jsonb:='[]';
begin
  rows:=greatest(8,n*2);rungs:=array_fill(false,array[rows,n-1]);
  for gap in 1..n-1 loop
    available:=array[]::integer[];
    for row_id in 1..rows loop
      if not coalesce(rungs[row_id][gap-1],false) and not coalesce(rungs[row_id][gap+1],false) then available:=array_append(available,row_id);end if;
    end loop;
    rungs[available[private.ladder_random_index(cardinality(available))+1]][gap]:=true;
  end loop;
  for row_id in 1..rows loop
    for gap in 1..n-1 loop
      if not rungs[row_id][gap] and not coalesce(rungs[row_id][gap-1],false) and not coalesce(rungs[row_id][gap+1],false)
        and not coalesce(rungs[row_id-1][gap],false) and not coalesce(rungs[row_id+1][gap],false)
        and private.ladder_random_index(1000)<least(550,5000/rows) then rungs[row_id][gap]:=true;end if;
    end loop;
    rung_json:=rung_json||jsonb_build_array(to_jsonb(rungs[row_id:row_id]));
  end loop;
  -- PostgreSQL multidimensional slices retain their outer dimension; flatten each row.
  rung_json:='[]';
  for row_id in 1..rows loop
    select rung_json||jsonb_build_array(jsonb_agg(to_jsonb(rungs[row_id][k]) order by k)) into rung_json from generate_series(1,n-1) k;
  end loop;
  seats:=array(select generate_series(0,n-1));slots:=seats;
  for i in reverse n..2 loop
    j:=private.ladder_random_index(i)+1;temp:=seats[i];seats[i]:=seats[j];seats[j]:=temp;
    j:=private.ladder_random_index(i)+1;temp:=slots[i];slots[i]:=slots[j];slots[j]:=temp;
  end loop;
  for i in 1..n loop lane_json:=lane_json||jsonb_build_array(jsonb_build_object('player',seats[i]));end loop;
  return jsonb_build_object('ladder',jsonb_build_object('columns',n,'rows',rows,'rungs',rung_json),'seats',to_jsonb(seats),'slots',to_jsonb(slots),'players',p_players,'outcomes',p_outcomes);
end; $$;

create function private.ladder_prune(p_room uuid) returns void
language plpgsql security definer set search_path='' as $$
declare room private.ladder_rooms; removed integer;
begin
  select * into room from private.ladder_rooms where id=p_room for update;
  if not found or room.phase='closed' or (room.start_at is not null and room.start_at<=now()) then return;end if;
  delete from private.ladder_players where room_id=p_room and (last_seen<now()-interval '45 seconds' or not private.member_approved(user_id));
  get diagnostics removed=row_count;
  if removed>0 then
    update private.ladder_players set ready=false where room_id=p_room;
    update private.ladder_rooms set phase=case when exists(select 1 from private.ladder_players where room_id=p_room and user_id=room.host_id) then 'waiting' else 'closed' end,
      start_at=null,finish_at=null,round=null,revision=revision+1 where id=p_room;
  end if;
end; $$;

create function private.ladder_snapshot(p_room uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('id',r.id,'code',r.code,'title',r.title,'capacity',r.capacity,'host_id',r.host_id,'revision',r.revision,'server_time',now(),
    'phase',case when r.phase='closed' then 'closed' when r.finish_at<=now() then 'finished' when r.start_at<=now() then 'running' else r.phase end,
    'start_at',r.start_at,'finish_at',r.finish_at,'round',case when r.phase<>'closed' and r.start_at<=now() then r.round end,
    'players',coalesce((select jsonb_agg(jsonb_build_object('id',p.user_id,'ready',p.ready,'nickname',u.nickname,'team',u.team,'region',u.region,'staff_role',u.staff_role) order by p.joined_at,p.user_id)
      from private.ladder_players p join public.profiles u on u.id=p.user_id where p.room_id=r.id),'[]'::jsonb))
  from private.ladder_rooms r where r.id=p_room;
$$;

create function public.list_ladder_rooms() returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
  if not private.member_approved((select auth.uid())) then raise exception 'Approved member required';end if;
  select coalesce(jsonb_agg(jsonb_build_object('code',r.code,'title',r.title,'capacity',r.capacity,'host',u.nickname,'count',(select count(*) from private.ladder_players where room_id=r.id)) order by r.created_at desc),'[]'::jsonb)
    into result from (select * from private.ladder_rooms where phase='waiting' and created_at>now()-interval '24 hours' and exists(select 1 from private.ladder_players where room_id=id and user_id=host_id and last_seen>now()-interval '45 seconds') order by created_at desc limit 30) r
    join public.profiles u on u.id=r.host_id;
  return result;
end; $$;

create function public.create_ladder_room(p_title text,p_outcomes jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); room private.ladder_rooms; n integer;
begin
  if not private.member_approved(actor) then raise exception 'Approved member required';end if;
  if p_title is null or char_length(trim(p_title)) not between 1 and 60 or jsonb_typeof(p_outcomes) is distinct from 'array' then raise exception 'Invalid room values';end if;
  n:=jsonb_array_length(p_outcomes);
  if n not between 2 and 12 or exists(select 1 from jsonb_array_elements(p_outcomes) e where jsonb_typeof(e)<>'string' or char_length(trim(e#>>'{}')) not between 1 and 30) then raise exception 'Invalid room values';end if;
  perform pg_advisory_xact_lock(hashtextextended('ladder-create:'||actor::text,0));
  if (select count(*) from private.ladder_rooms where host_id=actor and created_at>now()-interval '1 hour')>=10 then raise exception 'Room limit exceeded';end if;
  loop
    begin
      insert into private.ladder_rooms(code,host_id,title,capacity,outcomes) values(upper(substr(replace(gen_random_uuid()::text,'-',''),1,6)),actor,trim(p_title),n,p_outcomes) returning * into room;
      exit;
    exception when unique_violation then null;end;
  end loop;
  insert into private.ladder_players(room_id,user_id) values(room.id,actor);
  return private.ladder_snapshot(room.id);
end; $$;

create function public.join_ladder_room(p_code text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); room private.ladder_rooms;
begin
  if not private.member_approved(actor) then raise exception 'Approved member required';end if;
  select * into room from private.ladder_rooms where code=upper(trim(p_code)) for update;
  if not found or room.created_at<now()-interval '24 hours' then raise exception 'Room not found';end if;
  perform private.ladder_prune(room.id);
  select * into room from private.ladder_rooms where id=room.id;
  if room.phase='closed' then raise exception 'Room closed';end if;
  if exists(select 1 from private.ladder_players where room_id=room.id and user_id=actor) then
    update private.ladder_players set last_seen=now() where room_id=room.id and user_id=actor;
    return private.ladder_snapshot(room.id);
  end if;
  if room.phase<>'waiting' then raise exception 'Game already starting';end if;
  if (select count(*) from private.ladder_players where room_id=room.id)>=room.capacity then raise exception 'Room full';end if;
  insert into private.ladder_players(room_id,user_id) values(room.id,actor);
  update private.ladder_rooms set revision=revision+1 where id=room.id;
  return private.ladder_snapshot(room.id);
end; $$;

create function public.get_ladder_room(p_room uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  if not private.member_approved((select auth.uid())) then raise exception 'Approved member required';end if;
  perform 1 from private.ladder_rooms where id=p_room for update;
  if not found then raise exception 'Room not found';end if;
  update private.ladder_players set last_seen=now() where room_id=p_room and user_id=(select auth.uid());
  if not found then raise exception 'Room membership required';end if;
  perform private.ladder_prune(p_room);
  return private.ladder_snapshot(p_room);
end; $$;

create function public.set_ladder_ready(p_room uuid,p_ready boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); room private.ladder_rooms; people jsonb;
begin
  if not private.member_approved(actor) then raise exception 'Approved member required';end if;
  if p_ready is null then raise exception 'Invalid readiness';end if;
  select * into room from private.ladder_rooms where id=p_room for update;
  if not found then raise exception 'Room not found';end if;
  update private.ladder_players set last_seen=now() where room_id=p_room and user_id=actor;
  if not found then raise exception 'Room membership required';end if;
  perform private.ladder_prune(p_room);
  select * into room from private.ladder_rooms where id=p_room;
  if room.phase='closed' or (room.start_at is not null and room.start_at<=now()) then raise exception 'Game already starting';end if;
  update private.ladder_players set ready=p_ready where room_id=p_room and user_id=actor;
  if not p_ready then
    update private.ladder_rooms set phase='waiting',round=null,start_at=null,finish_at=null,revision=revision+1 where id=p_room;
  elsif room.phase='waiting' and (select count(*) from private.ladder_players where room_id=p_room)=room.capacity
    and not exists(select 1 from private.ladder_players where room_id=p_room and not ready) then
    select jsonb_agg(jsonb_build_object('id',p.user_id,'name',u.nickname) order by p.joined_at,p.user_id) into people from private.ladder_players p join public.profiles u on u.id=p.user_id where p.room_id=p_room;
    update private.ladder_rooms set phase='countdown',round=private.ladder_draw(people,outcomes),start_at=now()+interval '5 seconds',finish_at=now()+interval '5 seconds'+room.capacity*interval '4 seconds',revision=revision+1 where id=p_room;
  else update private.ladder_rooms set revision=revision+1 where id=p_room;end if;
  return private.ladder_snapshot(p_room);
end; $$;

create function public.leave_ladder_room(p_room uuid) returns void
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); room private.ladder_rooms;
begin
  if actor is null then raise exception 'Login required';end if;
  select * into room from private.ladder_rooms where id=p_room for update;
  if not found then return;end if;
  if not exists(select 1 from private.ladder_players where room_id=p_room and user_id=actor) then return;end if;
  delete from private.ladder_players where room_id=p_room and user_id=actor;
  if actor=room.host_id then update private.ladder_rooms set phase='closed',revision=revision+1 where id=p_room;
  elsif room.start_at is null or room.start_at>now() then
    update private.ladder_players set ready=false where room_id=p_room;
    update private.ladder_rooms set phase='waiting',round=null,start_at=null,finish_at=null,revision=revision+1 where id=p_room;
  end if;
end; $$;

revoke all on function private.ladder_random_index(integer),private.ladder_draw(jsonb,jsonb),private.ladder_prune(uuid),private.ladder_snapshot(uuid) from public,anon,authenticated;
revoke all on function public.list_ladder_rooms(),public.create_ladder_room(text,jsonb),public.join_ladder_room(text),public.get_ladder_room(uuid),public.set_ladder_ready(uuid,boolean),public.leave_ladder_room(uuid) from public,anon,authenticated;
grant execute on function public.list_ladder_rooms(),public.create_ladder_room(text,jsonb),public.join_ladder_room(text),public.get_ladder_room(uuid),public.set_ladder_ready(uuid,boolean),public.leave_ladder_room(uuid) to authenticated;
commit;

-- Apply after 022. One explicitly selected home notice; save content and selection atomically.
begin;
create function public.set_main_notice(p_post uuid,p_enabled boolean) returns void
language plpgsql security definer set search_path='' as $$
begin
  if not private.can_manage_members() or private.menu_permission((select auth.uid()),'notice')<>'write' then raise exception 'Notice management required';end if;
  if p_enabled is null then raise exception 'Invalid notice setting';end if;
  perform pg_advisory_xact_lock(hashtextextended('community-main-notice',0));
  perform 1 from public.posts where id=p_post and board='notice';
  if not found then raise exception 'Notice post required';end if;
  if p_enabled then update public.posts set is_notice=false where is_notice;end if;
  update public.posts set is_notice=p_enabled where id=p_post;
end; $$;
create function public.save_notice_post(p_id uuid,p_title text,p_body text,p_doc jsonb,p_images text[],p_main boolean) returns uuid
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); saved uuid; old_main boolean;
begin
  if not private.member_approved(actor) or private.menu_permission(actor,'notice')<>'write' then raise exception 'Notice write required';end if;
  if p_main is null then raise exception 'Invalid notice setting';end if;
  if p_main and not private.can_manage_members() then raise exception 'Notice management required';end if;
  -- Serialize post editing and main-notice selection in a consistent order.
  perform pg_advisory_xact_lock(hashtextextended('community-main-notice',0));
  if p_id is null then
    insert into public.posts(author_id,board,title,body,body_doc,images) values(actor,'notice',p_title,p_body,p_doc,p_images) returning id into saved;
  else
    select is_notice into old_main from public.posts where id=p_id and board='notice' and author_id=actor for update;
    if not found then raise exception 'Notice author required';end if;
    if old_main and not private.can_manage_members() then raise exception 'Notice management required';end if;
    update public.posts set title=p_title,body=p_body,body_doc=p_doc,images=p_images where id=p_id returning id into saved;
  end if;
  if private.can_manage_members() then perform public.set_main_notice(saved,p_main);end if;
  return saved;
end; $$;
revoke all on function public.set_main_notice(uuid,boolean),public.save_notice_post(uuid,text,text,jsonb,text[],boolean) from public,anon,authenticated;
grant execute on function public.set_main_notice(uuid,boolean),public.save_notice_post(uuid,text,text,jsonb,text[],boolean) to authenticated;
commit;

-- YB affiliation is an application request; only member managers grant membership.
begin;
alter table private.member_accounts add column yb_requested boolean not null default false;

create function private.capture_yb_request() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  select coalesce(u.raw_user_meta_data->'yb_requested'='true'::jsonb,false)
    into new.yb_requested from auth.users u where u.id=new.user_id;
  new.yb_requested:=coalesce(new.yb_requested,false);
  return new;
end; $$;
create trigger capture_yb_request before insert on private.member_accounts
for each row execute function private.capture_yb_request();
revoke all on function private.capture_yb_request() from public,anon,authenticated;

create or replace function private.admin_member_snapshot(p_user uuid) returns jsonb
language sql stable set search_path='' as $$
  select jsonb_build_object('id',p.id,'username',a.username,'nickname',p.nickname,'region',p.region,'team',p.team,
    'staff_role',p.staff_role,'yb_role',case when private.is_yb_member(p.id) then p.yb_role else 'member' end,'status',a.status,'yb_requested',a.yb_requested,'revision',a.revision,'created_at',p.created_at,'restriction_start',a.restriction_start,'restriction_end',a.restriction_end,'restriction_reason',a.restriction_reason,'is_restricted',private.restriction_active(p.id),
    'is_admin',exists(select 1 from private.admins where user_id=p.id),'is_yb_member',private.is_yb_member(p.id),
    'permissions',coalesce((select jsonb_object_agg(board,access) from private.member_permissions where user_id=p.id),'{}'::jsonb),
    'effective', (select jsonb_object_agg(board,private.menu_permission(p.id,board)) from unnest(array['free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','staff_plot','staff_minutes','yb_roster','yb_calendar','yb_holics','recruit']) board))
  from public.profiles p join private.member_accounts a on a.user_id=p.id where p.id=p_user;
$$;
commit;

-- Only the room creator configures participants and losers. Results are fixed labels.
begin;
drop function public.create_ladder_room(text,jsonb);
create function public.create_ladder_room(p_capacity integer,p_losers integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); room private.ladder_rooms; n integer; p_outcomes jsonb;
begin
  if not private.member_approved(actor) then raise exception 'Approved member required';end if;
  if p_capacity is null or p_capacity not between 2 and 12 or p_losers is null or p_losers not between 1 and p_capacity-1 then raise exception 'Invalid room values';end if;
  n:=p_capacity;
  select jsonb_agg(case when i<=p_losers then '꽝' else '통과' end order by i) into p_outcomes from generate_series(1,n) i;
  perform pg_advisory_xact_lock(hashtextextended('ladder-create:'||actor::text,0));
  if (select count(*) from private.ladder_rooms where host_id=actor and created_at>now()-interval '1 hour')>=10 then raise exception 'Room limit exceeded';end if;
  loop
    begin
      insert into private.ladder_rooms(code,host_id,title,capacity,outcomes) values(upper(substr(replace(gen_random_uuid()::text,'-',''),1,6)),actor,'사다리 게임',n,p_outcomes) returning * into room;
      exit;
    exception when unique_violation then null;end;
  end loop;
  insert into private.ladder_players(room_id,user_id) values(room.id,actor);
  return private.ladder_snapshot(room.id);
end; $$;
create or replace function private.ladder_snapshot(p_room uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('id',r.id,'code',r.code,'title',r.title,'capacity',r.capacity,'losers',(select count(*) from jsonb_array_elements_text(r.outcomes) e where e='꽝'),'host_id',r.host_id,'revision',r.revision,'server_time',now(),
    'phase',case when r.phase='closed' then 'closed' when r.finish_at<=now() then 'finished' when r.start_at<=now() then 'running' else r.phase end,
    'start_at',r.start_at,'finish_at',r.finish_at,'round',case when r.phase<>'closed' and r.start_at<=now() then r.round end,
    'players',coalesce((select jsonb_agg(jsonb_build_object('id',p.user_id,'ready',p.ready,'nickname',u.nickname,'team',u.team,'region',u.region,'staff_role',u.staff_role) order by p.joined_at,p.user_id)
      from private.ladder_players p join public.profiles u on u.id=p.user_id where p.room_id=r.id),'[]'::jsonb))
  from private.ladder_rooms r where r.id=p_room;
$$;
create function public.update_ladder_settings(p_room uuid,p_capacity integer,p_losers integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); room private.ladder_rooms; chosen_outcomes jsonb;
begin
  if not private.member_approved(actor) then raise exception 'Approved member required';end if;
  if p_capacity is null or p_capacity not between 2 and 12 or p_losers is null or p_losers not between 1 and p_capacity-1 then raise exception 'Invalid room values';end if;
  select * into room from private.ladder_rooms where id=p_room for update;
  if not found then raise exception 'Room not found';end if;
  if room.host_id<>actor then raise exception 'Host required';end if;
  perform private.ladder_prune(p_room);
  select * into room from private.ladder_rooms where id=p_room;
  if room.phase<>'waiting' then raise exception 'Room already starting';end if;
  if (select count(*) from private.ladder_players where room_id=p_room)>p_capacity then raise exception 'Capacity below participants';end if;
  select jsonb_agg(case when i<=p_losers then '꽝' else '통과' end order by i) into chosen_outcomes from generate_series(1,p_capacity) i;
  update private.ladder_rooms set capacity=p_capacity,outcomes=chosen_outcomes,round=null,start_at=null,finish_at=null,revision=revision+1 where id=p_room;
  update private.ladder_players set ready=false where room_id=p_room;
  return private.ladder_snapshot(p_room);
end; $$;
revoke all on function public.create_ladder_room(integer,integer),public.update_ladder_settings(uuid,integer,integer) from public,anon;
grant execute on function public.create_ladder_room(integer,integer),public.update_ladder_settings(uuid,integer,integer) to authenticated;
commit;

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

-- Apply after 026. Approved member access, author/moderator editing and recoverable deletion.
begin;
grant execute on function private.can_manage_members() to authenticated;
alter table public.posts add column deleted_at timestamptz, add column deleted_by uuid references auth.users(id);
alter table public.comments add column updated_at timestamptz not null default now(), add column deleted_at timestamptz, add column deleted_by uuid references auth.users(id);
create or replace function private.menu_permission(p_user uuid,p_menu text) returns text
language plpgsql stable security definer set search_path='' as $$
declare override_access text; member_role text;
begin
  if p_menu is null or p_menu not in ('free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','staff_plot','staff_minutes','yb_roster','yb_calendar','yb_holics','recruit') then return 'deny'; end if;
  if p_user is null then return 'deny'; end if;
  if not private.member_approved(p_user) then return 'deny'; end if;
  if exists(select 1 from private.admins where user_id=p_user) then return 'write'; end if;
  select staff_role into member_role from public.profiles where id=p_user;
  select access into override_access from private.member_permissions where user_id=p_user and board=p_menu;
  if found then return case when p_menu='yb_roster' and override_access='write' and not private.roster_editor_role(p_user) then 'read' when p_menu='recruit' and override_access='write' and member_role not in ('staff','vice_staff') then 'read' else override_access end; end if;
  select staff_role into member_role from public.profiles where id=p_user;
  if p_menu in ('free','humor','gallery_flash','gallery_attendance','gallery_meetup') then return 'write'; end if;
  if p_menu='recruit' then return case when member_role in ('staff','vice_staff') then 'write' else 'read' end; end if;
  if p_menu='notice' then return case when member_role in ('staff','vice_staff') then 'write' else 'read' end; end if;
  if p_menu in ('staff_plot','staff_minutes') then return case when member_role in ('staff','vice_staff') then 'write' else 'deny' end; end if;
  if p_menu='yb_roster' then return case when private.roster_editor_role(p_user) then 'write' else 'read' end; end if;
  if p_menu='yb_calendar' then return case when private.is_yb_member(p_user) and member_role in ('staff','vice_staff') then 'write' else 'read' end; end if;
  if member_role in ('staff','vice_staff') or private.is_yb_member(p_user) then return 'write'; end if;
  return 'deny';
end; $$;
drop policy profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated using(private.member_approved((select auth.uid())));
drop policy posts_read on public.posts;
create policy posts_read on public.posts for select to anon,authenticated using(deleted_at is null and private.can_read_post_menu(board,category));
drop policy posts_edit on public.posts;
create policy posts_edit on public.posts for update to authenticated
using(deleted_at is null and private.can_write_post_menu(board,category) and (author_id=(select auth.uid()) or private.can_manage_members()))
with check(deleted_at is null and private.can_write_post_menu(board,category) and (author_id=(select auth.uid()) or private.can_manage_members()));
drop policy comments_read on public.comments;
create policy comments_read on public.comments for select to anon,authenticated using(deleted_at is null and exists(select 1 from public.posts p where p.id=post_id));
grant update(body) on public.comments to authenticated;
create policy comments_edit on public.comments for update to authenticated
using(deleted_at is null and (author_id=(select auth.uid()) or private.can_manage_members()) and exists(select 1 from public.posts p where p.id=post_id and private.can_write_post_menu(p.board,p.category)))
with check(deleted_at is null and (author_id=(select auth.uid()) or private.can_manage_members()) and exists(select 1 from public.posts p where p.id=post_id and private.can_write_post_menu(p.board,p.category)));
create or replace view public.comment_feed with(security_invoker=true) as
select c.id,c.post_id,c.author_id,c.body,c.created_at,r.nickname,r.team,r.region,r.staff_role,private.is_yb_member(r.id) as is_yb_member,c.updated_at
from public.comments c join public.profiles r on r.id=c.author_id;

create or replace function private.validate_post_images() returns trigger
language plpgsql security definer set search_path='' as $$
declare retained text[]:='{}';
begin
  if tg_op='UPDATE' then retained:=old.images; end if;
  if exists(select 1 from unnest(new.images) image(url) where not exists(
    select 1 from public.upload_tickets t where t.secure_url=image.url and t.verified_at is not null
    and (t.owner_id=new.author_id or (tg_op='UPDATE' and image.url=any(retained)) or (private.can_manage_members() and t.owner_id=(select auth.uid())))
    and ((new.board in ('staff','yb') and t.board=new.board and t.delivery_type='authenticated') or (new.board not in ('staff','yb') and t.delivery_type='upload'))
  )) then raise exception 'Unverified or incorrectly protected attachment'; end if;
  new.updated_at:=now(); return new;
end; $$;
create function private.live_post_content() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if not exists(select 1 from public.posts where id=new.post_id and deleted_at is null) then raise exception 'Post unavailable';end if;
  if tg_table_name='comments' then new.updated_at:=now();end if;
  return new;
end; $$;
revoke all on function private.live_post_content() from public,anon,authenticated;
create trigger comments_live_post before insert or update of body on public.comments for each row execute function private.live_post_content();
create trigger likes_live_post before insert on public.likes for each row execute function private.live_post_content();

create function public.manage_deleted_content(p_kind text,p_id uuid,p_restore boolean) returns void
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); item_owner uuid; parent_id uuid; item_deleted timestamptz; item_board text; item_category text;
begin
  if not private.member_approved(actor) or p_restore is null then raise exception 'Approved member required';end if;
  if p_kind='post' then
    select author_id,deleted_at,board,category into item_owner,item_deleted,item_board,item_category from public.posts where id=p_id for update;
  elsif p_kind='comment' then
    select post_id into parent_id from public.comments where id=p_id;
    select board,category into item_board,item_category from public.posts where id=parent_id and deleted_at is null for update;
    if not found then raise exception 'Post unavailable';end if;
    select author_id,deleted_at into item_owner,item_deleted from public.comments where id=p_id for update;
  else raise exception 'Invalid content type';end if;
  if item_owner is null or not private.can_write_post_menu(item_board,item_category) or not (item_owner=actor or private.can_manage_members()) then raise exception 'Content management permission required';end if;
  if p_restore then
    if p_kind='post' then update public.posts set deleted_at=null,deleted_by=null,updated_at=now() where id=p_id;
    else update public.comments set deleted_at=null,deleted_by=null,updated_at=now() where id=p_id;end if;
  else
    if p_kind='post' then update public.posts set deleted_at=coalesce(deleted_at,now()),deleted_by=coalesce(deleted_by,actor),is_notice=false,updated_at=now() where id=p_id;
    else update public.comments set deleted_at=coalesce(deleted_at,now()),deleted_by=coalesce(deleted_by,actor),updated_at=now() where id=p_id;end if;
  end if;
end; $$;
create function public.get_deleted_content() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if not private.member_approved((select auth.uid())) then raise exception 'Approved member required';end if;
  return coalesce((select jsonb_agg(to_jsonb(items)) from (
    select * from (
      select 'post'::text kind,p.id,p.title label,p.board,p.category,p.deleted_at from public.posts p where p.deleted_at is not null and private.can_write_post_menu(p.board,p.category) and (p.author_id=(select auth.uid()) or private.can_manage_members())
      union all
      select 'comment',c.id,c.body,p.board,p.category,c.deleted_at from public.comments c join public.posts p on p.id=c.post_id where c.deleted_at is not null and p.deleted_at is null and private.can_write_post_menu(p.board,p.category) and (c.author_id=(select auth.uid()) or private.can_manage_members())
    ) content order by deleted_at desc limit 100
  ) items),'[]'::jsonb);
end; $$;
revoke all on function public.manage_deleted_content(text,uuid,boolean),public.get_deleted_content() from public,anon,authenticated;
grant execute on function public.manage_deleted_content(text,uuid,boolean),public.get_deleted_content() to authenticated;
create or replace function public.save_notice_post(p_id uuid,p_title text,p_body text,p_doc jsonb,p_images text[],p_main boolean) returns uuid
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); saved uuid; old_main boolean;
begin
  if not private.member_approved(actor) or private.menu_permission(actor,'notice')<>'write' then raise exception 'Notice write required';end if;
  if p_main is null then raise exception 'Invalid notice setting';end if;
  if p_main and not private.can_manage_members() then raise exception 'Notice management required';end if;
  -- Serialize post editing and main-notice selection in a consistent order.
  perform pg_advisory_xact_lock(hashtextextended('community-main-notice',0));
  if p_id is null then
    insert into public.posts(author_id,board,title,body,body_doc,images) values(actor,'notice',p_title,p_body,p_doc,p_images) returning id into saved;
  else
    select is_notice into old_main from public.posts where id=p_id and board='notice' and deleted_at is null and (author_id=actor or private.can_manage_members()) for update;
    if not found then raise exception 'Notice edit permission required';end if;
    if old_main and not private.can_manage_members() then raise exception 'Notice management required';end if;
    update public.posts set title=p_title,body=p_body,body_doc=p_doc,images=p_images where id=p_id returning id into saved;
  end if;
  if private.can_manage_members() then perform public.set_main_notice(saved,p_main);end if;
  return saved;
end; $$;
create or replace function public.set_main_notice(p_post uuid,p_enabled boolean) returns void
language plpgsql security definer set search_path='' as $$
begin
  if not private.can_manage_members() or private.menu_permission((select auth.uid()),'notice')<>'write' then raise exception 'Notice management required';end if;
  if p_enabled is null then raise exception 'Invalid notice setting';end if;
  perform pg_advisory_xact_lock(hashtextextended('community-main-notice',0));
  perform 1 from public.posts where id=p_post and board='notice' and deleted_at is null;
  if not found then raise exception 'Notice post required';end if;
  if p_enabled then update public.posts set is_notice=false where is_notice;end if;
  update public.posts set is_notice=p_enabled where id=p_post;
end; $$;
create or replace function public.get_team_roster() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  if private.menu_permission((select auth.uid()),'yb_roster') not in ('read','write') then raise exception 'Roster access required'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'role',r.role,'name',r.name,'jersey_number',r.jersey_number,
    'sort_order',r.sort_order,'revision',r.revision,'photo_url',r.photo_url,
    'photo_post_id',case when r.photo_url is null then p.id end,
    'photo_private',case when r.photo_url is not null then false else coalesce(p.board in ('staff','yb'),false) end,
    'photo',coalesce(r.photo_url,p.images[r.photo_index+1]))
    order by array_position(array['manager','coach','team_manager','pitcher','catcher','infielder','outfielder'],r.role),r.jersey_number asc nulls last,r.name,r.id),'[]'::jsonb)
  into result from private.team_roster r left join public.posts p on p.id=r.photo_post_id and p.deleted_at is null and private.can_read_post_menu(p.board,p.category)
  where r.deleted_at is null;
  return result;
end; $$;
commit;

-- Apply after 027. Preserve existing schedules and add validated game results.
begin;
alter table private.team_events
  add column game_status text not null default 'scheduled',
  add column holics_score integer,
  add column opponent_score integer;
alter table private.team_events add constraint team_events_result_check check (
  (game_status='scheduled' and holics_score is null and opponent_score is null)
  or (game_status in ('win','loss','draw') and holics_score is not null and opponent_score is not null
    and holics_score between 0 and 999 and opponent_score between 0 and 999
    and ((game_status='win' and holics_score>opponent_score)
      or (game_status='loss' and holics_score<opponent_score)
      or (game_status='draw' and holics_score=opponent_score)))
);

create or replace function public.get_team_events(p_from date,p_to date) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  if private.menu_permission((select auth.uid()),'yb_calendar') not in ('read','write') then raise exception 'Calendar access required'; end if;
  if p_from is null or p_to is null or p_to<p_from or p_to-p_from>370 then raise exception 'Invalid date range'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'title',title,'event_date',event_date,'event_time',event_time,
    'opponent',opponent,'location',location,'memo',memo,'revision',revision,
    'game_status',game_status,'holics_score',holics_score,'opponent_score',opponent_score)
    order by event_date,event_time nulls last,id),'[]'::jsonb)
  into result from private.team_events where deleted_at is null and event_date between p_from and p_to;
  return result;
end; $$;
revoke all on function public.get_team_events(date,date) from public,anon,authenticated;
grant execute on function public.get_team_events(date,date) to authenticated;

-- Keep the old save RPC compatible; it leaves these new result columns intact.
create function public.save_team_event_with_result(p_id uuid,p_revision bigint,p_title text,p_date date,p_time time,p_opponent text,p_location text,p_memo text,p_game_status text,p_holics_score integer,p_opponent_score integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare saved private.team_events; actor uuid:=(select auth.uid());
begin
  if private.menu_permission(actor,'yb_calendar')<>'write' then raise exception 'Calendar management required'; end if;
  if p_date is null or p_title is null or char_length(trim(p_title)) not between 1 and 80
    or p_opponent is null or char_length(p_opponent)>50 or p_location is null or char_length(p_location)>100
    or p_memo is null or char_length(p_memo)>1000 or p_revision is null then raise exception 'Invalid event'; end if;
  if p_game_status is null or p_game_status not in ('scheduled','win','loss','draw') then raise exception 'Invalid game status'; end if;
  if p_game_status='scheduled' then
    if p_holics_score is not null or p_opponent_score is not null then raise exception 'Scheduled game has no score'; end if;
  elsif p_holics_score is null or p_opponent_score is null or p_holics_score not between 0 and 999 or p_opponent_score not between 0 and 999
    or (p_game_status='win' and p_holics_score<=p_opponent_score)
    or (p_game_status='loss' and p_holics_score>=p_opponent_score)
    or (p_game_status='draw' and p_holics_score<>p_opponent_score) then raise exception 'Game result does not match score'; end if;
  if p_id is null then
    if p_revision<>0 then raise exception 'Invalid event revision'; end if;
    insert into private.team_events(title,event_date,event_time,opponent,location,memo,game_status,holics_score,opponent_score,created_by,updated_by)
    values(trim(p_title),p_date,p_time,trim(p_opponent),trim(p_location),trim(p_memo),p_game_status,p_holics_score,p_opponent_score,actor,actor) returning * into saved;
  else
    select * into saved from private.team_events where id=p_id and deleted_at is null for update;
    if not found then raise exception 'Event not found'; end if;
    if saved.revision<>p_revision then raise exception 'Event changed; reload required'; end if;
    update private.team_events set title=trim(p_title),event_date=p_date,event_time=p_time,opponent=trim(p_opponent),location=trim(p_location),memo=trim(p_memo),
      game_status=p_game_status,holics_score=p_holics_score,opponent_score=p_opponent_score,
      revision=revision+1,updated_at=now(),updated_by=actor where id=p_id returning * into saved;
  end if;
  return jsonb_build_object('id',saved.id,'title',saved.title,'event_date',saved.event_date,'event_time',saved.event_time,'opponent',saved.opponent,'location',saved.location,'memo',saved.memo,'revision',saved.revision,
    'game_status',saved.game_status,'holics_score',saved.holics_score,'opponent_score',saved.opponent_score);
end; $$;
revoke all on function public.save_team_event_with_result(uuid,bigint,text,date,time,text,text,text,text,integer,integer) from public,anon,authenticated;
grant execute on function public.save_team_event_with_result(uuid,bigint,text,date,time,text,text,text,text,integer,integer) to authenticated;
commit;

-- Apply after 028. Accept only a YouTube video ID, never iframe HTML or external URLs.
begin;
create or replace function private.rich_document_valid(p_doc jsonb,p_image_count integer) returns boolean
language plpgsql immutable set search_path='' as $$
declare item record; node jsonb; attrs jsonb; kind text; allowed text[]; child_types text[];
  mark jsonb; total_nodes integer:=0; total_text integer:=0;
begin
  if p_doc is null then return true; end if;
  if jsonb_typeof(p_doc)<>'object' or p_doc->>'type'<>'doc' or char_length(p_doc::text)>200000 then return false; end if;
  for item in
    with recursive walk(node,parent,depth) as (
      select p_doc,'ROOT'::text,0
      union all
      select child.value,w.node->>'type',w.depth+1 from walk w
      cross join lateral jsonb_array_elements(case when jsonb_typeof(w.node->'content')='array' then w.node->'content' else '[]'::jsonb end) child
      where w.depth<=10
    ) select * from walk
  loop
    node:=item.node; kind:=node->>'type'; total_nodes:=total_nodes+1;
    if total_nodes>2000 or item.depth>10 or jsonb_typeof(node)<>'object' or kind is null then return false; end if;
    child_types:=case item.parent
      when 'ROOT' then array['doc']
      when 'doc' then array['paragraph','heading','blockquote','bulletList','orderedList','codeBlock','horizontalRule','table','image','youtube']
      when 'paragraph' then array['text','hardBreak','yabolticon']
      when 'heading' then array['text','hardBreak','yabolticon']
      when 'codeBlock' then array['text']
      when 'blockquote' then array['paragraph','heading','blockquote','bulletList','orderedList','codeBlock','horizontalRule','table','image','youtube']
      when 'listItem' then array['paragraph','heading','blockquote','bulletList','orderedList','codeBlock','horizontalRule','table','image','youtube']
      when 'bulletList' then array['listItem']
      when 'orderedList' then array['listItem']
      when 'table' then array['tableRow']
      when 'tableRow' then array['tableCell','tableHeader']
      when 'tableCell' then array['paragraph','heading','blockquote','bulletList','orderedList','codeBlock','horizontalRule','image','youtube']
      when 'tableHeader' then array['paragraph','heading','blockquote','bulletList','orderedList','codeBlock','horizontalRule','image','youtube']
      else array[]::text[] end;
    if not(kind=any(child_types)) then return false; end if;
    allowed:=case
      when kind='text' then array['type','text','marks']
      when kind in ('image','yabolticon','youtube') then array['type','attrs']
      when kind in ('hardBreak','horizontalRule') then array['type']
      when kind in ('heading','orderedList','tableCell','tableHeader') then array['type','attrs','content']
      else array['type','content'] end;
    if exists(select 1 from jsonb_object_keys(node) key where not(key=any(allowed))) then return false; end if;
    if kind='text' then
      if jsonb_typeof(node->'text') is distinct from 'string' then return false; end if;
      total_text:=total_text+char_length(node->>'text'); if total_text>10000 then return false; end if;
      if node ? 'marks' then
        if jsonb_typeof(node->'marks')<>'array' or jsonb_array_length(node->'marks')>5 then return false; end if;
        for mark in select value from jsonb_array_elements(node->'marks') loop
          if jsonb_typeof(mark)<>'object' or (mark-'type')<>'{}'::jsonb or (mark->>'type') is null
            or not(mark->>'type'=any(array['bold','italic','underline','strike','code'])) then return false; end if;
        end loop;
      end if;
    elsif kind not in ('image','yabolticon','youtube','hardBreak','horizontalRule') then
      if jsonb_typeof(node->'content') is distinct from 'array' then return false; end if;
      if kind='table' and jsonb_array_length(node->'content') not between 1 and 20 then return false; end if;
      if kind='tableRow' and jsonb_array_length(node->'content') not between 1 and 10 then return false; end if;
    end if;
    if kind in ('image','yabolticon','youtube','heading','orderedList','tableCell','tableHeader') then
      attrs:=node->'attrs'; if jsonb_typeof(attrs) is distinct from 'object' then return false; end if;
      if kind='image' then
        if (attrs-array['index','alt'])<>'{}'::jsonb or jsonb_typeof(attrs->'index') is distinct from 'number'
          or coalesce(attrs->>'index','') !~ '^[0-4]$' or (attrs->>'index')::integer>=p_image_count
          or jsonb_typeof(attrs->'alt') is distinct from 'string' or char_length(attrs->>'alt')>200 then return false; end if;
      elsif kind='youtube' then
        if (attrs-'videoId')<>'{}'::jsonb or jsonb_typeof(attrs->'videoId') is distinct from 'string'
          or coalesce(attrs->>'videoId','') !~ '^[A-Za-z0-9_-]{11}$' then return false; end if;
      elsif kind='yabolticon' then
        if (attrs-'id')<>'{}'::jsonb or (attrs->>'id') is null
          or not(attrs->>'id'=any(array['hello','laugh','cheer','homerun','cry','angry','clap','thanks'])) then return false; end if;
      elsif kind='heading' then
        if (attrs-'level')<>'{}'::jsonb or jsonb_typeof(attrs->'level') is distinct from 'number' or coalesce(attrs->>'level','') !~ '^[23]$' then return false; end if;
      elsif kind='orderedList' then
        if (attrs-'start')<>'{}'::jsonb or jsonb_typeof(attrs->'start') is distinct from 'number'
          or coalesce(attrs->>'start','') !~ '^[1-9][0-9]{0,2}$' then return false; end if;
      else
        if (attrs-array['colspan','rowspan'])<>'{}'::jsonb or jsonb_typeof(attrs->'colspan') is distinct from 'number'
          or jsonb_typeof(attrs->'rowspan') is distinct from 'number' or coalesce(attrs->>'colspan','') !~ '^[1-9][0-9]?$'
          or coalesce(attrs->>'rowspan','') !~ '^[1-9][0-9]?$'
          or (attrs->>'colspan')::integer>10 or (attrs->>'rowspan')::integer>20 then return false; end if;
      end if;
    end if;
  end loop;
  return true;
exception when others then return false;
end; $$;
revoke all on function private.rich_document_valid(jsonb,integer) from public,anon,authenticated;

commit;

-- Apply after 029. Add cancelled games without changing existing results or access.
begin;
alter table private.team_events drop constraint team_events_result_check;
alter table private.team_events add constraint team_events_result_check check (
  (game_status in ('scheduled','cancelled') and holics_score is null and opponent_score is null)
  or (game_status in ('win','loss','draw') and holics_score is not null and opponent_score is not null
    and holics_score between 0 and 999 and opponent_score between 0 and 999
    and ((game_status='win' and holics_score>opponent_score)
      or (game_status='loss' and holics_score<opponent_score)
      or (game_status='draw' and holics_score=opponent_score)))
);

create or replace function public.save_team_event_with_result(p_id uuid,p_revision bigint,p_title text,p_date date,p_time time,p_opponent text,p_location text,p_memo text,p_game_status text,p_holics_score integer,p_opponent_score integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare saved private.team_events; actor uuid:=(select auth.uid());
begin
  if private.menu_permission(actor,'yb_calendar')<>'write' then raise exception 'Calendar management required'; end if;
  if p_date is null or p_title is null or char_length(trim(p_title)) not between 1 and 80
    or p_opponent is null or char_length(p_opponent)>50 or p_location is null or char_length(p_location)>100
    or p_memo is null or char_length(p_memo)>1000 or p_revision is null then raise exception 'Invalid event'; end if;
  if p_game_status is null or p_game_status not in ('scheduled','win','loss','draw','cancelled') then raise exception 'Invalid game status'; end if;
  if p_game_status in ('scheduled','cancelled') then
    if p_holics_score is not null or p_opponent_score is not null then raise exception 'Unplayed game has no score'; end if;
  elsif p_holics_score is null or p_opponent_score is null or p_holics_score not between 0 and 999 or p_opponent_score not between 0 and 999
    or (p_game_status='win' and p_holics_score<=p_opponent_score)
    or (p_game_status='loss' and p_holics_score>=p_opponent_score)
    or (p_game_status='draw' and p_holics_score<>p_opponent_score) then raise exception 'Game result does not match score'; end if;
  if p_id is null then
    if p_revision<>0 then raise exception 'Invalid event revision'; end if;
    insert into private.team_events(title,event_date,event_time,opponent,location,memo,game_status,holics_score,opponent_score,created_by,updated_by)
    values(trim(p_title),p_date,p_time,trim(p_opponent),trim(p_location),trim(p_memo),p_game_status,p_holics_score,p_opponent_score,actor,actor) returning * into saved;
  else
    select * into saved from private.team_events where id=p_id and deleted_at is null for update;
    if not found then raise exception 'Event not found'; end if;
    if saved.revision<>p_revision then raise exception 'Event changed; reload required'; end if;
    update private.team_events set title=trim(p_title),event_date=p_date,event_time=p_time,opponent=trim(p_opponent),location=trim(p_location),memo=trim(p_memo),
      game_status=p_game_status,holics_score=p_holics_score,opponent_score=p_opponent_score,
      revision=revision+1,updated_at=now(),updated_by=actor where id=p_id returning * into saved;
  end if;
  return jsonb_build_object('id',saved.id,'title',saved.title,'event_date',saved.event_date,'event_time',saved.event_time,'opponent',saved.opponent,'location',saved.location,'memo',saved.memo,'revision',saved.revision,
    'game_status',saved.game_status,'holics_score',saved.holics_score,'opponent_score',saved.opponent_score);
end; $$;
revoke all on function public.save_team_event_with_result(uuid,bigint,text,date,time,text,text,text,text,integer,integer) from public,anon,authenticated;
grant execute on function public.save_team_event_with_result(uuid,bigint,text,date,time,text,text,text,text,integer,integer) to authenticated;
commit;

-- Apply after 030. Canonical profile editing and role-based calendar editing.
begin;
create or replace function private.menu_permission(p_user uuid,p_menu text) returns text
language plpgsql stable security definer set search_path='' as $$
declare override_access text; member_role text;
begin
  if p_menu is null or p_menu not in ('free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','staff_plot','staff_minutes','yb_roster','yb_calendar','yb_holics','recruit') then return 'deny'; end if;
  if p_user is null then return 'deny'; end if;
  if not private.member_approved(p_user) then return 'deny'; end if;
  if exists(select 1 from private.admins where user_id=p_user) then return 'write'; end if;
  select staff_role into member_role from public.profiles where id=p_user;
  select access into override_access from private.member_permissions where user_id=p_user and board=p_menu;
  if found then return case when p_menu in ('yb_roster','yb_calendar') and override_access='write' and not private.roster_editor_role(p_user) then 'read' when p_menu='recruit' and override_access='write' and member_role not in ('staff','vice_staff') then 'read' else override_access end; end if;
  select staff_role into member_role from public.profiles where id=p_user;
  if p_menu in ('free','humor','gallery_flash','gallery_attendance','gallery_meetup') then return 'write'; end if;
  if p_menu='recruit' then return case when member_role in ('staff','vice_staff') then 'write' else 'read' end; end if;
  if p_menu='notice' then return case when member_role in ('staff','vice_staff') then 'write' else 'read' end; end if;
  if p_menu in ('staff_plot','staff_minutes') then return case when member_role in ('staff','vice_staff') then 'write' else 'deny' end; end if;
  if p_menu='yb_roster' then return case when private.roster_editor_role(p_user) then 'write' else 'read' end; end if;
  if p_menu='yb_calendar' then return case when private.roster_editor_role(p_user) then 'write' else 'read' end; end if;
  if member_role in ('staff','vice_staff') or private.is_yb_member(p_user) then return 'write'; end if;
  return 'deny';
end; $$;

create function public.update_my_profile(p_nickname text,p_region text,p_revision bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); current_revision bigint; previous jsonb; updated jsonb;
begin
  perform pg_advisory_xact_lock(hashtextextended('community-member-administration',0));
  if actor is null or not private.member_approved(actor) then raise exception 'Approved member required';end if;
  p_nickname:=trim(p_nickname);p_region:=trim(p_region);
  if p_nickname is null or char_length(p_nickname) not between 2 and 20 or p_nickname ~ '[[:cntrl:]]' then raise exception 'Invalid profile nickname';end if;
  if p_region is null or char_length(p_region) not between 1 and 20 or p_region ~ '[[:cntrl:]]' then raise exception 'Invalid profile region';end if;
  select revision into current_revision from private.member_accounts where user_id=actor for update;
  if not found then raise exception 'Member not found';end if;
  if p_revision is null or current_revision<>p_revision then raise exception 'Member settings changed; reload required';end if;
  previous:=private.admin_member_snapshot(actor);
  update public.profiles set nickname=p_nickname,region=p_region where id=actor;
  update private.member_accounts set revision=revision+1 where user_id=actor;
  updated:=private.admin_member_snapshot(actor);
  insert into private.admin_audit(actor_id,target_id,detail) values(actor,actor,jsonb_build_object('before',previous,'after',updated,'source','self_profile'));
  return public.get_my_membership();
end; $$;
revoke all on function public.update_my_profile(text,text,bigint) from public,anon,authenticated;
grant execute on function public.update_my_profile(text,text,bigint) to authenticated;

create or replace function public.admin_update_member_with_profile(p_user uuid,p_status text,p_staff_role text,p_is_yb boolean,p_yb_role text,p_is_admin boolean,p_team text,p_nickname text,p_region text,p_permissions jsonb,p_revision bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor_admin boolean; current_revision bigint; previous jsonb; updated jsonb; board_key text; mode text; actor uuid:=(select auth.uid());
begin
  -- Serialize administrator membership mutations and protect the final administrator.
  perform pg_advisory_xact_lock(hashtextextended('community-member-administration',0));
  if not private.can_manage_members() then raise exception 'Administrator required'; end if;
  actor_admin:=private.is_admin();
  p_nickname:=trim(p_nickname);p_region:=trim(p_region);
  if p_nickname is null or char_length(p_nickname) not between 2 and 20 or p_nickname ~ '[[:cntrl:]]' then raise exception 'Invalid profile nickname';end if;
  if p_region is null or char_length(p_region) not between 1 and 20 or p_region ~ '[[:cntrl:]]' then raise exception 'Invalid profile region';end if;
  if p_user is null or p_status is null or p_status not in ('pending','approved','rejected','suspended')
    or p_staff_role is null or p_staff_role not in ('member','staff','vice_staff') or p_is_yb is null or p_is_admin is null
    or p_yb_role is null or p_yb_role not in ('member','director','manager')
    or (p_team is not null and p_team not in ('kia','samsung','lg','doosan','kt','ssg','lotte','hanwha','nc','kiwoom'))
    or p_revision is null or jsonb_typeof(p_permissions) is distinct from 'object' then raise exception 'Invalid member settings'; end if;
  if (select count(*) from jsonb_object_keys(p_permissions))<>12
    or exists(select 1 from jsonb_each_text(p_permissions) entry where entry.key not in ('free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','staff_plot','staff_minutes','yb_roster','yb_calendar','yb_holics','recruit') or entry.value not in ('default','deny','read','write') or entry.value is null)
    then raise exception 'Invalid board permissions'; end if;
  if not p_is_yb and p_yb_role<>'member' then raise exception 'YB role requires membership'; end if;
  if p_permissions->>'yb_roster'='write' and not (p_is_admin or p_staff_role in ('staff','vice_staff') or (p_is_yb and p_yb_role in ('director','manager'))) then raise exception 'Roster role required'; end if;
  if p_permissions->>'yb_calendar'='write' and not (p_is_admin or p_staff_role in ('staff','vice_staff') or (p_is_yb and p_yb_role in ('director','manager'))) then raise exception 'Calendar role required'; end if;
  if p_permissions->>'recruit'='write' and not (p_is_admin or p_staff_role in ('staff','vice_staff')) then raise exception 'Recruitment moderator required'; end if;
  select revision into current_revision from private.member_accounts where user_id=p_user for update;
  if not found then raise exception 'Member not found'; end if;
  if current_revision<>p_revision then raise exception 'Member settings changed; reload required'; end if;
  if not actor_admin and (p_is_admin or exists(select 1 from private.admins where user_id=p_user)) then
    raise exception 'Only administrators may manage administrator accounts';
  end if;
  if p_is_admin and p_status<>'approved' then raise exception 'Administrator must remain approved'; end if;
  if p_user=actor and (p_status<>'approved' or (actor_admin and not p_is_admin) or (not actor_admin and p_staff_role not in ('staff','vice_staff'))) then raise exception 'Cannot remove your own administrator access'; end if;
  if exists(select 1 from private.admins where user_id=p_user) and not p_is_admin
    and (select count(*) from private.admins d join private.member_accounts a on a.user_id=d.user_id where a.status='approved')<=1
    then raise exception 'Cannot remove final administrator'; end if;
  previous:=private.admin_member_snapshot(p_user);
  update private.member_accounts set status=p_status,revision=revision+1,
    approved_at=case when p_status='approved' and status<>'approved' then now() else approved_at end,
    approved_by=case when p_status='approved' and status<>'approved' then actor else approved_by end where user_id=p_user;
  update public.profiles set staff_role=p_staff_role,yb_role=p_yb_role,team=p_team,nickname=p_nickname,region=p_region where id=p_user;
  if p_is_admin then insert into private.admins(user_id) values(p_user) on conflict do nothing;
  else delete from private.admins where user_id=p_user; end if;
  if p_is_yb then insert into private.board_memberships(user_id,board) values(p_user,'yb') on conflict do nothing;
  else delete from private.board_memberships where user_id=p_user and board='yb'; end if;
  delete from private.member_permissions where user_id=p_user;
  for board_key,mode in select key,value from jsonb_each_text(p_permissions) loop
    if mode<>'default' then insert into private.member_permissions(user_id,board,access) values(p_user,board_key,mode); end if;
  end loop;
  updated:=private.admin_member_snapshot(p_user);
  insert into private.admin_audit(actor_id,target_id,detail) values(actor,p_user,jsonb_build_object('before',previous,'after',updated));
  return updated;
end; $$;

revoke all on function public.admin_update_member_with_profile(uuid,text,text,boolean,text,boolean,text,text,text,jsonb,bigint) from public,anon,authenticated;
grant execute on function public.admin_update_member_with_profile(uuid,text,text,boolean,text,boolean,text,text,text,jsonb,bigint) to authenticated;
commit;

-- Apply after 031. Approved members can read and write recruitment posts by default.
-- Explicit read/deny exceptions and approval/restriction checks remain in force.
begin;
create or replace function private.menu_permission(p_user uuid,p_menu text) returns text
language plpgsql stable security definer set search_path='' as $$
declare override_access text; member_role text;
begin
  if p_menu is null or p_menu not in ('free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','staff_plot','staff_minutes','yb_roster','yb_calendar','yb_holics','recruit') then return 'deny'; end if;
  if p_user is null then return 'deny'; end if;
  if not private.member_approved(p_user) then return 'deny'; end if;
  if exists(select 1 from private.admins where user_id=p_user) then return 'write'; end if;
  select staff_role into member_role from public.profiles where id=p_user;
  select access into override_access from private.member_permissions where user_id=p_user and board=p_menu;
  if found then return case when p_menu in ('yb_roster','yb_calendar') and override_access='write' and not private.roster_editor_role(p_user) then 'read' else override_access end; end if;
  select staff_role into member_role from public.profiles where id=p_user;
  if p_menu in ('free','humor','recruit','gallery_flash','gallery_attendance','gallery_meetup') then return 'write'; end if;
  if p_menu='notice' then return case when member_role in ('staff','vice_staff') then 'write' else 'read' end; end if;
  if p_menu in ('staff_plot','staff_minutes') then return case when member_role in ('staff','vice_staff') then 'write' else 'deny' end; end if;
  if p_menu='yb_roster' then return case when private.roster_editor_role(p_user) then 'write' else 'read' end; end if;
  if p_menu='yb_calendar' then return case when private.roster_editor_role(p_user) then 'write' else 'read' end; end if;
  if member_role in ('staff','vice_staff') or private.is_yb_member(p_user) then return 'write'; end if;
  return 'deny';
end; $$;

create or replace function public.admin_update_member(p_user uuid,p_status text,p_staff_role text,p_is_yb boolean,p_yb_role text,p_is_admin boolean,p_team text,p_permissions jsonb,p_revision bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor_admin boolean; current_revision bigint; previous jsonb; updated jsonb; board_key text; mode text; actor uuid:=(select auth.uid());
begin
  -- Serialize administrator membership mutations and protect the final administrator.
  perform pg_advisory_xact_lock(hashtextextended('community-member-administration',0));
  if not private.can_manage_members() then raise exception 'Administrator required'; end if;
  actor_admin:=private.is_admin();
  if p_user is null or p_status is null or p_status not in ('pending','approved','rejected','suspended')
    or p_staff_role is null or p_staff_role not in ('member','staff','vice_staff') or p_is_yb is null or p_is_admin is null
    or p_yb_role is null or p_yb_role not in ('member','director','manager')
    or (p_team is not null and p_team not in ('kia','samsung','lg','doosan','kt','ssg','lotte','hanwha','nc','kiwoom'))
    or p_revision is null or jsonb_typeof(p_permissions) is distinct from 'object' then raise exception 'Invalid member settings'; end if;
  if (select count(*) from jsonb_object_keys(p_permissions))<>12
    or exists(select 1 from jsonb_each_text(p_permissions) entry where entry.key not in ('free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','staff_plot','staff_minutes','yb_roster','yb_calendar','yb_holics','recruit') or entry.value not in ('default','deny','read','write') or entry.value is null)
    then raise exception 'Invalid board permissions'; end if;
  if not p_is_yb and p_yb_role<>'member' then raise exception 'YB role requires membership'; end if;
  if p_permissions->>'yb_roster'='write' and not (p_is_admin or p_staff_role in ('staff','vice_staff') or (p_is_yb and p_yb_role in ('director','manager'))) then raise exception 'Roster role required'; end if;
  select revision into current_revision from private.member_accounts where user_id=p_user for update;
  if not found then raise exception 'Member not found'; end if;
  if current_revision<>p_revision then raise exception 'Member settings changed; reload required'; end if;
  if not actor_admin and (p_is_admin or exists(select 1 from private.admins where user_id=p_user)) then
    raise exception 'Only administrators may manage administrator accounts';
  end if;
  if p_is_admin and p_status<>'approved' then raise exception 'Administrator must remain approved'; end if;
  if p_user=actor and (p_status<>'approved' or (actor_admin and not p_is_admin) or (not actor_admin and p_staff_role not in ('staff','vice_staff'))) then raise exception 'Cannot remove your own administrator access'; end if;
  if exists(select 1 from private.admins where user_id=p_user) and not p_is_admin
    and (select count(*) from private.admins d join private.member_accounts a on a.user_id=d.user_id where a.status='approved')<=1
    then raise exception 'Cannot remove final administrator'; end if;
  previous:=private.admin_member_snapshot(p_user);
  update private.member_accounts set status=p_status,revision=revision+1,
    approved_at=case when p_status='approved' and status<>'approved' then now() else approved_at end,
    approved_by=case when p_status='approved' and status<>'approved' then actor else approved_by end where user_id=p_user;
  update public.profiles set staff_role=p_staff_role,yb_role=p_yb_role,team=p_team where id=p_user;
  if p_is_admin then insert into private.admins(user_id) values(p_user) on conflict do nothing;
  else delete from private.admins where user_id=p_user; end if;
  if p_is_yb then insert into private.board_memberships(user_id,board) values(p_user,'yb') on conflict do nothing;
  else delete from private.board_memberships where user_id=p_user and board='yb'; end if;
  delete from private.member_permissions where user_id=p_user;
  for board_key,mode in select key,value from jsonb_each_text(p_permissions) loop
    if mode<>'default' then insert into private.member_permissions(user_id,board,access) values(p_user,board_key,mode); end if;
  end loop;
  updated:=private.admin_member_snapshot(p_user);
  insert into private.admin_audit(actor_id,target_id,detail) values(actor,p_user,jsonb_build_object('before',previous,'after',updated));
  return updated;
end; $$;

create or replace function public.admin_update_member_with_profile(p_user uuid,p_status text,p_staff_role text,p_is_yb boolean,p_yb_role text,p_is_admin boolean,p_team text,p_nickname text,p_region text,p_permissions jsonb,p_revision bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor_admin boolean; current_revision bigint; previous jsonb; updated jsonb; board_key text; mode text; actor uuid:=(select auth.uid());
begin
  -- Serialize administrator membership mutations and protect the final administrator.
  perform pg_advisory_xact_lock(hashtextextended('community-member-administration',0));
  if not private.can_manage_members() then raise exception 'Administrator required'; end if;
  actor_admin:=private.is_admin();
  p_nickname:=trim(p_nickname);p_region:=trim(p_region);
  if p_nickname is null or char_length(p_nickname) not between 2 and 20 or p_nickname ~ '[[:cntrl:]]' then raise exception 'Invalid profile nickname';end if;
  if p_region is null or char_length(p_region) not between 1 and 20 or p_region ~ '[[:cntrl:]]' then raise exception 'Invalid profile region';end if;
  if p_user is null or p_status is null or p_status not in ('pending','approved','rejected','suspended')
    or p_staff_role is null or p_staff_role not in ('member','staff','vice_staff') or p_is_yb is null or p_is_admin is null
    or p_yb_role is null or p_yb_role not in ('member','director','manager')
    or (p_team is not null and p_team not in ('kia','samsung','lg','doosan','kt','ssg','lotte','hanwha','nc','kiwoom'))
    or p_revision is null or jsonb_typeof(p_permissions) is distinct from 'object' then raise exception 'Invalid member settings'; end if;
  if (select count(*) from jsonb_object_keys(p_permissions))<>12
    or exists(select 1 from jsonb_each_text(p_permissions) entry where entry.key not in ('free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','staff_plot','staff_minutes','yb_roster','yb_calendar','yb_holics','recruit') or entry.value not in ('default','deny','read','write') or entry.value is null)
    then raise exception 'Invalid board permissions'; end if;
  if not p_is_yb and p_yb_role<>'member' then raise exception 'YB role requires membership'; end if;
  if p_permissions->>'yb_roster'='write' and not (p_is_admin or p_staff_role in ('staff','vice_staff') or (p_is_yb and p_yb_role in ('director','manager'))) then raise exception 'Roster role required'; end if;
  if p_permissions->>'yb_calendar'='write' and not (p_is_admin or p_staff_role in ('staff','vice_staff') or (p_is_yb and p_yb_role in ('director','manager'))) then raise exception 'Calendar role required'; end if;
  select revision into current_revision from private.member_accounts where user_id=p_user for update;
  if not found then raise exception 'Member not found'; end if;
  if current_revision<>p_revision then raise exception 'Member settings changed; reload required'; end if;
  if not actor_admin and (p_is_admin or exists(select 1 from private.admins where user_id=p_user)) then
    raise exception 'Only administrators may manage administrator accounts';
  end if;
  if p_is_admin and p_status<>'approved' then raise exception 'Administrator must remain approved'; end if;
  if p_user=actor and (p_status<>'approved' or (actor_admin and not p_is_admin) or (not actor_admin and p_staff_role not in ('staff','vice_staff'))) then raise exception 'Cannot remove your own administrator access'; end if;
  if exists(select 1 from private.admins where user_id=p_user) and not p_is_admin
    and (select count(*) from private.admins d join private.member_accounts a on a.user_id=d.user_id where a.status='approved')<=1
    then raise exception 'Cannot remove final administrator'; end if;
  previous:=private.admin_member_snapshot(p_user);
  update private.member_accounts set status=p_status,revision=revision+1,
    approved_at=case when p_status='approved' and status<>'approved' then now() else approved_at end,
    approved_by=case when p_status='approved' and status<>'approved' then actor else approved_by end where user_id=p_user;
  update public.profiles set staff_role=p_staff_role,yb_role=p_yb_role,team=p_team,nickname=p_nickname,region=p_region where id=p_user;
  if p_is_admin then insert into private.admins(user_id) values(p_user) on conflict do nothing;
  else delete from private.admins where user_id=p_user; end if;
  if p_is_yb then insert into private.board_memberships(user_id,board) values(p_user,'yb') on conflict do nothing;
  else delete from private.board_memberships where user_id=p_user and board='yb'; end if;
  delete from private.member_permissions where user_id=p_user;
  for board_key,mode in select key,value from jsonb_each_text(p_permissions) loop
    if mode<>'default' then insert into private.member_permissions(user_id,board,access) values(p_user,board_key,mode); end if;
  end loop;
  updated:=private.admin_member_snapshot(p_user);
  insert into private.admin_audit(actor_id,target_id,detail) values(actor,p_user,jsonb_build_object('before',previous,'after',updated));
  return updated;
end; $$;
commit;
