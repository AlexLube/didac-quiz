-- =========================================================================
-- MIGRACIÓN 0007: 100 Logros, Hall of Fame Mensual y Fechas Especiales
-- =========================================================================

-- 1. Columnas de puntos extra por logros y bonificaciones en profiles
alter table public.profiles
    add column if not exists bonus_points integer not null default 0;

-- 2. Catálogo de 100 Logros (de 5 a 100 puntos)
create table if not exists public.achievements (
    id text primary key,
    title_es text not null,
    title_en text not null,
    description_es text not null,
    description_en text not null,
    points integer not null default 5,
    category text not null default 'general',
    target_value integer not null default 1,
    created_at timestamptz not null default now()
);

-- 3. Logros Desbloqueados por cada jugador
create table if not exists public.user_achievements (
    user_id uuid not null references public.profiles(id) on delete cascade,
    achievement_id text not null references public.achievements(id) on delete cascade,
    unlocked_at timestamptz not null default now(),
    primary key (user_id, achievement_id)
);

-- 4. Hall of Fame (Top 3 de cada mes)
create table if not exists public.hall_of_fame (
    year_month text not null, -- 'YYYY-MM'
    position integer not null check (position between 1 and 3),
    user_id uuid references public.profiles(id) on delete set null,
    alias text not null,
    total_points integer not null default 0,
    created_at timestamptz not null default now(),
    primary key (year_month, position)
);

-- 5. Fechas Especiales (6 al año, +1 punto extra al jugar ese día)
create table if not exists public.special_dates (
    date_key text primary key, -- 'MM-DD'
    name_es text not null,
    name_en text not null,
    bonus_points integer not null default 1
);

create table if not exists public.user_special_bonuses (
    user_id uuid not null references public.profiles(id) on delete cascade,
    year_date text not null, -- 'YYYY-MM-DD'
    bonus_points integer not null default 1,
    claimed_at timestamptz not null default now(),
    primary key (user_id, year_date)
);

alter table public.achievements enable row level security;
alter table public.user_achievements enable row level security;
alter table public.hall_of_fame enable row level security;
alter table public.special_dates enable row level security;
alter table public.user_special_bonuses enable row level security;

drop policy if exists "ach_read" on public.achievements;
create policy "ach_read" on public.achievements for select using (true);

drop policy if exists "uach_read" on public.user_achievements;
create policy "uach_read" on public.user_achievements for select using (true);

drop policy if exists "hof_read" on public.hall_of_fame;
create policy "hof_read" on public.hall_of_fame for select using (true);

drop policy if exists "sdate_read" on public.special_dates;
create policy "sdate_read" on public.special_dates for select using (true);

drop policy if exists "ubonus_read" on public.user_special_bonuses;
create policy "ubonus_read" on public.user_special_bonuses for select using (true);

-- 6. Poblar las 6 Fechas Especiales del año (+1 punto extra)
insert into public.special_dates (date_key, name_es, name_en, bonus_points) values
('01-01', 'Año Nuevo de Cine', 'New Year Cinema Day', 1),
('02-14', 'San Valentín de Película', 'Valentine Movie Day', 1),
('10-31', 'Noche de Terror (Halloween)', 'Halloween Horror Night', 1),
('12-01', 'Aniversario DidacCine', 'DidacCine Anniversary', 1),
('12-25', 'Especial de Navidad', 'Christmas Special', 1),
('12-28', 'Día Mundial del Cinematógrafo', 'World Cinematograph Day', 1)
on conflict (date_key) do nothing;

-- 7. Generar los 100 Logros (repartidos en 5 familias de 20 logros, de 5 a 100 pts)
do $$
declare
    i integer;
    v_pts integer;
    v_days integer[] := array[1,2,3,5,7,10,14,21,30,45,60,75,90,120,150,180,210,250,300,365];
    v_games integer[] := array[1,3,5,10,15,20,30,40,50,65,80,100,125,150,175,200,250,300,400,500];
    v_perfect integer[] := array[1,2,3,5,7,10,15,20,25,30,40,50,60,75,90,110,130,150,175,200];
    v_score integer[] := array[15,30,50,80,120,160,220,300,400,500,650,800,1000,1250,1500,1800,2200,2600,3000,4000];
    v_fast integer[] := array[1,2,3,5,8,12,16,20,25,30,40,50,65,80,100,120,140,160,180,200];
begin
    for i in 1..20 loop
        v_pts := least(100, 5 * i);
        -- Familia 1: Rachas (20 logros)
        insert into public.achievements (id, title_es, title_en, description_es, description_en, points, category, target_value)
        values (
            'streak_' || v_days[i],
            'Racha de ' || v_days[i] || ' días',
            v_days[i] || '-Day Streak',
            'Juega ' || v_days[i] || ' días seguidos sin fallar.',
            'Play ' || v_days[i] || ' consecutive days.',
            v_pts, 'streak', v_days[i]
        ) on conflict (id) do nothing;

        -- Familia 2: Partidas jugadas (20 logros)
        insert into public.achievements (id, title_es, title_en, description_es, description_en, points, category, target_value)
        values (
            'games_' || v_games[i],
            'Butaca #' || v_games[i],
            'Seat #' || v_games[i],
            'Completa ' || v_games[i] || ' retos diarios de cine.',
            'Complete ' || v_games[i] || ' daily movie challenges.',
            v_pts, 'milestone', v_games[i]
        ) on conflict (id) do nothing;

        -- Familia 3: Rondas excelentes >=15 pts (20 logros)
        insert into public.achievements (id, title_es, title_en, description_es, description_en, points, category, target_value)
        values (
            'master_' || v_perfect[i],
            'Crítico Experto ' || i,
            'Master Critic ' || i,
            'Consigue 15 o más puntos en ' || v_perfect[i] || ' retos.',
            'Score 15 or more points in ' || v_perfect[i] || ' challenges.',
            v_pts, 'score', v_perfect[i]
        ) on conflict (id) do nothing;

        -- Familia 4: Puntos acumulados (20 logros)
        insert into public.achievements (id, title_es, title_en, description_es, description_en, points, category, target_value)
        values (
            'points_' || v_score[i],
            'Taquilla de ' || v_score[i] || ' pts',
            v_score[i] || ' pts Box Office',
            'Acumula un total de ' || v_score[i] || ' puntos en el juego.',
            'Accumulate a total of ' || v_score[i] || ' points.',
            v_pts, 'milestone', v_score[i]
        ) on conflict (id) do nothing;

        -- Familia 5: Partidas sin usar comodines / veloces (20 logros)
        insert into public.achievements (id, title_es, title_en, description_es, description_en, points, category, target_value)
        values (
            'clean_' || v_fast[i],
            'Sin Guion ' || i,
            'Unscripted ' || i,
            'Termina ' || v_fast[i] || ' partidas en menos de 90 segundos.',
            'Finish ' || v_fast[i] || ' games in under 90 seconds.',
            v_pts, 'media', v_fast[i]
        ) on conflict (id) do nothing;
    end loop;
end $$;

-- 8. Función automática que evalúa logros, fechas especiales y Hall of Fame
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
    if p_user_id is null then
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
        join public.challenges c on c.id = g.challenge_id
        where g.finished_at is not null
          and to_char(c.challenge_date, 'YYYY-MM') = v_prev_month
        group by p.id, p.alias
        order by sum(g.total_points) desc, sum(g.total_ms) asc
        limit 3
        on conflict do nothing;
    end if;
end;
$$;

-- 9. Trigger automático al terminar partida
create or replace function public.trg_games_evaluate_progress()
returns trigger
language plpgsql
security definer
as $$
begin
    if new.finished_at is not null then
        perform public.evaluate_player_progress(new.user_id);
    end if;
    return new;
end;
$$;

drop trigger if exists trigger_check_achievements on public.games;
create trigger trigger_check_achievements
    after insert or update of finished_at on public.games
    for each row
    execute function public.trg_games_evaluate_progress();
