begin;
create or replace function public.get_member_info(p_user uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare records jsonb;profile jsonb;
begin
 -- Reuse the existing approved-viewer and accepted-target checks.
 records:=public.get_member_game_records(p_user);
 select jsonb_build_object('nickname',p.nickname,'region',p.region,'team',p.team,'staff_role',p.staff_role,
  'is_yb_member',private.is_yb_member(p.id),'created_at',p.created_at) into profile from public.profiles p where p.id=p_user;
 return records||jsonb_build_object('profile',profile,'activity',jsonb_build_object(
  'posts',(select count(*) from public.posts where author_id=p_user and deleted_at is null),
  'comments',(select count(*) from public.comments c join public.posts p on p.id=c.post_id where c.author_id=p_user and c.deleted_at is null and p.deleted_at is null)));
end;$$;
revoke all on function public.get_member_info(uuid) from public,anon,authenticated;
grant execute on function public.get_member_info(uuid) to authenticated;
commit;
