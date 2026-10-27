begin;
create table private.snake_runs(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,
 seed bigint not null check(seed between 0 and 4294967295),started_at timestamptz not null default now(),finished_at timestamptz,
 score integer check(score between 0 and 3960),elapsed_ms integer check(elapsed_ms between 85 and 86400000),moves integer check(moves between 1 and 1100000)
);
create index snake_runs_user_time on private.snake_runs(user_id,started_at desc);
alter table private.snake_runs enable row level security;
revoke all on private.snake_runs from public,anon,authenticated;
create table private.snake_bests(
 user_id uuid primary key references public.profiles(id) on delete cascade,run_id uuid not null references private.snake_runs(id) on delete cascade,
 score integer not null check(score between 10 and 3960),elapsed_ms integer not null check(elapsed_ms between 85 and 86400000),
 rank_month date not null check(extract(day from rank_month)=1),achieved_at timestamptz not null default now()
);
create index snake_bests_month_score on private.snake_bests(rank_month,score desc,elapsed_ms,achieved_at,user_id);
alter table private.snake_bests enable row level security;
revoke all on private.snake_bests from public,anon,authenticated;
create function private.snake_rank_month(p_at timestamptz) returns date language sql immutable set search_path='' as $$select date_trunc('month',p_at at time zone 'Asia/Seoul')::date$$;
create function public.begin_snake_run() returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid());r private.snake_runs;
begin
 if not private.member_approved(actor) then raise exception 'Approved member required';end if;
 perform pg_advisory_xact_lock(hashtextextended('snake:'||actor::text,0));
 if(select count(*) from private.snake_runs where user_id=actor and started_at>now()-interval '1 minute')>=20 then raise exception 'Too many game starts';end if;
 insert into private.snake_runs(user_id,seed) values(actor,floor(random()*4294967296)::bigint) returning * into r;
 return jsonb_build_object('id',r.id,'seed',r.seed);
end;$$;
create function public.complete_snake_run(p_run uuid,p_result jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid());r private.snake_runs;month_key date:=private.snake_rank_month(now());k text;v numeric;sc integer;ms integer;mv integer;food integer;len integer;reason text;
begin
 if not private.member_approved(actor) then raise exception 'Approved member required';end if;
 select * into r from private.snake_runs where id=p_run and user_id=actor for update;
 if not found then raise exception 'Game not found';end if;
 if r.finished_at is not null then return jsonb_build_object('score',r.score,'elapsedMs',r.elapsed_ms,'moves',r.moves);end if;
 if r.started_at<now()-interval '24 hours' or jsonb_typeof(p_result) is distinct from 'object' or p_result->'version' is distinct from '1'::jsonb then raise exception 'Invalid result';end if;
 foreach k in array array['score','eaten','length','moves','elapsedMs'] loop
  if jsonb_typeof(p_result->k) is distinct from 'number' then raise exception 'Invalid result';end if;
  v:=(p_result->>k)::numeric;if v<0 or v>100000000 or v<>trunc(v) then raise exception 'Invalid result';end if;
 end loop;
 sc:=(p_result->>'score')::integer;ms:=(p_result->>'elapsedMs')::integer;mv:=(p_result->>'moves')::integer;food:=(p_result->>'eaten')::integer;len:=(p_result->>'length')::integer;reason:=p_result->>'reason';
 if reason is null or reason not in ('wall','self','filled') or food not between 0 and 396 or sc<>food*10 or len<>4+food or mv not between 1 and 1100000 or food>mv or ms not between 85 and 86400000 or mv>ms/85.0+2 or ms>extract(epoch from now()-r.started_at)*1000+2000 or(reason='filled')<>(len=400) then raise exception 'Invalid result';end if;
 update private.snake_runs set score=sc,elapsed_ms=ms,moves=mv,finished_at=now() where id=r.id;
 if sc>0 then
  insert into private.snake_bests(user_id,run_id,score,elapsed_ms,rank_month) values(actor,p_run,sc,ms,month_key)
  on conflict(user_id) do update set run_id=excluded.run_id,score=excluded.score,elapsed_ms=excluded.elapsed_ms,rank_month=excluded.rank_month,achieved_at=now()
  where excluded.rank_month<>snake_bests.rank_month or excluded.score>snake_bests.score or(excluded.score=snake_bests.score and excluded.elapsed_ms<snake_bests.elapsed_ms);
 end if;
 return jsonb_build_object('score',sc,'elapsedMs',ms,'moves',mv);
end;$$;
create function public.get_snake_leaderboard() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=(select auth.uid());entries jsonb;best jsonb;month_key date:=private.snake_rank_month(now());
begin
 if not private.member_approved(actor) then raise exception 'Approved member required';end if;
 select jsonb_agg(jsonb_build_object('userId',t.user_id,'name',t.nickname,'score',t.score,'elapsedMs',t.elapsed_ms,'at',floor(extract(epoch from t.achieved_at)*1000)) order by t.score desc,t.elapsed_ms,t.achieved_at,t.user_id) into entries
 from(select b.*,p.nickname from private.snake_bests b join public.profiles p on p.id=b.user_id where b.rank_month=month_key and private.member_approved(b.user_id) order by b.score desc,b.elapsed_ms,b.achieved_at,b.user_id limit 30)t;
 select jsonb_build_object('score',score,'elapsedMs',elapsed_ms) into best from private.snake_bests where user_id=actor and rank_month=month_key;
 return jsonb_build_object('entries',coalesce(entries,'[]'::jsonb),'personalBest',best,'month',month_key,'serverNow',floor(extract(epoch from now())*1000),'resetsAt',floor(extract(epoch from ((month_key+interval '1 month') at time zone 'Asia/Seoul'))*1000));
end;$$;
revoke all on function public.begin_snake_run(),public.complete_snake_run(uuid,jsonb),public.get_snake_leaderboard() from public,anon,authenticated;
grant execute on function public.begin_snake_run(),public.complete_snake_run(uuid,jsonb),public.get_snake_leaderboard() to authenticated;
create function private.reset_snake_monthly() returns jsonb language plpgsql security definer set search_path='' as $$
declare month_key date:=private.snake_rank_month(now());removed_bests integer;removed_runs integer;
begin
 perform pg_advisory_xact_lock(hashtextextended('snake-monthly-reset',0));
 delete from private.snake_bests where rank_month<month_key;get diagnostics removed_bests=row_count;
 delete from private.snake_runs r where ((r.finished_at is not null and r.finished_at<(month_key::timestamp at time zone 'Asia/Seoul')) or(r.finished_at is null and r.started_at<now()-interval '24 hours')) and not exists(select 1 from private.snake_bests b where b.run_id=r.id);get diagnostics removed_runs=row_count;
 return jsonb_build_object('month',month_key,'rankingsRemoved',removed_bests,'runsRemoved',removed_runs);
end;$$;
revoke all on function private.reset_snake_monthly() from public,anon,authenticated,service_role;
do $$begin if coalesce(current_setting('cron.timezone',true),'GMT') not in ('GMT','UTC','Etc/UTC') then raise exception 'Expected UTC cron timezone';end if;end$$;
select cron.schedule('snake-monthly-ranking-maintenance','0 15 * * *','select private.reset_snake_monthly();');
commit;
