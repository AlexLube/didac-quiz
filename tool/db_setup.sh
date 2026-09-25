#!/usr/bin/env bash
# Aplica las migraciones pendientes y los datos iniciales a la base de datos.
# Uso:  SUPABASE_DB_URL="postgresql://..." tool/db_setup.sh
# Es seguro ejecutarlo varias veces: cada migración se aplica una sola vez.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${SUPABASE_DB_URL:?Falta SUPABASE_DB_URL}"
PSQL=(psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -q)

"${PSQL[@]}" <<'SQL'
create table if not exists public._didacquiz_migrations (
  name text primary key,
  applied_at timestamptz not null default now()
);
alter table public._didacquiz_migrations enable row level security;
revoke all on public._didacquiz_migrations from anon, authenticated;
SQL

for f in supabase/migrations/*.sql; do
  name="$(basename "$f")"
  done_already="$("${PSQL[@]}" -tAc "select 1 from public._didacquiz_migrations where name = '$name'")"
  if [[ "$done_already" == "1" ]]; then
    echo "· $name (ya aplicada)"
    continue
  fi
  echo "→ Aplicando $name"
  "${PSQL[@]}" -1 -f "$f"
  "${PSQL[@]}" -c "insert into public._didacquiz_migrations (name) values ('$name')"
done

echo "→ Países y ciudades"
"${PSQL[@]}" -f supabase/seed/places.sql
echo "→ Palabras no permitidas en alias"
"${PSQL[@]}" -f supabase/seed/banned_words.sql
echo "Base de datos lista."
