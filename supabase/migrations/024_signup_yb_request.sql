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
