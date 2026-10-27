begin;
create table private.solitaire_runs(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,
 seed bigint not null check(seed between 0 and 4294967295),started_at timestamptz not null default now(),finished_at timestamptz,
 score integer check(score between 0 and 1245),elapsed_ms integer check(elapsed_ms between 1000 and 86400000),moves integer check(moves between 52 and 20000)
);
create index solitaire_runs_user_time on private.solitaire_runs(user_id,started_at desc);
alter table private.solitaire_runs enable row level security;
revoke all on private.solitaire_runs from public,anon,authenticated;
create table private.solitaire_bests(
 user_id uuid primary key references public.profiles(id) on delete cascade,run_id uuid not null references private.solitaire_runs(id) on delete cascade,
 score integer not null check(score between 0 and 1245),elapsed_ms integer not null check(elapsed_ms between 1000 and 86400000),
 rank_month date not null check(extract(day from rank_month)=1),achieved_at timestamptz not null default now()
);
create index solitaire_bests_month_score on private.solitaire_bests(rank_month,score desc,elapsed_ms,achieved_at,user_id);
alter table private.solitaire_bests enable row level security;
revoke all on private.solitaire_bests from public,anon,authenticated;
create function private.solitaire_rank_month(p_at timestamptz) returns date language sql immutable strict set search_path='' as $$select date_trunc('month',p_at at time zone 'Asia/Seoul')::date$$;
revoke all on function private.solitaire_rank_month(timestamptz) from public,anon,authenticated;
create function public.begin_solitaire_run() returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid());r private.solitaire_runs;
begin
 if not private.member_approved(actor) then raise exception 'Approved member required';end if;
 perform pg_advisory_xact_lock(hashtextextended('solitaire:'||actor::text,0));
 if(select count(*) from private.solitaire_runs where user_id=actor and started_at>now()-interval '1 minute')>=8 then raise exception 'Too many game starts';end if;
 insert into private.solitaire_runs(user_id,seed) values(actor,floor(random()*4294967296)::bigint) returning * into r;
 return jsonb_build_object('id',r.id,'seed',r.seed);
end;$$;
create function public.complete_solitaire_run(p_run uuid,p_result jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid());r private.solitaire_runs;month_key date:=private.solitaire_rank_month(now());
 s jsonb:=p_result->'stats';k text;v numeric;f integer;w integer;fl integer;ret integer;re integer;u integer;sc integer;ms integer;mv integer;expected jsonb;
begin
 if not private.member_approved(actor) then raise exception 'Approved member required';end if;
 select * into r from private.solitaire_runs where id=p_run and user_id=actor for update;
 if not found then raise exception 'Game not found';end if;
 if r.finished_at is not null then return jsonb_build_object('score',r.score,'elapsedMs',r.elapsed_ms,'moves',r.moves);end if;
 if r.started_at<now()-interval '24 hours' or jsonb_typeof(p_result) is distinct from 'object' or jsonb_typeof(s) is distinct from 'object' then raise exception 'Invalid result';end if;
 foreach k in array array['foundation','waste','flips','returns','recycles','undos'] loop
  if jsonb_typeof(s->k) is distinct from 'number' then raise exception 'Invalid counters';end if;
  v:=(s->>k)::numeric;if v<0 or v>10000 or v<>trunc(v) then raise exception 'Invalid counters';end if;
 end loop;
 f:=(s->>'foundation')::integer;w:=(s->>'waste')::integer;fl:=(s->>'flips')::integer;ret:=(s->>'returns')::integer;re:=(s->>'recycles')::integer;u:=(s->>'undos')::integer;
 if fl<>21 or w>24 or f<>52+ret then raise exception 'Game not completed';end if;
 select jsonb_agg(t.pile order by t.suit) into expected from(select suit,jsonb_agg(suit*13+rank order by rank) as pile from generate_series(0,3)suit cross join generate_series(0,12)rank group by suit)t;
 if p_result->'foundations' is distinct from expected then raise exception 'Game not completed';end if;
 foreach k in array array['score','moves','elapsedMs'] loop
  if jsonb_typeof(p_result->k) is distinct from 'number' then raise exception 'Invalid result';end if;
  v:=(p_result->>k)::numeric;if v<0 or v>86400000 or v<>trunc(v) then raise exception 'Invalid result';end if;
 end loop;
 sc:=greatest(0,f*10+w*5+fl*5-ret*15-re*20-u*5+500);ms:=(p_result->>'elapsedMs')::integer;mv:=(p_result->>'moves')::integer;
 if (p_result->>'score')::integer<>sc or ms not between 1000 and 86400000 or mv not between 52+ret*2 and 20000 or mv<re+u or mv>ms/30.0+8 or ms>extract(epoch from now()-r.started_at)*1000+2000 then raise exception 'Invalid result';end if;
 update private.solitaire_runs set score=sc,elapsed_ms=ms,moves=mv,finished_at=now() where id=r.id;
 insert into private.solitaire_bests(user_id,run_id,score,elapsed_ms,rank_month) values(actor,p_run,sc,ms,month_key)
 on conflict(user_id) do update set run_id=excluded.run_id,score=excluded.score,elapsed_ms=excluded.elapsed_ms,rank_month=excluded.rank_month,achieved_at=now()
 where excluded.rank_month<>solitaire_bests.rank_month or excluded.score>solitaire_bests.score or(excluded.score=solitaire_bests.score and excluded.elapsed_ms<solitaire_bests.elapsed_ms);
 return jsonb_build_object('score',sc,'elapsedMs',ms,'moves',mv);
end;$$;
create function public.get_solitaire_leaderboard() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=(select auth.uid());entries jsonb;best jsonb;month_key date:=private.solitaire_rank_month(now());
begin
 if not private.member_approved(actor) then raise exception 'Approved member required';end if;
 select jsonb_agg(jsonb_build_object('userId',t.user_id,'name',t.nickname,'score',t.score,'elapsedMs',t.elapsed_ms,'at',floor(extract(epoch from t.achieved_at)*1000)) order by t.score desc,t.elapsed_ms,t.achieved_at,t.user_id) into entries
 from(select b.*,p.nickname from private.solitaire_bests b join public.profiles p on p.id=b.user_id where b.rank_month=month_key and private.member_approved(b.user_id) order by b.score desc,b.elapsed_ms,b.achieved_at,b.user_id limit 30)t;
 select jsonb_build_object('score',score,'elapsedMs',elapsed_ms) into best from private.solitaire_bests where user_id=actor and rank_month=month_key;
 return jsonb_build_object('entries',coalesce(entries,'[]'::jsonb),'personalBest',best,'month',month_key,'serverNow',floor(extract(epoch from now())*1000),'resetsAt',floor(extract(epoch from ((month_key+interval '1 month') at time zone 'Asia/Seoul'))*1000));
end;$$;
revoke all on function public.begin_solitaire_run(),public.complete_solitaire_run(uuid,jsonb),public.get_solitaire_leaderboard() from public,anon,authenticated;
grant execute on function public.begin_solitaire_run(),public.complete_solitaire_run(uuid,jsonb),public.get_solitaire_leaderboard() to authenticated;
create function private.reset_solitaire_monthly() returns jsonb language plpgsql security definer set search_path='' as $$
declare month_key date:=private.solitaire_rank_month(now());removed_bests integer;removed_runs integer;
begin
 perform pg_advisory_xact_lock(hashtextextended('solitaire-monthly-reset',0));
 delete from private.solitaire_bests where rank_month<month_key;get diagnostics removed_bests=row_count;
 delete from private.solitaire_runs r where ((r.finished_at is not null and r.finished_at<(month_key::timestamp at time zone 'Asia/Seoul')) or(r.finished_at is null and r.started_at<now()-interval '24 hours')) and not exists(select 1 from private.solitaire_bests b where b.run_id=r.id);get diagnostics removed_runs=row_count;
 return jsonb_build_object('month',month_key,'rankingsRemoved',removed_bests,'runsRemoved',removed_runs);
end;$$;
revoke all on function private.reset_solitaire_monthly() from public,anon,authenticated,service_role;
do $$begin if coalesce(current_setting('cron.timezone',true),'GMT') not in ('GMT','UTC','Etc/UTC') then raise exception 'Expected UTC cron timezone';end if;end$$;
select cron.schedule('solitaire-monthly-ranking-maintenance','0 15 * * *','select private.reset_solitaire_monthly();');
commit;
