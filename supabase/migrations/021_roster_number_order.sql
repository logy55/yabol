-- Apply after 020. Preserve role groups; number ascending, unnumbered members last.
begin;
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
  into result from private.team_roster r left join public.posts p on p.id=r.photo_post_id and private.can_read_post_menu(p.board,p.category)
  where r.deleted_at is null;
  return result;
end; $$;
commit;
