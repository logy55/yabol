-- Apply after 034. Original maps and natural simulation timing; existing ladder rooms are unchanged.
begin;
alter table private.marble_rooms add column map_index integer not null default 0 check(map_index between 0 and 3);
create or replace function private.marble_snapshot(p_room uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('map_index',r.map_index,'map_name',(array['운명의 수레바퀴','BubblePop','Pot of greed','Yoru ni Kakeru'])[r.map_index+1],'playback_version',coalesce((r.round->>'playback_version')::integer,1),'playback_duration_ms',(r.round->>'duration_ms')::integer,'id',r.id,'code',r.code,'title',r.title,'capacity',r.capacity,'losers',(select count(*) from jsonb_array_elements_text(r.outcomes) e where e='꽝'),'host_id',r.host_id,'revision',r.revision,'server_time',now(),
    'phase',case when r.phase='closed' then 'closed' when r.finish_at<=now() then 'finished' when r.start_at<=now() then 'running' else r.phase end,
    'start_at',r.start_at,'finish_at',r.finish_at,'simulation_seed',case when r.phase<>'closed' then r.round->'seed' end,'round',case when r.phase<>'closed' and r.start_at<=now() then r.round end,
    'players',coalesce((select jsonb_agg(jsonb_build_object('id',p.user_id,'ready',p.ready,'nickname',u.nickname,'team',u.team,'region',u.region,'staff_role',u.staff_role) order by p.joined_at,p.user_id)
      from private.marble_players p join public.profiles u on u.id=p.user_id where p.room_id=r.id),'[]'::jsonb))
  from private.marble_rooms r where r.id=p_room;
$$;
create or replace function public.set_marble_ready(p_room uuid,p_ready boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); room private.marble_rooms; people jsonb;
begin
  if not private.member_approved(actor) then raise exception 'Approved member required';end if;
  if p_ready is null then raise exception 'Invalid readiness';end if;
  select * into room from private.marble_rooms where id=p_room for update;
  if not found then raise exception 'Room not found';end if;
  update private.marble_players set last_seen=now() where room_id=p_room and user_id=actor;
  if not found then raise exception 'Room membership required';end if;
  perform private.marble_prune(p_room);
  select * into room from private.marble_rooms where id=p_room;
  if room.phase='closed' or (room.start_at is not null and room.start_at<=now()) then raise exception 'Game already starting';end if;
  update private.marble_players set ready=p_ready where room_id=p_room and user_id=actor;
  if not p_ready then
    update private.marble_rooms set phase='waiting',round=null,start_at=null,finish_at=null,revision=revision+1 where id=p_room;
  elsif room.phase='waiting' and (select count(*) from private.marble_players where room_id=p_room)=room.capacity
    and not exists(select 1 from private.marble_players where room_id=p_room and not ready) then
    select jsonb_agg(jsonb_build_object('id',p.user_id,'name',u.nickname) order by p.joined_at,p.user_id) into people from private.marble_players p join public.profiles u on u.id=p.user_id where p.room_id=p_room;
    update private.marble_rooms set phase='countdown',round=private.marble_draw(people,outcomes)||jsonb_build_object('playback_version',2),start_at=now()+interval '5 seconds',finish_at=now()+interval '305 seconds',revision=revision+1 where id=p_room;
  else update private.marble_rooms set revision=revision+1 where id=p_room;end if;
  return private.marble_snapshot(p_room);
end; $$;


create function public.create_marble_room(p_capacity integer,p_losers integer,p_map integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare room jsonb;begin
 if p_map is null or p_map not between 0 and 3 then raise exception 'Invalid map';end if;
 room:=public.create_marble_room(p_capacity,p_losers);
 update private.marble_rooms set map_index=p_map where id=(room->>'id')::uuid;
 return private.marble_snapshot((room->>'id')::uuid);
end;$$;
create function public.update_marble_settings(p_room uuid,p_capacity integer,p_losers integer,p_map integer) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if p_map is null or p_map not between 0 and 3 then raise exception 'Invalid map';end if;
 perform public.update_marble_settings(p_room,p_capacity,p_losers);
 update private.marble_rooms set map_index=p_map where id=p_room;
 return private.marble_snapshot(p_room);
end;$$;
create function public.report_marble_duration(p_room uuid,p_seed integer,p_duration_ms integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare room private.marble_rooms; actor uuid:=(select auth.uid());begin
 if not private.member_approved(actor) then raise exception 'Approved member required';end if;
 select * into room from private.marble_rooms where id=p_room for update;
 if not found then raise exception 'Room not found';end if;
 if room.host_id<>actor then raise exception 'Host required';end if;
 if p_duration_ms is null or p_duration_ms not between 10000 and 300000 then raise exception 'Invalid playback duration';end if;
 if room.phase<>'countdown' or room.round->>'playback_version' is distinct from '2' or (room.round->>'seed')::integer is distinct from p_seed then raise exception 'Round changed';end if;
 if room.round->>'duration_ms' is null then
  update private.marble_rooms set round=jsonb_set(round,'{duration_ms}',to_jsonb(p_duration_ms)),finish_at=start_at+make_interval(secs=>p_duration_ms/1000.0),revision=revision+1 where id=p_room;
 end if;
 return private.marble_snapshot(p_room);
end;$$;
revoke all on function public.create_marble_room(integer,integer,integer),public.update_marble_settings(uuid,integer,integer,integer),public.report_marble_duration(uuid,integer,integer) from public,anon,authenticated;
grant execute on function public.create_marble_room(integer,integer,integer),public.update_marble_settings(uuid,integer,integer,integer),public.report_marble_duration(uuid,integer,integer) to authenticated;
commit;
