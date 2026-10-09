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
