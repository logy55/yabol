begin;
-- Only display fields are shared; login identifiers and moderation details stay private.
create or replace function public.get_member_directory()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.member_approved((select auth.uid())) then raise exception 'Approved member required';end if;
 return (select jsonb_build_object('total',count(*),'members',coalesce(jsonb_agg(
  jsonb_build_object('id',p.id,'nickname',p.nickname,'region',p.region,'team',p.team,'staff_role',p.staff_role,
   'is_yb_member',private.is_yb_member(p.id),'created_at',p.created_at) order by p.nickname,p.id),'[]'::jsonb))
  from public.profiles p join private.member_accounts a on a.user_id=p.id where a.status in ('approved','suspended'));
end;$$;
revoke all on function public.get_member_directory() from public,anon,authenticated;
grant execute on function public.get_member_directory() to authenticated;
commit;
