-- Apply after 041. Server-verified baseball merge runs and one best per member.
begin;

create table private.baseball_runs(
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 seed bigint not null check(seed between 0 and 4294967295),
 started_at timestamptz not null default now(),
 finished_at timestamptz,
 score integer check(score between 0 and 2000000),
 max_level integer check(max_level between 0 and 10),
 frames integer check(frames between 0 and 216000),
 drops integer check(drops between 0 and 6000),
 merges integer check(merges between 0 and 12000)
);
create index baseball_runs_member_time on private.baseball_runs(user_id,started_at desc);
alter table private.baseball_runs enable row level security;
revoke all on private.baseball_runs from public,anon,authenticated;

create table private.baseball_bests(
 user_id uuid primary key references public.profiles(id) on delete cascade,
 run_id uuid not null references private.baseball_runs(id) on delete cascade,
 score integer not null check(score between 1 and 2000000),
 max_level integer not null check(max_level between 0 and 10),
 achieved_at timestamptz not null default now()
);
alter table private.baseball_bests enable row level security;
revoke all on private.baseball_bests from public,anon,authenticated;

create function public.begin_baseball_run(p_user uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r private.baseball_runs;
begin
 if not private.member_approved(p_user) then raise exception 'Approved member required';end if;
 perform pg_advisory_xact_lock(hashtextextended('baseball:'||p_user::text,0));
 if (select count(*) from private.baseball_runs where user_id=p_user and started_at>now()-interval '1 minute')>=8 then raise exception 'Too many game starts';end if;
 insert into private.baseball_runs(user_id,seed) values(p_user,floor(random()*4294967296)::bigint) returning * into r;
 return jsonb_build_object('id',r.id,'seed',r.seed,'startedAt',r.started_at);
end;$$;

create function public.baseball_run_for_validation(p_user uuid,p_run uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r private.baseball_runs;
begin
 if not private.member_approved(p_user) then raise exception 'Approved member required';end if;
 select * into r from private.baseball_runs where id=p_run and user_id=p_user;
 if not found then raise exception 'Game not found';end if;
 if r.started_at<now()-interval '24 hours' then raise exception 'Game expired';end if;
 return to_jsonb(r);
end;$$;

create function public.complete_baseball_run(p_user uuid,p_run uuid,p_score integer,p_level integer,p_frames integer,p_drops integer,p_merges integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r private.baseball_runs;
begin
 if not private.member_approved(p_user) then raise exception 'Approved member required';end if;
 select * into r from private.baseball_runs where id=p_run and user_id=p_user for update;
 if not found then raise exception 'Game not found';end if;
 if r.finished_at is not null then return jsonb_build_object('score',r.score,'maxLevel',r.max_level,'drops',r.drops,'merges',r.merges);end if;
 if p_score is null or p_score not between 0 and 2000000 or p_level is null or p_level not between 0 and 10 or p_frames is null or p_frames not between 0 and 216000 or p_drops is null or p_drops not between 0 and 6000 or p_merges is null or p_merges not between 0 and 12000 then raise exception 'Invalid game result';end if;
 if r.started_at<now()-interval '24 hours' or (p_frames/60.0)>extract(epoch from now()-r.started_at)+2 then raise exception 'Invalid game duration';end if;
 update private.baseball_runs set finished_at=now(),score=p_score,max_level=p_level,frames=p_frames,drops=p_drops,merges=p_merges where id=r.id;
 if p_score>0 then
  insert into private.baseball_bests(user_id,run_id,score,max_level) values(p_user,p_run,p_score,p_level)
  on conflict(user_id) do update set run_id=excluded.run_id,score=excluded.score,max_level=excluded.max_level,achieved_at=now()
  where excluded.score>baseball_bests.score;
 end if;
 return jsonb_build_object('score',p_score,'maxLevel',p_level,'drops',p_drops,'merges',p_merges);
end;$$;

create function public.get_baseball_leaderboard() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=(select auth.uid());entries jsonb;best integer;
begin
 if not private.member_approved(actor) then raise exception 'Approved member required';end if;
 select jsonb_agg(jsonb_build_object('userId',t.user_id,'name',t.nickname,'score',t.score,'maxLevel',t.max_level,'at',floor(extract(epoch from t.achieved_at)*1000)) order by t.score desc,t.achieved_at,t.user_id) into entries
 from(select b.*,p.nickname from private.baseball_bests b join public.profiles p on p.id=b.user_id where private.member_approved(b.user_id) order by b.score desc,b.achieved_at,b.user_id limit 10)t;
 select score into best from private.baseball_bests where user_id=actor;
 return jsonb_build_object('entries',coalesce(entries,'[]'::jsonb),'personalBest',coalesce(best,0));
end;$$;

revoke all on function public.begin_baseball_run(uuid),public.baseball_run_for_validation(uuid,uuid),public.complete_baseball_run(uuid,uuid,integer,integer,integer,integer,integer) from public,anon,authenticated;
grant execute on function public.begin_baseball_run(uuid),public.baseball_run_for_validation(uuid,uuid),public.complete_baseball_run(uuid,uuid,integer,integer,integer,integer,integer) to service_role;
revoke all on function public.get_baseball_leaderboard() from public,anon,authenticated;
grant execute on function public.get_baseball_leaderboard() to authenticated;
commit;
