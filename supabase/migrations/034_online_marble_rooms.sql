-- Apply after 033. Independent approved-member marble rooms with server-owned draws and a shared 30-second race.
-- Seeded original Box2D replay assigns anonymous trajectories to the canonical uniformly shuffled member ranking.
begin;
create table private.marble_rooms (
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
create table private.marble_players (
  room_id uuid not null references private.marble_rooms(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  ready boolean not null default false,
  joined_at timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  primary key(room_id,user_id));
alter table private.marble_rooms enable row level security;
alter table private.marble_players enable row level security;
revoke all on private.marble_rooms,private.marble_players from public,anon,authenticated;

create function private.marble_random_index(p_max integer) returns integer
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

create function private.marble_draw(p_players jsonb,p_outcomes jsonb) returns jsonb
language plpgsql volatile set search_path='' as $$
declare n integer:=jsonb_array_length(p_players); ranking integer[]; i integer; j integer; temp integer;
begin
  ranking:=array(select generate_series(0,n-1));
  for i in reverse n..2 loop
    j:=private.marble_random_index(i)+1;temp:=ranking[i];ranking[i]:=ranking[j];ranking[j]:=temp;
  end loop;
  return jsonb_build_object('seed',private.marble_random_index(2147483647),'ranking',to_jsonb(ranking),'players',p_players,'outcomes',p_outcomes);
end; $$;

create function private.marble_prune(p_room uuid) returns void
language plpgsql security definer set search_path='' as $$
declare room private.marble_rooms; removed integer;
begin
  select * into room from private.marble_rooms where id=p_room for update;
  if not found or room.phase='closed' or (room.start_at is not null and room.start_at<=now()) then return;end if;
  delete from private.marble_players where room_id=p_room and (last_seen<now()-interval '45 seconds' or not private.member_approved(user_id));
  get diagnostics removed=row_count;
  if removed>0 then
    update private.marble_players set ready=false where room_id=p_room;
    update private.marble_rooms set phase=case when exists(select 1 from private.marble_players where room_id=p_room and user_id=room.host_id) then 'waiting' else 'closed' end,
      start_at=null,finish_at=null,round=null,revision=revision+1 where id=p_room;
  end if;
end; $$;

create function private.marble_snapshot(p_room uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('id',r.id,'code',r.code,'title',r.title,'capacity',r.capacity,'host_id',r.host_id,'revision',r.revision,'server_time',now(),
    'phase',case when r.phase='closed' then 'closed' when r.finish_at<=now() then 'finished' when r.start_at<=now() then 'running' else r.phase end,
    'start_at',r.start_at,'finish_at',r.finish_at,'round',case when r.phase<>'closed' and r.start_at<=now() then r.round end,
    'players',coalesce((select jsonb_agg(jsonb_build_object('id',p.user_id,'ready',p.ready,'nickname',u.nickname,'team',u.team,'region',u.region,'staff_role',u.staff_role) order by p.joined_at,p.user_id)
      from private.marble_players p join public.profiles u on u.id=p.user_id where p.room_id=r.id),'[]'::jsonb))
  from private.marble_rooms r where r.id=p_room;
$$;

create function public.list_marble_rooms() returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
  if not private.member_approved((select auth.uid())) then raise exception 'Approved member required';end if;
  select coalesce(jsonb_agg(jsonb_build_object('code',r.code,'title',r.title,'capacity',r.capacity,'host',u.nickname,'count',(select count(*) from private.marble_players where room_id=r.id)) order by r.created_at desc),'[]'::jsonb)
    into result from (select * from private.marble_rooms where phase='waiting' and created_at>now()-interval '24 hours' and exists(select 1 from private.marble_players where room_id=id and user_id=host_id and last_seen>now()-interval '45 seconds') order by created_at desc limit 30) r
    join public.profiles u on u.id=r.host_id;
  return result;
end; $$;

create function public.create_marble_room(p_title text,p_outcomes jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); room private.marble_rooms; n integer;
begin
  if not private.member_approved(actor) then raise exception 'Approved member required';end if;
  if p_title is null or char_length(trim(p_title)) not between 1 and 60 or jsonb_typeof(p_outcomes) is distinct from 'array' then raise exception 'Invalid room values';end if;
  n:=jsonb_array_length(p_outcomes);
  if n not between 2 and 12 or exists(select 1 from jsonb_array_elements(p_outcomes) e where jsonb_typeof(e)<>'string' or char_length(trim(e#>>'{}')) not between 1 and 30) then raise exception 'Invalid room values';end if;
  perform pg_advisory_xact_lock(hashtextextended('marble-create:'||actor::text,0));
  if (select count(*) from private.marble_rooms where host_id=actor and created_at>now()-interval '1 hour')>=10 then raise exception 'Room limit exceeded';end if;
  loop
    begin
      insert into private.marble_rooms(code,host_id,title,capacity,outcomes) values(upper(substr(replace(gen_random_uuid()::text,'-',''),1,6)),actor,trim(p_title),n,p_outcomes) returning * into room;
      exit;
    exception when unique_violation then null;end;
  end loop;
  insert into private.marble_players(room_id,user_id) values(room.id,actor);
  return private.marble_snapshot(room.id);
end; $$;

create function public.join_marble_room(p_code text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); room private.marble_rooms;
begin
  if not private.member_approved(actor) then raise exception 'Approved member required';end if;
  select * into room from private.marble_rooms where code=upper(trim(p_code)) for update;
  if not found or room.created_at<now()-interval '24 hours' then raise exception 'Room not found';end if;
  perform private.marble_prune(room.id);
  select * into room from private.marble_rooms where id=room.id;
  if room.phase='closed' then raise exception 'Room closed';end if;
  if exists(select 1 from private.marble_players where room_id=room.id and user_id=actor) then
    update private.marble_players set last_seen=now() where room_id=room.id and user_id=actor;
    return private.marble_snapshot(room.id);
  end if;
  if room.phase<>'waiting' then raise exception 'Game already starting';end if;
  if (select count(*) from private.marble_players where room_id=room.id)>=room.capacity then raise exception 'Room full';end if;
  insert into private.marble_players(room_id,user_id) values(room.id,actor);
  update private.marble_rooms set revision=revision+1 where id=room.id;
  return private.marble_snapshot(room.id);
end; $$;

create function public.get_marble_room(p_room uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  if not private.member_approved((select auth.uid())) then raise exception 'Approved member required';end if;
  perform 1 from private.marble_rooms where id=p_room for update;
  if not found then raise exception 'Room not found';end if;
  update private.marble_players set last_seen=now() where room_id=p_room and user_id=(select auth.uid());
  if not found then raise exception 'Room membership required';end if;
  perform private.marble_prune(p_room);
  return private.marble_snapshot(p_room);
end; $$;

create function public.set_marble_ready(p_room uuid,p_ready boolean) returns jsonb
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
    update private.marble_rooms set phase='countdown',round=private.marble_draw(people,outcomes),start_at=now()+interval '5 seconds',finish_at=now()+interval '35 seconds',revision=revision+1 where id=p_room;
  else update private.marble_rooms set revision=revision+1 where id=p_room;end if;
  return private.marble_snapshot(p_room);
end; $$;

create function public.leave_marble_room(p_room uuid) returns void
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); room private.marble_rooms;
begin
  if actor is null then raise exception 'Login required';end if;
  select * into room from private.marble_rooms where id=p_room for update;
  if not found then return;end if;
  if not exists(select 1 from private.marble_players where room_id=p_room and user_id=actor) then return;end if;
  delete from private.marble_players where room_id=p_room and user_id=actor;
  if actor=room.host_id then update private.marble_rooms set phase='closed',revision=revision+1 where id=p_room;
  elsif room.start_at is null or room.start_at>now() then
    update private.marble_players set ready=false where room_id=p_room;
    update private.marble_rooms set phase='waiting',round=null,start_at=null,finish_at=null,revision=revision+1 where id=p_room;
  end if;
end; $$;

revoke all on function private.marble_random_index(integer),private.marble_draw(jsonb,jsonb),private.marble_prune(uuid),private.marble_snapshot(uuid) from public,anon,authenticated;
revoke all on function public.list_marble_rooms(),public.create_marble_room(text,jsonb),public.join_marble_room(text),public.get_marble_room(uuid),public.set_marble_ready(uuid,boolean),public.leave_marble_room(uuid) from public,anon,authenticated;
grant execute on function public.list_marble_rooms(),public.create_marble_room(text,jsonb),public.join_marble_room(text),public.get_marble_room(uuid),public.set_marble_ready(uuid,boolean),public.leave_marble_room(uuid) to authenticated;

drop function public.create_marble_room(text,jsonb);
create function public.create_marble_room(p_capacity integer,p_losers integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); room private.marble_rooms; n integer; p_outcomes jsonb;
begin
  if not private.member_approved(actor) then raise exception 'Approved member required';end if;
  if p_capacity is null or p_capacity not between 2 and 12 or p_losers is null or p_losers not between 1 and p_capacity-1 then raise exception 'Invalid room values';end if;
  n:=p_capacity;
  select jsonb_agg(case when i<=p_losers then '꽝' else '통과' end order by i) into p_outcomes from generate_series(1,n) i;
  perform pg_advisory_xact_lock(hashtextextended('marble-create:'||actor::text,0));
  if (select count(*) from private.marble_rooms where host_id=actor and created_at>now()-interval '1 hour')>=10 then raise exception 'Room limit exceeded';end if;
  loop
    begin
      insert into private.marble_rooms(code,host_id,title,capacity,outcomes) values(upper(substr(replace(gen_random_uuid()::text,'-',''),1,6)),actor,'마블룰렛',n,p_outcomes) returning * into room;
      exit;
    exception when unique_violation then null;end;
  end loop;
  insert into private.marble_players(room_id,user_id) values(room.id,actor);
  return private.marble_snapshot(room.id);
end; $$;
create or replace function private.marble_snapshot(p_room uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('id',r.id,'code',r.code,'title',r.title,'capacity',r.capacity,'losers',(select count(*) from jsonb_array_elements_text(r.outcomes) e where e='꽝'),'host_id',r.host_id,'revision',r.revision,'server_time',now(),
    'phase',case when r.phase='closed' then 'closed' when r.finish_at<=now() then 'finished' when r.start_at<=now() then 'running' else r.phase end,
    'start_at',r.start_at,'finish_at',r.finish_at,'simulation_seed',case when r.phase<>'closed' then r.round->'seed' end,'round',case when r.phase<>'closed' and r.start_at<=now() then r.round end,
    'players',coalesce((select jsonb_agg(jsonb_build_object('id',p.user_id,'ready',p.ready,'nickname',u.nickname,'team',u.team,'region',u.region,'staff_role',u.staff_role) order by p.joined_at,p.user_id)
      from private.marble_players p join public.profiles u on u.id=p.user_id where p.room_id=r.id),'[]'::jsonb))
  from private.marble_rooms r where r.id=p_room;
$$;
create function public.update_marble_settings(p_room uuid,p_capacity integer,p_losers integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); room private.marble_rooms; chosen_outcomes jsonb;
begin
  if not private.member_approved(actor) then raise exception 'Approved member required';end if;
  if p_capacity is null or p_capacity not between 2 and 12 or p_losers is null or p_losers not between 1 and p_capacity-1 then raise exception 'Invalid room values';end if;
  select * into room from private.marble_rooms where id=p_room for update;
  if not found then raise exception 'Room not found';end if;
  if room.host_id<>actor then raise exception 'Host required';end if;
  perform private.marble_prune(p_room);
  select * into room from private.marble_rooms where id=p_room;
  if room.phase<>'waiting' then raise exception 'Room already starting';end if;
  if (select count(*) from private.marble_players where room_id=p_room)>p_capacity then raise exception 'Capacity below participants';end if;
  select jsonb_agg(case when i<=p_losers then '꽝' else '통과' end order by i) into chosen_outcomes from generate_series(1,p_capacity) i;
  update private.marble_rooms set capacity=p_capacity,outcomes=chosen_outcomes,round=null,start_at=null,finish_at=null,revision=revision+1 where id=p_room;
  update private.marble_players set ready=false where room_id=p_room;
  return private.marble_snapshot(p_room);
end; $$;
revoke all on function public.create_marble_room(integer,integer),public.update_marble_settings(uuid,integer,integer) from public,anon;
grant execute on function public.create_marble_room(integer,integer),public.update_marble_settings(uuid,integer,integer) to authenticated;

commit;
