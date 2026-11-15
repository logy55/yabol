begin;
-- One ranking order: score DESC, floors DESC, elapsed time ASC.
create function private.game_hall_floor(p_game text,p_details jsonb) returns integer language sql immutable set search_path='' as $$select case when p_game='stack' then coalesce((p_details->>'floors')::integer,0) else 0 end$$;
revoke all on function private.game_hall_floor(text,jsonb) from public,anon,authenticated,service_role;

create or replace function public.complete_stack_run(p_run uuid,p_result jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid());r private.stack_runs;month_key date:=private.stack_rank_month(now());k text;v numeric;sc integer;ms integer;fl integer;pf integer;mc integer;
begin
 if not private.member_approved(actor) then raise exception 'Approved member required';end if;
 select * into r from private.stack_runs where id=p_run and user_id=actor for update;
 if not found then raise exception 'Game not found';end if;
 if r.finished_at is not null then return jsonb_build_object('score',r.score,'floors',r.floors,'elapsedMs',r.elapsed_ms);end if;
 if r.started_at<now()-interval '24 hours' or jsonb_typeof(p_result) is distinct from 'object' or p_result->'version' is distinct from '1'::jsonb then raise exception 'Invalid result';end if;
 foreach k in array array['score','floors','perfects','maxCombo','elapsedMs'] loop
  if jsonb_typeof(p_result->k) is distinct from 'number' then raise exception 'Invalid result';end if;
  v:=(p_result->>k)::numeric;if v<0 or v>100000000 or v<>trunc(v) then raise exception 'Invalid result';end if;
 end loop;
 sc:=(p_result->>'score')::integer;ms:=(p_result->>'elapsedMs')::integer;fl:=(p_result->>'floors')::integer;pf:=(p_result->>'perfects')::integer;mc:=(p_result->>'maxCombo')::integer;
 if fl not between 0 and 10000 or pf not between 0 and fl or mc not between 0 and pf or (pf=0)<>(mc=0) or sc not between fl+pf and fl+5*pf or sc>60000 or ms not between 1 and 86400000 or fl>ms/140.0+1 or ms>extract(epoch from now()-r.started_at)*1000+2000 then raise exception 'Invalid result';end if;
 update private.stack_runs set score=sc,floors=fl,elapsed_ms=ms,perfects=pf,max_combo=mc,finished_at=now() where id=r.id;
 if sc>0 then
  insert into private.stack_bests(user_id,run_id,score,floors,elapsed_ms,rank_month) values(actor,p_run,sc,fl,ms,month_key)
  on conflict(user_id) do update set run_id=excluded.run_id,score=excluded.score,floors=excluded.floors,elapsed_ms=excluded.elapsed_ms,rank_month=excluded.rank_month,achieved_at=now()
  where excluded.rank_month<>stack_bests.rank_month or excluded.score>stack_bests.score or(excluded.score=stack_bests.score and (excluded.floors>stack_bests.floors or(excluded.floors=stack_bests.floors and excluded.elapsed_ms<stack_bests.elapsed_ms)));
 end if;
 return jsonb_build_object('score',sc,'floors',fl,'elapsedMs',ms);
end;$$;

create or replace function public.get_stack_leaderboard() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=(select auth.uid());entries jsonb;best jsonb;month_key date:=private.stack_rank_month(now());
begin
 if not private.member_approved(actor) then raise exception 'Approved member required';end if;
 select jsonb_agg(jsonb_build_object('userId',t.user_id,'name',t.nickname,'score',t.score,'floors',t.floors,'elapsedMs',t.elapsed_ms,'at',floor(extract(epoch from t.achieved_at)*1000)) order by t.score desc,t.floors desc,t.elapsed_ms,t.achieved_at,t.user_id) into entries
 from(select b.*,p.nickname from private.stack_bests b join public.profiles p on p.id=b.user_id where b.rank_month=month_key and private.member_approved(b.user_id) order by b.score desc,b.floors desc,b.elapsed_ms,b.achieved_at,b.user_id limit 30)t;
 select jsonb_build_object('score',score,'floors',floors,'elapsedMs',elapsed_ms) into best from private.stack_bests where user_id=actor and rank_month=month_key;
 return jsonb_build_object('entries',coalesce(entries,'[]'::jsonb),'personalBest',best,'month',month_key,'serverNow',floor(extract(epoch from now())*1000),'resetsAt',floor(extract(epoch from ((month_key+interval '1 month') at time zone 'Asia/Seoul'))*1000));
end;$$;

create or replace function private.remember_game_hall_record(p_game text,p_user uuid,p_name text,p_score integer,p_elapsed integer,p_at timestamptz,p_month date,p_details jsonb) returns void
language sql security definer set search_path='' as $$
 insert into private.game_hall_records as h(game,user_id,name,score,elapsed_ms,achieved_at,month,details)
 values(p_game,p_user,p_name,p_score,p_elapsed,p_at,p_month,p_details)
 on conflict(game) do update set user_id=excluded.user_id,name=excluded.name,score=excluded.score,elapsed_ms=excluded.elapsed_ms,achieved_at=excluded.achieved_at,month=excluded.month,details=excluded.details
 where excluded.score>h.score or(excluded.score=h.score and (
  private.game_hall_floor(excluded.game,excluded.details)>private.game_hall_floor(h.game,h.details) or(
   private.game_hall_floor(excluded.game,excluded.details)=private.game_hall_floor(h.game,h.details) and(
    coalesce(excluded.elapsed_ms,2147483647)<coalesce(h.elapsed_ms,2147483647) or(
     coalesce(excluded.elapsed_ms,2147483647)=coalesce(h.elapsed_ms,2147483647) and(excluded.achieved_at,excluded.user_id)<(h.achieved_at,h.user_id)
    )
   )
  )
 ));
$$;

create or replace function private.close_game_hall_months() returns void language plpgsql security definer set search_path='' as $$
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
    select r.*,row_number() over(partition by game order by score desc,private.game_hall_floor(game,details) desc,elapsed_ms asc nulls last,achieved_at,user_id)::integer place from private.game_hall_rows(target_month) r
   ) ranked where place<=3;
  end if;
 end loop;
end;$$;

create or replace function public.get_game_hall_of_fame() returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid());current_month date:=date_trunc('month',now() at time zone 'Asia/Seoul')::date;months jsonb;current_entries jsonb;records jsonb;
begin
 if not private.member_approved(actor) then raise exception 'Approved member required';end if;
 perform private.close_game_hall_months();
 select coalesce(jsonb_agg(to_jsonb(t) order by t.game,t.place),'[]') into current_entries from(
  select game,user_id as "userId",name,score,elapsed_ms as "elapsedMs",achieved_at as "achievedAt",details,place from(
   select r.*,row_number() over(partition by game order by score desc,private.game_hall_floor(game,details) desc,elapsed_ms asc nulls last,achieved_at,user_id)::integer place from private.game_hall_rows(current_month) r
  ) ranked where place<=3
 ) t;
 select coalesce(jsonb_agg(jsonb_build_object('month',m.month,'finalized',true,'entries',coalesce((select jsonb_agg(jsonb_build_object('game',p.game,'place',p.place,'userId',p.user_id,'name',p.name,'score',p.score,'elapsedMs',p.elapsed_ms,'achievedAt',p.achieved_at,'details',p.details) order by p.game,p.place) from private.game_hall_podium p where p.month=m.month),'[]'::jsonb)) order by m.month desc),'[]'::jsonb) into months from private.game_hall_months m;
 select coalesce(jsonb_agg(jsonb_build_object('game',r.game,'name',r.name,'userId',r.user_id,'score',r.score,'elapsedMs',r.elapsed_ms,'achievedAt',r.achieved_at,'month',r.month,'details',r.details) order by r.game),'[]'::jsonb) into records from private.game_hall_records r;
 return jsonb_build_object('months',jsonb_build_array(jsonb_build_object('month',current_month,'finalized',false,'entries',current_entries))||months,'records',records,'serverNow',floor(extract(epoch from now())*1000),'resetsAt',floor(extract(epoch from ((current_month+interval '1 month') at time zone 'Asia/Seoul'))*1000));
end;$$;

-- Re-select existing current-month personal records from saved completed runs.
insert into private.stack_bests as b(user_id,run_id,score,floors,elapsed_ms,rank_month,achieved_at)
select distinct on(user_id) user_id,id,score,floors,elapsed_ms,private.stack_rank_month(finished_at),finished_at
from private.stack_runs where finished_at is not null and score>0 and floors>0 and elapsed_ms>0 and private.stack_rank_month(finished_at)=private.stack_rank_month(now())
order by user_id,score desc,floors desc,elapsed_ms,finished_at,id
on conflict(user_id) do update set run_id=excluded.run_id,score=excluded.score,floors=excluded.floors,elapsed_ms=excluded.elapsed_ms,rank_month=excluded.rank_month,achieved_at=excluded.achieved_at
where(b.rank_month,b.run_id) is distinct from(excluded.rank_month,excluded.run_id);

-- Reconcile the all-time winner using the new tie-break without clearing archives.
do $$declare r record;begin
 for r in select * from private.game_hall_rows(null) where game='stack' order by score desc,private.game_hall_floor(game,details) desc,elapsed_ms,achieved_at,user_id limit 1 loop
  perform private.remember_game_hall_record(r.game,r.user_id,r.name,r.score,r.elapsed_ms,r.achieved_at,r.month,r.details);
 end loop;
end$$;
create index stack_bests_month_floors on private.stack_bests(rank_month,score desc,floors desc,elapsed_ms,achieved_at,user_id);
drop index private.stack_bests_month_score;
notify pgrst,'reload schema';
commit;
