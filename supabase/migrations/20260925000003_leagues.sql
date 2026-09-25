-- Didac-Quiz · Ligas privadas entre amigos
-- Se unen con un código de invitación. La clasificación usa las mismas
-- partidas del reto diario (no hay que jugar dos veces).

create table public.leagues (
  id          bigserial primary key,
  name        text not null check (char_length(trim(name)) between 3 and 40),
  invite_code text not null unique,
  owner_id    uuid not null references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now()
);

create table public.league_members (
  league_id bigint not null references public.leagues(id) on delete cascade,
  user_id   uuid   not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (league_id, user_id)
);
create index league_members_user_idx on public.league_members (user_id);

alter table public.leagues        enable row level security;
alter table public.league_members enable row level security;
revoke all on public.leagues, public.league_members from anon, authenticated;

insert into public.app_config (key, value) values
  ('league_max_members', '100'),
  ('leagues_per_user',   '20')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
create or replace function public._require_profile() returns uuid
language plpgsql stable security definer set search_path = public as $$
declare v uuid := _require_user();
begin
  if not exists (select 1 from profiles where id = v) then
    raise exception 'profile_required';
  end if;
  return v;
end $$;

create or replace function public._new_invite_code() returns text
language plpgsql volatile set search_path = public, extensions as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_code text;
  v_bytes bytea;
begin
  loop
    v_bytes := gen_random_bytes(6);
    v_code := '';
    for i in 0..5 loop
      v_code := v_code || substr(v_alphabet, (get_byte(v_bytes, i) % 32) + 1, 1);
    end loop;
    exit when not exists (select 1 from leagues where invite_code = v_code);
  end loop;
  return v_code;
end $$;

create or replace function public._league_json(p_league bigint, p_uid uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id',          l.id,
    'name',        l.name,
    'invite_code', l.invite_code,
    'is_owner',    l.owner_id = p_uid,
    'owner_alias', (select alias from profiles where id = l.owner_id),
    'members',     (select count(*) from league_members m where m.league_id = l.id),
    'created_at',  l.created_at
  )
  from leagues l where l.id = p_league
$$;

create or replace function public._check_league_limits(p_uid uuid) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if (select count(*) from league_members where user_id = p_uid) >= _cfg_int('leagues_per_user') then
    raise exception 'too_many_leagues';
  end if;
end $$;

-- ---------------------------------------------------------------------------
create or replace function public.create_league(p_name text) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_uid uuid := _require_profile();
  v_id  bigint;
begin
  if p_name is null or char_length(trim(p_name)) not between 3 and 40 then
    raise exception 'invalid_league_name';
  end if;
  if exists (select 1 from banned_words
              where position(word in lower(regexp_replace(p_name, '[^[:alnum:]]', '', 'g'))) > 0) then
    raise exception 'invalid_league_name';
  end if;
  perform _check_league_limits(v_uid);
  insert into leagues (name, invite_code, owner_id)
  values (trim(p_name), _new_invite_code(), v_uid)
  returning id into v_id;
  insert into league_members (league_id, user_id) values (v_id, v_uid);
  return _league_json(v_id, v_uid);
end $$;

create or replace function public.join_league(p_code text) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_uid uuid := _require_profile();
  v_l   leagues%rowtype;
begin
  select * into v_l from leagues where invite_code = _normalize_code(p_code);
  if not found then raise exception 'league_not_found'; end if;
  if exists (select 1 from league_members where league_id = v_l.id and user_id = v_uid) then
    return _league_json(v_l.id, v_uid);
  end if;
  perform _check_league_limits(v_uid);
  if (select count(*) from league_members where league_id = v_l.id) >= _cfg_int('league_max_members') then
    raise exception 'league_full';
  end if;
  insert into league_members (league_id, user_id) values (v_l.id, v_uid);
  return _league_json(v_l.id, v_uid);
end $$;

create or replace function public.my_leagues() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(_league_json(m.league_id, m.user_id) order by m.joined_at), '[]'::jsonb)
    from league_members m where m.user_id = _require_user()
$$;

-- Salir de una liga. Si sale el creador, la liga pasa al miembro más antiguo;
-- si no queda nadie, se borra.
create or replace function public.leave_league(p_league bigint) returns void
language plpgsql volatile security definer set search_path = public as $$
declare
  v_uid uuid := _require_user();
  v_next uuid;
begin
  delete from league_members where league_id = p_league and user_id = v_uid;
  if not found then raise exception 'not_a_member'; end if;
  if (select owner_id from leagues where id = p_league) = v_uid then
    select user_id into v_next from league_members
     where league_id = p_league order by joined_at limit 1;
    if v_next is null then
      delete from leagues where id = p_league;
    else
      update leagues set owner_id = v_next where id = p_league;
    end if;
  end if;
end $$;

create or replace function public.remove_league_member(p_league bigint, p_alias text) returns void
language plpgsql volatile security definer set search_path = public as $$
declare
  v_uid    uuid := _require_user();
  v_target uuid;
begin
  if (select owner_id from leagues where id = p_league) is distinct from v_uid then
    raise exception 'not_league_owner';
  end if;
  select id into v_target from profiles where lower(alias) = lower(p_alias);
  if v_target is null or v_target = v_uid then raise exception 'not_a_member'; end if;
  delete from league_members where league_id = p_league and user_id = v_target;
  if not found then raise exception 'not_a_member'; end if;
end $$;

create or replace function public.delete_league(p_league bigint) returns void
language plpgsql volatile security definer set search_path = public as $$
begin
  delete from leagues where id = p_league and owner_id = _require_user();
  if not found then raise exception 'not_league_owner'; end if;
end $$;

-- Al borrar la cuenta, las ligas que creó pasan a otro miembro en vez de borrarse.
create or replace function public.delete_my_account() returns void
language plpgsql volatile security definer set search_path = public as $$
declare
  v_uid uuid := _require_user();
  v_l   bigint;
begin
  for v_l in select league_id from league_members where user_id = v_uid loop
    perform leave_league(v_l);
  end loop;
  update reports set user_id = null where user_id = v_uid;
  delete from auth.users where id = v_uid;
end $$;

-- Clasificación de una liga: mismo formato que get_leaderboard. Aparecen todos
-- los miembros, también los que aún no han jugado en el periodo (con 0 puntos).
create or replace function public.league_leaderboard(
  p_league bigint, p_period text, p_date date default null
) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid  uuid := _require_user();
  v_date date := coalesce(p_date, _today());
  v_from date;
  v_to   date;
  v_minor_year integer := extract(year from _today())::integer - _cfg_int('minor_age');
  v_result jsonb;
begin
  if not exists (select 1 from league_members where league_id = p_league and user_id = v_uid) then
    raise exception 'not_a_member';
  end if;
  case p_period
    when 'day'   then v_from := v_date; v_to := v_date;
    when 'week'  then v_from := date_trunc('week', v_date)::date;  v_to := v_from + 6;
    when 'month' then v_from := date_trunc('month', v_date)::date;
                      v_to := (v_from + interval '1 month' - interval '1 day')::date;
    when 'all'   then v_from := date '2000-01-01'; v_to := v_date;
    else raise exception 'invalid_period';
  end case;

  with scores as (
    select m.user_id,
           coalesce(sum(g.total_points), 0)::integer as pts,
           coalesce(sum(g.total_ms), 0)::bigint as ms,
           count(g.id)::integer as games
      from league_members m
      left join games g on g.user_id = m.user_id and g.finished_at is not null
                       and g.challenge_date between v_from and v_to
     where m.league_id = p_league
     group by m.user_id
  ), ranked as (
    -- quien no ha jugado va al final, aunque su tiempo sea 0
    select s.*, rank() over (order by s.pts desc, (s.games = 0), s.ms asc) as rnk from scores s
  ), rows as (
    select r.rnk, r.user_id, jsonb_build_object(
             'rank',         r.rnk,
             'alias',        p.alias,
             'country_code', p.country_code,
             'city',         case when p.birth_year > v_minor_year then null else c.name end,
             'points',       r.pts,
             'ms',           r.ms,
             'games',        r.games,
             'is_me',        r.user_id = v_uid) as j
      from ranked r
      join profiles p on p.id = r.user_id
      join cities c on c.id = p.city_id
  )
  select jsonb_build_object(
    'scope',  'league',
    'period', p_period,
    'from',   v_from,
    'to',     v_to,
    'label',  jsonb_build_object('type', 'league', 'name', (select name from leagues where id = p_league)),
    'league', _league_json(p_league, v_uid),
    'total_players', (select count(*) from ranked),
    'top',    coalesce((select jsonb_agg(j order by rnk, j ->> 'alias') from rows), '[]'::jsonb),
    'me',     (select j from rows where user_id = v_uid),
    'around', '[]'::jsonb
  ) into v_result;
  return v_result;
end $$;

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

grant execute on function public.create_league(text)                            to authenticated;
grant execute on function public.join_league(text)                              to authenticated;
grant execute on function public.my_leagues()                                   to authenticated;
grant execute on function public.leave_league(bigint)                           to authenticated;
grant execute on function public.remove_league_member(bigint, text)             to authenticated;
grant execute on function public.delete_league(bigint)                          to authenticated;
grant execute on function public.league_leaderboard(bigint, text, date)         to authenticated;

grant execute on function public.challenges_remaining()                         to service_role;
grant execute on function public.recalibrate_questions(integer)                 to service_role;
