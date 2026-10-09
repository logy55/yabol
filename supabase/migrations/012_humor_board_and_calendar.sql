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
