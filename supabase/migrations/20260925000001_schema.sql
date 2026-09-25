-- Didac-Quiz · Esquema base
-- Toda la lógica de juego vive en funciones SECURITY DEFINER (archivo 0002).
-- Las tablas no se exponen directamente a la app: RLS activado y sin políticas,
-- salvo lectura pública de países y ciudades.

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- Lugares (lista cerrada para rankings nacionales y locales)
-- ---------------------------------------------------------------------------
create table public.countries (
  code    char(2) primary key,
  name_es text not null,
  name_en text not null
);

create table public.cities (
  id           integer primary key,           -- geonameid
  country_code char(2) not null references public.countries(code),
  name         text    not null,
  region_code  text    not null,               -- país + admin1 (p. ej. 'ES-60')
  population   integer not null default 0
);
create index cities_country_name_idx on public.cities (country_code, lower(name));
create index cities_region_idx on public.cities (region_code);

-- ---------------------------------------------------------------------------
-- Jugadores
-- ---------------------------------------------------------------------------
create table public.profiles (
  id                       uuid primary key references auth.users(id) on delete cascade,
  alias                    text not null check (alias ~ '^[A-Za-z0-9_.-]{3,20}$'),
  country_code             char(2) not null references public.countries(code),
  city_id                  integer not null references public.cities(id),
  birth_year               integer not null check (birth_year between 1900 and 2100),
  auth_method              text not null default 'password'
                             check (auth_method in ('password', 'google', 'apple')),
  recovery_code_hash       text,
  recovery_failed_attempts integer not null default 0,
  recovery_locked_until    timestamptz,
  location_changed_at      timestamptz,
  streak_current           integer not null default 0,
  streak_best              integer not null default 0,
  last_played_date         date,
  streak_lost              integer,          -- racha perdida recuperable con anuncio
  streak_lost_on           date,
  last_streak_restore      date,
  excluded_from_rankings   boolean not null default false,
  created_at               timestamptz not null default now()
);
create unique index profiles_alias_lower_idx on public.profiles (lower(alias));
create index profiles_city_idx on public.profiles (city_id);
create index profiles_country_idx on public.profiles (country_code);

create table public.banned_words (
  word text primary key            -- en minúsculas; se busca como subcadena del alias
);

-- ---------------------------------------------------------------------------
-- Preguntas y retos
-- ---------------------------------------------------------------------------
create table public.questions (
  id                bigserial primary key,
  external_id       text unique,                -- id estable del generador (para upsert)
  format            text not null check (format in
                      ('choice', 'true_false', 'order', 'intruder', 'decade',
                       'clues', 'image_choice', 'image_reveal')),
  difficulty        smallint not null check (difficulty between 1 and 3),
  topic             text,
  entity_ids        text[] not null default '{}',   -- QIDs de Wikidata implicados
  prompt            jsonb not null,                  -- {"es": "...", "en": "..."}
  options           jsonb not null,                  -- [{"es": "...", "en": "..."}, ...]
  answer            jsonb not null,                  -- índice (2) o permutación ([2,0,3,1])
  explanation       jsonb,                           -- curiosidad {"es","en"}
  image_url         text,
  image_attribution text,
  source            text,
  active            boolean not null default true,
  times_shown       integer not null default 0,
  times_correct     integer not null default 0,
  created_at        timestamptz not null default now(),
  check (jsonb_typeof(options) = 'array' and jsonb_array_length(options) between 2 and 6)
);

create table public.challenges (
  challenge_date date primary key,
  kind           text not null default 'general',
  title          jsonb,
  question_ids   bigint[] not null check (cardinality(question_ids) = 10)
);

-- ---------------------------------------------------------------------------
-- Partidas
-- ---------------------------------------------------------------------------
create table public.games (
  id               bigserial primary key,
  user_id          uuid not null references auth.users(id) on delete cascade,
  challenge_date   date not null references public.challenges(challenge_date),
  started_at       timestamptz not null default now(),
  finished_at      timestamptz,
  current_position smallint not null default 0 check (current_position between 0 and 10),
  total_points     integer not null default 0,
  total_ms         integer not null default 0,
  unique (user_id, challenge_date)
);
create index games_date_finished_idx on public.games (challenge_date) where finished_at is not null;

create table public.game_answers (
  game_id         bigint not null references public.games(id) on delete cascade,
  position        smallint not null check (position between 0 and 9),
  question_id     bigint not null references public.questions(id),
  served_at       timestamptz not null default now(),
  answered_at     timestamptz,
  given           jsonb,
  correct         boolean,
  points          smallint not null default 0,
  elapsed_ms      integer,
  joker_used      boolean not null default false,
  removed_options smallint[],
  primary key (game_id, position)
);

create table public.reports (
  id          bigserial primary key,
  question_id bigint not null references public.questions(id) on delete cascade,
  user_id     uuid references auth.users(id) on delete set null,
  reason      text not null check (char_length(reason) between 1 and 500),
  status      text not null default 'open' check (status in ('open', 'fixed', 'dismissed')),
  created_at  timestamptz not null default now()
);

create table public.app_config (
  key   text primary key,
  value jsonb not null
);

insert into public.app_config (key, value) values
  ('question_time_ms',      '20000'),
  ('network_grace_ms',      '3000'),
  ('jokers_per_week',       '3'),
  ('min_city_players',      '20'),
  ('location_change_days',  '30'),
  ('streak_restore_days',   '30'),
  ('minor_age',             '14');

-- ---------------------------------------------------------------------------
-- Seguridad: nada es accesible directamente salvo países y ciudades.
-- ---------------------------------------------------------------------------
alter table public.countries    enable row level security;
alter table public.cities       enable row level security;
alter table public.profiles     enable row level security;
alter table public.banned_words enable row level security;
alter table public.questions    enable row level security;
alter table public.challenges   enable row level security;
alter table public.games        enable row level security;
alter table public.game_answers enable row level security;
alter table public.reports      enable row level security;
alter table public.app_config   enable row level security;

create policy countries_read on public.countries for select to anon, authenticated using (true);
create policy cities_read    on public.cities    for select to anon, authenticated using (true);

revoke all on all tables in schema public from anon, authenticated;
grant select on public.countries, public.cities to anon, authenticated;
