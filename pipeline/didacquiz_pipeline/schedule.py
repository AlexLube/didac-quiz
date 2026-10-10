"""Planificador del calendario de retos diarios.

Reglas: 4 fáciles + 4 medias + 2 difíciles; al menos 6 tipos de pregunta
distintos por reto (máximo 2 del mismo tipo); al menos 2 preguntas con imagen,
emoji o audio cada día; la misma película, actor o director no se repite en 60
días.
"""
from __future__ import annotations

import datetime as dt
import random
from collections import deque

MIX = {1: 4, 2: 4, 3: 2}
MEDIA_FORMATS = {"emoji", "image_choice", "image_reveal", "audio"}


def is_media(q: dict) -> bool:
    return q.get("format") in MEDIA_FORMATS


def plan(questions: list[dict], start: dt.date, days: int, spacing: int = 60,
         min_formats: int = 6, min_media: int = 2,
         used_external_ids: set[str] | None = None, seed: int = 7) -> list[dict]:
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
            chosen_ids: set[str] = set()
            media = 0
            ok = True
            for diff, count in MIX.items():
                picked = 0
                limit = 3 if relax else 2
                # Pasadas, en orden: multimedia primero (hasta cubrir el mínimo del día),
                # después tipos que aún no han salido hoy y, por último, cualquiera.
                for want_media, fresh_only in ((True, True), (True, False), (False, True), (False, False)):
                    if want_media and media >= min_media:
                        continue
                    for q in pools[diff]:
                        if picked == count or (want_media and media >= min_media):
                            break
                        if q["external_id"] in chosen_ids:
                            continue
                        if want_media and not is_media(q):
                            continue
                        ents = set(q.get("entity_ids") or [])
                        if ents & blocked or ents & entities:
                            continue
                        kind = q.get("topic") or q["format"]
                        if (fresh_only and kind in formats) or formats.get(kind, 0) >= limit:
                            continue
                        chosen.append(q)
                        chosen_ids.add(q["external_id"])
                        entities |= ents
                        formats[kind] = formats.get(kind, 0) + 1
                        picked += 1
                        media += is_media(q)
                    if picked == count:
                        break
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
