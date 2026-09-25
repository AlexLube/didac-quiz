-- Palabras no permitidas en alias (se buscan como subcadena, sin _ . -).
-- Lista inicial breve: amplíala desde el panel de Supabase cuando haga falta.
insert into public.banned_words (word) values
  -- reservadas
  ('admin'), ('didacquiz'), ('didaccine'), ('moderador'), ('moderator'), ('soporte'), ('support'),
  -- ofensivas (es)
  ('puta'), ('puto'), ('mierda'), ('cabron'), ('gilipolla'), ('maricon'), ('polla'), ('coño'),
  ('follar'), ('zorra'), ('subnormal'),
  -- ofensivas (en)
  ('fuck'), ('shit'), ('bitch'), ('cunt'), ('whore'), ('slut'), ('dick'), ('pussy'), ('faggot'), ('nigg'),
  -- odio
  ('nazi'), ('hitler'), ('kkk')
on conflict do nothing;
