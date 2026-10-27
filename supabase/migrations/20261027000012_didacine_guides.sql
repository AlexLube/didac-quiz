-- =========================================================================
-- MIGRACIÓN 0012: «Llévala a clase» · enlace a la guía de DidacCine
-- =========================================================================
-- En las soluciones, si la película de la pregunta tiene guía publicada en
-- didacine.com, se devuelve su enlace (campo «guide»). La guía solo aparece
-- desde su fecha de estreno en la web, así que las programadas salen solas.
-- La película se reconoce por su título (normalizado con _norm_title) entre
-- las películas de la pregunta (entity_ids) y por el año (±1).
-- Lista sacada de la Cartelera de DidacCine el 27/10/2026 (126 guías).

create table if not exists public.didacine_guides (
  wp_id    integer primary key,
  title    text not null,
  year     smallint,
  release  date not null,
  url      text not null,
  norms    text[] not null default '{}'
);
alter table public.didacine_guides enable row level security;
revoke all on public.didacine_guides from anon, authenticated;

-- Variantes del título para casar con Wikidata: entero, sin paréntesis,
-- lo de dentro del paréntesis y lo de antes de «:».
create or replace function public._guide_norms(t text) returns text[]
language sql immutable as $$
  select array(select distinct n from unnest(array[
      _norm_title(t),
      _norm_title(regexp_replace(t, '\s*\(.*\)\s*', ' ', 'g')),
      _norm_title(substring(t from '\((.*)\)')),
      _norm_title(split_part(t, ':', 1))
    ]) n where n <> '')
$$;

create or replace function public._didacine_guide(p_entities text[]) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('title', g.title, 'url', g.url || case when position('?' in g.url) > 0 then '&' else '?' end
                                                        || 'utm_source=quiz&utm_medium=soluciones')
    from didacine_guides g
    join film_titles ft on ft.norm = any(g.norms) and ft.qid = any(p_entities)
   where g.release <= _today()
     -- Con año, ±1; sin año en Wikidata, solo si coincide el título entero.
     and (abs(ft.year - g.year) <= 1 or (ft.year is null and ft.norm = _norm_title(g.title)))
   order by array_position(p_entities, ft.qid), g.release desc
   limit 1
$$;
revoke all on function public._didacine_guide(text[]) from anon, authenticated;

insert into public.didacine_guides (wp_id, title, year, release, url) values
(43, 'El Rey León', 1994, date '2025-11-20', 'https://didacine.com/el-rey-leon/'),
(57, 'Del Revés (Inside Out)', 2015, date '2025-11-20', 'https://didacine.com/del-reves-inside-out/'),
(69, 'Regreso al Futuro', 1985, date '2025-11-21', 'https://didacine.com/regreso-al-futuro/'),
(59, 'Figuras Ocultas', 2016, date '2025-11-21', 'https://didacine.com/figuras-ocultas/'),
(165, 'Matilda', 1996, date '2025-11-22', 'https://didacine.com/matilda/'),
(167, 'Monstruos, S.A.', 2001, date '2025-11-22', 'https://didacine.com/monstruos-s-a/'),
(158, 'Gattaca', 1997, date '2025-11-22', 'https://didacine.com/gattaca/'),
(162, 'El Club de los Poetas Muertos', 1989, date '2025-11-22', 'https://didacine.com/el-club-de-los-poetas-muertos/'),
(155, 'El Show de Truman', 1998, date '2025-11-22', 'https://didacine.com/el-show-de-truman/'),
(138, 'Los Cretinos', 2025, date '2025-11-22', 'https://didacine.com/los-cretinos/'),
(330, 'Mi Vecino Totoro', 1988, date '2025-11-23', 'https://didacine.com/mi-vecino-totoro/'),
(351, 'El Gigante de Hierro', 1999, date '2025-11-24', 'https://didacine.com/el-gigante-de-hierro/'),
(386, 'Oppenheimer', 2023, date '2025-11-26', 'https://didacine.com/oppenheimer/'),
(432, 'Forrest Gump', 1994, date '2025-11-27', 'https://didacine.com/forrest-gump/'),
(413, 'Soul', 2020, date '2025-11-27', 'https://didacine.com/soul/'),
(438, 'Big Hero 6', 2014, date '2025-11-27', 'https://didacine.com/big-hero-6/'),
(426, 'La Llegada', 2016, date '2025-11-27', 'https://didacine.com/la-llegada/'),
(450, 'Tiempos Modernos', 1936, date '2025-11-27', 'https://didacine.com/tiempos-modernos/'),
(444, 'Intocable', 2011, date '2025-11-27', 'https://didacine.com/intocable/'),
(419, 'Encanto', 2021, date '2025-11-27', 'https://didacine.com/encanto/'),
(19, 'Matrix', 1999, date '2025-11-30', 'https://didacine.com/matrix/'),
(153, 'Blade Runner', 1982, date '2025-12-05', 'https://didacine.com/blade-runner/'),
(755, 'Klaus', 2019, date '2025-12-12', 'https://didacine.com/klaus/'),
(768, 'Feliz Navidad', 2005, date '2025-12-19', 'https://didacine.com/joyeux-noel/'),
(792, 'Cuento de Navidad', 2009, date '2025-12-26', 'https://didacine.com/cuento-de-navidad/'),
(1012, 'Hasta Que Me Quede Sin Voz', 2025, date '2025-12-31', 'https://didacine.com/hasta-que-me-quede-sin-voz/'),
(804, 'Arthur Christmas: Operación Regalo', 2011, date '2026-01-02', 'https://didacine.com/arthur-christmas-operacion-regalo/'),
(318, 'La Lista de Schindler', 1993, date '2026-01-09', 'https://didacine.com/la-lista-de-schindler/'),
(171, 'Fantástico Sr. Fox', 2009, date '2026-01-16', 'https://didacine.com/fantastico-sr-fox/'),
(861, 'Descifrando Enigma', 2014, date '2026-01-23', 'https://didacine.com/descifrando-enigma/'),
(908, 'Captain Fantastic', 2016, date '2026-01-30', 'https://didacine.com/captain-fantastic/'),
(924, 'Big Fish', 2003, date '2026-02-06', 'https://didacine.com/big-fish/'),
(405, 'Del Revés 2', 2024, date '2026-02-13', 'https://didacine.com/del-reves-2/'),
(850, 'Anatomía De Un Instante', 2025, date '2026-02-20', 'https://didacine.com/anatomia-de-un-instante/'),
(54, 'The Martian', 2015, date '2026-02-27', 'https://didacine.com/the-martian/'),
(1066, 'De Todos Lados Un Poco', 2025, date '2026-03-01', 'https://didacine.com/de-todos-lados-un-poco/'),
(888, 'Persepolis', 2007, date '2026-03-06', 'https://didacine.com/persepolis/'),
(1523, 'Hoppers', 2026, date '2026-03-13', 'https://didacine.com/hoppers/'),
(374, 'Interstellar', 2014, date '2026-03-20', 'https://didacine.com/interstellar/'),
(950, 'Las 13 Rosas', 2007, date '2026-03-27', 'https://didacine.com/las-13-rosas/'),
(1504, 'Proyecto Salvación', 2026, date '2026-04-03', 'https://didacine.com/1504-2/'),
(1041, 'Up', 2009, date '2026-04-10', 'https://didacine.com/up/'),
(1080, 'Billy Elliot', 2000, date '2026-04-17', 'https://didacine.com/billy-elliot/'),
(1095, 'El Viaje De Chihiro', 2001, date '2026-04-24', 'https://didacine.com/el-viaje-de-chihiro/'),
(1117, 'El Niño que domó el viento', 2019, date '2026-05-01', 'https://didacine.com/el-nino-que-domo-el-viento/'),
(1140, 'Mary Poppins', 1964, date '2026-05-08', 'https://didacine.com/mary-poppins/'),
(1168, 'Coco', 2017, date '2026-05-15', 'https://didacine.com/coco/'),
(1183, '12 Hombres Sin Piedad', 1957, date '2026-05-22', 'https://didacine.com/12-hombres-sin-piedad/'),
(1199, 'Paddington 2', 2017, date '2026-05-29', 'https://didacine.com/paddington-2/'),
(1216, 'Toy Story', 1995, date '2026-06-05', 'https://didacine.com/toy-story/'),
(1226, 'Campeones', 2018, date '2026-06-12', 'https://didacine.com/campeones/'),
(1280, 'Matar a un Ruiseñor', 1962, date '2026-06-19', 'https://didacine.com/matar-a-un-ruisenor/'),
(1298, 'Bichos', 1998, date '2026-06-26', 'https://didacine.com/bichos/'),
(1325, 'El Libro de la Selva', 2016, date '2026-07-03', 'https://didacine.com/el-libro-de-la-selva/'),
(1345, 'La Princesa Prometida', 1987, date '2026-07-10', 'https://didacine.com/la-princesa-prometida/'),
(1367, '101 Dálmatas', 1961, date '2026-07-17', 'https://didacine.com/101-dalmatas/'),
(1388, 'Buscando a Nemo', 2003, date '2026-07-24', 'https://didacine.com/1388-2/'),
(1416, 'Charlie y la Fabrica de Chocolate', 2005, date '2026-07-31', 'https://didacine.com/charlie-y-la-fabrica-de-chocolate/'),
(2397, 'Planeta Prehistorico', 2022, date '2026-08-05', 'https://didacine.com/planeta-prehistorico/'),
(1434, 'Pinocho', 1940, date '2026-08-07', 'https://didacine.com/pinocho/'),
(1451, 'Jumanji', 1995, date '2026-08-14', 'https://didacine.com/jumanji/'),
(978, 'Zootropolis', 2016, date '2026-08-21', 'https://didacine.com/zootropolis/'),
(169, 'Ponyo en el Acantilado', 2008, date '2026-08-28', 'https://didacine.com/ponyo-en-el-acantilado/'),
(1547, 'Red', 2022, date '2026-09-04', 'https://didacine.com/red/'),
(1568, 'Elemental', 2023, date '2026-09-11', 'https://didacine.com/elemental/'),
(1590, 'Robot Dreams', 2023, date '2026-09-18', 'https://didacine.com/robot-dreams/'),
(1613, 'Cinema Paradiso', 1988, date '2026-09-25', 'https://didacine.com/cinema-paradiso/'),
(1634, 'El Nombre De la Rosa', 1986, date '2026-10-02', 'https://didacine.com/el-nombre-de-la-rosa/'),
(1650, 'Cafarnaum', 2018, date '2026-10-09', 'https://didacine.com/cafarnaum/'),
(1665, 'Amigos Imaginarios', 2024, date '2026-10-16', 'https://didacine.com/amigos-imaginarios/'),
(1693, 'Orión y la Oscuridad', 2024, date '2026-10-23', 'https://didacine.com/orion-y-la-oscuridad/'),
(1706, 'La Ola', 2008, date '2026-10-30', 'https://didacine.com/la-ola/'),
(1721, 'Flee', 2021, date '2026-11-06', 'https://didacine.com/flee/'),
(1741, 'Luca', 2021, date '2026-11-13', 'https://didacine.com/luca/'),
(1759, 'Wonder', 2017, date '2026-11-20', 'https://didacine.com/wonder/'),
(1777, 'Spotlight', 2015, date '2026-11-27', 'https://didacine.com/spotlight/'),
(1790, 'El maestro que Prometió el Mar', 2023, date '2026-12-04', 'https://didacine.com/el-maestro-que-prometio-el-mar/'),
(1812, 'Navidad en 8 bits', 2021, date '2026-12-11', 'https://didacine.com/ocho-bits-de-navidad/'),
(1828, 'Los Que Se Quedan', 2023, date '2026-12-18', 'https://didacine.com/los-que-se-quedan/'),
(1842, 'El chico que salvó la Navidad', 2021, date '2026-12-25', 'https://didacine.com/el-chico-que-salvo-la-navidad/'),
(1851, 'Peti Roja', 2021, date '2027-01-01', 'https://didacine.com/peti-roja/'),
(1888, 'Dias Perfectos', 2023, date '2027-01-08', 'https://didacine.com/perfect-days/'),
(1905, 'EL CHICO Y LA GARZA', 2023, date '2027-01-15', 'https://didacine.com/el-chico-y-la-garza/'),
(1922, 'Altas Capacidades', 2026, date '2027-01-22', 'https://didacine.com/altas-capacidades/'),
(1941, 'LEO', 2023, date '2027-01-29', 'https://didacine.com/leo/'),
(1963, 'La Vida Secreta De Walter Mitty', 2013, date '2027-02-05', 'https://didacine.com/la-vida-secreta-de-walter-mitty/'),
(1984, 'Parasitos', 2019, date '2027-02-12', 'https://didacine.com/parasitos/'),
(1997, 'Goat (Como Cabras)', 2026, date '2027-02-19', 'https://didacine.com/goat-como-cabras/'),
(2014, 'Los Fabelman', 2022, date '2027-02-26', 'https://didacine.com/los-fabelman/'),
(2027, 'El Indomable Will Hunting', 1997, date '2027-03-05', 'https://didacine.com/el-indomable-will-hunting/'),
(2039, 'Los Mitchell Contra Las Maquinas', 2021, date '2027-03-12', 'https://didacine.com/los-mitchell-contra-las-maquinas/'),
(2056, 'No Mires Arriba', 2021, date '2027-03-19', 'https://didacine.com/no-mires-arriba/'),
(2075, 'El Monstruo Marino', 2022, date '2027-03-26', 'https://didacine.com/el-monstruo-marino/'),
(2091, 'One Piece', 2023, date '2027-04-02', 'https://didacine.com/one-piece/'),
(2101, 'Migración: Un Viaje Patas Arriba', 2023, date '2027-04-09', 'https://didacine.com/migracion-un-viaje-patas-arriba/'),
(2113, 'Cadena de Favores', 2000, date '2027-04-16', 'https://didacine.com/cadena-de-favores/'),
(2123, 'Como Entrenar A Tu Dragón', 2025, date '2027-04-23', 'https://didacine.com/como-entrenar-a-tu-dragon/'),
(2132, 'Todo A La Vez En Todas Partes', 2022, date '2027-04-30', 'https://didacine.com/todo-a-la-vez-en-todas-partes/'),
(2142, 'Un Monstruo Viene A Verme', 2016, date '2027-05-07', 'https://didacine.com/un-monstruo-viene-a-verme/'),
(2158, 'Ron Da Error', 2021, date '2027-05-14', 'https://didacine.com/ron-da-error/'),
(2167, 'AIR', 2023, date '2027-05-21', 'https://didacine.com/air/'),
(2184, '¡CANTA!', 2016, date '2027-05-28', 'https://didacine.com/canta/'),
(2193, 'BOHEMIAN RHAPSODY', 2018, date '2027-06-04', 'https://didacine.com/bohemian-rhapsody/'),
(2207, 'Con Amor, Simón', 2018, date '2027-06-11', 'https://didacine.com/con-amor-simon/'),
(2221, 'Vaiana', 2016, date '2027-06-18', 'https://didacine.com/vaiana/'),
(2232, 'Los Asesinos de la Luna', 2023, date '2027-06-25', 'https://didacine.com/los-asesinos-de-la-luna/'),
(2247, 'E.T. El Extraterrestre', 1982, date '2027-07-02', 'https://didacine.com/e-t-el-extraterrestre/'),
(2266, 'CODA', 2021, date '2027-07-09', 'https://didacine.com/coda/'),
(2276, 'Kirikú y la bruja', 1998, date '2027-07-16', 'https://didacine.com/kiriku-y-la-bruja/'),
(2284, 'Nomadland', 2020, date '2027-07-23', 'https://didacine.com/nomadland/'),
(2293, 'Spiderman: Un Nuevo Universo', 2018, date '2027-07-30', 'https://didacine.com/spiderman-un-nuevo-universo/'),
(2314, 'Sala de Profesores', 2023, date '2027-08-06', 'https://didacine.com/sala-de-profesores/'),
(2326, 'Mas Allá de la Luna', 2020, date '2027-08-13', 'https://didacine.com/mas-alla-de-la-luna/'),
(2348, 'El Padre', 2020, date '2027-08-20', 'https://didacine.com/el-padre/'),
(2360, 'Kubo y Las Dos Cuerdas Mágicas', 2016, date '2027-08-27', 'https://didacine.com/kubo-y-las-dos-cuerdas-magicas/'),
(2368, 'Radical', 2023, date '2027-09-03', 'https://didacine.com/radical/'),
(2381, 'El Viaje de Arlo', 2015, date '2027-09-10', 'https://didacine.com/el-viaje-de-arlo/'),
(2412, 'Mark Rober: CrunchLabs', 2025, date '2027-09-17', 'https://didacine.com/mark-rober-crunchlabs/'),
(2422, 'El Discurso del Rey', 2010, date '2027-09-24', 'https://didacine.com/el-discurso-del-rey/'),
(2436, 'Her', 2013, date '2027-10-01', 'https://didacine.com/her/'),
(2570, 'Mary y la flor de la bruja', 2017, date '2027-10-08', 'https://didacine.com/?p=2570'),
(2574, 'MICKEY 17', 2025, date '2027-10-15', 'https://didacine.com/?p=2574'),
(2796, 'WALL·E: Batallón de limpieza', 2008, date '2027-10-22', 'https://didacine.com/?p=2796'),
(2941, 'Frankenstein', 2025, date '2027-10-29', 'https://didacine.com/?p=2941'),
(3105, 'Yo, Daniel Blake', 2016, date '2027-11-05', 'https://didacine.com/?p=3105'),
(3285, 'Ágora', 2009, date '2027-11-12', 'https://didacine.com/?p=3285')
on conflict (wp_id) do update set title = excluded.title, year = excluded.year,
  release = excluded.release, url = excluded.url;
update public.didacine_guides set norms = _guide_norms(title);

-- get_solutions: igual que en la 0005, con «guide».
create or replace function public.get_solutions(p_date date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid  uuid := _require_user();
  v_date date := coalesce(p_date, _today() - 1);
  v_ch   challenges%rowtype;
begin
  if v_date >= _today() then raise exception 'challenge_still_open'; end if;
  select * into v_ch from challenges where challenge_date = v_date;
  if not found then return null; end if;
  return jsonb_build_object(
    'date',  v_ch.challenge_date,
    'kind',  v_ch.kind,
    'title', v_ch.title,
    'questions', (
      select jsonb_agg(jsonb_build_object(
               'position',          o.pos - 1,
               'id',                q.id,
               'format',            q.format,
               'difficulty',        q.difficulty,
               'max_points',        q.max_points,
               'prompt',            q.prompt,
               'options',           q.options,
               'extra',             q.extra,
               'answer',            q.answer,
               'explanation',       q.explanation,
               'image_url',         q.image_url,
               'image_attribution', q.image_attribution,
               'audio_url',         q.audio_url,
               'audio_attribution', q.audio_attribution,
               'media_start_ms',    q.media_start_ms,
               'accuracy',          case when q.times_shown > 0
                                         then round(q.times_correct::numeric / q.times_shown, 2) end,
               'my_answer',         a.given,
               'my_correct',        a.correct,
               'my_points',         a.points,
               'guide',             _didacine_guide(q.entity_ids))
             order by o.pos)
        from unnest(v_ch.question_ids) with ordinality o(qid, pos)
        join questions q on q.id = o.qid
        left join games g on g.user_id = v_uid and g.challenge_date = v_ch.challenge_date
        left join game_answers a on a.game_id = g.id and a.position = o.pos - 1)
  );
end $$;
