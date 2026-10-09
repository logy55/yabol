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
