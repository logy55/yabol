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
