"""Planificador del calendario de retos diarios.

Reglas: 4 fáciles + 4 medias + 2 difíciles; al menos 6 tipos de pregunta
distintos por reto (máximo 2 del mismo tipo); la misma película, actor o
director no se repite en 60 días.
"""
from __future__ import annotations

import datetime as dt
import random
from collections import deque

MIX = {1: 4, 2: 4, 3: 2}


def plan(questions: list[dict], start: dt.date, days: int, spacing: int = 60,
         min_formats: int = 6, used_external_ids: set[str] | None = None,
         seed: int = 7) -> list[dict]:
    rng = random.Random(seed)
    used_external_ids = set(used_external_ids or ())
    pools = {d: [q for q in questions if q["difficulty"] == d and q["external_id"] not in used_external_ids]
             for d in MIX}
    for p in pools.values():
        rng.shuffle(p)
    recent: deque[set[str]] = deque(maxlen=spacing)
    calendar = []

    for n in range(days):
        day = start + dt.timedelta(days=n)
        blocked = set().union(*recent) if recent else set()
        chosen: list[dict] = []
        entities: set[str] = set()
        formats: dict[str, int] = {}

        for relax in (False, True):
            chosen, entities, formats = [], set(), {}
            ok = True
            for diff, count in MIX.items():
                picked = 0
                for q in pools[diff]:
                    if picked == count:
                        break
                    ents = set(q.get("entity_ids") or [])
                    if ents & blocked or ents & entities:
                        continue
                    # Variedad: como mucho 2 preguntas del mismo tipo (3 si hay que relajar)
                    kind = q.get("topic") or q["format"]
                    limit = 3 if relax else 2
                    if formats.get(kind, 0) >= limit:
                        continue
                    chosen.append(q)
                    entities |= ents
                    formats[kind] = formats.get(kind, 0) + 1
                    picked += 1
                if picked < count:
                    ok = False
                    break
            if ok and (len(formats) >= min_formats or relax):
                break
        else:
            ok = False
        if not ok or len(chosen) != 10:
            raise RuntimeError(f"No hay preguntas suficientes para el {day.isoformat()} "
                               f"(genera más o reduce el espaciado)")

        for q in chosen:
            pools[q["difficulty"]].remove(q)
        recent.append(entities)
        # Orden dentro del reto: dificultad creciente
        ordered = []
        for diff in (1, 2, 3):
            block = [q for q in chosen if q["difficulty"] == diff]
            rng.shuffle(block)
            ordered += block
        calendar.append({"date": day.isoformat(), "kind": "general", "title": None,
                         "external_ids": [q["external_id"] for q in ordered]})
    return calendar
