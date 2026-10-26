begin;
create table private.game2048_runs(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,
 seed bigint not null check(seed between 0 and 4294967295),started_at timestamptz not null default now(),saved_at timestamptz,finished_at timestamptz,
 score integer check(score between 0 and 2000000000),moves integer check(moves between 1 and 50000),max_tile integer check(max_tile between 2 and 131072 and (max_tile&(max_tile-1))=0),kind text check(kind in ('milestone','over'))
);
create index game2048_runs_user_time on private.game2048_runs(user_id,started_at desc);
alter table private.game2048_runs enable row level security;
revoke all on private.game2048_runs from public,anon,authenticated;
create table private.game2048_bests(
 user_id uuid primary key references public.profiles(id) on delete cascade,run_id uuid not null references private.game2048_runs(id) on delete cascade,
 score integer not null check(score between 1 and 2000000000),max_tile integer not null check(max_tile between 2 and 131072 and (max_tile&(max_tile-1))=0),rank_month date not null check(extract(day from rank_month)=1),achieved_at timestamptz not null default now()
);
create index game2048_bests_month_score on private.game2048_bests(rank_month,score desc,achieved_at,user_id);
alter table private.game2048_bests enable row level security;
revoke all on private.game2048_bests from public,anon,authenticated;
create function private.game2048_rank_month(p_at timestamptz) returns date language sql immutable strict set search_path='' as $$select date_trunc('month',p_at at time zone 'Asia/Seoul')::date$$;
revoke all on function private.game2048_rank_month(timestamptz) from public,anon,authenticated;
create function public.begin_game2048_run(p_user uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare r private.game2048_runs;
begin
 if not private.member_approved(p_user) then raise exception 'Approved member required';end if;
 perform pg_advisory_xact_lock(hashtextextended('game2048:'||p_user::text,0));
 if(select count(*) from private.game2048_runs where user_id=p_user and started_at>now()-interval '1 minute')>=8 then raise exception 'Too many game starts';end if;
 insert into private.game2048_runs(user_id,seed) values(p_user,floor(random()*4294967296)::bigint) returning * into r;
 return jsonb_build_object('id',r.id,'seed',r.seed);
end;$$;
create function public.game2048_run_for_save(p_user uuid,p_run uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare r private.game2048_runs;
begin
 if not private.member_approved(p_user) then raise exception 'Approved member required';end if;
 select * into r from private.game2048_runs where id=p_run and user_id=p_user;
 if not found or r.started_at<now()-interval '24 hours' then raise exception 'Game not found';end if;
 return to_jsonb(r);
end;$$;
create function public.complete_game2048_run(p_user uuid,p_run uuid,p_score integer,p_moves integer,p_tile integer,p_kind text) returns jsonb language plpgsql security definer set search_path='' as $$
declare r private.game2048_runs;month_key date:=private.game2048_rank_month(now());
begin
 if not private.member_approved(p_user) then raise exception 'Approved member required';end if;
 select * into r from private.game2048_runs where id=p_run and user_id=p_user for update;
 if not found then raise exception 'Game not found';end if;
 if r.finished_at is not null or (r.moves is not null and p_moves<=r.moves) then return jsonb_build_object('score',r.score,'moves',r.moves,'maxTile',r.max_tile,'kind',r.kind);end if;
 if p_score is null or p_score not between 0 and 2000000000 or p_moves is null or p_moves not between 1 and 50000 or p_tile is null or p_tile not between 2 and 131072 or (p_tile&(p_tile-1))<>0 or p_kind is null or p_kind not in ('milestone','over') or (p_kind='milestone' and p_tile<2048) then raise exception 'Invalid result';end if;
 if r.started_at<now()-interval '24 hours' or p_moves>extract(epoch from now()-r.started_at)*20+8 then raise exception 'Invalid game duration';end if;
 if (r.score is not null and p_score<r.score) or (r.max_tile is not null and p_tile<r.max_tile) then raise exception 'Invalid progression';end if;
 update private.game2048_runs set score=p_score,moves=p_moves,max_tile=p_tile,kind=p_kind,saved_at=now(),finished_at=case when p_kind='over' then now() else null end where id=r.id;
 if p_score>0 then
  insert into private.game2048_bests(user_id,run_id,score,max_tile,rank_month) values(p_user,p_run,p_score,p_tile,month_key)
  on conflict(user_id) do update set run_id=excluded.run_id,score=excluded.score,max_tile=excluded.max_tile,rank_month=excluded.rank_month,achieved_at=now()
  where excluded.rank_month<>game2048_bests.rank_month or excluded.score>game2048_bests.score;
 end if;
 return jsonb_build_object('score',p_score,'moves',p_moves,'maxTile',p_tile,'kind',p_kind);
end;$$;
create function public.get_game2048_leaderboard() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=(select auth.uid());entries jsonb;best integer;month_key date:=private.game2048_rank_month(now());
begin
 if not private.member_approved(actor) then raise exception 'Approved member required';end if;
 select jsonb_agg(jsonb_build_object('userId',t.user_id,'name',t.nickname,'score',t.score,'maxTile',t.max_tile,'at',floor(extract(epoch from t.achieved_at)*1000)) order by t.score desc,t.achieved_at,t.user_id) into entries
 from(select b.*,p.nickname from private.game2048_bests b join public.profiles p on p.id=b.user_id where b.rank_month=month_key and private.member_approved(b.user_id) order by b.score desc,b.achieved_at,b.user_id limit 30)t;
 select score into best from private.game2048_bests where user_id=actor and rank_month=month_key;
 return jsonb_build_object('entries',coalesce(entries,'[]'::jsonb),'personalBest',coalesce(best,0),'month',month_key,'serverNow',floor(extract(epoch from now())*1000),'resetsAt',floor(extract(epoch from ((month_key+interval '1 month') at time zone 'Asia/Seoul'))*1000));
end;$$;
revoke all on function public.begin_game2048_run(uuid),public.game2048_run_for_save(uuid,uuid),public.complete_game2048_run(uuid,uuid,integer,integer,integer,text) from public,anon,authenticated;
grant execute on function public.begin_game2048_run(uuid),public.game2048_run_for_save(uuid,uuid),public.complete_game2048_run(uuid,uuid,integer,integer,integer,text) to service_role;
revoke all on function public.get_game2048_leaderboard() from public,anon,authenticated;
grant execute on function public.get_game2048_leaderboard() to authenticated;
create function private.reset_game2048_monthly() returns jsonb language plpgsql security definer set search_path='' as $$
declare month_key date:=private.game2048_rank_month(now());removed_bests integer;removed_runs integer;
begin
 perform pg_advisory_xact_lock(hashtextextended('game2048-monthly-reset',0));
 delete from private.game2048_bests where rank_month<month_key;get diagnostics removed_bests=row_count;
 delete from private.game2048_runs r where ((r.finished_at is not null and r.finished_at<(month_key::timestamp at time zone 'Asia/Seoul')) or(r.finished_at is null and coalesce(r.saved_at,r.started_at)<now()-interval '24 hours')) and not exists(select 1 from private.game2048_bests b where b.run_id=r.id);get diagnostics removed_runs=row_count;
 return jsonb_build_object('month',month_key,'rankingsRemoved',removed_bests,'runsRemoved',removed_runs);
end;$$;
revoke all on function private.reset_game2048_monthly() from public,anon,authenticated,service_role;
do $$begin if coalesce(current_setting('cron.timezone',true),'GMT') not in ('GMT','UTC','Etc/UTC') then raise exception 'Expected UTC cron timezone';end if;end$$;
select cron.schedule('game2048-monthly-ranking-maintenance','0 15 * * *','select private.reset_game2048_monthly();');
commit;
