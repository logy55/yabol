-- Apply after migration 003. Staff badges are server-managed presentation roles.
begin;
alter table public.profiles add column staff_role text not null default 'member'
  check(staff_role in ('member','staff','vice_staff'));
update public.profiles p set staff_role='staff'
where exists(select 1 from private.admins a where a.user_id=p.id);

-- The existing profile grants allow clients to read, but never write this field.
-- Editable Auth metadata is deliberately not used for staff roles.
create or replace function public.get_my_membership() returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('username',a.username,'nickname',p.nickname,'team',p.team,'region',p.region,
    'status',case when private.member_approved(p.id) then 'approved' else 'pending' end,
    'created_at',p.created_at,'staff_role',p.staff_role)
  from public.profiles p join private.member_accounts a on a.user_id=p.id where p.id=(select auth.uid());
$$;

create or replace view public.post_feed with(security_invoker=true) as
select p.id,p.author_id,p.board,p.title,p.body,p.images,p.is_notice,p.created_at,p.updated_at,r.nickname,
  (select count(*) from public.likes l where l.post_id=p.id) as like_count,
  (select count(*) from public.comments c where c.post_id=p.id) as comment_count,p.category,r.team,r.region,r.staff_role
from public.posts p join public.profiles r on r.id=p.author_id;
create or replace view public.comment_feed with(security_invoker=true) as
select c.*,r.nickname,r.team,r.region,r.staff_role from public.comments c join public.profiles r on r.id=c.author_id;
commit;
