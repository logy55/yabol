-- Retire obsolete replay caches without touching completed scores or leaderboards.
begin;
update private.baseball_runs
set verification_target=null,verification_inputs=null,verification_state=null,verification_cursor=0,verification_revision=verification_revision+1
where finished_at is null and (verification_target is not null or verification_inputs is not null or verification_state is not null or verification_cursor<>0);
revoke execute on function public.save_baseball_verification(uuid,uuid,integer,jsonb,integer,integer,jsonb),public.complete_baseball_verified_run(uuid,uuid,integer,integer,integer,integer,integer,integer),public.pending_baseball_verifications(uuid) from service_role;
commit;
