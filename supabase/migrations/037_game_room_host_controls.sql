-- Apply after 036. Host removal, coffee stakes and ready-state exit protection.

begin;

alter table private.ladder_rooms add column bet_type text not null default 'none' check(bet_type in ('none','starbucks','mgc','compose'));

create or replace function private.ladder_snapshot(p_room uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('bet_type',r.bet_type,'id',r.id,'code',r.code,'title',r.title,'capacity',r.capacity,'losers',(select count(*) from jsonb_array_elements_text(r.outcomes) e where e='꽝'),'host_id',r.host_id,'revision',r.revision,'server_time',now(),
    'phase',case when r.phase='closed' then 'closed' when r.finish_at<=now() then 'finished' when r.start_at<=now() then 'running' else r.phase end,
    'start_at',r.start_at,'finish_at',r.finish_at,'round',case when r.phase<>'closed' and r.start_at<=now() then r.round end,
    'players',coalesce((select jsonb_agg(jsonb_build_object('id',p.user_id,'ready',p.ready,'nickname',u.nickname,'team',u.team,'region',u.region,'staff_role',u.staff_role) order by p.joined_at,p.user_id)
      from private.ladder_players p join public.profiles u on u.id=p.user_id where p.room_id=r.id),'[]'::jsonb))
  from private.ladder_rooms r where r.id=p_room;
$$;

create or replace function public.list_ladder_rooms() returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
  if not private.member_approved((select auth.uid())) then raise exception 'Approved member required';end if;
  select coalesce(jsonb_agg(jsonb_build_object('bet_type',r.bet_type,'code',r.code,'title',r.title,'capacity',r.capacity,'host',u.nickname,'count',(select count(*) from private.ladder_players where room_id=r.id)) order by r.created_at desc),'[]'::jsonb)
    into result from (select * from private.ladder_rooms where phase='waiting' and created_at>now()-interval '24 hours' and exists(select 1 from private.ladder_players where room_id=id and user_id=host_id and last_seen>now()-interval '45 seconds') order by created_at desc limit 30) r
    join public.profiles u on u.id=r.host_id;
  return result;
end; $$;

create function public.create_ladder_room(p_capacity integer,p_losers integer,p_bet text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare room jsonb;begin
 if p_bet is null or p_bet not in ('none','starbucks','mgc','compose') then raise exception 'Invalid bet';end if;
 room:=public.create_ladder_room(p_capacity,p_losers);
 update private.ladder_rooms set bet_type=p_bet where id=(room->>'id')::uuid;
 return private.ladder_snapshot((room->>'id')::uuid);
end;$$;

create function public.update_ladder_settings(p_room uuid,p_capacity integer,p_losers integer,p_bet text) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if p_bet is null or p_bet not in ('none','starbucks','mgc','compose') then raise exception 'Invalid bet';end if;
 perform public.update_ladder_settings(p_room,p_capacity,p_losers);
 update private.ladder_rooms set bet_type=p_bet where id=p_room;
 return private.ladder_snapshot(p_room);
end;$$;

create function public.kick_ladder_player(p_room uuid,p_user uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); room private.ladder_rooms;begin
 if not private.member_approved(actor) then raise exception 'Approved member required';end if;
 select * into room from private.ladder_rooms where id=p_room for update;
 if not found then raise exception 'Room not found';end if;
 if room.host_id<>actor or not exists(select 1 from private.ladder_players where room_id=p_room and user_id=actor) then raise exception 'Host required';end if;
 if p_user is null or p_user=actor then raise exception 'Invalid kick target';end if;
 if room.phase='closed' or (room.start_at is not null and room.start_at<=now()) then raise exception 'Game already starting';end if;
 delete from private.ladder_players where room_id=p_room and user_id=p_user;
 if not found then raise exception 'Player not found';end if;
 -- This removes one seat only. No blacklist or membership restriction is created.
 update private.ladder_players set ready=false where room_id=p_room;
 update private.ladder_rooms set phase='waiting',round=null,start_at=null,finish_at=null,revision=revision+1 where id=p_room;
 return private.ladder_snapshot(p_room);
end;$$;

create or replace function public.leave_ladder_room(p_room uuid) returns void
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); room private.ladder_rooms;
begin
  if actor is null then raise exception 'Login required';end if;
  select * into room from private.ladder_rooms where id=p_room for update;
  if not found then return;end if;
  if not exists(select 1 from private.ladder_players where room_id=p_room and user_id=actor) then return;end if;
  if room.phase<>'closed' and (room.finish_at is null or room.finish_at>now()) then
    if room.start_at is not null and room.start_at<=now() then raise exception 'Game already starting';end if;
    if exists(select 1 from private.ladder_players where room_id=p_room and user_id=actor and ready) then raise exception 'Cancel readiness before leaving';end if;
  end if;
  delete from private.ladder_players where room_id=p_room and user_id=actor;
  if actor=room.host_id then update private.ladder_rooms set phase='closed',revision=revision+1 where id=p_room;
  elsif room.start_at is null or room.start_at>now() then
    update private.ladder_players set ready=false where room_id=p_room;
    update private.ladder_rooms set phase='waiting',round=null,start_at=null,finish_at=null,revision=revision+1 where id=p_room;
  end if;
end; $$;

alter table private.marble_rooms add column bet_type text not null default 'none' check(bet_type in ('none','starbucks','mgc','compose'));

create or replace function private.marble_snapshot(p_room uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('bet_type',r.bet_type,'map_index',r.map_index,'map_name',(array['운명의 수레바퀴','버블 팝','욕망의 항아리','밤을 달리다'])[r.map_index+1],'playback_version',coalesce((r.round->>'playback_version')::integer,1),'playback_duration_ms',(r.round->>'duration_ms')::integer,'id',r.id,'code',r.code,'title',r.title,'capacity',r.capacity,'losers',(select count(*) from jsonb_array_elements_text(r.outcomes) e where e='꽝'),'host_id',r.host_id,'revision',r.revision,'server_time',now(),
    'phase',case when r.phase='closed' then 'closed' when r.finish_at<=now() then 'finished' when r.start_at<=now() then 'running' else r.phase end,
    'start_at',r.start_at,'finish_at',r.finish_at,'simulation_seed',case when r.phase<>'closed' then r.round->'seed' end,'round',case when r.phase<>'closed' and r.start_at<=now() then r.round end,
    'players',coalesce((select jsonb_agg(jsonb_build_object('id',p.user_id,'ready',p.ready,'nickname',u.nickname,'team',u.team,'region',u.region,'staff_role',u.staff_role) order by p.joined_at,p.user_id)
      from private.marble_players p join public.profiles u on u.id=p.user_id where p.room_id=r.id),'[]'::jsonb))
  from private.marble_rooms r where r.id=p_room;
$$;

create or replace function public.list_marble_rooms() returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
  if not private.member_approved((select auth.uid())) then raise exception 'Approved member required';end if;
  select coalesce(jsonb_agg(jsonb_build_object('map_index',r.map_index,'map_name',(array['운명의 수레바퀴','버블 팝','욕망의 항아리','밤을 달리다'])[r.map_index+1],'bet_type',r.bet_type,'code',r.code,'title',r.title,'capacity',r.capacity,'host',u.nickname,'count',(select count(*) from private.marble_players where room_id=r.id)) order by r.created_at desc),'[]'::jsonb)
    into result from (select * from private.marble_rooms where phase='waiting' and created_at>now()-interval '24 hours' and exists(select 1 from private.marble_players where room_id=id and user_id=host_id and last_seen>now()-interval '45 seconds') order by created_at desc limit 30) r
    join public.profiles u on u.id=r.host_id;
  return result;
end; $$;

create function public.create_marble_room(p_capacity integer,p_losers integer,p_map integer,p_bet text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare room jsonb;begin
 if p_bet is null or p_bet not in ('none','starbucks','mgc','compose') then raise exception 'Invalid bet';end if;
 room:=public.create_marble_room(p_capacity,p_losers,p_map);
 update private.marble_rooms set bet_type=p_bet where id=(room->>'id')::uuid;
 return private.marble_snapshot((room->>'id')::uuid);
end;$$;

create function public.update_marble_settings(p_room uuid,p_capacity integer,p_losers integer,p_map integer,p_bet text) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if p_bet is null or p_bet not in ('none','starbucks','mgc','compose') then raise exception 'Invalid bet';end if;
 perform public.update_marble_settings(p_room,p_capacity,p_losers,p_map);
 update private.marble_rooms set bet_type=p_bet where id=p_room;
 return private.marble_snapshot(p_room);
end;$$;

create function public.kick_marble_player(p_room uuid,p_user uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); room private.marble_rooms;begin
 if not private.member_approved(actor) then raise exception 'Approved member required';end if;
 select * into room from private.marble_rooms where id=p_room for update;
 if not found then raise exception 'Room not found';end if;
 if room.host_id<>actor or not exists(select 1 from private.marble_players where room_id=p_room and user_id=actor) then raise exception 'Host required';end if;
 if p_user is null or p_user=actor then raise exception 'Invalid kick target';end if;
 if room.phase='closed' or (room.start_at is not null and room.start_at<=now()) then raise exception 'Game already starting';end if;
 delete from private.marble_players where room_id=p_room and user_id=p_user;
 if not found then raise exception 'Player not found';end if;
 -- This removes one seat only. No blacklist or membership restriction is created.
 update private.marble_players set ready=false where room_id=p_room;
 update private.marble_rooms set phase='waiting',round=null,start_at=null,finish_at=null,revision=revision+1 where id=p_room;
 return private.marble_snapshot(p_room);
end;$$;

create or replace function public.leave_marble_room(p_room uuid) returns void
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); room private.marble_rooms;
begin
  if actor is null then raise exception 'Login required';end if;
  select * into room from private.marble_rooms where id=p_room for update;
  if not found then return;end if;
  if not exists(select 1 from private.marble_players where room_id=p_room and user_id=actor) then return;end if;
  if room.phase<>'closed' and (room.finish_at is null or room.finish_at>now()) then
    if room.start_at is not null and room.start_at<=now() then raise exception 'Game already starting';end if;
    if exists(select 1 from private.marble_players where room_id=p_room and user_id=actor and ready) then raise exception 'Cancel readiness before leaving';end if;
  end if;
  delete from private.marble_players where room_id=p_room and user_id=actor;
  if actor=room.host_id then update private.marble_rooms set phase='closed',revision=revision+1 where id=p_room;
  elsif room.start_at is null or room.start_at>now() then
    update private.marble_players set ready=false where room_id=p_room;
    update private.marble_rooms set phase='waiting',round=null,start_at=null,finish_at=null,revision=revision+1 where id=p_room;
  end if;
end; $$;

revoke all on function public.create_ladder_room(integer,integer,text),public.update_ladder_settings(uuid,integer,integer,text),public.kick_ladder_player(uuid,uuid),public.create_marble_room(integer,integer,integer,text),public.update_marble_settings(uuid,integer,integer,integer,text),public.kick_marble_player(uuid,uuid) from public,anon,authenticated;

grant execute on function public.create_ladder_room(integer,integer,text),public.update_ladder_settings(uuid,integer,integer,text),public.kick_ladder_player(uuid,uuid),public.create_marble_room(integer,integer,integer,text),public.update_marble_settings(uuid,integer,integer,integer,text),public.kick_marble_player(uuid,uuid) to authenticated;

commit;
