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
