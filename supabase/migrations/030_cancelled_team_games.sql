-- Apply after 029. Add cancelled games without changing existing results or access.
begin;
alter table private.team_events drop constraint team_events_result_check;
alter table private.team_events add constraint team_events_result_check check (
  (game_status in ('scheduled','cancelled') and holics_score is null and opponent_score is null)
  or (game_status in ('win','loss','draw') and holics_score is not null and opponent_score is not null
    and holics_score between 0 and 999 and opponent_score between 0 and 999
    and ((game_status='win' and holics_score>opponent_score)
      or (game_status='loss' and holics_score<opponent_score)
      or (game_status='draw' and holics_score=opponent_score)))
);

create or replace function public.save_team_event_with_result(p_id uuid,p_revision bigint,p_title text,p_date date,p_time time,p_opponent text,p_location text,p_memo text,p_game_status text,p_holics_score integer,p_opponent_score integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare saved private.team_events; actor uuid:=(select auth.uid());
begin
  if private.menu_permission(actor,'yb_calendar')<>'write' then raise exception 'Calendar management required'; end if;
  if p_date is null or p_title is null or char_length(trim(p_title)) not between 1 and 80
    or p_opponent is null or char_length(p_opponent)>50 or p_location is null or char_length(p_location)>100
    or p_memo is null or char_length(p_memo)>1000 or p_revision is null then raise exception 'Invalid event'; end if;
  if p_game_status is null or p_game_status not in ('scheduled','win','loss','draw','cancelled') then raise exception 'Invalid game status'; end if;
  if p_game_status in ('scheduled','cancelled') then
    if p_holics_score is not null or p_opponent_score is not null then raise exception 'Unplayed game has no score'; end if;
  elsif p_holics_score is null or p_opponent_score is null or p_holics_score not between 0 and 999 or p_opponent_score not between 0 and 999
    or (p_game_status='win' and p_holics_score<=p_opponent_score)
    or (p_game_status='loss' and p_holics_score>=p_opponent_score)
    or (p_game_status='draw' and p_holics_score<>p_opponent_score) then raise exception 'Game result does not match score'; end if;
  if p_id is null then
    if p_revision<>0 then raise exception 'Invalid event revision'; end if;
    insert into private.team_events(title,event_date,event_time,opponent,location,memo,game_status,holics_score,opponent_score,created_by,updated_by)
    values(trim(p_title),p_date,p_time,trim(p_opponent),trim(p_location),trim(p_memo),p_game_status,p_holics_score,p_opponent_score,actor,actor) returning * into saved;
  else
    select * into saved from private.team_events where id=p_id and deleted_at is null for update;
    if not found then raise exception 'Event not found'; end if;
    if saved.revision<>p_revision then raise exception 'Event changed; reload required'; end if;
    update private.team_events set title=trim(p_title),event_date=p_date,event_time=p_time,opponent=trim(p_opponent),location=trim(p_location),memo=trim(p_memo),
      game_status=p_game_status,holics_score=p_holics_score,opponent_score=p_opponent_score,
      revision=revision+1,updated_at=now(),updated_by=actor where id=p_id returning * into saved;
  end if;
  return jsonb_build_object('id',saved.id,'title',saved.title,'event_date',saved.event_date,'event_time',saved.event_time,'opponent',saved.opponent,'location',saved.location,'memo',saved.memo,'revision',saved.revision,
    'game_status',saved.game_status,'holics_score',saved.holics_score,'opponent_score',saved.opponent_score);
end; $$;
revoke all on function public.save_team_event_with_result(uuid,bigint,text,date,time,text,text,text,text,integer,integer) from public,anon,authenticated;
grant execute on function public.save_team_event_with_result(uuid,bigint,text,date,time,text,text,text,text,integer,integer) to authenticated;
commit;
