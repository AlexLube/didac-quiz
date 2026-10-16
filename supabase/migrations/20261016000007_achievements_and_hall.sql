-- =========================================================================
-- MIGRACIÓN: Logros, Hall of Fame y Fechas Especiales
-- =========================================================================

-- 1. Catálogo de Logros
create table if not exists public.achievements (
    id text primary key,
    title_es text not null,
    title_en text not null,
    description_es text not null,
    description_en text not null,
    points integer not null default 5,
    category text not null default 'general',
    created_at timestamptz not null default now()
);

-- 2. Logros Desbloqueados por los usuarios
create table if not exists public.user_achievements (
    profile_id uuid not null references public.profiles(id) on delete cascade,
    achievement_id text not null references public.achievements(id) on delete cascade,
    unlocked_at timestamptz not null default now(),
    primary key (profile_id, achievement_id)
);

-- 3. Hall of Fame (Pabellón de la Fama mensual)
create table if not exists public.hall_of_fame (
    year_month text not null, -- formato 'YYYY-MM'
    profile_id uuid not null references public.profiles(id) on delete cascade,
    position integer not null, -- 1 (Oro), 2 (Plata), 3 (Bronce)
    total_points integer not null default 0,
    created_at timestamptz not null default now(),
    primary key (year_month, position)
);

-- 4. Fechas Especiales (Bonus del día)
create table if not exists public.special_dates (
    date_key text primary key, -- formato 'MM-DD'
    name text not null,
    bonus_points integer not null default 5
);

-- RLS (Seguridad)
alter table public.achievements enable row level security;
alter table public.user_achievements enable row level security;
alter table public.hall_of_fame enable row level security;
alter table public.special_dates enable row level security;

create policy "Logros públicos de lectura" on public.achievements for select using (true);
create policy "Logros de usuario públicos" on public.user_achievements for select using (true);
create policy "Hall of fame público" on public.hall_of_fame for select using (true);
create policy "Fechas especiales públicas" on public.special_dates for select using (true);

-- Insertar algunos logros iniciales de ejemplo (fáciles, medios y épicos)
insert into public.achievements (id, title_es, title_en, description_es, description_en, points, category) values
('streak_3', 'Cinéfilo Novato', 'Novice Cinephile', 'Mantén una racha de 3 días', 'Maintain a 3-day streak', 10, 'streak'),
('streak_7', 'Constancia de Oro', 'Gold Consistency', 'Mantén una racha de 7 días', 'Maintain a 7-day streak', 15, 'streak'),
('streak_30', 'Mes de Cine', 'Movie Month', 'Mantén una racha de 30 días', 'Maintain a 30-day streak', 50, 'streak'),
('perfect_round', 'Platea Perfecta', 'Perfect Theater', 'Consigue la puntuación máxima en un reto', 'Get the maximum score in a challenge', 25, 'score'),
('legend_1000', 'Leyenda del Celuloide', 'Celluloid Legend', 'Acumula más de 1.000 puntos en total', 'Accumulate over 1,000 total points', 100, 'milestone')
on conflict (id) do nothing;

-- Insertar fechas especiales de ejemplo (Navidad y Año Nuevo)
insert into public.special_dates (date_key, name, bonus_points) values
('12-25', 'Navidad de Cine', 5),
('01-01', 'Año Nuevo Cinematográfico', 5)
on conflict (date_key) do nothing;
