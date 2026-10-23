-- Apply after 040. Any approved unrestricted member can read member game summaries.
begin;

create or replace function private.member_game_records(p_user uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=p_user;r record;result jsonb:='{}';game_kind text;totals jsonb;details jsonb;unclassified jsonb;
begin
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

revoke all on function private.member_game_records(uuid) from public,anon,authenticated;

create or replace function public.get_my_game_records() returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid());
begin
 if not private.member_approved(actor) then raise exception 'Approved member required';end if;
 return private.member_game_records(actor);
end;$$;

create function public.get_member_game_records(p_user uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if not private.member_approved((select auth.uid())) then raise exception 'Approved member required';end if;
 if p_user is null or not exists(select 1 from public.profiles p join private.member_accounts a on a.user_id=p.id where p.id=p_user and a.status in ('approved','suspended')) then raise exception 'Member not found';end if;
 return private.member_game_records(p_user);
end;$$;

revoke all on function public.get_member_game_records(uuid) from public,anon,authenticated;
grant execute on function public.get_member_game_records(uuid) to authenticated;
commit;
