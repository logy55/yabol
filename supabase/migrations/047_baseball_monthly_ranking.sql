-- Monthly TOP 30 in Asia/Seoul. Keep only the current month.
begin;
create function private.baseball_rank_month(p_at timestamptz) returns date
language sql immutable strict set search_path='' as $$
 select date_trunc('month',p_at at time zone 'Asia/Seoul')::date;
$$;
revoke all on function private.baseball_rank_month(timestamptz) from public,anon,authenticated;

alter table private.baseball_bests add column rank_month date;
update private.baseball_bests set rank_month=private.baseball_rank_month(achieved_at);
alter table private.baseball_bests alter column rank_month set not null;
alter table private.baseball_bests add constraint baseball_bests_month_start check(extract(day from rank_month)=1);
create index baseball_bests_month_score on private.baseball_bests(rank_month,score desc,achieved_at,user_id);

create or replace function public.complete_baseball_run(p_user uuid,p_run uuid,p_score integer,p_level integer,p_frames integer,p_drops integer,p_merges integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r private.baseball_runs;month_key date:=private.baseball_rank_month(now());
begin
 if not private.member_approved(p_user) then raise exception 'Approved member required';end if;
 select * into r from private.baseball_runs where id=p_run and user_id=p_user for update;
 if not found then raise exception 'Game not found';end if;
 if r.finished_at is not null then return jsonb_build_object('score',r.score,'maxLevel',r.max_level,'drops',r.drops,'merges',r.merges);end if;
 if p_score is null or p_score not between 0 and 2000000 or p_level is null or p_level not between 0 and 10 or p_frames is null or p_frames not between 0 and 216000 or p_drops is null or p_drops not between 0 and 6000 or p_merges is null or p_merges not between 0 and 12000 then raise exception 'Invalid game result';end if;
 if r.started_at<now()-interval '24 hours' or (p_frames/60.0)>extract(epoch from now()-r.started_at)+2 then raise exception 'Invalid game duration';end if;
 update private.baseball_runs set finished_at=now(),score=p_score,max_level=p_level,frames=p_frames,drops=p_drops,merges=p_merges where id=r.id;
 if p_score>0 then
  insert into private.baseball_bests(user_id,rank_month,run_id,score,max_level) values(p_user,month_key,p_run,p_score,p_level)
  on conflict(user_id) do update set rank_month=excluded.rank_month,run_id=excluded.run_id,score=excluded.score,max_level=excluded.max_level,achieved_at=now()
  where excluded.rank_month<>baseball_bests.rank_month or excluded.score>baseball_bests.score;
 end if;
 return jsonb_build_object('score',p_score,'maxLevel',p_level,'drops',p_drops,'merges',p_merges);
end;$$;

create or replace function public.get_baseball_leaderboard() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=(select auth.uid());entries jsonb;best integer;month_key date:=private.baseball_rank_month(now());
begin
 if not private.member_approved(actor) then raise exception 'Approved member required';end if;
 select jsonb_agg(jsonb_build_object('userId',t.user_id,'name',t.nickname,'score',t.score,'maxLevel',t.max_level,'at',floor(extract(epoch from t.achieved_at)*1000)) order by t.score desc,t.achieved_at,t.user_id) into entries
 from(select b.*,p.nickname from private.baseball_bests b join public.profiles p on p.id=b.user_id where b.rank_month=month_key and private.member_approved(b.user_id) order by b.score desc,b.achieved_at,b.user_id limit 30)t;
 select score into best from private.baseball_bests where user_id=actor and rank_month=month_key;
 return jsonb_build_object('entries',coalesce(entries,'[]'::jsonb),'personalBest',coalesce(best,0),'month',month_key,'serverNow',floor(extract(epoch from now())*1000),'resetsAt',floor(extract(epoch from ((month_key+interval '1 month') at time zone 'Asia/Seoul'))*1000));
end;$$;

create function private.reset_baseball_monthly() returns jsonb
language plpgsql security definer set search_path='' as $$
declare month_key date:=private.baseball_rank_month(now());month_start timestamptz;removed_bests integer;removed_runs integer;
begin
 month_start:=month_key::timestamp at time zone 'Asia/Seoul';
 perform pg_advisory_xact_lock(hashtextextended('baseball-monthly-reset',0));
 delete from private.baseball_bests where rank_month<month_key;
 get diagnostics removed_bests=row_count;
 delete from private.baseball_runs r where ((r.finished_at is not null and r.finished_at<month_start) or (r.finished_at is null and r.started_at<now()-interval '24 hours')) and not exists(select 1 from private.baseball_bests b where b.run_id=r.id);
 get diagnostics removed_runs=row_count;
 return jsonb_build_object('month',month_key,'rankingsRemoved',removed_bests,'runsRemoved',removed_runs);
end;$$;
revoke all on function private.reset_baseball_monthly() from public,anon,authenticated,service_role;

create extension if not exists pg_cron;
do $$begin
 if coalesce(current_setting('cron.timezone',true),'GMT') not in ('GMT','UTC','Etc/UTC') then raise exception 'Expected UTC cron timezone';end if;
end$$;
-- 15:00 UTC is 00:00 Asia/Seoul. Daily maintenance expires idle runs;
-- old rankings and completed runs are removed at the first midnight of a month.
select cron.schedule('baseball-monthly-ranking-maintenance','0 15 * * *','select private.reset_baseball_monthly();');
select private.reset_baseball_monthly();
commit;
