-- =========================================================================
-- MIGRACIÓN 0011: medallas «Síguenos» en Instagram y Facebook
-- =========================================================================
-- Meta no permite premiar seguir una cuenta y tampoco se puede comprobar si
-- alguien sigue de verdad: la medalla se da al visitar el perfil desde la app
-- y es solo decorativa (0 puntos, no cuenta para el ranking).

insert into public.achievements (id, title_es, title_en, description_es, description_en, points, category, target_value) values
('social_instagram', 'Fan en Instagram', 'Instagram Fan',
 'Visita a DidacCine en Instagram desde el Quiz. Medalla especial: no suma puntos.',
 'Visit DidacCine on Instagram from the Quiz. Special medal: no points.', 0, 'social', 1),
('social_facebook', 'Fan en Facebook', 'Facebook Fan',
 'Visita a DidacCine en Facebook desde el Quiz. Medalla especial: no suma puntos.',
 'Visit DidacCine on Facebook from the Quiz. Special medal: no points.', 0, 'social', 1)
on conflict (id) do nothing;

-- Se llama al pulsar el botón de la red. Devuelve true si la medalla es nueva.
create or replace function public.claim_social(p_network text) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_id text := 'social_' || p_network;
  v_new integer;
begin
  if p_network not in ('instagram', 'facebook') then
    raise exception 'bad_network';
  end if;
  -- Los invitados no tienen perfil: la medalla se gana al registrarse.
  if auth.uid() is null or not exists (select 1 from profiles where id = auth.uid()) then
    return false;
  end if;
  insert into user_achievements (user_id, achievement_id) values (auth.uid(), v_id)
  on conflict do nothing;
  get diagnostics v_new = row_count;
  return v_new > 0;
end;
$$;

revoke execute on function public.claim_social(text) from public, anon;
grant execute on function public.claim_social(text) to authenticated;
