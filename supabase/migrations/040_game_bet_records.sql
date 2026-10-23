-- Apply after 039. Snapshot bet details and coffee obligations per completed round.
begin;

alter table private.game_results
 add column bet_type text check(bet_type in ('none','starbucks','mgc','compose')),
 add column participant_count smallint check(participant_count between 2 and 12),
 add column loser_count smallint check(loser_count>=1 and loser_count<participant_count),
 add column gifts_received smallint check(gifts_received>=0),
 add column gifts_sent smallint check(gifts_sent>=0),
 add constraint game_result_bet_details_complete check(
  (bet_type is null and participant_count is null and loser_count is null and gifts_received is null and gifts_sent is null)
  or (bet_type is not null and participant_count is not null and loser_count is not null and gifts_received is not null and gifts_sent is not null
   and (bet_type<>'none' or (gifts_received=0 and gifts_sent=0))
   and (not is_loss or gifts_received=0) and (is_loss or gifts_sent=0)));

-- Every passing player receives one coffee. Losers share that many coffees.
-- The stable result order assigns any indivisible remainder one at a time.
create function private.game_gift_quantities(p_bet text,p_count integer,p_losses integer[],p_index integer)
returns integer[] language plpgsql immutable set search_path='' as $$
declare losers integer:=cardinality(p_losses);position integer:=array_position(p_losses,p_index);winners integer:=p_count-losers;
begin
 if p_bet='none' then return array[0,0];end if;
 if p_bet is null or p_bet not in ('starbucks','mgc','compose') or p_count<2 or p_count>12 or losers<1 or losers>=p_count or p_index<0 or p_index>=p_count then raise exception 'Invalid gift result';end if;
 if position is null then return array[1,0];end if;
 return array[0,winners/losers+case when position<=winners%losers then 1 else 0 end];
end;$$;

create or replace function private.record_completed_game(p_game text,p_room uuid) returns void
language plpgsql security definer set search_path='' as $$
declare r record;losses integer[];i integer;person uuid;people integer;gifts integer[];
begin
 if p_game not in ('ladder','marble') or p_game is null then raise exception 'Invalid game';end if;
 execute format('select phase,round,start_at,finish_at,round_number,records_enabled,bet_type from private.%I where id=$1 for update',p_game||'_rooms') into r using p_room;
 if r is null or not r.records_enabled or r.phase<>'countdown' or r.round is null or r.start_at is null or r.finish_at is null or r.finish_at>now() or r.finish_at<=r.start_at then return;end if;
 losses:=private.game_loss_indexes(p_game,r.round);people:=jsonb_array_length(r.round->'players');
 for i in 0..people-1 loop
  person:=(r.round->'players'->i->>'id')::uuid;
  if exists(select 1 from auth.users where id=person) then
   gifts:=private.game_gift_quantities(r.bet_type,people,losses,i);
   insert into private.game_results(game,room_id,round_number,user_id,is_loss,finished_at,bet_type,participant_count,loser_count,gifts_received,gifts_sent)
   values(p_game,p_room,r.round_number,person,i=any(losses),r.finish_at,r.bet_type,people,cardinality(losses),gifts[1],gifts[2]) on conflict do nothing;
  end if;
 end loop;
end;$$;

-- Recover 039 details only when its exact original round still exists unchanged.
-- Older overwritten rounds retain their total wins/losses as unclassified records.
do $$declare game_kind text;r record;p record;losses integer[];people integer;gifts integer[];begin
 foreach game_kind in array array['ladder','marble'] loop
  for r in execute format('select g.id,g.round,g.round_number,g.finish_at,g.bet_type from private.%I g where g.round is not null and exists(select 1 from private.game_results s where s.game=$1 and s.room_id=g.id and s.round_number=g.round_number and s.finished_at=g.finish_at and s.bet_type is null)',game_kind||'_rooms') using game_kind loop
   people:=jsonb_array_length(r.round->'players');losses:=private.game_loss_indexes(game_kind,r.round);
   for p in select value,ordinality::integer-1 as player_index from jsonb_array_elements(r.round->'players') with ordinality loop
    gifts:=private.game_gift_quantities(r.bet_type,people,losses,p.player_index);
    update private.game_results set bet_type=r.bet_type,participant_count=people,loser_count=cardinality(losses),gifts_received=gifts[1],gifts_sent=gifts[2]
     where game=game_kind and room_id=r.id and round_number=r.round_number and user_id=(p.value->>'id')::uuid and finished_at=r.finish_at and bet_type is null and is_loss=(p.player_index=any(losses));
   end loop;
  end loop;
 end loop;
end;$$;

create or replace function public.get_my_game_records() returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid());r record;result jsonb:='{}';game_kind text;totals jsonb;details jsonb;unclassified jsonb;
begin
 if not private.member_approved(actor) then raise exception 'Approved member required';end if;
 for r in select id from private.ladder_rooms g where records_enabled and phase='countdown' and finish_at<=now() and round->'players' @> jsonb_build_array(jsonb_build_object('id',actor))
  and not exists(select 1 from private.game_results s where s.game='ladder' and s.room_id=g.id and s.round_number=g.round_number and s.user_id=actor) order by id
 loop perform private.record_completed_game('ladder',r.id);end loop;
 for r in select id from private.marble_rooms g where records_enabled and phase='countdown' and finish_at<=now() and round->'players' @> jsonb_build_array(jsonb_build_object('id',actor))
  and not exists(select 1 from private.game_results s where s.game='marble' and s.room_id=g.id and s.round_number=g.round_number and s.user_id=actor) order by id
 loop perform private.record_completed_game('marble',r.id);end loop;
 foreach game_kind in array array['ladder','marble'] loop
  select jsonb_build_object('wins',count(*) filter(where not is_loss),'losses',count(*) filter(where is_loss)),
   jsonb_build_object('wins',count(*) filter(where bet_type is null and not is_loss),'losses',count(*) filter(where bet_type is null and is_loss))
   into totals,unclassified from private.game_results where user_id=actor and game=game_kind;
  select jsonb_object_agg(bet,counts) into details from (
   select bet,jsonb_build_object('wins',count(s.user_id) filter(where not s.is_loss),'losses',count(s.user_id) filter(where s.is_loss),'received',coalesce(sum(s.gifts_received),0),'sent',coalesce(sum(s.gifts_sent),0)) counts
   from unnest(array['none','starbucks','mgc','compose']) bet
   left join private.game_results s on s.bet_type=bet and s.user_id=actor and s.game=game_kind group by bet
  ) groups;
  result:=result||jsonb_build_object(game_kind,totals||jsonb_build_object('bets',details,'unclassified',unclassified));
 end loop;
 return result;
end;$$;

revoke all on function private.game_gift_quantities(text,integer,integer[],integer) from public,anon,authenticated;
-- Existing own-account-only RPC grants and private ledger RLS remain unchanged.
commit;
