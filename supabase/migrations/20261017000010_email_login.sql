-- Cuenta única: también se entra con un enlace al correo (sin contraseña).
alter table public.profiles drop constraint if exists profiles_auth_method_check;
alter table public.profiles add constraint profiles_auth_method_check
  check (auth_method in ('password', 'google', 'apple', 'email'));

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
  if p_auth_method not in ('password', 'google', 'apple', 'email') then
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
