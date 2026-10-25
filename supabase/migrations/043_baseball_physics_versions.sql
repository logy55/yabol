-- Keep existing and older-client runs on v1; only a v2 start opts in to v2.
begin;
alter table private.baseball_runs add column physics_version smallint not null default 1 check(physics_version in (1,2));
create function public.begin_baseball_run_v2(p_user uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r private.baseball_runs;
begin
 if not private.member_approved(p_user) then raise exception 'Approved member required';end if;
 perform pg_advisory_xact_lock(hashtextextended('baseball:'||p_user::text,0));
 if (select count(*) from private.baseball_runs where user_id=p_user and started_at>now()-interval '1 minute')>=8 then raise exception 'Too many game starts';end if;
 insert into private.baseball_runs(user_id,seed,physics_version) values(p_user,floor(random()*4294967296)::bigint,2) returning * into r;
 return jsonb_build_object('id',r.id,'seed',r.seed,'startedAt',r.started_at,'physicsVersion',r.physics_version);
end;$$;
revoke all on function public.begin_baseball_run_v2(uuid) from public,anon,authenticated;
grant execute on function public.begin_baseball_run_v2(uuid) to service_role;
commit;
