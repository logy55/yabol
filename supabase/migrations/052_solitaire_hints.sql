begin;
-- Preserve existing runs, rankings, grants and legacy snapshots with no hints field.
create or replace function public.complete_solitaire_run(p_run uuid,p_result jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid());r private.solitaire_runs;month_key date:=private.solitaire_rank_month(now());
 s jsonb:=p_result->'stats';k text;v numeric;f integer;w integer;fl integer;ret integer;re integer;u integer;h integer:=0;sc integer;ms integer;mv integer;expected jsonb;
begin
 if not private.member_approved(actor) then raise exception 'Approved member required';end if;
 select * into r from private.solitaire_runs where id=p_run and user_id=actor for update;
 if not found then raise exception 'Game not found';end if;
 if r.finished_at is not null then return jsonb_build_object('score',r.score,'elapsedMs',r.elapsed_ms,'moves',r.moves);end if;
 if r.started_at<now()-interval '24 hours' or jsonb_typeof(p_result) is distinct from 'object' or jsonb_typeof(s) is distinct from 'object' then raise exception 'Invalid result';end if;
 foreach k in array array['foundation','waste','flips','returns','recycles','undos'] loop
  if jsonb_typeof(s->k) is distinct from 'number' then raise exception 'Invalid counters';end if;
  v:=(s->>k)::numeric;if v<0 or v>10000 or v<>trunc(v) then raise exception 'Invalid counters';end if;
 end loop;
 if s ? 'hints' then
  if jsonb_typeof(s->'hints') is distinct from 'number' then raise exception 'Invalid hint count';end if;
  v:=(s->>'hints')::numeric;if v<0 or v>10000 or v<>trunc(v) then raise exception 'Invalid hint count';end if;h:=v::integer;
 end if;
 f:=(s->>'foundation')::integer;w:=(s->>'waste')::integer;fl:=(s->>'flips')::integer;ret:=(s->>'returns')::integer;re:=(s->>'recycles')::integer;u:=(s->>'undos')::integer;
 if fl<>21 or w>24 or f<>52+ret then raise exception 'Game not completed';end if;
 select jsonb_agg(t.pile order by t.suit) into expected from(select suit,jsonb_agg(suit*13+rank order by rank) as pile from generate_series(0,3)suit cross join generate_series(0,12)rank group by suit)t;
 if p_result->'foundations' is distinct from expected then raise exception 'Game not completed';end if;
 foreach k in array array['score','moves','elapsedMs'] loop
  if jsonb_typeof(p_result->k) is distinct from 'number' then raise exception 'Invalid result';end if;
  v:=(p_result->>k)::numeric;if v<0 or v>86400000 or v<>trunc(v) then raise exception 'Invalid result';end if;
 end loop;
 sc:=greatest(0,f*10+w*5+fl*5-ret*15-re*20-u*5-h*5+500);ms:=(p_result->>'elapsedMs')::integer;mv:=(p_result->>'moves')::integer;
 if (p_result->>'score')::integer<>sc or ms not between 1000 and 86400000 or mv not between 52+ret*2 and 20000 or mv<re+u or mv>ms/30.0+8 or ms>extract(epoch from now()-r.started_at)*1000+2000 then raise exception 'Invalid result';end if;
 update private.solitaire_runs set score=sc,elapsed_ms=ms,moves=mv,finished_at=now() where id=r.id;
 insert into private.solitaire_bests(user_id,run_id,score,elapsed_ms,rank_month) values(actor,p_run,sc,ms,month_key)
 on conflict(user_id) do update set run_id=excluded.run_id,score=excluded.score,elapsed_ms=excluded.elapsed_ms,rank_month=excluded.rank_month,achieved_at=now()
 where excluded.rank_month<>solitaire_bests.rank_month or excluded.score>solitaire_bests.score or(excluded.score=solitaire_bests.score and excluded.elapsed_ms<solitaire_bests.elapsed_ms);
 return jsonb_build_object('score',sc,'elapsedMs',ms,'moves',mv);
end;$$;
commit;
