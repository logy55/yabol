begin;
alter table private.baseball_runs drop constraint baseball_runs_physics_version_check;
alter table private.baseball_runs add constraint baseball_runs_physics_version_check check(physics_version in (1,2,3));
alter table private.baseball_runs
 add column verification_target integer check(verification_target between 0 and 216000),
 add column verification_inputs jsonb,
 add column verification_state jsonb,
 add column verification_cursor integer not null default 0 check(verification_cursor between 0 and 216000),
 add column verification_revision integer not null default 0 check(verification_revision>=0);

create function public.begin_baseball_run_v3(p_user uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r private.baseball_runs;
begin
 if not private.member_approved(p_user) then raise exception 'Approved member required';end if;
 perform pg_advisory_xact_lock(hashtextextended('baseball:'||p_user::text,0));
 if (select count(*) from private.baseball_runs where user_id=p_user and started_at>now()-interval '1 minute')>=8 then raise exception 'Too many game starts';end if;
 insert into private.baseball_runs(user_id,seed,physics_version) values(p_user,floor(random()*4294967296)::bigint,3) returning * into r;
 return jsonb_build_object('id',r.id,'seed',r.seed,'startedAt',r.started_at,'physicsVersion',r.physics_version);
end;$$;

create function public.save_baseball_verification(p_user uuid,p_run uuid,p_revision integer,p_inputs jsonb,p_frames integer,p_cursor integer,p_state jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r private.baseball_runs;
begin
 if not private.member_approved(p_user) then raise exception 'Approved member required';end if;
 select * into r from private.baseball_runs where id=p_run and user_id=p_user for update;
 if not found or r.started_at<now()-interval '24 hours' then raise exception 'Game not found';end if;
 if r.finished_at is not null then return jsonb_build_object('finished',true);end if;
 if p_revision is null then raise exception 'Invalid verification revision';end if;
 if r.verification_revision<>p_revision then return jsonb_build_object('accepted',false,'cursor',r.verification_cursor,'total',r.verification_target);end if;
 if p_frames is null or p_frames not between 0 and 216000 or p_cursor is null or p_cursor<=r.verification_cursor or p_cursor>p_frames then raise exception 'Invalid verification cursor';end if;
 if r.verification_target is not null and r.verification_target<>p_frames then raise exception 'Verification target changed';end if;
 if r.verification_inputs is null and (p_inputs is null or jsonb_typeof(p_inputs)<>'array' or jsonb_array_length(p_inputs)>6000) then raise exception 'Invalid verification inputs';end if;
 if p_state is null or jsonb_typeof(p_state)<>'object' or (p_state#>>'{fields,frame}')::integer is distinct from p_cursor or (p_state#>>'{fields,physicsVersion}')::integer is distinct from r.physics_version then raise exception 'Invalid verification state';end if;
 update private.baseball_runs set verification_target=coalesce(verification_target,p_frames),verification_inputs=coalesce(verification_inputs,p_inputs),verification_state=p_state,verification_cursor=p_cursor,verification_revision=verification_revision+1 where id=r.id;
 return jsonb_build_object('accepted',true,'cursor',p_cursor,'total',p_frames);
end;$$;

create function public.complete_baseball_verified_run(p_user uuid,p_run uuid,p_revision integer,p_score integer,p_level integer,p_frames integer,p_drops integer,p_merges integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r private.baseball_runs;result jsonb;
begin
 if not private.member_approved(p_user) then raise exception 'Approved member required';end if;
 select * into r from private.baseball_runs where id=p_run and user_id=p_user for update;
 if not found then raise exception 'Game not found';end if;
 if p_revision is null then raise exception 'Invalid verification revision';end if;
 if r.finished_at is null and r.verification_revision<>p_revision then return jsonb_build_object('pending',true,'verifiedFrames',r.verification_cursor,'totalFrames',r.verification_target);end if;
 if r.finished_at is null and r.verification_target is not null and r.verification_target<>p_frames then raise exception 'Verification target changed';end if;
 result:=public.complete_baseball_run(p_user,p_run,p_score,p_level,p_frames,p_drops,p_merges);
 return jsonb_build_object('result',result);
end;$$;

create function public.pending_baseball_verifications(p_user uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if not private.member_approved(p_user) then raise exception 'Approved member required';end if;
 return(select coalesce(jsonb_agg(jsonb_build_object('runId',id,'verifiedFrames',verification_cursor,'totalFrames',verification_target)),'[]'::jsonb) from(select id,verification_cursor,verification_target from private.baseball_runs where user_id=p_user and finished_at is null and verification_target is not null and started_at>now()-interval '24 hours' order by started_at desc limit 5)t);
end;$$;

create function private.clear_baseball_verification() returns trigger language plpgsql set search_path='' as $$
begin
 if new.finished_at is not null then new.verification_inputs:=null;new.verification_state:=null;new.verification_target:=null;new.verification_cursor:=0;end if;
 return new;
end;$$;
create trigger clear_finished_baseball_verification before update of finished_at on private.baseball_runs for each row execute function private.clear_baseball_verification();
revoke all on function private.clear_baseball_verification() from public,anon,authenticated;

revoke all on function public.begin_baseball_run_v3(uuid),public.save_baseball_verification(uuid,uuid,integer,jsonb,integer,integer,jsonb),public.complete_baseball_verified_run(uuid,uuid,integer,integer,integer,integer,integer,integer),public.pending_baseball_verifications(uuid) from public,anon,authenticated;
grant execute on function public.begin_baseball_run_v3(uuid),public.save_baseball_verification(uuid,uuid,integer,jsonb,integer,integer,jsonb),public.complete_baseball_verified_run(uuid,uuid,integer,integer,integer,integer,integer,integer),public.pending_baseball_verifications(uuid) to service_role;
commit;
