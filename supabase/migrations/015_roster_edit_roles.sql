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
