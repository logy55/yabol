-- Apply after migration 004. YB affiliation uses the existing trusted membership.
begin;
create function private.is_yb_member(p_user uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from private.board_memberships where user_id=p_user and board='yb');
$$;
revoke all on function private.is_yb_member(uuid) from public,anon,authenticated;
grant execute on function private.is_yb_member(uuid) to anon,authenticated,service_role;

-- Administrators' general board access is not itself YB affiliation.
-- Client-editable Auth metadata is never used for this badge.
create or replace function public.get_my_membership() returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('username',a.username,'nickname',p.nickname,'team',p.team,'region',p.region,
    'status',case when private.member_approved(p.id) then 'approved' else 'pending' end,
    'created_at',p.created_at,'staff_role',p.staff_role,'is_yb_member',private.is_yb_member(p.id))
  from public.profiles p join private.member_accounts a on a.user_id=p.id where p.id=(select auth.uid());
$$;
create or replace view public.post_feed with(security_invoker=true) as
select p.id,p.author_id,p.board,p.title,p.body,p.images,p.is_notice,p.created_at,p.updated_at,r.nickname,
  (select count(*) from public.likes l where l.post_id=p.id) as like_count,
  (select count(*) from public.comments c where c.post_id=p.id) as comment_count,
  p.category,r.team,r.region,r.staff_role,private.is_yb_member(r.id) as is_yb_member
from public.posts p join public.profiles r on r.id=p.author_id;
create or replace view public.comment_feed with(security_invoker=true) as
select c.*,r.nickname,r.team,r.region,r.staff_role,private.is_yb_member(r.id) as is_yb_member
from public.comments c join public.profiles r on r.id=c.author_id;
commit;
