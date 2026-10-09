-- Apply after 026. Approved member access, author/moderator editing and recoverable deletion.
begin;
grant execute on function private.can_manage_members() to authenticated;
alter table public.posts add column deleted_at timestamptz, add column deleted_by uuid references auth.users(id);
alter table public.comments add column updated_at timestamptz not null default now(), add column deleted_at timestamptz, add column deleted_by uuid references auth.users(id);
create or replace function private.menu_permission(p_user uuid,p_menu text) returns text
language plpgsql stable security definer set search_path='' as $$
declare override_access text; member_role text;
begin
  if p_menu is null or p_menu not in ('free','humor','gallery_flash','gallery_attendance','gallery_meetup','notice','staff_plot','staff_minutes','yb_roster','yb_calendar','yb_holics','recruit') then return 'deny'; end if;
  if p_user is null then return 'deny'; end if;
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
drop policy profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated using(private.member_approved((select auth.uid())));
drop policy posts_read on public.posts;
create policy posts_read on public.posts for select to anon,authenticated using(deleted_at is null and private.can_read_post_menu(board,category));
drop policy posts_edit on public.posts;
create policy posts_edit on public.posts for update to authenticated
using(deleted_at is null and private.can_write_post_menu(board,category) and (author_id=(select auth.uid()) or private.can_manage_members()))
with check(deleted_at is null and private.can_write_post_menu(board,category) and (author_id=(select auth.uid()) or private.can_manage_members()));
drop policy comments_read on public.comments;
create policy comments_read on public.comments for select to anon,authenticated using(deleted_at is null and exists(select 1 from public.posts p where p.id=post_id));
grant update(body) on public.comments to authenticated;
create policy comments_edit on public.comments for update to authenticated
using(deleted_at is null and (author_id=(select auth.uid()) or private.can_manage_members()) and exists(select 1 from public.posts p where p.id=post_id and private.can_write_post_menu(p.board,p.category)))
with check(deleted_at is null and (author_id=(select auth.uid()) or private.can_manage_members()) and exists(select 1 from public.posts p where p.id=post_id and private.can_write_post_menu(p.board,p.category)));
create or replace view public.comment_feed with(security_invoker=true) as
select c.id,c.post_id,c.author_id,c.body,c.created_at,r.nickname,r.team,r.region,r.staff_role,private.is_yb_member(r.id) as is_yb_member,c.updated_at
from public.comments c join public.profiles r on r.id=c.author_id;

create or replace function private.validate_post_images() returns trigger
language plpgsql security definer set search_path='' as $$
declare retained text[]:='{}';
begin
  if tg_op='UPDATE' then retained:=old.images; end if;
  if exists(select 1 from unnest(new.images) image(url) where not exists(
    select 1 from public.upload_tickets t where t.secure_url=image.url and t.verified_at is not null
    and (t.owner_id=new.author_id or (tg_op='UPDATE' and image.url=any(retained)) or (private.can_manage_members() and t.owner_id=(select auth.uid())))
    and ((new.board in ('staff','yb') and t.board=new.board and t.delivery_type='authenticated') or (new.board not in ('staff','yb') and t.delivery_type='upload'))
  )) then raise exception 'Unverified or incorrectly protected attachment'; end if;
  new.updated_at:=now(); return new;
end; $$;
create function private.live_post_content() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if not exists(select 1 from public.posts where id=new.post_id and deleted_at is null) then raise exception 'Post unavailable';end if;
  if tg_table_name='comments' then new.updated_at:=now();end if;
  return new;
end; $$;
revoke all on function private.live_post_content() from public,anon,authenticated;
create trigger comments_live_post before insert or update of body on public.comments for each row execute function private.live_post_content();
create trigger likes_live_post before insert on public.likes for each row execute function private.live_post_content();

create function public.manage_deleted_content(p_kind text,p_id uuid,p_restore boolean) returns void
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); item_owner uuid; parent_id uuid; item_deleted timestamptz; item_board text; item_category text;
begin
  if not private.member_approved(actor) or p_restore is null then raise exception 'Approved member required';end if;
  if p_kind='post' then
    select author_id,deleted_at,board,category into item_owner,item_deleted,item_board,item_category from public.posts where id=p_id for update;
  elsif p_kind='comment' then
    select post_id into parent_id from public.comments where id=p_id;
    select board,category into item_board,item_category from public.posts where id=parent_id and deleted_at is null for update;
    if not found then raise exception 'Post unavailable';end if;
    select author_id,deleted_at into item_owner,item_deleted from public.comments where id=p_id for update;
  else raise exception 'Invalid content type';end if;
  if item_owner is null or not private.can_write_post_menu(item_board,item_category) or not (item_owner=actor or private.can_manage_members()) then raise exception 'Content management permission required';end if;
  if p_restore then
    if p_kind='post' then update public.posts set deleted_at=null,deleted_by=null,updated_at=now() where id=p_id;
    else update public.comments set deleted_at=null,deleted_by=null,updated_at=now() where id=p_id;end if;
  else
    if p_kind='post' then update public.posts set deleted_at=coalesce(deleted_at,now()),deleted_by=coalesce(deleted_by,actor),is_notice=false,updated_at=now() where id=p_id;
    else update public.comments set deleted_at=coalesce(deleted_at,now()),deleted_by=coalesce(deleted_by,actor),updated_at=now() where id=p_id;end if;
  end if;
end; $$;
create function public.get_deleted_content() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if not private.member_approved((select auth.uid())) then raise exception 'Approved member required';end if;
  return coalesce((select jsonb_agg(to_jsonb(items)) from (
    select * from (
      select 'post'::text kind,p.id,p.title label,p.board,p.category,p.deleted_at from public.posts p where p.deleted_at is not null and private.can_write_post_menu(p.board,p.category) and (p.author_id=(select auth.uid()) or private.can_manage_members())
      union all
      select 'comment',c.id,c.body,p.board,p.category,c.deleted_at from public.comments c join public.posts p on p.id=c.post_id where c.deleted_at is not null and p.deleted_at is null and private.can_write_post_menu(p.board,p.category) and (c.author_id=(select auth.uid()) or private.can_manage_members())
    ) content order by deleted_at desc limit 100
  ) items),'[]'::jsonb);
end; $$;
revoke all on function public.manage_deleted_content(text,uuid,boolean),public.get_deleted_content() from public,anon,authenticated;
grant execute on function public.manage_deleted_content(text,uuid,boolean),public.get_deleted_content() to authenticated;
create or replace function public.save_notice_post(p_id uuid,p_title text,p_body text,p_doc jsonb,p_images text[],p_main boolean) returns uuid
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); saved uuid; old_main boolean;
begin
  if not private.member_approved(actor) or private.menu_permission(actor,'notice')<>'write' then raise exception 'Notice write required';end if;
  if p_main is null then raise exception 'Invalid notice setting';end if;
  if p_main and not private.can_manage_members() then raise exception 'Notice management required';end if;
  -- Serialize post editing and main-notice selection in a consistent order.
  perform pg_advisory_xact_lock(hashtextextended('community-main-notice',0));
  if p_id is null then
    insert into public.posts(author_id,board,title,body,body_doc,images) values(actor,'notice',p_title,p_body,p_doc,p_images) returning id into saved;
  else
    select is_notice into old_main from public.posts where id=p_id and board='notice' and deleted_at is null and (author_id=actor or private.can_manage_members()) for update;
    if not found then raise exception 'Notice edit permission required';end if;
    if old_main and not private.can_manage_members() then raise exception 'Notice management required';end if;
    update public.posts set title=p_title,body=p_body,body_doc=p_doc,images=p_images where id=p_id returning id into saved;
  end if;
  if private.can_manage_members() then perform public.set_main_notice(saved,p_main);end if;
  return saved;
end; $$;
create or replace function public.set_main_notice(p_post uuid,p_enabled boolean) returns void
language plpgsql security definer set search_path='' as $$
begin
  if not private.can_manage_members() or private.menu_permission((select auth.uid()),'notice')<>'write' then raise exception 'Notice management required';end if;
  if p_enabled is null then raise exception 'Invalid notice setting';end if;
  perform pg_advisory_xact_lock(hashtextextended('community-main-notice',0));
  perform 1 from public.posts where id=p_post and board='notice' and deleted_at is null;
  if not found then raise exception 'Notice post required';end if;
  if p_enabled then update public.posts set is_notice=false where is_notice;end if;
  update public.posts set is_notice=p_enabled where id=p_post;
end; $$;
create or replace function public.get_team_roster() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  if private.menu_permission((select auth.uid()),'yb_roster') not in ('read','write') then raise exception 'Roster access required'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'role',r.role,'name',r.name,'jersey_number',r.jersey_number,
    'sort_order',r.sort_order,'revision',r.revision,'photo_url',r.photo_url,
    'photo_post_id',case when r.photo_url is null then p.id end,
    'photo_private',case when r.photo_url is not null then false else coalesce(p.board in ('staff','yb'),false) end,
    'photo',coalesce(r.photo_url,p.images[r.photo_index+1]))
    order by array_position(array['manager','coach','team_manager','pitcher','catcher','infielder','outfielder'],r.role),r.jersey_number asc nulls last,r.name,r.id),'[]'::jsonb)
  into result from private.team_roster r left join public.posts p on p.id=r.photo_post_id and p.deleted_at is null and private.can_read_post_menu(p.board,p.category)
  where r.deleted_at is null;
  return result;
end; $$;
commit;
