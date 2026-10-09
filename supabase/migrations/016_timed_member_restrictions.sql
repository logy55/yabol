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
