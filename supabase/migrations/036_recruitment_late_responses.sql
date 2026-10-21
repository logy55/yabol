-- Apply after 035. Button-only recruitment responses and ten-minute late-arrival choices.
begin;
alter table private.recruitment_responses drop constraint recruitment_responses_response_check;
alter table private.recruitment_responses add constraint recruitment_responses_response_check check(response in ('attend','late','decline'));
alter table private.recruitment_responses add column delay_minutes integer;
alter table private.recruitment_responses add constraint recruitment_responses_delay_check check(
 (response='late' and delay_minutes is not null and delay_minutes between 10 and 1430 and mod(delay_minutes,10)=0)
 or (response<>'late' and delay_minutes is null));

create or replace function public.get_recruitment_response(p_post uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;begin
 if not exists(select 1 from public.posts where id=p_post and board='recruit' and deleted_at is null) then raise exception 'Recruitment post required';end if;
 if not private.member_approved((select auth.uid())) or private.menu_permission((select auth.uid()),'recruit') not in ('read','write') then raise exception 'Recruitment access required';end if;
 select jsonb_build_object('attend',count(*) filter(where r.response='attend'),'late',count(*) filter(where r.response='late'),'decline',count(*) filter(where r.response='decline'),
  'mine',max(r.response) filter(where r.user_id=(select auth.uid())), 'mine_delay_minutes',max(r.delay_minutes) filter(where r.user_id=(select auth.uid()))) into result
 from private.recruitment_responses r join public.comments c on c.id=r.comment_id where r.post_id=p_post and c.deleted_at is null;
 return result;
end;$$;

create function public.set_recruitment_response(p_post uuid,p_response text,p_delay_minutes integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid());existing private.recruitment_responses;comment uuid;message text;duration text;
begin
 if actor is null or not private.member_approved(actor) or private.menu_permission(actor,'recruit') not in ('read','write') then raise exception 'Approved member required';end if;
 if p_response is null or p_response not in ('attend','late','decline') then raise exception 'Invalid recruitment response';end if;
 if (p_response='late' and (p_delay_minutes is null or p_delay_minutes not between 10 and 1430 or mod(p_delay_minutes,10)<>0))
  or (p_response<>'late' and p_delay_minutes is not null) then raise exception 'Invalid late duration';end if;
 perform 1 from public.posts where id=p_post and board='recruit' and deleted_at is null for share;
 if not found then raise exception 'Recruitment post required';end if;
 perform pg_advisory_xact_lock(hashtextextended('recruitment:'||p_post::text||':'||actor::text,0));
 select * into existing from private.recruitment_responses where post_id=p_post and user_id=actor for update;
 duration:=concat_ws(' ',case when p_delay_minutes/60>0 then (p_delay_minutes/60)::text||'시간' end,case when mod(p_delay_minutes,60)>0 then mod(p_delay_minutes,60)::text||'분' end);
 message:=case p_response when 'attend' then '참석합니다.' when 'decline' then '아쉽지만 이번에는 불참합니다. 마음만은 함께할게요!' else '참석합니다! 그런데 '||duration||'쯤 늦을 것 같아요.. ㅠ.ㅠ 조금만 기다려 주세요!' end;
 if existing.comment_id is not null then
  update public.comments set body=message,deleted_at=null where id=existing.comment_id and author_id=actor and post_id=p_post and (body is distinct from message or deleted_at is not null);
  update private.recruitment_responses set response=p_response,delay_minutes=p_delay_minutes,updated_at=now() where post_id=p_post and user_id=actor;
 else
  insert into public.comments(post_id,author_id,body) values(p_post,actor,message) returning id into comment;
  insert into private.recruitment_responses(post_id,user_id,comment_id,response,delay_minutes) values(p_post,actor,comment,p_response,p_delay_minutes);
 end if;
 return public.get_recruitment_response(p_post);
end;$$;

-- Older clients retain attend/decline; all writes use the same validation and message builder.
create or replace function public.set_recruitment_response(p_post uuid,p_response text) returns jsonb
language sql security definer set search_path='' as $$select public.set_recruitment_response(p_post,p_response,null);$$;
revoke all on function public.set_recruitment_response(uuid,text,integer),public.set_recruitment_response(uuid,text),public.get_recruitment_response(uuid) from public,anon,authenticated;
grant execute on function public.set_recruitment_response(uuid,text,integer),public.set_recruitment_response(uuid,text),public.get_recruitment_response(uuid) to authenticated;

-- The definer RPC above owns automatic comments; direct authenticated inserts/edits cannot bypass the buttons.
create policy recruitment_comments_automatic_insert on public.comments as restrictive for insert to authenticated
 with check(not exists(select 1 from public.posts p where p.id=post_id and p.board='recruit'));
create policy recruitment_comments_automatic_update on public.comments as restrictive for update to authenticated
 using(not exists(select 1 from public.posts p where p.id=post_id and p.board='recruit'))
 with check(not exists(select 1 from public.posts p where p.id=post_id and p.board='recruit'));
commit;
