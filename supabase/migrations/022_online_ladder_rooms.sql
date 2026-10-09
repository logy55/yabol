-- Apply after 021. Server-owned rooms, readiness, shared draw and server timestamps.
-- Ladder construction adapts Whozzie (MIT, copyright 2025 zeikar); see THIRD-PARTY-NOTICES.md.
begin;
create table private.ladder_rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  host_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check(char_length(title) between 1 and 60),
  capacity integer not null check(capacity between 2 and 12),
  outcomes jsonb not null,
  phase text not null default 'waiting' check(phase in ('waiting','countdown','closed')),
  round jsonb,
  start_at timestamptz,
  finish_at timestamptz,
  revision bigint not null default 1,
  created_at timestamptz not null default now());
create table private.ladder_players (
  room_id uuid not null references private.ladder_rooms(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  ready boolean not null default false,
  joined_at timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  primary key(room_id,user_id));
alter table private.ladder_rooms enable row level security;
alter table private.ladder_players enable row level security;
revoke all on private.ladder_rooms,private.ladder_players from public,anon,authenticated;

create function private.ladder_random_index(p_max integer) returns integer
language plpgsql volatile set search_path='' as $$
declare number bigint; ceiling bigint;
begin
  if p_max<1 then raise exception 'Invalid random range'; end if;
  ceiling:=4294967296-mod(4294967296,p_max);
  loop
    number:=('x'||substr(replace(gen_random_uuid()::text,'-',''),1,8))::bit(32)::bigint;
    exit when number<ceiling;
  end loop;
  return mod(number,p_max)::integer;
end; $$;

create function private.ladder_draw(p_players jsonb,p_outcomes jsonb) returns jsonb
language plpgsql volatile set search_path='' as $$
declare n integer:=jsonb_array_length(p_players); rows integer; rungs boolean[][]; available integer[];
  seats integer[]; slots integer[]; row_id integer; gap integer; i integer; j integer; temp integer;
  rung_json jsonb:='[]'; lane_json jsonb:='[]';
begin
  rows:=greatest(8,n*2);rungs:=array_fill(false,array[rows,n-1]);
  for gap in 1..n-1 loop
    available:=array[]::integer[];
    for row_id in 1..rows loop
      if not coalesce(rungs[row_id][gap-1],false) and not coalesce(rungs[row_id][gap+1],false) then available:=array_append(available,row_id);end if;
    end loop;
    rungs[available[private.ladder_random_index(cardinality(available))+1]][gap]:=true;
  end loop;
  for row_id in 1..rows loop
    for gap in 1..n-1 loop
      if not rungs[row_id][gap] and not coalesce(rungs[row_id][gap-1],false) and not coalesce(rungs[row_id][gap+1],false)
        and not coalesce(rungs[row_id-1][gap],false) and not coalesce(rungs[row_id+1][gap],false)
        and private.ladder_random_index(1000)<least(550,5000/rows) then rungs[row_id][gap]:=true;end if;
    end loop;
    rung_json:=rung_json||jsonb_build_array(to_jsonb(rungs[row_id:row_id]));
  end loop;
  -- PostgreSQL multidimensional slices retain their outer dimension; flatten each row.
  rung_json:='[]';
  for row_id in 1..rows loop
    select rung_json||jsonb_build_array(jsonb_agg(to_jsonb(rungs[row_id][k]) order by k)) into rung_json from generate_series(1,n-1) k;
  end loop;
  seats:=array(select generate_series(0,n-1));slots:=seats;
  for i in reverse n..2 loop
    j:=private.ladder_random_index(i)+1;temp:=seats[i];seats[i]:=seats[j];seats[j]:=temp;
    j:=private.ladder_random_index(i)+1;temp:=slots[i];slots[i]:=slots[j];slots[j]:=temp;
  end loop;
  for i in 1..n loop lane_json:=lane_json||jsonb_build_array(jsonb_build_object('player',seats[i]));end loop;
  return jsonb_build_object('ladder',jsonb_build_object('columns',n,'rows',rows,'rungs',rung_json),'seats',to_jsonb(seats),'slots',to_jsonb(slots),'players',p_players,'outcomes',p_outcomes);
end; $$;

create function private.ladder_prune(p_room uuid) returns void
language plpgsql security definer set search_path='' as $$
declare room private.ladder_rooms; removed integer;
begin
  select * into room from private.ladder_rooms where id=p_room for update;
  if not found or room.phase='closed' or (room.start_at is not null and room.start_at<=now()) then return;end if;
  delete from private.ladder_players where room_id=p_room and (last_seen<now()-interval '45 seconds' or not private.member_approved(user_id));
  get diagnostics removed=row_count;
  if removed>0 then
    update private.ladder_players set ready=false where room_id=p_room;
    update private.ladder_rooms set phase=case when exists(select 1 from private.ladder_players where room_id=p_room and user_id=room.host_id) then 'waiting' else 'closed' end,
      start_at=null,finish_at=null,round=null,revision=revision+1 where id=p_room;
  end if;
end; $$;

create function private.ladder_snapshot(p_room uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('id',r.id,'code',r.code,'title',r.title,'capacity',r.capacity,'host_id',r.host_id,'revision',r.revision,'server_time',now(),
    'phase',case when r.phase='closed' then 'closed' when r.finish_at<=now() then 'finished' when r.start_at<=now() then 'running' else r.phase end,
    'start_at',r.start_at,'finish_at',r.finish_at,'round',case when r.phase<>'closed' and r.start_at<=now() then r.round end,
    'players',coalesce((select jsonb_agg(jsonb_build_object('id',p.user_id,'ready',p.ready,'nickname',u.nickname,'team',u.team,'region',u.region,'staff_role',u.staff_role) order by p.joined_at,p.user_id)
      from private.ladder_players p join public.profiles u on u.id=p.user_id where p.room_id=r.id),'[]'::jsonb))
  from private.ladder_rooms r where r.id=p_room;
$$;

create function public.list_ladder_rooms() returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
  if not private.member_approved((select auth.uid())) then raise exception 'Approved member required';end if;
  select coalesce(jsonb_agg(jsonb_build_object('code',r.code,'title',r.title,'capacity',r.capacity,'host',u.nickname,'count',(select count(*) from private.ladder_players where room_id=r.id)) order by r.created_at desc),'[]'::jsonb)
    into result from (select * from private.ladder_rooms where phase='waiting' and created_at>now()-interval '24 hours' and exists(select 1 from private.ladder_players where room_id=id and user_id=host_id and last_seen>now()-interval '45 seconds') order by created_at desc limit 30) r
    join public.profiles u on u.id=r.host_id;
  return result;
end; $$;

create function public.create_ladder_room(p_title text,p_outcomes jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); room private.ladder_rooms; n integer;
begin
  if not private.member_approved(actor) then raise exception 'Approved member required';end if;
  if p_title is null or char_length(trim(p_title)) not between 1 and 60 or jsonb_typeof(p_outcomes) is distinct from 'array' then raise exception 'Invalid room values';end if;
  n:=jsonb_array_length(p_outcomes);
  if n not between 2 and 12 or exists(select 1 from jsonb_array_elements(p_outcomes) e where jsonb_typeof(e)<>'string' or char_length(trim(e#>>'{}')) not between 1 and 30) then raise exception 'Invalid room values';end if;
  perform pg_advisory_xact_lock(hashtextextended('ladder-create:'||actor::text,0));
  if (select count(*) from private.ladder_rooms where host_id=actor and created_at>now()-interval '1 hour')>=10 then raise exception 'Room limit exceeded';end if;
  loop
    begin
      insert into private.ladder_rooms(code,host_id,title,capacity,outcomes) values(upper(substr(replace(gen_random_uuid()::text,'-',''),1,6)),actor,trim(p_title),n,p_outcomes) returning * into room;
      exit;
    exception when unique_violation then null;end;
  end loop;
  insert into private.ladder_players(room_id,user_id) values(room.id,actor);
  return private.ladder_snapshot(room.id);
end; $$;

create function public.join_ladder_room(p_code text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); room private.ladder_rooms;
begin
  if not private.member_approved(actor) then raise exception 'Approved member required';end if;
  select * into room from private.ladder_rooms where code=upper(trim(p_code)) for update;
  if not found or room.created_at<now()-interval '24 hours' then raise exception 'Room not found';end if;
  perform private.ladder_prune(room.id);
  select * into room from private.ladder_rooms where id=room.id;
  if room.phase='closed' then raise exception 'Room closed';end if;
  if exists(select 1 from private.ladder_players where room_id=room.id and user_id=actor) then
    update private.ladder_players set last_seen=now() where room_id=room.id and user_id=actor;
    return private.ladder_snapshot(room.id);
  end if;
  if room.phase<>'waiting' then raise exception 'Game already starting';end if;
  if (select count(*) from private.ladder_players where room_id=room.id)>=room.capacity then raise exception 'Room full';end if;
  insert into private.ladder_players(room_id,user_id) values(room.id,actor);
  update private.ladder_rooms set revision=revision+1 where id=room.id;
  return private.ladder_snapshot(room.id);
end; $$;

create function public.get_ladder_room(p_room uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  if not private.member_approved((select auth.uid())) then raise exception 'Approved member required';end if;
  perform 1 from private.ladder_rooms where id=p_room for update;
  if not found then raise exception 'Room not found';end if;
  update private.ladder_players set last_seen=now() where room_id=p_room and user_id=(select auth.uid());
  if not found then raise exception 'Room membership required';end if;
  perform private.ladder_prune(p_room);
  return private.ladder_snapshot(p_room);
end; $$;

create function public.set_ladder_ready(p_room uuid,p_ready boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); room private.ladder_rooms; people jsonb;
begin
  if not private.member_approved(actor) then raise exception 'Approved member required';end if;
  if p_ready is null then raise exception 'Invalid readiness';end if;
  select * into room from private.ladder_rooms where id=p_room for update;
  if not found then raise exception 'Room not found';end if;
  update private.ladder_players set last_seen=now() where room_id=p_room and user_id=actor;
  if not found then raise exception 'Room membership required';end if;
  perform private.ladder_prune(p_room);
  select * into room from private.ladder_rooms where id=p_room;
  if room.phase='closed' or (room.start_at is not null and room.start_at<=now()) then raise exception 'Game already starting';end if;
  update private.ladder_players set ready=p_ready where room_id=p_room and user_id=actor;
  if not p_ready then
    update private.ladder_rooms set phase='waiting',round=null,start_at=null,finish_at=null,revision=revision+1 where id=p_room;
  elsif room.phase='waiting' and (select count(*) from private.ladder_players where room_id=p_room)=room.capacity
    and not exists(select 1 from private.ladder_players where room_id=p_room and not ready) then
    select jsonb_agg(jsonb_build_object('id',p.user_id,'name',u.nickname) order by p.joined_at,p.user_id) into people from private.ladder_players p join public.profiles u on u.id=p.user_id where p.room_id=p_room;
    update private.ladder_rooms set phase='countdown',round=private.ladder_draw(people,outcomes),start_at=now()+interval '5 seconds',finish_at=now()+interval '5 seconds'+room.capacity*interval '4 seconds',revision=revision+1 where id=p_room;
  else update private.ladder_rooms set revision=revision+1 where id=p_room;end if;
  return private.ladder_snapshot(p_room);
end; $$;

create function public.leave_ladder_room(p_room uuid) returns void
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); room private.ladder_rooms;
begin
  if actor is null then raise exception 'Login required';end if;
  select * into room from private.ladder_rooms where id=p_room for update;
  if not found then return;end if;
  if not exists(select 1 from private.ladder_players where room_id=p_room and user_id=actor) then return;end if;
  delete from private.ladder_players where room_id=p_room and user_id=actor;
  if actor=room.host_id then update private.ladder_rooms set phase='closed',revision=revision+1 where id=p_room;
  elsif room.start_at is null or room.start_at>now() then
    update private.ladder_players set ready=false where room_id=p_room;
    update private.ladder_rooms set phase='waiting',round=null,start_at=null,finish_at=null,revision=revision+1 where id=p_room;
  end if;
end; $$;

revoke all on function private.ladder_random_index(integer),private.ladder_draw(jsonb,jsonb),private.ladder_prune(uuid),private.ladder_snapshot(uuid) from public,anon,authenticated;
revoke all on function public.list_ladder_rooms(),public.create_ladder_room(text,jsonb),public.join_ladder_room(text),public.get_ladder_room(uuid),public.set_ladder_ready(uuid,boolean),public.leave_ladder_room(uuid) from public,anon,authenticated;
grant execute on function public.list_ladder_rooms(),public.create_ladder_room(text,jsonb),public.join_ladder_room(text),public.get_ladder_room(uuid),public.set_ladder_ready(uuid,boolean),public.leave_ladder_room(uuid) to authenticated;
commit;
