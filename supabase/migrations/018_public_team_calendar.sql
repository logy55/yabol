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
