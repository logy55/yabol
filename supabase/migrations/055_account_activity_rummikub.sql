begin;
-- Keep the initial totals snapshot consistent with rounds finishing during deployment.
lock table private.rummikub_rooms,private.rummikub_monthly in share row exclusive mode;
create table if not exists private.rummikub_totals(
 user_id uuid primary key references public.profiles(id) on delete cascade,
 games bigint not null check(games>=0),wins bigint not null check(wins>=0 and wins<=games),lasts bigint not null check(lasts>=0 and lasts<=games)
);
alter table private.rummikub_totals enable row level security;
revoke all on private.rummikub_totals from public,anon,authenticated,service_role;
-- Seed only records still retained by the existing monthly leaderboard.
insert into private.rummikub_totals(user_id,games,wins,lasts)
 select user_id,games,wins,lasts from private.rummikub_monthly on conflict(user_id) do nothing;
create or replace function private.rummikub_record_finished(p_state jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare month_key date:=private.rummikub_rank_month(now());ended_at timestamptz;n integer;i integer;uid uuid;points integer;won integer;lasted integer;loser integer;total integer;
begin
 ended_at:=to_timestamp(coalesce((p_state->>'finishedAt')::numeric,extract(epoch from now())*1000)/1000);
 if private.rummikub_rank_month(ended_at)<>month_key then return;end if;
 n:=jsonb_array_length(p_state#>'{game,players}');
 if n not between 2 and 4 or jsonb_array_length(p_state#>'{game,result,scores}')<>n or jsonb_array_length(p_state#>'{game,result,winners}')<1 then raise exception 'Invalid result';end if;
 if (select count(distinct p->>'id') from jsonb_array_elements(p_state#>'{game,players}') p)<>n then raise exception 'Invalid players';end if;
 select sum((v#>>'{}')::integer) into total from jsonb_array_elements(p_state#>'{game,result,scores}') v;
 if total<>0 then raise exception 'Invalid score total';end if;
 loser:=(p_state#>>'{outcome,loserIndex}')::integer;
 if loser is null or loser not between 0 and n-1 then raise exception 'Invalid last place';end if;
 for i in 0..n-1 loop
  uid:=((p_state#>'{game,players}')->i->>'id')::uuid;points:=((p_state#>'{game,result,scores}')->>i)::integer;
  if points not between -1000 and 1000 then raise exception 'Invalid score';end if;
  won:=case when (p_state#>'{game,result,winners}') @> jsonb_build_array(i) then 1 else 0 end;lasted:=case when loser=i then 1 else 0 end;
  insert into private.rummikub_monthly as monthly(user_id,rank_month,games,wins,lasts,score) values(uid,month_key,1,won,lasted,points)
  on conflict(user_id) do update set rank_month=excluded.rank_month,
   games=case when monthly.rank_month=excluded.rank_month then monthly.games+1 else 1 end,
   wins=case when monthly.rank_month=excluded.rank_month then monthly.wins+excluded.wins else excluded.wins end,
   lasts=case when monthly.rank_month=excluded.rank_month then monthly.lasts+excluded.lasts else excluded.lasts end,
   score=case when monthly.rank_month=excluded.rank_month then monthly.score+excluded.score else excluded.score end,updated_at=now();
  insert into private.rummikub_totals as totals(user_id,games,wins,lasts) values(uid,1,won,lasted)
  on conflict(user_id) do update set games=totals.games+1,wins=totals.wins+excluded.wins,lasts=totals.lasts+excluded.lasts;
 end loop;
end; $$;

create or replace function private.member_rummikub_records(p_user uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce((select jsonb_build_object('games',games,'wins',wins,'losses',games-wins,'lasts',lasts)
 from private.rummikub_totals where user_id=p_user),jsonb_build_object('games',0,'wins',0,'losses',0,'lasts',0))
$$;
revoke all on function private.member_rummikub_records(uuid) from public,anon,authenticated,service_role;
create or replace function public.get_my_game_records() returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid());
begin
 if not private.member_approved(actor) then raise exception 'Approved member required';end if;
 return private.member_game_records(actor)||jsonb_build_object('rummikub',private.member_rummikub_records(actor),
 'activity',jsonb_build_object('posts',(select count(*) from public.posts where author_id=actor and deleted_at is null),
 'comments',(select count(*) from public.comments c join public.posts p on p.id=c.post_id where c.author_id=actor and c.deleted_at is null and p.deleted_at is null)));
end;$$;
create or replace function public.get_member_game_records(p_user uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if not private.member_approved((select auth.uid())) then raise exception 'Approved member required';end if;
 if p_user is null or not exists(select 1 from public.profiles p join private.member_accounts a on a.user_id=p.id where p.id=p_user and a.status in ('approved','suspended')) then raise exception 'Member not found';end if;
 return private.member_game_records(p_user)||jsonb_build_object('rummikub',private.member_rummikub_records(p_user));
end;$$;
commit;
