-- Apply after 032. Only approved, unrestricted membership managers can read the pending count.
begin;
create function public.get_pending_member_count() returns bigint
language plpgsql stable security definer set search_path='' as $$
begin
  if not private.can_manage_members() then raise exception 'Administrator required' using errcode='42501';end if;
  return (select count(*) from private.member_accounts where status='pending');
end; $$;
revoke all on function public.get_pending_member_count() from public,anon,authenticated;
grant execute on function public.get_pending_member_count() to authenticated;
commit;
