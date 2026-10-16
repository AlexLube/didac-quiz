-- =========================================================================
-- TRIGGER: Automatizar logros al terminar una partida
-- =========================================================================

create or replace function public.trg_check_achievements_on_game()
returns trigger
language plpgsql
security definer
as $$
begin
    -- Cada vez que se inserta o actualiza una partida, comprobamos los logros del usuario
    perform public.check_and_unlock_achievements(new.profile_id);
    return new;
end;
$$;

-- Asociar el trigger a la tabla de partidas (games)
drop trigger if exists trigger_check_achievements on public.games;
create trigger trigger_check_achievements
    after insert or update on public.games
    for each row
    execute function public.trg_check_achievements_on_game();
