-- DidacCine Quiz · Variedad: nuevos formatos interactivos y puntuación variable
--
-- · Cada pregunta tiene `max_points` (por defecto = dificultad) y puede dar puntos
--   parciales: 0..max_points.
-- · `extra` guarda datos PÚBLICOS del formato (rango del slider, pistas, columna
--   derecha de "emparejar"...). La respuesta correcta sigue en `answer` (privada).
-- · Formatos nuevos: year_slider, versus, match, map, burst, typed_title,
--   odd_images, pick_two. `clues` e `image_reveal` admiten puntuación por rapidez
--   (extra.speed = true).
-- · Autocompletado de títulos (tabla film_titles + search_titles).

-- ---------------------------------------------------------------------------
-- Columnas y restricciones
-- ---------------------------------------------------------------------------
alter table public.questions
  add column if not exists max_points    smallint,
  add column if not exists extra         jsonb not null default '{}'::jsonb,
  add column if not exists time_limit_ms integer;

update public.questions set max_points = difficulty where max_points is null;
alter table public.questions alter column max_points set not null;
alter table public.questions add constraint questions_max_points_check check (max_points between 1 and 3);

create or replace function public._questions_defaults() returns trigger
language plpgsql as $$
begin
  if new.max_points is null then new.max_points := new.difficulty; end if;
  return new;
end $$;
drop trigger if exists questions_defaults on public.questions;
create trigger questions_defaults before insert on public.questions
  for each row execute function public._questions_defaults();

alter table public.questions drop constraint if exists questions_format_check;
alter table public.questions add constraint questions_format_check check (format in
  ('choice', 'true_false', 'order', 'intruder', 'decade', 'clues', 'emoji',
   'image_choice', 'image_reveal', 'audio',
   'year_slider', 'versus', 'match', 'map', 'burst', 'typed_title', 'odd_images', 'pick_two'));

alter table public.questions drop constraint if exists questions_options_check;
alter table public.questions add constraint questions_options_check
  check (jsonb_typeof(options) = 'array' and jsonb_array_length(options) between 0 and 8);

-- El reto puede llevar un tema (domingos temáticos, minijuego del día...)
alter table public.challenges add column if not exists theme text;

-- ---------------------------------------------------------------------------
-- Títulos para el autocompletado de "escribe el título"
-- ---------------------------------------------------------------------------
create table if not exists public.film_titles (
  id         bigserial primary key,
  qid        text not null,
  title      text not null,
  norm       text not null,
  year       smallint,
  popularity integer not null default 0,
  unique (qid, norm)
);
create index if not exists film_titles_norm_idx on public.film_titles (norm text_pattern_ops);
alter table public.film_titles enable row level security;
revoke all on public.film_titles from anon, authenticated;

-- Normaliza para comparar: minúsculas, sin acentos ni signos, sin artículo inicial.
create or replace function public._norm_title(t text) returns text
language sql immutable as $$
  select regexp_replace(
    btrim(regexp_replace(
      translate(lower(coalesce(t, '')),
                'áàäâãåéèëêíìïîóòöôõøúùüûñçß',
                'aaaaaaeeeeiiiioooooouuuunc' || 's'),
      '[^a-z0-9]+', ' ', 'g')),
    '^(el|la|los|las|un|una|the|a|an|le|les|il|lo|der|die|das|l) ', '')
$$;

create or replace function public.search_titles(p_query text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_q text := _norm_title(p_query);
begin
  perform _require_user();
  if char_length(v_q) < 2 then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('title', s.title, 'year', s.year) order by s.rank_key, s.popularity desc)
      from (
        select distinct on (qid) title, year, popularity,
               case when norm like v_q || '%' then 0 else 1 end as rank_key
          from film_titles
         where norm like v_q || '%' or norm like '% ' || v_q || '%'
         order by qid, case when norm like v_q || '%' then 0 else 1 end, popularity desc
      ) s
     limit 8), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------
-- Puntuación
-- ---------------------------------------------------------------------------
-- Puntos según la distancia y unos umbrales [para 3, para 2, para 1].
create or replace function public._band_points(p_dist numeric, p_bands jsonb) returns integer
language sql immutable as $$
  select case when p_dist <= (p_bands ->> 0)::numeric then 3
              when p_dist <= (p_bands ->> 1)::numeric then 2
              when p_dist <= (p_bands ->> 2)::numeric then 1
              else 0 end
$$;

create or replace function public._haversine_km(lat1 numeric, lon1 numeric, lat2 numeric, lon2 numeric)
returns numeric language sql immutable as $$
  select 12742 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lon2 - lon1) / 2), 2)))
$$;

-- Devuelve {points, correct, partial}. Nunca lanza error por una respuesta mal formada.
create or replace function public._score_answer(
  q public.questions, g jsonb, p_elapsed_ms integer, p_limit_ms integer
) returns jsonb
language plpgsql stable as $$
declare
  v_max  integer := q.max_points;
  v_pts  integer := 0;
  v_full boolean := false;
  v_ok   integer;
  v_n    integer;
  v_dist numeric;
begin
  if g is null or g = 'null'::jsonb then
    return jsonb_build_object('points', 0, 'correct', false, 'partial', false);
  end if;

  begin
    if q.format = 'year_slider' then
      if jsonb_typeof(g) = 'number' then
        v_pts := least(v_max, _band_points(abs((g #>> '{}')::numeric - (q.answer ->> 'year')::numeric),
                                           coalesce(q.extra -> 'bands', '[1,3,7]'::jsonb)));
        v_full := v_pts = v_max;
      end if;

    elsif q.format = 'map' then
      -- Vale cualquiera de los lugares válidos: answer = {lat, lon, alts: [{lat, lon}, ...]}
      if jsonb_typeof(g) = 'object' then
        select min(_haversine_km((g ->> 'lat')::numeric, (g ->> 'lon')::numeric,
                                 (p ->> 'lat')::numeric, (p ->> 'lon')::numeric))
          into v_dist
          from (select q.answer as p
                union all
                select a from jsonb_array_elements(coalesce(q.answer -> 'alts', '[]'::jsonb)) a) pts;
        v_pts  := least(v_max, _band_points(v_dist, coalesce(q.extra -> 'bands', '[300,1000,2500]'::jsonb)));
        v_full := v_pts = v_max;
      end if;

    elsif q.format in ('match', 'burst') then
      v_n := jsonb_array_length(q.answer);
      if jsonb_typeof(g) = 'array' and jsonb_array_length(g) = v_n then
        select count(*) into v_ok
          from jsonb_array_elements(q.answer) with ordinality a(v, i)
          join jsonb_array_elements(g) with ordinality b(v, i) using (i)
         where a.v = b.v;
        v_pts  := (v_max * v_ok) / v_n;
        v_full := v_ok = v_n;
      end if;

    elsif q.format = 'pick_two' then
      if jsonb_typeof(g) = 'array' and jsonb_array_length(g) = 2 and g ->> 0 <> g ->> 1 then
        select count(*) into v_ok
          from jsonb_array_elements(g) x(v)
         where exists (select 1 from jsonb_array_elements(q.answer) y(v) where y.v = x.v);
        v_pts  := case v_ok when 2 then v_max when 1 then v_max / 2 else 0 end;
        v_full := v_ok = 2;
      end if;

    elsif q.format = 'typed_title' then
      if jsonb_typeof(g) = 'string' then
        v_full := exists (
          select 1 from jsonb_array_elements_text(q.answer -> 'accept') a(t)
           where _norm_title(a.t) = _norm_title(g #>> '{}') and _norm_title(a.t) <> '');
        v_pts := case when v_full then v_max else 0 end;
      end if;

    else  -- choice, true_false, order, intruder, decade, clues, emoji, image_*, audio, versus, odd_images
      v_full := q.answer = g;
      v_pts  := case when v_full then v_max else 0 end;
    end if;
  exception when others then
    v_pts := 0; v_full := false;
  end;

  -- Puntuación por rapidez: cuanto antes aciertas, más puntos (se mantiene al menos 1).
  if v_full and coalesce((q.extra ->> 'speed')::boolean, false) then
    v_pts := greatest(1, v_max - least(2, floor((3.0 * p_elapsed_ms) / greatest(p_limit_ms, 1))::integer));
  end if;

  return jsonb_build_object('points', v_pts, 'correct', v_full, 'partial', (not v_full) and v_pts > 0);
end $$;

-- ---------------------------------------------------------------------------
-- Funciones del juego actualizadas
-- ---------------------------------------------------------------------------
create or replace function public._limit_for(q public.questions) returns integer
language sql stable as $$ select coalesce(q.time_limit_ms, _cfg_int('question_time_ms')) $$;

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
    'max_points',        q.max_points,
    'prompt',            q.prompt,
    'options',           q.options,
    'extra',             q.extra,
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

create or replace function public._game_summary(p_game bigint) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'date',         g.challenge_date,
    'finished',     g.finished_at is not null,
    'position',     g.current_position,
    'total_points', g.total_points,
    'max_points',   (select coalesce(sum(q.max_points), 0)
                       from challenges c, unnest(c.question_ids) qid
                       join questions q on q.id = qid
                      where c.challenge_date = g.challenge_date),
    'total_ms',     g.total_ms,
    'answers',      coalesce((
                      select jsonb_agg(jsonb_build_object(
                               'position',   a.position,
                               'difficulty', q.difficulty,
                               'max_points', q.max_points,
                               'format',     q.format,
                               'correct',    a.correct,
                               'points',     a.points,
                               'elapsed_ms', a.elapsed_ms,
                               'joker_used', a.joker_used)
                             order by a.position)
                        from game_answers a join questions q on q.id = a.question_id
                       where a.game_id = g.id and a.answered_at is not null), '[]'::jsonb)
  )
  from games g where g.id = p_game
$$;

create or replace function public._close_answer(
  p_game bigint, p_position smallint, p_given jsonb, p_elapsed_ms integer
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_q      questions%rowtype;
  v_score  jsonb;
  v_points integer;
  v_ok     boolean;
  v_game   games%rowtype;
begin
  select q.* into v_q
    from game_answers a join questions q on q.id = a.question_id
   where a.game_id = p_game and a.position = p_position;

  v_score  := _score_answer(v_q, p_given, p_elapsed_ms, _limit_for(v_q));
  v_points := (v_score ->> 'points')::integer;
  v_ok     := (v_score ->> 'correct')::boolean;

  update game_answers set
    answered_at = now(), given = p_given, correct = v_ok,
    points = v_points, elapsed_ms = p_elapsed_ms
  where game_id = p_game and position = p_position;

  update questions set
    times_shown   = times_shown + 1,
    times_correct = times_correct + v_ok::integer
  where id = v_q.id;

  update games set
    total_points     = total_points + v_points,
    total_ms         = total_ms + p_elapsed_ms,
    current_position = current_position + 1
  where id = p_game
  returning * into v_game;

  if v_game.current_position >= 10 then
    perform _finish_game(p_game);
  end if;

  return jsonb_build_object(
    'position',     p_position,
    'correct',      v_ok,
    'partial',      (v_score ->> 'partial')::boolean,
    'points',       v_points,
    'max_points',   v_q.max_points,
    'total_points', v_game.total_points,
    'finished',     v_game.current_position >= 10
  );
end $$;

create or replace function public.next_question() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_uid     uuid := _require_user();
  v_ch      challenges%rowtype;
  v_game    games%rowtype;
  v_ans     game_answers%rowtype;
  v_q       questions%rowtype;
  v_limit   integer;
  v_grace   integer := _cfg_int('network_grace_ms');
  v_elapsed integer;
begin
  select * into v_ch from challenges where challenge_date = _today();
  if not found then
    raise exception 'no_challenge_today';
  end if;

  select * into v_game from games
   where user_id = v_uid and challenge_date = v_ch.challenge_date for update;
  if not found then
    insert into games (user_id, challenge_date) values (v_uid, v_ch.challenge_date)
    returning * into v_game;
  end if;

  loop
    if v_game.current_position >= 10 then
      return jsonb_build_object('finished', true, 'game', _game_summary(v_game.id));
    end if;

    select * into v_ans from game_answers
     where game_id = v_game.id and position = v_game.current_position;
    if not found then
      insert into game_answers (game_id, position, question_id, served_at)
      values (v_game.id, v_game.current_position,
              v_ch.question_ids[v_game.current_position + 1], clock_timestamp())
      returning * into v_ans;
    end if;

    select * into v_q from questions where id = v_ans.question_id;
    v_limit   := _limit_for(v_q);
    v_elapsed := (extract(epoch from (clock_timestamp() - v_ans.served_at)) * 1000)::integer;
    if v_elapsed > v_limit + v_grace then
      perform _close_answer(v_game.id, v_ans.position, null, v_limit);
      select * into v_game from games where id = v_game.id;
      continue;
    end if;

    return jsonb_build_object(
      'finished', false,
      'total_points', v_game.total_points,
      'jokers_left', _jokers_left(v_uid),
      'question', _question_payload(v_q, v_ans.position,
                                    greatest(v_limit - v_elapsed, 0), v_limit,
                                    v_ans.removed_options));
  end loop;
end $$;

create or replace function public.submit_answer(p_position integer, p_answer jsonb) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_uid     uuid := _require_user();
  v_game    games%rowtype;
  v_ans     game_answers%rowtype;
  v_q       questions%rowtype;
  v_limit   integer;
  v_grace   integer := _cfg_int('network_grace_ms');
  v_elapsed integer;
begin
  select * into v_game from games
   where user_id = v_uid and challenge_date = _today() for update;
  if not found then raise exception 'no_game'; end if;
  if v_game.current_position <> p_position then raise exception 'wrong_position'; end if;

  select * into v_ans from game_answers
   where game_id = v_game.id and position = p_position;
  if not found or v_ans.answered_at is not null then raise exception 'not_served'; end if;

  select * into v_q from questions where id = v_ans.question_id;
  v_limit   := _limit_for(v_q);
  v_elapsed := (extract(epoch from (clock_timestamp() - v_ans.served_at)) * 1000)::integer;
  if v_elapsed > v_limit + v_grace then
    return _close_answer(v_game.id, v_ans.position, null, v_limit)
           || jsonb_build_object('timeout', true);
  end if;
  return _close_answer(v_game.id, v_ans.position, p_answer, least(v_elapsed, v_limit))
         || jsonb_build_object('timeout', false);
end $$;

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
                        'image_reveal', 'audio', 'odd_images')
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
               'max_points',        q.max_points,
               'prompt',            q.prompt,
               'options',           q.options,
               'extra',             q.extra,
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
               'my_correct',        a.correct,
               'my_points',         a.points)
             order by o.pos)
        from unnest(v_ch.question_ids) with ordinality o(qid, pos)
        join questions q on q.id = o.qid
        left join games g on g.user_id = v_uid and g.challenge_date = v_ch.challenge_date
        left join game_answers a on a.game_id = g.id and a.position = o.pos - 1)
  );
end $$;

-- get_today: incluye el tema del reto
create or replace function public.get_today() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid  uuid := _require_user();
  v_ch   challenges%rowtype;
  v_game games%rowtype;
begin
  select * into v_ch from challenges where challenge_date = _today();
  if not found then
    return jsonb_build_object('date', _today(), 'available', false);
  end if;
  select * into v_game from games where user_id = v_uid and challenge_date = v_ch.challenge_date;
  return jsonb_build_object(
    'date',          v_ch.challenge_date,
    'available',     true,
    'kind',          v_ch.kind,
    'title',         v_ch.title,
    'theme',         v_ch.theme,
    'max_points',    (select coalesce(sum(q.max_points), 0)
                        from unnest(v_ch.question_ids) qid join questions q on q.id = qid),
    'time_limit_ms', _cfg_int('question_time_ms'),
    'status',        case when v_game.id is null then 'not_started'
                          when v_game.finished_at is null then 'in_progress'
                          else 'finished' end,
    'game',          case when v_game.id is null then null else _game_summary(v_game.id) end,
    'jokers_left',   _jokers_left(v_uid),
    'profile',       _profile_json(v_uid)
  );
end $$;

revoke execute on function public._score_answer(public.questions, jsonb, integer, integer)
  from public, anon, authenticated;
revoke execute on function public._limit_for(public.questions) from public, anon, authenticated;
revoke execute on function public._questions_defaults() from public, anon, authenticated;
grant execute on function public.search_titles(text)       to authenticated;
grant execute on function public.next_question()           to authenticated;
grant execute on function public.submit_answer(integer, jsonb) to authenticated;
grant execute on function public.use_joker(integer)        to authenticated;
grant execute on function public.get_solutions(date)       to authenticated;
grant execute on function public.get_today()               to authenticated;
