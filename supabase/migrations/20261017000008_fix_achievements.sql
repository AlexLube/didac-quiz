-- =========================================================================
-- MIGRACIÓN 0008: corrige la evaluación de logros de la 0007
-- =========================================================================
-- · El Hall of Fame buscaba challenges.id, que no existe: la fecha del reto
--   ya está en games.challenge_date. Ese error impedía terminar partidas.
-- · Los invitados no tienen perfil: no se les asignan logros todavía.
-- · Si algo falla al evaluar logros, la partida se termina igualmente.
-- · La racha se actualiza después de cerrar la partida: se vuelve a evaluar
--   cuando cambia la mejor racha del perfil, para dar el logro ese mismo día.

create or replace function public.evaluate_player_progress(p_user_id uuid)
returns void
language plpgsql
security definer
as $$
declare
    v_streak integer := 0;
    v_games_count integer := 0;
    v_master_count integer := 0;
    v_total_pts integer := 0;
    v_fast_count integer := 0;
    v_today_mmdd text := to_char((now() at time zone 'utc')::date, 'MM-DD');
    v_today_full text := to_char((now() at time zone 'utc')::date, 'YYYY-MM-DD');
    v_prev_month text := to_char(((now() at time zone 'utc')::date - interval '1 month'), 'YYYY-MM');
    v_special_pts integer;
    r record;
begin
    -- Los invitados aún no tienen perfil: sus logros se cuentan cuando se registren.
    if p_user_id is null or not exists (select 1 from public.profiles where id = p_user_id) then
        return;
    end if;

    select coalesce(streak_best, 0) into v_streak
    from public.profiles where id = p_user_id;

    select
        count(*),
        count(*) filter (where total_points >= 15),
        coalesce(sum(total_points), 0),
        count(*) filter (where total_ms > 0 and total_ms <= 90000)
    into v_games_count, v_master_count, v_total_pts, v_fast_count
    from public.games
    where user_id = p_user_id and finished_at is not null;

    -- Desbloquear logros cumplidos que aún no tenga el jugador
    for r in
        select a.id, a.points
        from public.achievements a
        where not exists (
            select 1 from public.user_achievements ua
            where ua.user_id = p_user_id and ua.achievement_id = a.id
        )
        and (
            (a.category = 'streak' and v_streak >= a.target_value) or
            (a.id like 'games_%' and v_games_count >= a.target_value) or
            (a.category = 'score' and v_master_count >= a.target_value) or
            (a.id like 'points_%' and v_total_pts >= a.target_value) or
            (a.category = 'media' and v_fast_count >= a.target_value)
        )
    loop
        insert into public.user_achievements (user_id, achievement_id)
        values (p_user_id, r.id)
        on conflict do nothing;

        update public.profiles
        set bonus_points = bonus_points + r.points
        where id = p_user_id;
    end loop;

    -- Recompensa de +1 punto extra si juega en Fecha Especial
    select bonus_points into v_special_pts
    from public.special_dates where date_key = v_today_mmdd;

    if v_special_pts is not null then
        if not exists (
            select 1 from public.user_special_bonuses
            where user_id = p_user_id and year_date = v_today_full
        ) then
            insert into public.user_special_bonuses (user_id, year_date, bonus_points)
            values (p_user_id, v_today_full, v_special_pts)
            on conflict do nothing;

            update public.profiles
            set bonus_points = bonus_points + v_special_pts
            where id = p_user_id;
        end if;
    end if;

    -- Archivar automáticamente el Top 3 del mes pasado en el Hall of Fame si aún no está guardado
    if not exists (select 1 from public.hall_of_fame where year_month = v_prev_month) then
        insert into public.hall_of_fame (year_month, position, user_id, alias, total_points)
        select
            v_prev_month,
            row_number() over (order by sum(g.total_points) desc, sum(g.total_ms) asc),
            p.id,
            coalesce(p.alias, 'Jugador'),
            sum(g.total_points)::integer
        from public.games g
        join public.profiles p on p.id = g.user_id
        where g.finished_at is not null
          and to_char(g.challenge_date, 'YYYY-MM') = v_prev_month
        group by p.id, p.alias
        order by sum(g.total_points) desc, sum(g.total_ms) asc
        limit 3
        on conflict do nothing;
    end if;
end;
$$;

create or replace function public.trg_games_evaluate_progress()
returns trigger
language plpgsql
security definer
as $$
begin
    if new.finished_at is not null then
        begin
            perform public.evaluate_player_progress(new.user_id);
        exception when others then
            raise warning 'evaluate_player_progress(%): %', new.user_id, sqlerrm;
        end;
    end if;
    return new;
end;
$$;

create or replace function public.trg_profiles_evaluate_progress()
returns trigger
language plpgsql
security definer
as $$
begin
    if new.streak_best is distinct from old.streak_best then
        begin
            perform public.evaluate_player_progress(new.id);
        exception when others then
            raise warning 'evaluate_player_progress(%): %', new.id, sqlerrm;
        end;
    end if;
    return new;
end;
$$;

drop trigger if exists trigger_check_streak_achievements on public.profiles;
create trigger trigger_check_streak_achievements
    after update of streak_best on public.profiles
    for each row
    execute function public.trg_profiles_evaluate_progress();
