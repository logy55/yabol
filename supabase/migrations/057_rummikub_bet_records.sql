begin;
lock table private.rummikub_rooms,private.rummikub_totals in share row exclusive mode;
alter table private.rummikub_rooms add column if not exists bet_scored_round integer not null default 0 check(bet_scored_round>=0);
create table if not exists private.rummikub_bet_totals(
 user_id uuid not null references public.profiles(id) on delete cascade,
 bet_type text not null check(bet_type in ('none','starbucks','mgc','compose')),
 wins bigint not null default 0 check(wins>=0),losses bigint not null default 0 check(losses>=0),
 received bigint not null default 0 check(received>=0),sent bigint not null default 0 check(sent>=0),
 primary key(user_id,bet_type),check(bet_type<>'none' or(received=0 and sent=0))
);
alter table private.rummikub_bet_totals enable row level security;
revoke all on private.rummikub_bet_totals from public,anon,authenticated,service_role;

create or replace function private.record_rummikub_bet(p_state jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare room_id uuid:=(p_state->>'id')::uuid;round_no integer:=(p_state->>'round')::integer;
 bet text:=coalesce(p_state->>'bet','none');n integer:=jsonb_array_length(p_state#>'{game,players}');
 loser integer:=(p_state#>>'{outcome,loserIndex}')::integer;changed integer;i integer;uid uuid;gifts integer[];
begin
 if room_id is null or round_no is null or round_no<1 or bet not in ('none','starbucks','mgc','compose')
  or n is null or n not between 2 and 4 or loser is null or loser not between 0 and n-1 then raise exception 'Invalid bet result';end if;
 if(select count(distinct p->>'id') from jsonb_array_elements(p_state#>'{game,players}')p)<>n then raise exception 'Invalid bet players';end if;
 update private.rummikub_rooms set bet_scored_round=round_no where id=room_id and bet_scored_round<round_no;
 get diagnostics changed=row_count;if changed=0 then return;end if;
 for i in 0..n-1 loop
  uid:=((p_state#>'{game,players}')->i->>'id')::uuid;
  if not exists(select 1 from public.profiles where id=uid) then continue;end if;
  gifts:=private.game_gift_quantities(bet,n,array[loser],i);
  insert into private.rummikub_bet_totals as totals(user_id,bet_type,wins,losses,received,sent)
  values(uid,bet,case when i<>loser then 1 else 0 end,case when i=loser then 1 else 0 end,gifts[1],gifts[2])
  on conflict(user_id,bet_type) do update set wins=totals.wins+excluded.wins,losses=totals.losses+excluded.losses,
   received=totals.received+excluded.received,sent=totals.sent+excluded.sent;
 end loop;
end;$$;
revoke all on function private.record_rummikub_bet(jsonb) from public,anon,authenticated,service_role;

-- Only an exact, already-scored round with retained bet settings can be classified.
-- Older overwritten rounds remain unclassified; aggregate wins are never invented.
do $$declare r record;begin
 for r in select state from private.rummikub_rooms where scored_round>0
  and scored_round=(state->>'round')::integer and state#>'{game,result}' is not null
  and state->>'finishedAt' is not null
  and private.rummikub_rank_month(to_timestamp((state->>'finishedAt')::numeric/1000))=private.rummikub_rank_month(now())
 loop perform private.record_rummikub_bet(r.state);end loop;
end;$$;

create or replace function private.member_rummikub_records(p_user uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare g bigint:=0;firsts bigint:=0;lasts bigint:=0;known_wins bigint;known_losses bigint;details jsonb;
begin
 select coalesce(t.games,0),coalesce(t.wins,0),coalesce(t.lasts,0) into g,firsts,lasts from private.rummikub_totals t where user_id=p_user;
 g:=coalesce(g,0);firsts:=coalesce(firsts,0);lasts:=coalesce(lasts,0);
 select coalesce(sum(wins),0),coalesce(sum(losses),0) into known_wins,known_losses from private.rummikub_bet_totals where user_id=p_user;
 if known_wins>g-lasts or known_losses>lasts then raise exception 'Inconsistent Rummikub records';end if;
 select jsonb_object_agg(bet,counts) into details from(
  select bet,jsonb_build_object('wins',coalesce(t.wins,0),'losses',coalesce(t.losses,0),'received',coalesce(t.received,0),'sent',coalesce(t.sent,0)) counts
  from unnest(array['none','starbucks','mgc','compose']) bet
  left join private.rummikub_bet_totals t on t.user_id=p_user and t.bet_type=bet
 ) rows;
 return jsonb_build_object('games',g,'wins',g-lasts,'losses',lasts,'firsts',firsts,'lasts',lasts,'bets',details,
  'unclassified',jsonb_build_object('wins',g-lasts-known_wins,'losses',lasts-known_losses));
end;$$;
revoke all on function private.member_rummikub_records(uuid) from public,anon,authenticated,service_role;
-- The existing monthly score and first-place ranking rules are preserved below.
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
 perform private.record_rummikub_bet(p_state);
end; $$;


commit;
