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
