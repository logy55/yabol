begin;
alter table private.baseball_runs drop constraint baseball_runs_physics_version_check;
alter table private.baseball_runs add constraint baseball_runs_physics_version_check check(physics_version in (1,2,3,4));
create function public.begin_baseball_run_v4(p_user uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r private.baseball_runs;
begin
 if not private.member_approved(p_user) then raise exception 'Approved member required';end if;
 perform pg_advisory_xact_lock(hashtextextended('baseball:'||p_user::text,0));
 if (select count(*) from private.baseball_runs where user_id=p_user and started_at>now()-interval '1 minute')>=8 then raise exception 'Too many game starts';end if;
 insert into private.baseball_runs(user_id,seed,physics_version) values(p_user,floor(random()*4294967296)::bigint,4) returning * into r;
 return jsonb_build_object('id',r.id,'seed',r.seed,'startedAt',r.started_at,'physicsVersion',r.physics_version);
end;$$;
revoke all on function public.begin_baseball_run_v4(uuid) from public,anon,authenticated;
grant execute on function public.begin_baseball_run_v4(uuid) to service_role;
commit;
