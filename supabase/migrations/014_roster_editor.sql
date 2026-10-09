-- Apply after 013. Roster writing is controlled by the yb_roster submenu permission.
begin;
alter table private.team_roster
  add column photo_url text,
  add column revision bigint not null default 1 check(revision>0),
  add column updated_at timestamptz not null default now(),
  add column updated_by uuid references auth.users(id) on delete set null,
  add column deleted_at timestamptz;
alter table public.upload_tickets drop constraint upload_tickets_board_check;
alter table public.upload_tickets add constraint upload_tickets_board_check check(board in ('free','humor','gallery','notice','staff','yb','yb_roster'));

create function public.member_can_write_menu(p_user uuid,p_menu text) returns boolean
language sql stable security definer set search_path='' as $$ select private.menu_permission(p_user,p_menu)='write'; $$;
revoke all on function public.member_can_write_menu(uuid,text) from public,anon,authenticated;
grant execute on function public.member_can_write_menu(uuid,text) to service_role;

create function public.reserve_roster_upload(p_owner uuid,p_public_id text) returns void
language plpgsql security definer set search_path='' as $$
begin
  if private.menu_permission(p_owner,'yb_roster')<>'write' then raise exception 'Roster management required'; end if;
  if p_public_id is null or p_public_id not like 'community/'||p_owner::text||'/%' then raise exception 'Invalid asset'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_owner::text,0));
  if (select count(*) from public.upload_tickets where owner_id=p_owner and created_at>now()-interval '1 hour')>=30 or
    (select count(*) from public.upload_tickets where owner_id=p_owner and created_at>now()-interval '1 day')>=100 then raise exception 'Upload quota exceeded'; end if;
  insert into public.upload_tickets(public_id,owner_id,board,delivery_type) values(p_public_id,p_owner,'yb_roster','upload');
end; $$;
revoke all on function public.reserve_roster_upload(uuid,text) from public,anon,authenticated;
grant execute on function public.reserve_roster_upload(uuid,text) to service_role;

create function public.save_team_roster(p_id uuid,p_revision bigint,p_role text,p_name text,p_number integer,p_sort_order integer,p_photo_url text,p_remove_photo boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); current_row private.team_roster; saved private.team_roster; next_photo text;
begin
  if private.menu_permission(actor,'yb_roster')<>'write' then raise exception 'Roster management required'; end if;
  if p_role is null or p_role not in ('manager','coach','team_manager','pitcher','catcher','infielder','outfielder') or
    p_name is null or char_length(trim(p_name)) not between 1 and 50 or
    (p_number is not null and p_number not between 0 and 999) or p_sort_order is null or p_sort_order<0 or
    p_remove_photo is null or p_revision is null then raise exception 'Invalid roster values'; end if;
  if p_id is not null then
    select * into current_row from private.team_roster where id=p_id and deleted_at is null for update;
    if not found or current_row.revision<>p_revision then raise exception 'Roster changed'; end if;
  elsif p_revision<>0 then raise exception 'Roster changed'; end if;
  next_photo:=case when p_remove_photo then null else coalesce(nullif(p_photo_url,''),current_row.photo_url) end;
  if next_photo is not null and next_photo is distinct from current_row.photo_url and not exists(
    select 1 from public.upload_tickets where owner_id=actor and board='yb_roster' and delivery_type='upload'
      and secure_url=next_photo and verified_at is not null and format in ('jpg','png','webp')
  ) then raise exception 'Verified roster photo required'; end if;
  if p_id is null then
    insert into private.team_roster(role,name,jersey_number,sort_order,photo_url,updated_by)
    values(p_role,trim(p_name),p_number,p_sort_order,next_photo,actor) returning * into saved;
  else
    update private.team_roster set role=p_role,name=trim(p_name),jersey_number=p_number,sort_order=p_sort_order,
      photo_url=next_photo,
      photo_post_id=case when p_remove_photo or next_photo is not null then null else photo_post_id end,
      photo_index=case when p_remove_photo or next_photo is not null then 0 else photo_index end,
      revision=revision+1,updated_at=now(),updated_by=actor where id=p_id returning * into saved;
  end if;
  return jsonb_build_object('id',saved.id,'revision',saved.revision);
end; $$;
revoke all on function public.save_team_roster(uuid,bigint,text,text,integer,integer,text,boolean) from public,anon,authenticated;
grant execute on function public.save_team_roster(uuid,bigint,text,text,integer,integer,text,boolean) to authenticated;

create function public.delete_team_roster(p_id uuid,p_revision bigint) returns void
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); current_revision bigint;
begin
  if private.menu_permission(actor,'yb_roster')<>'write' then raise exception 'Roster management required'; end if;
  select revision into current_revision from private.team_roster where id=p_id and deleted_at is null for update;
  if not found or p_revision is null or current_revision<>p_revision then raise exception 'Roster changed'; end if;
  update private.team_roster set deleted_at=now(),updated_at=now(),updated_by=actor,revision=revision+1 where id=p_id;
end; $$;
revoke all on function public.delete_team_roster(uuid,bigint) from public,anon,authenticated;
grant execute on function public.delete_team_roster(uuid,bigint) to authenticated;

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
    order by array_position(array['manager','coach','team_manager','pitcher','catcher','infielder','outfielder'],r.role),r.sort_order,r.name,r.id),'[]'::jsonb)
  into result from private.team_roster r left join public.posts p on p.id=r.photo_post_id and private.can_read_post_menu(p.board,p.category)
  where r.deleted_at is null;
  return result;
end; $$;
revoke all on function public.get_team_roster() from public,anon,authenticated;
grant execute on function public.get_team_roster() to anon,authenticated;
commit;
