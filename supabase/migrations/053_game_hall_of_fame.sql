begin;
create table private.game_hall_months(
 month date primary key check(extract(day from month)=1 and month>=date '2026-10-01'),
 finalized_at timestamptz not null default now()
);
create table private.game_hall_podium(
 month date not null references private.game_hall_months(month),game text not null check(game in('baseball','2048','solitaire','snake')),
 place integer not null check(place between 1 and 3),user_id uuid not null,name text not null,score integer not null check(score>=0),
 elapsed_ms integer,achieved_at timestamptz not null,details jsonb not null default '{}',primary key(month,game,place),unique(month,game,user_id)
);
create table private.game_hall_records(
 game text primary key check(game in('baseball','2048','solitaire','snake')),user_id uuid not null,name text not null,
 score integer not null check(score>=0),elapsed_ms integer,achieved_at timestamptz not null,month date not null,details jsonb not null default '{}'
);
alter table private.game_hall_months enable row level security;
alter table private.game_hall_podium enable row level security;
alter table private.game_hall_records enable row level security;
revoke all on private.game_hall_months,private.game_hall_podium,private.game_hall_records from public,anon,authenticated,service_role;

create function private.game_hall_rows(p_month date) returns table(game text,user_id uuid,name text,score integer,elapsed_ms integer,achieved_at timestamptz,month date,details jsonb)
language sql stable security definer set search_path='' as $$
 select 'baseball'::text,b.user_id,p.nickname,b.score,null::integer,b.achieved_at,b.rank_month,jsonb_build_object('maxLevel',b.max_level)
 from private.baseball_bests b join public.profiles p on p.id=b.user_id where(p_month is null or b.rank_month=p_month) and private.member_approved(b.user_id)
 union all select '2048',b.user_id,p.nickname,b.score,null::integer,b.achieved_at,b.rank_month,jsonb_build_object('maxTile',b.max_tile)
 from private.game2048_bests b join public.profiles p on p.id=b.user_id where(p_month is null or b.rank_month=p_month) and private.member_approved(b.user_id)
 union all select 'solitaire',b.user_id,p.nickname,b.score,b.elapsed_ms,b.achieved_at,b.rank_month,'{}'::jsonb
 from private.solitaire_bests b join public.profiles p on p.id=b.user_id where(p_month is null or b.rank_month=p_month) and private.member_approved(b.user_id)
 union all select 'snake',b.user_id,p.nickname,b.score,b.elapsed_ms,b.achieved_at,b.rank_month,'{}'::jsonb
 from private.snake_bests b join public.profiles p on p.id=b.user_id where(p_month is null or b.rank_month=p_month) and private.member_approved(b.user_id);
$$;
revoke all on function private.game_hall_rows(date) from public,anon,authenticated,service_role;

create function private.remember_game_hall_record(p_game text,p_user uuid,p_name text,p_score integer,p_elapsed integer,p_at timestamptz,p_month date,p_details jsonb) returns void
language sql security definer set search_path='' as $$
 insert into private.game_hall_records as h(game,user_id,name,score,elapsed_ms,achieved_at,month,details)
 values(p_game,p_user,p_name,p_score,p_elapsed,p_at,p_month,p_details)
 on conflict(game) do update set user_id=excluded.user_id,name=excluded.name,score=excluded.score,elapsed_ms=excluded.elapsed_ms,achieved_at=excluded.achieved_at,month=excluded.month,details=excluded.details
 where excluded.score>h.score or(excluded.score=h.score and coalesce(excluded.elapsed_ms,2147483647)<coalesce(h.elapsed_ms,2147483647))
 or(excluded.score=h.score and coalesce(excluded.elapsed_ms,2147483647)=coalesce(h.elapsed_ms,2147483647) and(excluded.achieved_at,excluded.user_id)<(h.achieved_at,h.user_id));
$$;
revoke all on function private.remember_game_hall_record(text,uuid,text,integer,integer,timestamptz,date,jsonb) from public,anon,authenticated,service_role;

create function private.close_game_hall_months() returns void language plpgsql security definer set search_path='' as $$
declare current_month date:=date_trunc('month',now() at time zone 'Asia/Seoul')::date;last_month date;target_month date;
begin
 if current_month<=date '2026-10-01' then return;end if;
 select coalesce(max(month),date '2026-09-01') into last_month from private.game_hall_months;
 if last_month>=current_month-interval '1 month' then return;end if;
 perform pg_advisory_xact_lock(hashtextextended('game-hall-month-close',0));
 select coalesce(max(month),date '2026-09-01') into last_month from private.game_hall_months;
 for target_month in select generate_series(last_month+interval '1 month',current_month-interval '1 month',interval '1 month')::date loop
  insert into private.game_hall_months(month) values(target_month) on conflict do nothing;
  if found then
   insert into private.game_hall_podium(month,game,place,user_id,name,score,elapsed_ms,achieved_at,details)
   select target_month,game,place,user_id,name,score,elapsed_ms,achieved_at,details from(
    select r.*,row_number() over(partition by game order by score desc,elapsed_ms asc nulls last,achieved_at,user_id)::integer place from private.game_hall_rows(target_month) r
   ) ranked where place<=3;
  end if;
 end loop;
end;$$;
revoke all on function private.close_game_hall_months() from public,anon,authenticated,service_role;

create function private.game_hall_before_change() returns trigger language plpgsql security definer set search_path='' as $$
begin
 -- Close the old month before a new-month UPSERT replaces it or maintenance deletes it.
 perform pg_advisory_xact_lock(hashtextextended('game-hall-month-close',0));
 perform private.close_game_hall_months();
 if tg_op='DELETE' then return old;end if;return new;
end;$$;
create function private.game_hall_after_best() returns trigger language plpgsql security definer set search_path='' as $$
declare data jsonb:=to_jsonb(new);member_name text;
begin
 select nickname into member_name from public.profiles where id=new.user_id;
 if member_name is not null and private.member_approved(new.user_id) then
  perform private.remember_game_hall_record(tg_argv[0],new.user_id,member_name,new.score,(data->>'elapsed_ms')::integer,new.achieved_at,new.rank_month,
   jsonb_strip_nulls(jsonb_build_object('maxLevel',data->'max_level','maxTile',data->'max_tile')));
 end if;return new;
end;$$;
revoke all on function private.game_hall_before_change(),private.game_hall_after_best() from public,anon,authenticated,service_role;
create trigger game_hall_before_change before insert or update or delete on private.baseball_bests for each row execute function private.game_hall_before_change();
create trigger game_hall_before_change before insert or update or delete on private.game2048_bests for each row execute function private.game_hall_before_change();
create trigger game_hall_before_change before insert or update or delete on private.solitaire_bests for each row execute function private.game_hall_before_change();
create trigger game_hall_before_change before insert or update or delete on private.snake_bests for each row execute function private.game_hall_before_change();
create trigger game_hall_after_best after insert or update on private.baseball_bests for each row execute function private.game_hall_after_best('baseball');
create trigger game_hall_after_best after insert or update on private.game2048_bests for each row execute function private.game_hall_after_best('2048');
create trigger game_hall_after_best after insert or update on private.solitaire_bests for each row execute function private.game_hall_after_best('solitaire');
create trigger game_hall_after_best after insert or update on private.snake_bests for each row execute function private.game_hall_after_best('snake');

do $$declare r record;begin
 for r in select distinct on(game) * from private.game_hall_rows(null) order by game,score desc,elapsed_ms asc nulls last,achieved_at,user_id loop
  perform private.remember_game_hall_record(r.game,r.user_id,r.name,r.score,r.elapsed_ms,r.achieved_at,r.month,r.details);
 end loop;
end$$;
select private.close_game_hall_months();
do $$begin if coalesce(current_setting('cron.timezone',true),'GMT') not in('GMT','UTC','Etc/UTC') then raise exception 'Expected UTC cron timezone';end if;end$$;
select cron.schedule('game-hall-month-close','0 15 * * *','select private.close_game_hall_months();');

create function public.get_game_hall_of_fame() returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid());current_month date:=date_trunc('month',now() at time zone 'Asia/Seoul')::date;months jsonb;current_entries jsonb;records jsonb;
begin
 if not private.member_approved(actor) then raise exception 'Approved member required';end if;
 perform private.close_game_hall_months();
 select coalesce(jsonb_agg(to_jsonb(t) order by t.game,t.place),'[]') into current_entries from(
  select game,user_id as "userId",name,score,elapsed_ms as "elapsedMs",achieved_at as "achievedAt",details,place from(
   select r.*,row_number() over(partition by game order by score desc,elapsed_ms asc nulls last,achieved_at,user_id)::integer place from private.game_hall_rows(current_month) r
  ) ranked where place<=3
 ) t;
 select coalesce(jsonb_agg(jsonb_build_object('month',m.month,'finalized',true,'entries',coalesce((select jsonb_agg(jsonb_build_object('game',p.game,'place',p.place,'userId',p.user_id,'name',p.name,'score',p.score,'elapsedMs',p.elapsed_ms,'achievedAt',p.achieved_at,'details',p.details) order by p.game,p.place) from private.game_hall_podium p where p.month=m.month),'[]'::jsonb)) order by m.month desc),'[]'::jsonb) into months from private.game_hall_months m;
 select coalesce(jsonb_agg(jsonb_build_object('game',r.game,'name',r.name,'userId',r.user_id,'score',r.score,'elapsedMs',r.elapsed_ms,'achievedAt',r.achieved_at,'month',r.month,'details',r.details) order by r.game),'[]'::jsonb) into records from private.game_hall_records r;
 return jsonb_build_object('months',jsonb_build_array(jsonb_build_object('month',current_month,'finalized',false,'entries',current_entries))||months,'records',records,'serverNow',floor(extract(epoch from now())*1000),'resetsAt',floor(extract(epoch from ((current_month+interval '1 month') at time zone 'Asia/Seoul'))*1000));
end;$$;
revoke all on function public.get_game_hall_of_fame() from public,anon,authenticated,service_role;
grant execute on function public.get_game_hall_of_fame() to authenticated;
commit;
