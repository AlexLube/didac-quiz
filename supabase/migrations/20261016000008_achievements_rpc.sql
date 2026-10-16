-- =========================================================================
-- FUNCIÓN RPC: Comprobar y desbloquear logros automáticamente
-- =========================================================================

create or replace function public.check_and_unlock_achievements(p_profile_id uuid)
returns json
language plpgsql
security definer
as $$
declare
    v_streak integer;
    v_total_points integer;
    v_unlocked_count integer := 0;
    v_ach record;
begin
    -- 1. Obtener datos actuales del perfil del usuario
    select streak_current, total_points 
    into v_streak, v_total_points
    from public.profiles
    where id = p_profile_id;

    if not found then
        raise exception 'Perfil no encontrado';
    end if;

    -- 2. Evaluar logros basados en racha (streak)
    if v_streak >= 3 then
        perform public.internal_unlock_achievement(p_profile_id, 'streak_3');
    end if;
    if v_streak >= 7 then
        perform public.internal_unlock_achievement(p_profile_id, 'streak_7');
    end if;
    if v_streak >= 30 then
        perform public.internal_unlock_achievement(p_profile_id, 'streak_30');
    end if;

    -- 3. Evaluar logros basados en puntos totales (ej: Leyenda con 1000 pts)
    if v_total_points >= 1000 then
        perform public.internal_unlock_achievement(p_profile_id, 'legend_1000');
    end if;

    -- Devolver los logros desbloqueados recientemente o estado OK
    return json_build_object('success', true, 'streak', v_streak);
end;
$$;

-- Función interna auxiliar para insertar el logro de forma segura si no lo tenía
create or replace function public.internal_unlock_achievement(p_profile_id uuid, p_achievement_id text)
returns void
language plpgsql
security definer
as $$
declare
    v_points integer;
begin
    -- Comprobar si ya lo tiene desbloqueado
    if exists (
        select 1 from public.user_achievements 
        where profile_id = p_profile_id and achievement_id = p_achievement_id
    ) then
        return;
    end if;

    -- Obtener los puntos que otorga este logro
    select points into v_points from public.achievements where id = p_achievement_id;
    if not found then
        return;
    end if;

    -- Insertar en user_achievements
    insert into public.user_achievements (profile_id, achievement_id)
    values (p_profile_id, p_achievement_id)
    on conflict do nothing;

    -- Sumar los puntos del logro al total de puntos del perfil del usuario
    update public.profiles
    set total_points = total_points + v_points
    where id = p_profile_id;
end;
$$;
