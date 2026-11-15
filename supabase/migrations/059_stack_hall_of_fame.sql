begin;
-- Extend the existing archive without changing any finalized months or records.
alter table private.game_hall_podium drop constraint game_hall_podium_game_check;
alter table private.game_hall_podium add constraint game_hall_podium_game_check check(game in('baseball','2048','solitaire','snake','stack'));
alter table private.game_hall_records drop constraint game_hall_records_game_check;
alter table private.game_hall_records add constraint game_hall_records_game_check check(game in('baseball','2048','solitaire','snake','stack'));

create or replace function private.game_hall_rows(p_month date) returns table(game text,user_id uuid,name text,score integer,elapsed_ms integer,achieved_at timestamptz,month date,details jsonb)
language sql stable security definer set search_path='' as $$
 select 'baseball'::text,b.user_id,p.nickname,b.score,null::integer,b.achieved_at,b.rank_month,jsonb_build_object('maxLevel',b.max_level)
 from private.baseball_bests b join public.profiles p on p.id=b.user_id where(p_month is null or b.rank_month=p_month) and private.member_approved(b.user_id)
 union all select '2048',b.user_id,p.nickname,b.score,null::integer,b.achieved_at,b.rank_month,jsonb_build_object('maxTile',b.max_tile)
 from private.game2048_bests b join public.profiles p on p.id=b.user_id where(p_month is null or b.rank_month=p_month) and private.member_approved(b.user_id)
 union all select 'solitaire',b.user_id,p.nickname,b.score,b.elapsed_ms,b.achieved_at,b.rank_month,'{}'::jsonb
 from private.solitaire_bests b join public.profiles p on p.id=b.user_id where(p_month is null or b.rank_month=p_month) and private.member_approved(b.user_id)
 union all select 'snake',b.user_id,p.nickname,b.score,b.elapsed_ms,b.achieved_at,b.rank_month,'{}'::jsonb
 from private.snake_bests b join public.profiles p on p.id=b.user_id where(p_month is null or b.rank_month=p_month) and private.member_approved(b.user_id)
 union all select 'stack',b.user_id,p.nickname,b.score,b.elapsed_ms,b.achieved_at,b.rank_month,jsonb_build_object('floors',b.floors)
 from private.stack_bests b join public.profiles p on p.id=b.user_id where(p_month is null or b.rank_month=p_month) and private.member_approved(b.user_id);
$$;

create or replace function private.game_hall_after_best() returns trigger language plpgsql security definer set search_path='' as $$
declare data jsonb:=to_jsonb(new);member_name text;
begin
 select nickname into member_name from public.profiles where id=new.user_id;
 if member_name is not null and private.member_approved(new.user_id) then
  perform private.remember_game_hall_record(tg_argv[0],new.user_id,member_name,new.score,(data->>'elapsed_ms')::integer,new.achieved_at,new.rank_month,
   jsonb_strip_nulls(jsonb_build_object('maxLevel',data->'max_level','maxTile',data->'max_tile','floors',data->'floors')));
 end if;return new;
end;$$;

create trigger game_hall_before_change before insert or update or delete on private.stack_bests for each row execute function private.game_hall_before_change();
create trigger game_hall_after_best after insert or update on private.stack_bests for each row execute function private.game_hall_after_best('stack');

-- Include scores played between the game's release and this archive integration.
do $$declare r record;begin
 for r in select * from private.game_hall_rows(null) where game='stack' order by score desc,elapsed_ms,achieved_at,user_id limit 1 loop
  perform private.remember_game_hall_record(r.game,r.user_id,r.name,r.score,r.elapsed_ms,r.achieved_at,r.month,r.details);
 end loop;
end$$;
notify pgrst,'reload schema';
commit;
