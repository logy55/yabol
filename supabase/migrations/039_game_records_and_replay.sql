-- Apply after 038. Exactly-once game records and host-controlled rematches.

begin;

create table private.game_results (
 game text not null check(game in ('ladder','marble')),
 room_id uuid not null,
 round_number bigint not null check(round_number>0),
 user_id uuid not null references auth.users(id) on delete cascade,
 is_loss boolean not null,
 finished_at timestamptz not null,
 primary key(game,room_id,round_number,user_id));
create index game_results_by_member on private.game_results(user_id,game,is_loss);
alter table private.game_results enable row level security;
revoke all on private.game_results from public,anon,authenticated;
-- Existing rounds are not presented as a complete historical record.
alter table private.ladder_rooms add column round_number bigint not null default 1 check(round_number>0),add column records_enabled boolean not null default false;
alter table private.marble_rooms add column round_number bigint not null default 1 check(round_number>0),add column records_enabled boolean not null default false;
alter table private.ladder_rooms alter column records_enabled set default true;
alter table private.marble_rooms alter column records_enabled set default true;

create function private.game_loss_indexes(p_game text,p_round jsonb) returns integer[]
language plpgsql immutable set search_path='' as $$
declare n integer:=jsonb_array_length(p_round->'players');losses integer[]:='{}';seat integer;lane integer;row_id integer;rung jsonb;player_index integer;losers integer;
begin
 if n<2 then return losses;end if;
 if p_game='ladder' then
  for seat in 0..n-1 loop
   lane:=seat;
   for row_id in 0..jsonb_array_length(p_round->'ladder'->'rungs')-1 loop
    rung:=p_round->'ladder'->'rungs'->row_id;
    if lane<n-1 and coalesce((rung->>lane)::boolean,false) then lane:=lane+1;
    elsif lane>0 and coalesce((rung->>(lane-1))::boolean,false) then lane:=lane-1;end if;
   end loop;
   if p_round->'outcomes'->>((p_round->'slots'->>lane)::integer)='꽝' then losses:=array_append(losses,(p_round->'seats'->>seat)::integer);end if;
  end loop;
 elsif p_game='marble' then
  select count(*) into losers from jsonb_array_elements_text(p_round->'outcomes') e where e='꽝';
  for seat in n-losers..n-1 loop losses:=array_append(losses,(p_round->'ranking'->>seat)::integer);end loop;
 else raise exception 'Invalid game';end if;
 return losses;
end;$$;

create function private.record_completed_game(p_game text,p_room uuid) returns void
language plpgsql security definer set search_path='' as $$
declare r record;losses integer[];i integer;person uuid;
begin
 if p_game not in ('ladder','marble') or p_game is null then raise exception 'Invalid game';end if;
 execute format('select phase,round,start_at,finish_at,round_number,records_enabled from private.%I where id=$1 for update',p_game||'_rooms') into r using p_room;
 if r is null or not r.records_enabled or r.phase<>'countdown' or r.round is null or r.start_at is null or r.finish_at is null or r.finish_at>now() or r.finish_at<=r.start_at then return;end if;
 losses:=private.game_loss_indexes(p_game,r.round);
 for i in 0..jsonb_array_length(r.round->'players')-1 loop
  person:=(r.round->'players'->i->>'id')::uuid;
  if exists(select 1 from auth.users where id=person) then
   insert into private.game_results(game,room_id,round_number,user_id,is_loss,finished_at)
   values(p_game,p_room,r.round_number,person,i=any(losses),r.finish_at) on conflict do nothing;
  end if;
 end loop;
end;$$;

create function private.preserve_game_round() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if old.records_enabled and old.phase='countdown' and old.round is not null and old.finish_at<=now() then
  perform private.record_completed_game(tg_argv[0],old.id);
 end if;
 if new.start_at is not null and new.start_at is distinct from old.start_at then new.records_enabled:=true;end if;
 return new;
end;$$;
create trigger ladder_round_records before update on private.ladder_rooms for each row execute function private.preserve_game_round('ladder');
create trigger marble_round_records before update on private.marble_rooms for each row execute function private.preserve_game_round('marble');

create function public.get_my_game_records() returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid());r record;result jsonb;
begin
 if not private.member_approved(actor) then raise exception 'Approved member required';end if;
 -- Also settle completed rounds when every player has already closed the page.
 for r in select id from private.ladder_rooms g where records_enabled and phase='countdown' and finish_at<=now() and round->'players' @> jsonb_build_array(jsonb_build_object('id',actor))
  and not exists(select 1 from private.game_results s where s.game='ladder' and s.room_id=g.id and s.round_number=g.round_number and s.user_id=actor) order by id
 loop perform private.record_completed_game('ladder',r.id);end loop;
 for r in select id from private.marble_rooms g where records_enabled and phase='countdown' and finish_at<=now() and round->'players' @> jsonb_build_array(jsonb_build_object('id',actor))
  and not exists(select 1 from private.game_results s where s.game='marble' and s.room_id=g.id and s.round_number=g.round_number and s.user_id=actor) order by id
 loop perform private.record_completed_game('marble',r.id);end loop;
 select jsonb_build_object(
 'ladder',jsonb_build_object('wins',count(*) filter(where game='ladder' and not is_loss),'losses',count(*) filter(where game='ladder' and is_loss)),
 'marble',jsonb_build_object('wins',count(*) filter(where game='marble' and not is_loss),'losses',count(*) filter(where game='marble' and is_loss)))
 into result from private.game_results where user_id=actor;
 return result;
end;$$;

create or replace function private.ladder_snapshot(p_room uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('round_number',r.round_number,'bet_type',r.bet_type,'id',r.id,'code',r.code,'title',r.title,'capacity',r.capacity,'losers',(select count(*) from jsonb_array_elements_text(r.outcomes) e where e='꽝'),'host_id',r.host_id,'revision',r.revision,'server_time',now(),
    'phase',case when r.phase='closed' then 'closed' when r.finish_at<=now() then 'finished' when r.start_at<=now() then 'running' else r.phase end,
    'start_at',r.start_at,'finish_at',r.finish_at,'round',case when r.phase<>'closed' and r.start_at<=now() then r.round end,
    'players',coalesce((select jsonb_agg(jsonb_build_object('id',p.user_id,'ready',p.ready,'nickname',u.nickname,'team',u.team,'region',u.region,'staff_role',u.staff_role) order by p.joined_at,p.user_id)
      from private.ladder_players p join public.profiles u on u.id=p.user_id where p.room_id=r.id),'[]'::jsonb))
  from private.ladder_rooms r where r.id=p_room;
$$;

create or replace function public.get_ladder_room(p_room uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  if not private.member_approved((select auth.uid())) then raise exception 'Approved member required';end if;
  perform 1 from private.ladder_rooms where id=p_room for update;
  if not found then raise exception 'Room not found';end if;
  update private.ladder_players set last_seen=now() where room_id=p_room and user_id=(select auth.uid());
  if not found then raise exception 'Room membership required';end if;
  perform private.ladder_prune(p_room);
  perform private.record_completed_game('ladder',p_room);
  return private.ladder_snapshot(p_room);
end; $$;

create function public.replay_ladder_room(p_room uuid,p_round_number bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid());r private.ladder_rooms;people integer;losers integer;chosen jsonb;
begin
 if not private.member_approved(actor) then raise exception 'Approved member required';end if;
 select * into r from private.ladder_rooms where id=p_room for update;
 if not found then raise exception 'Room not found';end if;
 if r.host_id<>actor or not exists(select 1 from private.ladder_players where room_id=p_room and user_id=actor) then raise exception 'Host required';end if;
 if p_round_number is distinct from r.round_number then raise exception 'Round changed';end if;
 if r.phase<>'countdown' or r.finish_at is null or r.finish_at>now() or r.round is null then raise exception 'Game not finished';end if;
 select count(*) into people from private.ladder_players where room_id=p_room;
 if people<2 then raise exception 'Two players required';end if;
 perform private.record_completed_game('ladder',p_room);
 select least(count(*)::integer,people-1) into losers from jsonb_array_elements_text(r.outcomes) e where e='꽝';
 select jsonb_agg(case when n<=losers then '꽝' else '통과' end order by n) into chosen from generate_series(1,people) n;
 update private.ladder_players set ready=false where room_id=p_room;
 update private.ladder_rooms set phase='waiting',round=null,start_at=null,finish_at=null,round_number=round_number+1,
  records_enabled=true,capacity=people,outcomes=chosen,revision=revision+1,created_at=now() where id=p_room;
 return private.ladder_snapshot(p_room);
end;$$;

create or replace function private.marble_snapshot(p_room uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('round_number',r.round_number,'bet_type',r.bet_type,'map_index',r.map_index,'map_name',(array['운명의 수레바퀴','버블 팝','욕망의 항아리','밤을 달리다'])[r.map_index+1],'playback_version',coalesce((r.round->>'playback_version')::integer,1),'playback_duration_ms',(r.round->>'duration_ms')::integer,'id',r.id,'code',r.code,'title',r.title,'capacity',r.capacity,'losers',(select count(*) from jsonb_array_elements_text(r.outcomes) e where e='꽝'),'host_id',r.host_id,'revision',r.revision,'server_time',now(),
    'phase',case when r.phase='closed' then 'closed' when r.finish_at<=now() then 'finished' when r.start_at<=now() then 'running' else r.phase end,
    'start_at',r.start_at,'finish_at',r.finish_at,'simulation_seed',case when r.phase<>'closed' then r.round->'seed' end,'round',case when r.phase<>'closed' and r.start_at<=now() then r.round end,
    'players',coalesce((select jsonb_agg(jsonb_build_object('id',p.user_id,'ready',p.ready,'nickname',u.nickname,'team',u.team,'region',u.region,'staff_role',u.staff_role) order by p.joined_at,p.user_id)
      from private.marble_players p join public.profiles u on u.id=p.user_id where p.room_id=r.id),'[]'::jsonb))
  from private.marble_rooms r where r.id=p_room;
$$;

create or replace function public.get_marble_room(p_room uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  if not private.member_approved((select auth.uid())) then raise exception 'Approved member required';end if;
  perform 1 from private.marble_rooms where id=p_room for update;
  if not found then raise exception 'Room not found';end if;
  update private.marble_players set last_seen=now() where room_id=p_room and user_id=(select auth.uid());
  if not found then raise exception 'Room membership required';end if;
  perform private.marble_prune(p_room);
  perform private.record_completed_game('marble',p_room);
  return private.marble_snapshot(p_room);
end; $$;

create function public.replay_marble_room(p_room uuid,p_round_number bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid());r private.marble_rooms;people integer;losers integer;chosen jsonb;
begin
 if not private.member_approved(actor) then raise exception 'Approved member required';end if;
 select * into r from private.marble_rooms where id=p_room for update;
 if not found then raise exception 'Room not found';end if;
 if r.host_id<>actor or not exists(select 1 from private.marble_players where room_id=p_room and user_id=actor) then raise exception 'Host required';end if;
 if p_round_number is distinct from r.round_number then raise exception 'Round changed';end if;
 if r.phase<>'countdown' or r.finish_at is null or r.finish_at>now() or r.round is null then raise exception 'Game not finished';end if;
 select count(*) into people from private.marble_players where room_id=p_room;
 if people<2 then raise exception 'Two players required';end if;
 perform private.record_completed_game('marble',p_room);
 select least(count(*)::integer,people-1) into losers from jsonb_array_elements_text(r.outcomes) e where e='꽝';
 select jsonb_agg(case when n<=losers then '꽝' else '통과' end order by n) into chosen from generate_series(1,people) n;
 update private.marble_players set ready=false where room_id=p_room;
 update private.marble_rooms set phase='waiting',round=null,start_at=null,finish_at=null,round_number=round_number+1,
  records_enabled=true,capacity=people,outcomes=chosen,revision=revision+1,created_at=now() where id=p_room;
 return private.marble_snapshot(p_room);
end;$$;

revoke all on function private.game_loss_indexes(text,jsonb),private.record_completed_game(text,uuid),private.preserve_game_round() from public,anon,authenticated;

revoke all on function public.get_my_game_records(),public.replay_ladder_room(uuid,bigint),public.replay_marble_room(uuid,bigint) from public,anon,authenticated;

grant execute on function public.get_my_game_records(),public.replay_ladder_room(uuid,bigint),public.replay_marble_room(uuid,bigint) to authenticated;

commit;
