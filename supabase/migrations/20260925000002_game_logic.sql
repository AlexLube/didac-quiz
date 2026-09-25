-- Didac-Quiz · Lógica de juego en el servidor
-- La app solo llama a estas funciones (RPC). Nunca recibe la respuesta correcta
-- antes de contestar, y el tiempo lo mide siempre el servidor.

-- ---------------------------------------------------------------------------
-- Utilidades internas
-- ---------------------------------------------------------------------------
create or replace function public._cfg_int(p_key text) returns integer
language sql stable security definer set search_path = public as $$
  select (value #>> '{}')::integer from app_config where key = p_key
$$;

create or replace function public._today() returns date
language sql stable as $$
  select (now() at time zone 'utc')::date
$$;

create or replace function public._require_user() returns uuid
language plpgsql stable as $$
declare v uuid := auth.uid();
begin
  if v is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  return v;
end $$;

create or replace function public._jokers_left(p_uid uuid) returns integer
language sql stable security definer set search_path = public as $$
  select greatest(_cfg_int('jokers_per_week') - count(*)::integer, 0)
  from game_answers a
  join games g on g.id = a.game_id
  where g.user_id = p_uid
    and a.joker_used
    and g.challenge_date >= date_trunc('week', _today())::date   -- lunes 00:00 UTC
$$;

create or replace function public._new_recovery_code() returns text
language plpgsql volatile set search_path = public, extensions as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';   -- sin 0/O ni 1/I
  v_bytes bytea := gen_random_bytes(12);
  v_code text := '';
begin
  for i in 0..11 loop
    v_code := v_code || substr(v_alphabet, (get_byte(v_bytes, i) % 32) + 1, 1);
    if i in (3, 7) then v_code := v_code || '-'; end if;
  end loop;
  return v_code;   -- formato XXXX-XXXX-XXXX
end $$;

create or replace function public._normalize_code(p_code text) returns text
language sql immutable as $$
  select upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'))
$$;

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
    'max_points',   (select coalesce(sum(q.difficulty), 0)
                       from challenges c, unnest(c.question_ids) qid
                       join questions q on q.id = qid
                      where c.challenge_date = g.challenge_date),
    'total_ms',     g.total_ms,
    'answers',      coalesce((
                      select jsonb_agg(jsonb_build_object(
                               'position',   a.position,
                               'difficulty', q.difficulty,
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

create or replace function public._finish_game(p_game bigint) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_game games%rowtype;
  v_p    profiles%rowtype;
begin
  update games set finished_at = now() where id = p_game returning * into v_game;
  select * into v_p from profiles where id = v_game.user_id for update;
  if not found then
    return;    -- invitado: sin racha hasta que cree cuenta
  end if;

  if v_p.last_played_date = v_game.challenge_date then
    return;
  elsif v_p.last_played_date = v_game.challenge_date - 1 then
    v_p.streak_current := v_p.streak_current + 1;
  else
    if v_p.streak_current > 1 then
      v_p.streak_lost    := v_p.streak_current;
      v_p.streak_lost_on := v_game.challenge_date;
    end if;
    v_p.streak_current := 1;
  end if;

  update profiles set
    streak_current   = v_p.streak_current,
    streak_best      = greatest(v_p.streak_best, v_p.streak_current),
    streak_lost      = v_p.streak_lost,
    streak_lost_on   = v_p.streak_lost_on,
    last_played_date = v_game.challenge_date
  where id = v_p.id;
end $$;

create or replace function public._close_answer(
  p_game bigint, p_position smallint, p_given jsonb, p_elapsed_ms integer
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_q       questions%rowtype;
  v_correct boolean;
  v_points  integer;
  v_game    games%rowtype;
begin
  select q.* into v_q
    from game_answers a join questions q on q.id = a.question_id
   where a.game_id = p_game and a.position = p_position;

  v_correct := p_given is not null and v_q.answer = p_given;
  v_points  := case when v_correct then v_q.difficulty else 0 end;

  update game_answers set
    answered_at = now(), given = p_given, correct = v_correct,
    points = v_points, elapsed_ms = p_elapsed_ms
  where game_id = p_game and position = p_position;

  update questions set
    times_shown   = times_shown + 1,
    times_correct = times_correct + v_correct::integer
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
    'correct',      v_correct,
    'points',       v_points,
    'total_points', v_game.total_points,
    'finished',     v_game.current_position >= 10
  );
end $$;

-- ---------------------------------------------------------------------------
-- Perfil
-- ---------------------------------------------------------------------------
create or replace function public._profile_json(p_uid uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'alias',            p.alias,
    'country_code',     p.country_code,
    'country_name',     jsonb_build_object('es', co.name_es, 'en', co.name_en),
    'city_id',          p.city_id,
    'city_name',        ci.name,
    'birth_year',       p.birth_year,
    'is_minor',         p.birth_year > extract(year from _today())::integer - _cfg_int('minor_age'),
    'auth_method',      p.auth_method,
    'streak_current',   case when p.last_played_date >= _today() - 1 then p.streak_current else 0 end,
    'streak_best',      p.streak_best,
    'last_played_date', p.last_played_date,
    'can_restore_streak',
        p.streak_lost is not null
        and p.streak_lost_on = p.last_played_date
        and p.last_played_date >= _today() - 1
        and (p.last_streak_restore is null
             or p.last_streak_restore <= _today() - _cfg_int('streak_restore_days')),
    'streak_lost',      p.streak_lost,
    'location_change_available_on',
        coalesce((p.location_changed_at at time zone 'utc')::date
                 + _cfg_int('location_change_days'), _today()),
    'created_at',       p.created_at
  )
  from profiles p
  join countries co on co.code = p.country_code
  join cities ci on ci.id = p.city_id
  where p.id = p_uid
$$;

create or replace function public.get_my_profile() returns jsonb
language sql stable security definer set search_path = public as $$
  select _profile_json(_require_user())
$$;

create or replace function public.is_alias_available(p_alias text) returns text
language plpgsql stable security definer set search_path = public as $$
begin
  if p_alias is null or p_alias !~ '^[A-Za-z0-9_.-]{3,20}$' then
    return 'invalid';
  end if;
  if exists (select 1 from banned_words
              where position(word in lower(regexp_replace(p_alias, '[_.-]', '', 'g'))) > 0) then
    return 'banned';
  end if;
  if exists (select 1 from profiles where lower(alias) = lower(p_alias)) then
    return 'taken';
  end if;
  return 'ok';
end $$;

create or replace function public._check_location(p_country char(2), p_city integer) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not exists (select 1 from cities where id = p_city and country_code = upper(p_country)) then
    raise exception 'invalid_location';
  end if;
end $$;

-- Crea el perfil de un usuario ya convertido en cuenta permanente
-- (usuario+contraseña, Google o Apple). Devuelve el código de recuperación
-- solo en cuentas con contraseña; no se vuelve a mostrar nunca.
create or replace function public.register_profile(
  p_alias text, p_country char(2), p_city integer, p_birth_year integer,
  p_auth_method text default 'password'
) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as $$
declare
  v_uid       uuid := _require_user();
  v_status    text;
  v_code      text;
  v_played    date;
begin
  if coalesce((select is_anonymous from auth.users where id = v_uid), true) then
    raise exception 'account_not_permanent';
  end if;
  if exists (select 1 from profiles where id = v_uid) then
    raise exception 'profile_exists';
  end if;
  if p_auth_method not in ('password', 'google', 'apple') then
    raise exception 'invalid_auth_method';
  end if;
  v_status := is_alias_available(p_alias);
  if v_status <> 'ok' then
    raise exception 'alias_%', v_status;
  end if;
  perform _check_location(p_country, p_city);
  if p_birth_year is null
     or p_birth_year < extract(year from _today())::integer - 110
     or p_birth_year > extract(year from _today())::integer - 4 then
    raise exception 'invalid_birth_year';
  end if;

  if p_auth_method = 'password' then
    v_code := _new_recovery_code();
  end if;

  -- Si jugó el reto de hoy como invitado, esa partida ya cuenta para la racha.
  select challenge_date into v_played from games
   where user_id = v_uid and finished_at is not null and challenge_date = _today();

  insert into profiles (id, alias, country_code, city_id, birth_year, auth_method,
                        recovery_code_hash, streak_current, streak_best, last_played_date)
  values (v_uid, p_alias, upper(p_country), p_city, p_birth_year, p_auth_method,
          case when v_code is null then null else crypt(_normalize_code(v_code), gen_salt('bf', 8)) end,
          case when v_played is null then 0 else 1 end,
          case when v_played is null then 0 else 1 end,
          v_played);

  return jsonb_build_object('profile', _profile_json(v_uid), 'recovery_code', v_code);
end $$;

create or replace function public.regenerate_recovery_code() returns text
language plpgsql volatile security definer set search_path = public, extensions as $$
declare
  v_uid  uuid := _require_user();
  v_code text := _new_recovery_code();
begin
  update profiles
     set recovery_code_hash = crypt(_normalize_code(v_code), gen_salt('bf', 8))
   where id = v_uid and auth_method = 'password';
  if not found then
    raise exception 'not_password_account';
  end if;
  return v_code;
end $$;

-- Recuperación sin email: alias + código → nueva contraseña y nuevo código.
-- Máximo 5 intentos fallidos; después, bloqueo de 15 minutos.
create or replace function public.recover_account(
  p_alias text, p_code text, p_new_password text
) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as $$
declare
  v_p    profiles%rowtype;
  v_code text;
begin
  if p_new_password is null or char_length(p_new_password) < 8 then
    raise exception 'weak_password';
  end if;
  select * into v_p from profiles
   where lower(alias) = lower(p_alias) and auth_method = 'password' for update;
  if not found then
    raise exception 'invalid_recovery';
  end if;
  if v_p.recovery_locked_until is not null and v_p.recovery_locked_until > now() then
    raise exception 'recovery_locked';
  end if;
  if v_p.recovery_code_hash is null
     or crypt(_normalize_code(p_code), v_p.recovery_code_hash) <> v_p.recovery_code_hash then
    update profiles set
      recovery_failed_attempts = recovery_failed_attempts + 1,
      recovery_locked_until = case when recovery_failed_attempts + 1 >= 5
                                   then now() + interval '15 minutes' end
    where id = v_p.id;
    return jsonb_build_object('ok', false);
  end if;

  v_code := _new_recovery_code();
  update auth.users
     set encrypted_password = crypt(p_new_password, gen_salt('bf', 10)),
         updated_at = now()
   where id = v_p.id;
  update profiles set
    recovery_code_hash = crypt(_normalize_code(v_code), gen_salt('bf', 8)),
    recovery_failed_attempts = 0,
    recovery_locked_until = null
  where id = v_p.id;
  return jsonb_build_object('ok', true, 'recovery_code', v_code);
end $$;

create or replace function public.update_location(p_country char(2), p_city integer) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_uid uuid := _require_user();
  v_p   profiles%rowtype;
begin
  select * into v_p from profiles where id = v_uid for update;
  if not found then raise exception 'profile_required'; end if;
  if v_p.location_changed_at is not null
     and v_p.location_changed_at > now() - make_interval(days => _cfg_int('location_change_days')) then
    raise exception 'location_change_too_soon';
  end if;
  perform _check_location(p_country, p_city);
  update profiles set country_code = upper(p_country), city_id = p_city, location_changed_at = now()
   where id = v_uid;
  return _profile_json(v_uid);
end $$;

create or replace function public.search_cities(
  p_country char(2), p_query text default '', p_limit integer default 20
) returns table (id integer, name text, population integer)
language sql stable security definer set search_path = public as $$
  select c.id, c.name, c.population
    from cities c
   where c.country_code = upper(p_country)
     and (coalesce(p_query, '') = '' or lower(c.name) like lower(p_query) || '%'
          or lower(c.name) like '% ' || lower(p_query) || '%')
   order by c.population desc, c.name
   limit least(greatest(coalesce(p_limit, 20), 1), 50)
$$;

create or replace function public.restore_streak() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_uid uuid := _require_user();
  v_ok  boolean;
begin
  select (_profile_json(v_uid) ->> 'can_restore_streak')::boolean into v_ok;
  if not coalesce(v_ok, false) then
    raise exception 'streak_restore_unavailable';
  end if;
  update profiles set
    streak_current      = streak_lost + streak_current,
    streak_best         = greatest(streak_best, streak_lost + streak_current),
    streak_lost         = null,
    streak_lost_on      = null,
    last_streak_restore = _today()
  where id = v_uid;
  return _profile_json(v_uid);
end $$;

create or replace function public.delete_my_account() returns void
language plpgsql volatile security definer set search_path = public as $$
declare v_uid uuid := _require_user();
begin
  update reports set user_id = null where user_id = v_uid;
  delete from auth.users where id = v_uid;   -- borra en cascada perfil y partidas
end $$;

-- ---------------------------------------------------------------------------
-- Juego
-- ---------------------------------------------------------------------------
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
    'time_limit_ms', _cfg_int('question_time_ms'),
    'status',        case when v_game.id is null then 'not_started'
                          when v_game.finished_at is null then 'in_progress'
                          else 'finished' end,
    'game',          case when v_game.id is null then null else _game_summary(v_game.id) end,
    'jokers_left',   _jokers_left(v_uid),
    'profile',       _profile_json(v_uid)
  );
end $$;

-- Entrega la pregunta en curso (o la siguiente). Si el jugador cerró la app y
-- el tiempo ya se agotó, esa pregunta cuenta como fallo y se pasa a la siguiente.
create or replace function public.next_question() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_uid     uuid := _require_user();
  v_ch      challenges%rowtype;
  v_game    games%rowtype;
  v_ans     game_answers%rowtype;
  v_q       questions%rowtype;
  v_limit   integer := _cfg_int('question_time_ms');
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

    v_elapsed := (extract(epoch from (clock_timestamp() - v_ans.served_at)) * 1000)::integer;
    if v_elapsed > v_limit + v_grace then
      perform _close_answer(v_game.id, v_ans.position, null, v_limit);
      select * into v_game from games where id = v_game.id;
      continue;
    end if;

    select * into v_q from questions where id = v_ans.question_id;
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
  v_limit   integer := _cfg_int('question_time_ms');
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

  v_elapsed := (extract(epoch from (clock_timestamp() - v_ans.served_at)) * 1000)::integer;
  if v_elapsed > v_limit + v_grace then
    return _close_answer(v_game.id, v_ans.position, null, v_limit)
           || jsonb_build_object('timeout', true);
  end if;
  return _close_answer(v_game.id, v_ans.position, p_answer, least(v_elapsed, v_limit))
         || jsonb_build_object('timeout', false);
end $$;

-- Comodín 50/50: gratis, 3 por semana (se reinicia el lunes a las 00:00 UTC).
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
  if v_q.format not in ('choice', 'intruder', 'decade', 'clues', 'image_choice', 'image_reveal')
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

create or replace function public.get_game_summary(p_date date default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select _game_summary(g.id) from games g
   where g.user_id = _require_user() and g.challenge_date = coalesce(p_date, _today())
$$;

-- Soluciones: solo de retos ya cerrados para todo el mundo (días anteriores).
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

create or replace function public.report_question(p_question_id bigint, p_reason text) returns void
language plpgsql volatile security definer set search_path = public as $$
declare v_uid uuid := _require_user();
begin
  if not exists (select 1 from game_answers a join games g on g.id = a.game_id
                  where g.user_id = v_uid and a.question_id = p_question_id) then
    raise exception 'question_not_seen';
  end if;
  if (select count(*) from reports where user_id = v_uid and created_at > now() - interval '1 day') >= 20 then
    raise exception 'too_many_reports';
  end if;
  insert into reports (question_id, user_id, reason)
  values (p_question_id, v_uid, left(trim(p_reason), 500));
end $$;

-- ---------------------------------------------------------------------------
-- Rankings: 3 ámbitos (world, country, city) × 4 periodos (day, week, month, all)
-- Desempate: menos tiempo total. Ciudades con pocos jugadores se agrupan por región.
-- ---------------------------------------------------------------------------
create or replace function public.get_leaderboard(
  p_scope text, p_period text, p_date date default null, p_limit integer default 100
) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid        uuid := _require_user();
  v_date       date := coalesce(p_date, _today());
  v_from       date;
  v_to         date;
  v_me         profiles%rowtype;
  v_country    char(2);
  v_city       integer;
  v_region     text;
  v_label      jsonb;
  v_minor_year integer := extract(year from _today())::integer - _cfg_int('minor_age');
  v_limit      integer := least(greatest(coalesce(p_limit, 100), 1), 200);
  v_result     jsonb;
begin
  case p_period
    when 'day'   then v_from := v_date; v_to := v_date;
    when 'week'  then v_from := date_trunc('week', v_date)::date;  v_to := v_from + 6;
    when 'month' then v_from := date_trunc('month', v_date)::date;
                      v_to := (v_from + interval '1 month' - interval '1 day')::date;
    when 'all'   then v_from := date '2000-01-01'; v_to := v_date;
    else raise exception 'invalid_period';
  end case;

  select * into v_me from profiles where id = v_uid;

  case p_scope
    when 'world' then
      v_label := jsonb_build_object('type', 'world');
    when 'country' then
      if v_me.id is null then raise exception 'profile_required'; end if;
      v_country := v_me.country_code;
      v_label := (select jsonb_build_object('type', 'country', 'code', code,
                                            'name', jsonb_build_object('es', name_es, 'en', name_en))
                    from countries where code = v_country);
    when 'city' then
      if v_me.id is null then raise exception 'profile_required'; end if;
      if (select count(*) from profiles where city_id = v_me.city_id and not excluded_from_rankings)
         >= _cfg_int('min_city_players') then
        v_city := v_me.city_id;
        v_label := (select jsonb_build_object('type', 'city', 'name', name) from cities where id = v_city);
      else
        v_region := (select region_code from cities where id = v_me.city_id);
        v_label := (select jsonb_build_object('type', 'region', 'name', name)
                      from cities where region_code = v_region
                     order by population desc limit 1);
      end if;
    else raise exception 'invalid_scope';
  end case;

  with scores as (
    select g.user_id, sum(g.total_points)::integer as pts, sum(g.total_ms)::bigint as ms,
           count(*)::integer as games
      from games g
      join profiles p on p.id = g.user_id
     where g.finished_at is not null
       and g.challenge_date between v_from and v_to
       and not p.excluded_from_rankings
       and (v_country is null or p.country_code = v_country)
       and (v_city is null or p.city_id = v_city)
       and (v_region is null or p.city_id in (select id from cities where region_code = v_region))
     group by g.user_id
  ), ranked as (
    select s.*, rank() over (order by s.pts desc, s.ms asc) as rnk from scores s
  ), rows as (
    select r.rnk, jsonb_build_object(
             'rank',         r.rnk,
             'alias',        p.alias,
             'country_code', p.country_code,
             'city',         case when p.birth_year > v_minor_year then null else c.name end,
             'points',       r.pts,
             'ms',           r.ms,
             'games',        r.games,
             'is_me',        r.user_id = v_uid) as j,
           r.user_id
      from ranked r
      join profiles p on p.id = r.user_id
      join cities c on c.id = p.city_id
  ), me as (
    select rnk from ranked where user_id = v_uid
  )
  select jsonb_build_object(
    'scope',  p_scope,
    'period', p_period,
    'from',   v_from,
    'to',     v_to,
    'label',  v_label,
    'total_players', (select count(*) from ranked),
    'top',    coalesce((select jsonb_agg(j order by rnk, j ->> 'alias')
                          from (select * from rows order by rnk limit v_limit) t), '[]'::jsonb),
    'me',     (select j from rows where user_id = v_uid),
    'around', coalesce((select jsonb_agg(j order by rnk, j ->> 'alias') from rows
                         where (select rnk from me) > v_limit
                           and rnk between (select rnk from me) - 2 and (select rnk from me) + 2),
                       '[]'::jsonb)
  ) into v_result;

  return v_result;
end $$;

-- ---------------------------------------------------------------------------
-- Mantenimiento (solo service_role: pipeline y tareas programadas)
-- ---------------------------------------------------------------------------
create or replace function public.challenges_remaining() returns integer
language sql stable security definer set search_path = public as $$
  -- días consecutivos a partir de hoy que ya tienen reto programado
  select count(*)::integer from (
    select d, bool_and(c.challenge_date is not null) over (order by d) as ok
      from generate_series(_today(), _today() + 730, interval '1 day') d
      left join challenges c on c.challenge_date = d::date
  ) s where ok
$$;

-- Reclasifica la dificultad según el porcentaje real de acierto.
create or replace function public.recalibrate_questions(p_min_shown integer default 200) returns integer
language plpgsql volatile security definer set search_path = public as $$
declare v_count integer;
begin
  with updated as (
    update questions set difficulty = case
        when times_correct::numeric / times_shown >= 0.75 then 1
        when times_correct::numeric / times_shown >= 0.40 then 2
        else 3 end
     where times_shown >= p_min_shown
       and difficulty is distinct from case
        when times_correct::numeric / times_shown >= 0.75 then 1
        when times_correct::numeric / times_shown >= 0.40 then 2
        else 3 end
    returning 1)
  select count(*) into v_count from updated;
  return v_count;
end $$;

-- ---------------------------------------------------------------------------
-- Permisos de ejecución
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema public from public, anon, authenticated;

grant execute on function public.is_alias_available(text)                       to anon, authenticated;
grant execute on function public.recover_account(text, text, text)              to anon, authenticated;
grant execute on function public.search_cities(char, text, integer)             to anon, authenticated;

grant execute on function public.get_my_profile()                               to authenticated;
grant execute on function public.register_profile(text, char, integer, integer, text) to authenticated;
grant execute on function public.regenerate_recovery_code()                     to authenticated;
grant execute on function public.update_location(char, integer)                 to authenticated;
grant execute on function public.restore_streak()                               to authenticated;
grant execute on function public.delete_my_account()                            to authenticated;
grant execute on function public.get_today()                                    to authenticated;
grant execute on function public.next_question()                                to authenticated;
grant execute on function public.submit_answer(integer, jsonb)                  to authenticated;
grant execute on function public.use_joker(integer)                             to authenticated;
grant execute on function public.get_game_summary(date)                         to authenticated;
grant execute on function public.get_solutions(date)                            to authenticated;
grant execute on function public.report_question(bigint, text)                  to authenticated;
grant execute on function public.get_leaderboard(text, text, date, integer)     to authenticated;

grant execute on function public.challenges_remaining()                         to service_role;
grant execute on function public.recalibrate_questions(integer)                 to service_role;
