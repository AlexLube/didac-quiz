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
