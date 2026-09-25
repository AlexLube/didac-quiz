"""Genera supabase/seed/places.sql con países y ciudades (>15.000 habitantes).

Fuente: GeoNames (CC BY 4.0) a través del paquete geonamescache.
Nombres de países en español e inglés: datos CLDR a través de Babel.

Uso:  pip install geonamescache babel && python tool/build_places_seed.py
"""
from __future__ import annotations

from pathlib import Path

import geonamescache
from babel import Locale

OUT = Path(__file__).resolve().parent.parent / "supabase" / "seed" / "places.sql"


def q(text: str) -> str:
    return "'" + text.replace("'", "''") + "'"


def main() -> None:
    gc = geonamescache.GeonamesCache()
    es, en = Locale("es"), Locale("en")
    countries = gc.get_countries()
    cities = gc.get_cities()

    used = {c["countrycode"] for c in cities.values()}
    lines = [
        "-- Generado por tool/build_places_seed.py. Datos: GeoNames (CC BY 4.0) y CLDR.",
        "begin;",
        "insert into public.countries (code, name_es, name_en) values",
    ]
    rows = []
    for code in sorted(used):
        info = countries.get(code, {})
        name_en = en.territories.get(code) or info.get("name") or code
        name_es = es.territories.get(code) or name_en
        rows.append(f"  ({q(code)}, {q(name_es)}, {q(name_en)})")
    lines.append(",\n".join(rows) + "\non conflict (code) do update set name_es = excluded.name_es, name_en = excluded.name_en;")

    city_rows = []
    for c in sorted(cities.values(), key=lambda x: (x["countrycode"], -x["population"])):
        region = f"{c['countrycode']}-{c.get('admin1code') or '00'}"
        city_rows.append(
            f"({c['geonameid']}, {q(c['countrycode'])}, {q(c['name'])}, {q(region)}, {int(c['population'])})"
        )
    for i in range(0, len(city_rows), 1000):
        chunk = city_rows[i : i + 1000]
        lines.append("insert into public.cities (id, country_code, name, region_code, population) values")
        lines.append(",\n".join(chunk))
        lines.append(
            "on conflict (id) do update set name = excluded.name, region_code = excluded.region_code, "
            "population = excluded.population;"
        )
    lines.append("commit;")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{len(rows)} países, {len(city_rows)} ciudades -> {OUT}")


if __name__ == "__main__":
    main()
