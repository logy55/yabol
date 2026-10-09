-- Only the room creator configures participants and losers. Results are fixed labels.
begin;
drop function public.create_ladder_room(text,jsonb);
create function public.create_ladder_room(p_capacity integer,p_losers integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); room private.ladder_rooms; n integer; p_outcomes jsonb;
begin
  if not private.member_approved(actor) then raise exception 'Approved member required';end if;
  if p_capacity is null or p_capacity not between 2 and 12 or p_losers is null or p_losers not between 1 and p_capacity-1 then raise exception 'Invalid room values';end if;
  n:=p_capacity;
  select jsonb_agg(case when i<=p_losers then '꽝' else '통과' end order by i) into p_outcomes from generate_series(1,n) i;
  perform pg_advisory_xact_lock(hashtextextended('ladder-create:'||actor::text,0));
  if (select count(*) from private.ladder_rooms where host_id=actor and created_at>now()-interval '1 hour')>=10 then raise exception 'Room limit exceeded';end if;
  loop
    begin
      insert into private.ladder_rooms(code,host_id,title,capacity,outcomes) values(upper(substr(replace(gen_random_uuid()::text,'-',''),1,6)),actor,'사다리 게임',n,p_outcomes) returning * into room;
      exit;
    exception when unique_violation then null;end;
  end loop;
  insert into private.ladder_players(room_id,user_id) values(room.id,actor);
  return private.ladder_snapshot(room.id);
end; $$;
create or replace function private.ladder_snapshot(p_room uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('id',r.id,'code',r.code,'title',r.title,'capacity',r.capacity,'losers',(select count(*) from jsonb_array_elements_text(r.outcomes) e where e='꽝'),'host_id',r.host_id,'revision',r.revision,'server_time',now(),
    'phase',case when r.phase='closed' then 'closed' when r.finish_at<=now() then 'finished' when r.start_at<=now() then 'running' else r.phase end,
    'start_at',r.start_at,'finish_at',r.finish_at,'round',case when r.phase<>'closed' and r.start_at<=now() then r.round end,
    'players',coalesce((select jsonb_agg(jsonb_build_object('id',p.user_id,'ready',p.ready,'nickname',u.nickname,'team',u.team,'region',u.region,'staff_role',u.staff_role) order by p.joined_at,p.user_id)
      from private.ladder_players p join public.profiles u on u.id=p.user_id where p.room_id=r.id),'[]'::jsonb))
  from private.ladder_rooms r where r.id=p_room;
$$;
create function public.update_ladder_settings(p_room uuid,p_capacity integer,p_losers integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); room private.ladder_rooms; chosen_outcomes jsonb;
begin
  if not private.member_approved(actor) then raise exception 'Approved member required';end if;
  if p_capacity is null or p_capacity not between 2 and 12 or p_losers is null or p_losers not between 1 and p_capacity-1 then raise exception 'Invalid room values';end if;
  select * into room from private.ladder_rooms where id=p_room for update;
  if not found then raise exception 'Room not found';end if;
  if room.host_id<>actor then raise exception 'Host required';end if;
  perform private.ladder_prune(p_room);
  select * into room from private.ladder_rooms where id=p_room;
  if room.phase<>'waiting' then raise exception 'Room already starting';end if;
  if (select count(*) from private.ladder_players where room_id=p_room)>p_capacity then raise exception 'Capacity below participants';end if;
  select jsonb_agg(case when i<=p_losers then '꽝' else '통과' end order by i) into chosen_outcomes from generate_series(1,p_capacity) i;
  update private.ladder_rooms set capacity=p_capacity,outcomes=chosen_outcomes,round=null,start_at=null,finish_at=null,revision=revision+1 where id=p_room;
  update private.ladder_players set ready=false where room_id=p_room;
  return private.ladder_snapshot(p_room);
end; $$;
revoke all on function public.create_ladder_room(integer,integer),public.update_ladder_settings(uuid,integer,integer) from public,anon;
grant execute on function public.create_ladder_room(integer,integer),public.update_ladder_settings(uuid,integer,integer) to authenticated;
commit;
