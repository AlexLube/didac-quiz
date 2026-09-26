-- Didac-Quiz · Preguntas multimedia: emojis, fotos y audio
-- Imágenes y audio proceden de Wikimedia Commons (licencias libres o dominio
-- público) y se muestran siempre con su atribución.

alter table public.questions drop constraint if exists questions_format_check;
alter table public.questions add constraint questions_format_check check (format in
  ('choice', 'true_false', 'order', 'intruder', 'decade', 'clues', 'emoji',
   'image_choice', 'image_reveal', 'audio'));

alter table public.questions
  add column if not exists audio_url         text,
  add column if not exists audio_attribution text,
  add column if not exists media_start_ms    integer not null default 0;

create or replace function public._question_payload(
  q public.questions, p_position smallint, p_remaining_ms integer,
  p_limit_ms integer, p_removed smallint[]
) returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'position',          p_position,
    'id',                q.id,
    'format',            q.format,
    'difficulty',        q.difficulty,
    'prompt',            q.prompt,
    'options',           q.options,
    'image_url',         q.image_url,
    'image_attribution', q.image_attribution,
    'audio_url',         q.audio_url,
    'audio_attribution', q.audio_attribution,
    'media_start_ms',    q.media_start_ms,
    'time_limit_ms',     p_limit_ms,
    'remaining_ms',      p_remaining_ms,
    'removed_options',   coalesce(to_jsonb(p_removed), '[]'::jsonb)
  )
$$;

-- El comodín 50/50 también sirve en las preguntas de emoji y audio.
create or replace function public.use_joker(p_position integer) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_uid     uuid := _require_user();
  v_game    games%rowtype;
  v_ans     game_answers%rowtype;
  v_q       questions%rowtype;
  v_removed smallint[];
begin
  select * into v_game from games
   where user_id = v_uid and challenge_date = _today() for update;
  if not found or v_game.current_position <> p_position then raise exception 'wrong_position'; end if;
  select * into v_ans from game_answers where game_id = v_game.id and position = p_position;
  if not found or v_ans.answered_at is not null then raise exception 'not_served'; end if;
  if v_ans.joker_used then raise exception 'joker_already_used'; end if;

  select * into v_q from questions where id = v_ans.question_id;
  if v_q.format not in ('choice', 'intruder', 'decade', 'clues', 'emoji', 'image_choice',
                        'image_reveal', 'audio')
     or jsonb_array_length(v_q.options) <> 4 then
    raise exception 'joker_not_allowed';
  end if;
  if _jokers_left(v_uid) <= 0 then raise exception 'no_jokers_left'; end if;

  select array_agg(i order by i) into v_removed from (
    select i::smallint as i from generate_series(0, 3) i
     where i <> (v_q.answer #>> '{}')::integer
     order by random() limit 2) s;

  update game_answers set joker_used = true, removed_options = v_removed
   where game_id = v_game.id and position = p_position;
  return jsonb_build_object('removed_options', to_jsonb(v_removed), 'jokers_left', _jokers_left(v_uid));
end $$;

create or replace function public.get_solutions(p_date date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid  uuid := _require_user();
  v_date date := coalesce(p_date, _today() - 1);
  v_ch   challenges%rowtype;
begin
  if v_date >= _today() then raise exception 'challenge_still_open'; end if;
  select * into v_ch from challenges where challenge_date = v_date;
  if not found then return null; end if;
  return jsonb_build_object(
    'date',  v_ch.challenge_date,
    'kind',  v_ch.kind,
    'title', v_ch.title,
    'questions', (
      select jsonb_agg(jsonb_build_object(
               'position',          o.pos - 1,
               'id',                q.id,
               'format',            q.format,
               'difficulty',        q.difficulty,
               'prompt',            q.prompt,
               'options',           q.options,
               'answer',            q.answer,
               'explanation',       q.explanation,
               'image_url',         q.image_url,
               'image_attribution', q.image_attribution,
               'audio_url',         q.audio_url,
               'audio_attribution', q.audio_attribution,
               'media_start_ms',    q.media_start_ms,
               'accuracy',          case when q.times_shown > 0
                                         then round(q.times_correct::numeric / q.times_shown, 2) end,
               'my_answer',         a.given,
               'my_correct',        a.correct)
             order by o.pos)
        from unnest(v_ch.question_ids) with ordinality o(qid, pos)
        join questions q on q.id = o.qid
        left join games g on g.user_id = v_uid and g.challenge_date = v_ch.challenge_date
        left join game_answers a on a.game_id = g.id and a.position = o.pos - 1)
  );
end $$;

revoke execute on function public._question_payload(public.questions, smallint, integer, integer, smallint[])
  from public, anon, authenticated;
grant execute on function public.use_joker(integer)   to authenticated;
grant execute on function public.get_solutions(date)  to authenticated;
