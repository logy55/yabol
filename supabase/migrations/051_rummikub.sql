-- Ephemeral, server-owned Rummikub rooms. No client can read other players' racks.
begin;
create table private.rummikub_rooms(
 id uuid primary key,
 code text not null unique check(code ~ '^[A-F0-9]{6}$'),
 host_id uuid not null references public.profiles(id) on delete cascade,
 phase text not null check(phase in ('waiting','countdown','running','finished','closed')),
 state jsonb not null,
 version bigint not null default 1,
 scored_round integer not null default 0 check(scored_round>=0),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index rummikub_room_listing on private.rummikub_rooms(phase,updated_at desc);
alter table private.rummikub_rooms enable row level security;
revoke all on private.rummikub_rooms from public,anon,authenticated;

create table private.rummikub_monthly(
 user_id uuid primary key references public.profiles(id) on delete cascade,
 rank_month date not null check(extract(day from rank_month)=1),
 games integer not null check(games>0),wins integer not null check(wins>=0 and wins<=games),
 lasts integer not null check(lasts>=0 and lasts<=games),score bigint not null,
 updated_at timestamptz not null default now()
);
alter table private.rummikub_monthly enable row level security;
revoke all on private.rummikub_monthly from public,anon,authenticated;
create function private.rummikub_rank_month(p_at timestamptz) returns date language sql immutable set search_path='' as $$
 select date_trunc('month',p_at at time zone 'Asia/Seoul')::date
$$;

create function private.rummikub_record_finished(p_state jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare month_key date:=private.rummikub_rank_month(now());ended_at timestamptz;n integer;i integer;uid uuid;points integer;won integer;lasted integer;loser integer;total integer;
begin
 ended_at:=to_timestamp(coalesce((p_state->>'finishedAt')::numeric,extract(epoch from now())*1000)/1000);
 if private.rummikub_rank_month(ended_at)<>month_key then return;end if;
 n:=jsonb_array_length(p_state#>'{game,players}');
 if n not between 2 and 4 or jsonb_array_length(p_state#>'{game,result,scores}')<>n or jsonb_array_length(p_state#>'{game,result,winners}')<1 then raise exception 'Invalid result';end if;
 if (select count(distinct p->>'id') from jsonb_array_elements(p_state#>'{game,players}') p)<>n then raise exception 'Invalid players';end if;
 select sum((v#>>'{}')::integer) into total from jsonb_array_elements(p_state#>'{game,result,scores}') v;
 if total<>0 then raise exception 'Invalid score total';end if;
 loser:=(p_state#>>'{outcome,loserIndex}')::integer;
 if loser is null or loser not between 0 and n-1 then raise exception 'Invalid last place';end if;
 for i in 0..n-1 loop
  uid:=((p_state#>'{game,players}')->i->>'id')::uuid;points:=((p_state#>'{game,result,scores}')->>i)::integer;
  if points not between -1000 and 1000 then raise exception 'Invalid score';end if;
  won:=case when (p_state#>'{game,result,winners}') @> jsonb_build_array(i) then 1 else 0 end;lasted:=case when loser=i then 1 else 0 end;
  insert into private.rummikub_monthly as monthly(user_id,rank_month,games,wins,lasts,score) values(uid,month_key,1,won,lasted,points)
  on conflict(user_id) do update set rank_month=excluded.rank_month,
   games=case when monthly.rank_month=excluded.rank_month then monthly.games+1 else 1 end,
   wins=case when monthly.rank_month=excluded.rank_month then monthly.wins+excluded.wins else excluded.wins end,
   lasts=case when monthly.rank_month=excluded.rank_month then monthly.lasts+excluded.lasts else excluded.lasts end,
   score=case when monthly.rank_month=excluded.rank_month then monthly.score+excluded.score else excluded.score end,updated_at=now();
 end loop;
end; $$;
revoke all on function private.rummikub_record_finished(jsonb) from public,anon,authenticated,service_role;

create function public.rummikub_actor(p_user uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if not private.member_approved(p_user) then raise exception 'Approved member required';end if;
 return (select jsonb_build_object('id',id,'name',nickname,'approved',true) from public.profiles where id=p_user);
end; $$;

create function public.rummikub_list(p_user uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if not private.member_approved(p_user) then raise exception 'Approved member required';end if;
 return (select coalesce(jsonb_agg(state order by updated_at desc),'[]') from
  (select state,updated_at from private.rummikub_rooms where phase='waiting' and updated_at>now()-interval '20 minutes' order by updated_at desc limit 30) rooms);
end; $$;

create function public.rummikub_read(p_user uuid,p_room uuid default null,p_code text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare room private.rummikub_rooms;
begin
 if not private.member_approved(p_user) then raise exception 'Approved member required';end if;
 select * into room from private.rummikub_rooms where (p_room is not null and id=p_room) or (p_code is not null and code=upper(p_code)) limit 1;
 if not found then raise exception 'Room not found';end if;
 return jsonb_build_object('id',room.id,'version',room.version,'state',room.state);
end; $$;

create function public.rummikub_create(p_user uuid,p_state jsonb) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not private.member_approved(p_user) then raise exception 'Approved member required';end if;
 if (p_state->>'hostId')::uuid is distinct from p_user or p_state->>'phase'<>'waiting' then raise exception 'Invalid room';end if;
 perform pg_advisory_xact_lock(hashtextextended('rummikub-create:'||p_user::text,0));
 if (select count(*) from private.rummikub_rooms where host_id=p_user and created_at>now()-interval '1 hour')>=10 then raise exception 'Room limit exceeded';end if;
 -- Match state is temporary; finished/abandoned games are not a permanent history.
 delete from private.rummikub_rooms where updated_at<now()-interval '2 days';
 insert into private.rummikub_rooms(id,code,host_id,phase,state)
 values((p_state->>'id')::uuid,p_state->>'code',p_user,p_state->>'phase',p_state);
end; $$;

create function public.rummikub_store(p_user uuid,p_room uuid,p_version bigint,p_state jsonb) returns boolean
language plpgsql security definer set search_path='' as $$
declare changed integer;last_scored integer;next_round integer;
begin
 if not private.member_approved(p_user) then raise exception 'Approved member required';end if;
 if (p_state->>'id')::uuid is distinct from p_room then raise exception 'Invalid room';end if;
 update private.rummikub_rooms set state=p_state,phase=p_state->>'phase',host_id=(p_state->>'hostId')::uuid,version=version+1,updated_at=now()
  where id=p_room and version=p_version returning scored_round into last_scored;
 get diagnostics changed=row_count;if changed=0 then return false;end if;
 next_round:=(p_state->>'round')::integer;
 if p_state->>'phase'='finished' and next_round>last_scored then
  perform private.rummikub_record_finished(p_state);
  update private.rummikub_rooms set scored_round=next_round where id=p_room;
 end if;
 return true;
end; $$;

create function public.rummikub_leaderboard(p_user uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare entries jsonb;personal jsonb;month_key date:=private.rummikub_rank_month(now());
begin
 if not private.member_approved(p_user) then raise exception 'Approved member required';end if;
 with ranked as(
  select m.*,p.nickname,rank() over(order by m.wins desc,m.wins::numeric/m.games desc,m.score desc) place,
   row_number() over(order by m.wins desc,m.wins::numeric/m.games desc,m.score desc,p.nickname,m.user_id) display_order
  from private.rummikub_monthly m join public.profiles p on p.id=m.user_id
  where m.rank_month=month_key and private.member_approved(m.user_id)
 ),payload as(
  select user_id,display_order,jsonb_build_object('userId',user_id,'name',nickname,'rank',place,'wins',wins,'games',games,'lasts',lasts,'score',score,'winRate',round(wins::numeric/games*100,1)) data from ranked
 )
 select coalesce(jsonb_agg(data order by display_order) filter(where display_order<=30),'[]'::jsonb),
  (jsonb_agg(data) filter(where user_id=p_user))->0 into entries,personal from payload;
 return jsonb_build_object('entries',entries,'personal',personal,'month',month_key,'serverNow',floor(extract(epoch from now())*1000),'resetsAt',floor(extract(epoch from ((month_key+interval '1 month') at time zone 'Asia/Seoul'))*1000));
end; $$;

-- All full-state RPCs are callable only by the authenticated Edge Function's service client.
revoke all on function public.rummikub_actor(uuid),public.rummikub_list(uuid),public.rummikub_read(uuid,uuid,text),public.rummikub_create(uuid,jsonb),public.rummikub_store(uuid,uuid,bigint,jsonb),public.rummikub_leaderboard(uuid) from public,anon,authenticated;
grant execute on function public.rummikub_actor(uuid),public.rummikub_list(uuid),public.rummikub_read(uuid,uuid,text),public.rummikub_create(uuid,jsonb),public.rummikub_store(uuid,uuid,bigint,jsonb),public.rummikub_leaderboard(uuid) to service_role;

create function private.reset_rummikub_monthly() returns void language plpgsql security definer set search_path='' as $$
begin delete from private.rummikub_monthly where rank_month<private.rummikub_rank_month(now());end; $$;
revoke all on function private.reset_rummikub_monthly() from public,anon,authenticated,service_role;
do $$begin if coalesce(current_setting('cron.timezone',true),'GMT') not in ('GMT','UTC','Etc/UTC') then raise exception 'Expected UTC cron timezone';end if;end$$;
select cron.schedule('rummikub-monthly-ranking-maintenance','0 15 * * *','select private.reset_rummikub_monthly();');
commit;
