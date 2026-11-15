begin;
create table private.stack_runs(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,
 seed bigint not null check(seed between 0 and 4294967295),started_at timestamptz not null default now(),finished_at timestamptz,
 score integer check(score between 0 and 60000),floors integer check(floors between 0 and 10000),elapsed_ms integer check(elapsed_ms between 1 and 86400000),perfects integer,max_combo integer
);
create index stack_runs_user_time on private.stack_runs(user_id,started_at desc);
alter table private.stack_runs enable row level security;
revoke all on private.stack_runs from public,anon,authenticated,service_role;
create table private.stack_bests(
 user_id uuid primary key references public.profiles(id) on delete cascade,run_id uuid not null references private.stack_runs(id) on delete cascade,
 score integer not null check(score between 1 and 60000),floors integer not null check(floors between 1 and 10000),elapsed_ms integer not null check(elapsed_ms between 1 and 86400000),
 rank_month date not null check(extract(day from rank_month)=1),achieved_at timestamptz not null default now()
);
create index stack_bests_month_score on private.stack_bests(rank_month,score desc,elapsed_ms,achieved_at,user_id);
alter table private.stack_bests enable row level security;
revoke all on private.stack_bests from public,anon,authenticated,service_role;
create function private.stack_rank_month(p_at timestamptz) returns date language sql immutable set search_path='' as $$select date_trunc('month',p_at at time zone 'Asia/Seoul')::date$$;
create function public.begin_stack_run() returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid());r private.stack_runs;
begin
 if not private.member_approved(actor) then raise exception 'Approved member required';end if;
 perform pg_advisory_xact_lock(hashtextextended('stack:'||actor::text,0));
 if(select count(*) from private.stack_runs where user_id=actor and started_at>now()-interval '1 minute')>=20 then raise exception 'Too many game starts';end if;
 insert into private.stack_runs(user_id,seed) values(actor,floor(random()*4294967296)::bigint) returning * into r;
 return jsonb_build_object('id',r.id,'seed',r.seed);
end;$$;
create function public.complete_stack_run(p_run uuid,p_result jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
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
  where excluded.rank_month<>stack_bests.rank_month or excluded.score>stack_bests.score or(excluded.score=stack_bests.score and excluded.elapsed_ms<stack_bests.elapsed_ms);
 end if;
 return jsonb_build_object('score',sc,'floors',fl,'elapsedMs',ms);
end;$$;
create function public.get_stack_leaderboard() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=(select auth.uid());entries jsonb;best jsonb;month_key date:=private.stack_rank_month(now());
begin
 if not private.member_approved(actor) then raise exception 'Approved member required';end if;
 select jsonb_agg(jsonb_build_object('userId',t.user_id,'name',t.nickname,'score',t.score,'floors',t.floors,'elapsedMs',t.elapsed_ms,'at',floor(extract(epoch from t.achieved_at)*1000)) order by t.score desc,t.elapsed_ms,t.achieved_at,t.user_id) into entries
 from(select b.*,p.nickname from private.stack_bests b join public.profiles p on p.id=b.user_id where b.rank_month=month_key and private.member_approved(b.user_id) order by b.score desc,b.elapsed_ms,b.achieved_at,b.user_id limit 30)t;
 select jsonb_build_object('score',score,'floors',floors,'elapsedMs',elapsed_ms) into best from private.stack_bests where user_id=actor and rank_month=month_key;
 return jsonb_build_object('entries',coalesce(entries,'[]'::jsonb),'personalBest',best,'month',month_key,'serverNow',floor(extract(epoch from now())*1000),'resetsAt',floor(extract(epoch from ((month_key+interval '1 month') at time zone 'Asia/Seoul'))*1000));
end;$$;
revoke all on function public.begin_stack_run(),public.complete_stack_run(uuid,jsonb),public.get_stack_leaderboard() from public,anon,authenticated;
grant execute on function public.begin_stack_run(),public.complete_stack_run(uuid,jsonb),public.get_stack_leaderboard() to authenticated;
create function private.reset_stack_monthly() returns jsonb language plpgsql security definer set search_path='' as $$
declare month_key date:=private.stack_rank_month(now());removed_bests integer;removed_runs integer;
begin
 perform pg_advisory_xact_lock(hashtextextended('stack-monthly-reset',0));
 delete from private.stack_bests where rank_month<month_key;get diagnostics removed_bests=row_count;
 delete from private.stack_runs r where ((r.finished_at is not null and r.finished_at<(month_key::timestamp at time zone 'Asia/Seoul')) or(r.finished_at is null and r.started_at<now()-interval '24 hours')) and not exists(select 1 from private.stack_bests b where b.run_id=r.id);get diagnostics removed_runs=row_count;
 return jsonb_build_object('month',month_key,'rankingsRemoved',removed_bests,'runsRemoved',removed_runs);
end;$$;
revoke all on function private.reset_stack_monthly() from public,anon,authenticated,service_role;
do $$begin if coalesce(current_setting('cron.timezone',true),'GMT') not in ('GMT','UTC','Etc/UTC') then raise exception 'Expected UTC cron timezone';end if;end$$;
select cron.schedule('stack-monthly-ranking-maintenance','0 15 * * *','select private.reset_stack_monthly();');
notify pgrst,'reload schema';
commit;
