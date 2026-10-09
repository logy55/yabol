-- Apply after 022. One explicitly selected home notice; save content and selection atomically.
begin;
create function public.set_main_notice(p_post uuid,p_enabled boolean) returns void
language plpgsql security definer set search_path='' as $$
begin
  if not private.can_manage_members() or private.menu_permission((select auth.uid()),'notice')<>'write' then raise exception 'Notice management required';end if;
  if p_enabled is null then raise exception 'Invalid notice setting';end if;
  perform pg_advisory_xact_lock(hashtextextended('community-main-notice',0));
  perform 1 from public.posts where id=p_post and board='notice';
  if not found then raise exception 'Notice post required';end if;
  if p_enabled then update public.posts set is_notice=false where is_notice;end if;
  update public.posts set is_notice=p_enabled where id=p_post;
end; $$;
create function public.save_notice_post(p_id uuid,p_title text,p_body text,p_doc jsonb,p_images text[],p_main boolean) returns uuid
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
    select is_notice into old_main from public.posts where id=p_id and board='notice' and author_id=actor for update;
    if not found then raise exception 'Notice author required';end if;
    if old_main and not private.can_manage_members() then raise exception 'Notice management required';end if;
    update public.posts set title=p_title,body=p_body,body_doc=p_doc,images=p_images where id=p_id returning id into saved;
  end if;
  if private.can_manage_members() then perform public.set_main_notice(saved,p_main);end if;
  return saved;
end; $$;
revoke all on function public.set_main_notice(uuid,boolean),public.save_notice_post(uuid,text,text,jsonb,text[],boolean) from public,anon,authenticated;
grant execute on function public.set_main_notice(uuid,boolean),public.save_notice_post(uuid,text,text,jsonb,text[],boolean) to authenticated;
commit;
