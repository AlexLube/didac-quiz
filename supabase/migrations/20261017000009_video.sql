-- =========================================================================
-- MIGRACIÓN 0009: preguntas con vídeo (tráiler oficial de YouTube)
-- =========================================================================
-- El vídeo va en extra = {"youtube": "<id>", "start": s, "end": s}: es un dato
-- público (la respuesta sigue en `answer`, que nunca viaja a la app).

alter table public.questions drop constraint if exists questions_format_check;
alter table public.questions add constraint questions_format_check check (format in
  ('choice', 'true_false', 'order', 'intruder', 'decade', 'clues', 'emoji',
   'image_choice', 'image_reveal', 'audio', 'video',
   'year_slider', 'versus', 'match', 'map', 'burst', 'typed_title', 'odd_images', 'pick_two'));

-- =========================================================================
-- Logros: progreso de cada jugador (para las barras de la pestaña Logros)
-- =========================================================================
create or replace function public.my_achievement_progress() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'streak_best',  coalesce((select streak_best from profiles where id = auth.uid()), 0),
    'games',        count(*),
    'master',       count(*) filter (where total_points >= 15),
    'points',       coalesce(sum(total_points), 0),
    'fast',         count(*) filter (where total_ms > 0 and total_ms <= 90000),
    'bonus_points', coalesce((select bonus_points from profiles where id = auth.uid()), 0),
    'unlocked',     coalesce((select jsonb_agg(achievement_id order by unlocked_at)
                                from user_achievements where user_id = auth.uid()), '[]'::jsonb)
  )
  from games
  where user_id = auth.uid() and finished_at is not null
$$;

-- Permisos explícitos: la app lee el catálogo de logros y el Hall of Fame,
-- y nadie puede lanzar a mano la evaluación de logros de otra persona.
grant select on public.achievements, public.user_achievements, public.hall_of_fame,
  public.special_dates to anon, authenticated;
revoke execute on function public.evaluate_player_progress(uuid) from public, anon, authenticated;
revoke execute on function public.trg_games_evaluate_progress() from public, anon, authenticated;
revoke execute on function public.trg_profiles_evaluate_progress() from public, anon, authenticated;
grant execute on function public.my_achievement_progress() to anon, authenticated;
