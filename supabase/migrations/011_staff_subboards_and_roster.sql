-- Apply after 010. Staff subboards share staff permission; roster shares YB permission.
begin;
alter table public.posts drop constraint posts_category_check;
create temporary table staff_subboard_timestamps on commit drop as select id,updated_at from public.posts where board='staff' and category is null;
update public.posts set category='plot' where board='staff' and category is null;
update public.posts p set updated_at=t.updated_at from staff_subboard_timestamps t where p.id=t.id;
alter table public.posts add constraint posts_category_check check (
  (board='free' and category is not null and category in ('humor','info','chat','question'))
  or (board='gallery' and (category is null or category in ('meetup','flash','meme','attendance')))
  or (board='staff' and category is not null and category in ('plot','minutes'))
  or (board in ('notice','yb') and category is null)
);
create or replace function private.default_free_topic() returns trigger
language plpgsql set search_path='' as $$
begin
  if new.board='free' and new.category is null then new.category:='chat'; end if;
  if new.board='staff' and new.category is null then new.category:='plot'; end if;
  return new;
end; $$;

create table private.team_roster (
  id uuid primary key default gen_random_uuid(),
  role text not null check(role in ('manager','coach','team_manager','pitcher','catcher','infielder','outfielder')),
  name text not null check(char_length(trim(name)) between 1 and 50),
  jersey_number integer check(jersey_number between 0 and 999),
  sort_order integer not null default 0 check(sort_order>=0),
  photo_post_id uuid references public.posts(id) on delete set null,
  photo_index integer not null default 0 check(photo_index between 0 and 4)
);
alter table private.team_roster enable row level security;
revoke all on private.team_roster from public,anon,authenticated;
create function public.get_team_roster() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  if not private.member_approved((select auth.uid())) or not private.can_access_board('yb') then raise exception 'YB membership required'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'role',r.role,'name',r.name,'jersey_number',r.jersey_number,
    'photo_post_id',p.id,'photo',p.images[r.photo_index+1]) order by array_position(array['manager','coach','team_manager','pitcher','catcher','infielder','outfielder'],r.role),r.sort_order,r.name,r.id),'[]'::jsonb)
  into result from private.team_roster r left join public.posts p on p.id=r.photo_post_id and p.board='yb';
  return result;
end; $$;
revoke all on function public.get_team_roster() from public,anon,authenticated;
grant execute on function public.get_team_roster() to authenticated;
commit;
