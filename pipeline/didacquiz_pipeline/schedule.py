"""Planificador del calendario de retos diarios.

Reglas de cada reto de 10 preguntas:
· 4 fáciles + 4 medias + 2 difíciles (la puntuación real puede variar por formato);
· al menos 6 temas distintos (máximo 2 del mismo);
· al menos 2 preguntas visuales o sonoras y al menos 2 interactivas;
· la misma película, actor o director no se repite en 60 días.

Días especiales:
· domingo: reto temático (cine español, clásico, una década, sagas...);
· miércoles: «minijuegos» (≥5 interactivas); jueves: «imagen y sonido» (≥5 visuales).
"""
from __future__ import annotations

import datetime as dt
import random
from collections import deque

from .variety import INTERACTIVE_FORMATS, VISUAL_FORMATS

MIX = {1: 4, 2: 4, 3: 2}
MEDIA_FORMATS = VISUAL_FORMATS   # compatibilidad

SUNDAY_THEMES = [
    ("country:ES", {"es": "Domingo de cine español", "en": "Spanish cinema Sunday"}),
    ("classic", {"es": "Domingo de cine clásico", "en": "Classic cinema Sunday"}),
    ("decade:1980", {"es": "Domingo ochentero", "en": "Eighties Sunday"}),
    ("awards", {"es": "Domingo de grandes premios", "en": "Big awards Sunday"}),
    ("decade:1990", {"es": "Domingo de los 90", "en": "Nineties Sunday"}),
    ("saga", {"es": "Domingo de sagas", "en": "Franchise Sunday"}),
    ("country:FR", {"es": "Domingo de cine francés", "en": "French cinema Sunday"}),
    ("decade:2000", {"es": "Domingo de los 2000", "en": "Two-thousands Sunday"}),
    ("decade:1970", {"es": "Domingo de cine setentero", "en": "Seventies Sunday"}),
    ("country:IT", {"es": "Domingo de cine italiano", "en": "Italian cinema Sunday"}),
    ("country:JP", {"es": "Domingo de cine japonés", "en": "Japanese cinema Sunday"}),
    ("decade:2010", {"es": "Domingo de los 2010", "en": "Twenty-tens Sunday"}),
]
SPOTLIGHTS = {
    2: ("interactive", {"es": "Miércoles de minijuegos", "en": "Minigame Wednesday"}),
    3: ("visual", {"es": "Jueves de imagen y sonido", "en": "Sight & sound Thursday"}),
}


def is_media(q: dict) -> bool:
    return q.get("format") in VISUAL_FORMATS


def is_interactive(q: dict) -> bool:
    return q.get("format") in INTERACTIVE_FORMATS or bool((q.get("extra") or {}).get("clues"))


def plan(questions: list[dict], start: dt.date, days: int, spacing: int = 60,
         min_formats: int = 6, min_media: int = 2, min_interactive: int = 2,
         used_external_ids: set[str] | None = None, seed: int = 7, specials: bool = True,
         recent_entities: list[set[str]] | None = None) -> list[dict]:
    rng = random.Random(seed)
    used_external_ids = set(used_external_ids or ())
    pools = {d: [q for q in questions if q["difficulty"] == d and q["external_id"] not in used_external_ids]
             for d in MIX}
    for p in pools.values():
        rng.shuffle(p)
    recent: deque[set[str]] = deque(recent_entities or [], maxlen=spacing)
    calendar = []

    def pick_day(blocked: set[str], want_media: int, want_inter: int, tag: str | None):
        """Intenta formar un reto; devuelve (elegidas, entidades) o None."""
        for relax in (False, True):
            chosen: list[dict] = []
            chosen_ids: set[str] = set()
            entities: set[str] = set()
            kinds: dict[str, int] = {}
            media = inter = 0
            ok = True
            for diff in (3, 2, 1):                       # primero lo más escaso
                count = MIX[diff]
                picked = 0
                limit = 3 if relax else 2
                passes = (("media", True), ("inter", True), ("media", False), ("inter", False),
                          ("any", True), ("any", False))
                for want, fresh_only in passes:
                    if picked == count:
                        break
                    if want == "media" and media >= want_media:
                        continue
                    if want == "inter" and inter >= want_inter:
                        continue
                    for q in pools[diff]:
                        if picked == count:
                            break
                        if want == "media" and (media >= want_media or not is_media(q)):
                            continue
                        if want == "inter" and (inter >= want_inter or not is_interactive(q)):
                            continue
                        if q["external_id"] in chosen_ids:
                            continue
                        if tag and tag not in (q.get("_tags") or ()):
                            continue
                        ents = set(q.get("entity_ids") or [])
                        if ents & blocked or ents & entities:
                            continue
                        kind = q.get("topic") or q["format"]
                        if (fresh_only and kind in kinds) or kinds.get(kind, 0) >= limit:
                            continue
                        chosen.append(q)
                        chosen_ids.add(q["external_id"])
                        entities |= ents
                        kinds[kind] = kinds.get(kind, 0) + 1
                        picked += 1
                        media += is_media(q)
                        inter += is_interactive(q)
                if picked < count:
                    ok = False
                    break
            if ok and (len(kinds) >= min_formats or relax or tag):
                return chosen, entities
        return None

    for n in range(days):
        day = start + dt.timedelta(days=n)
        blocked = set().union(*recent) if recent else set()
        kind, title, theme = "general", None, None
        result = None

        if specials and day.weekday() == 6:        # domingo temático
            week = day.isocalendar()[1] + day.year * 53
            for shift in range(len(SUNDAY_THEMES)):
                tag, ttl = SUNDAY_THEMES[(week + shift) % len(SUNDAY_THEMES)]
                result = pick_day(blocked, min_media, min_interactive, tag)
                if result:
                    kind, title, theme = "special", ttl, tag
                    break
        elif specials and day.weekday() in SPOTLIGHTS:
            which, ttl = SPOTLIGHTS[day.weekday()]
            result = pick_day(blocked, 5 if which == "visual" else min_media,
                              5 if which == "interactive" else min_interactive, None)
            if result:
                kind, title = "spotlight", ttl
        if result is None:
            result = pick_day(blocked, min_media, min_interactive, None)
        if result is None:
            raise RuntimeError(f"No hay preguntas suficientes para el {day.isoformat()} "
                               f"(genera más o reduce el espaciado)")
        chosen, entities = result
        if len(chosen) != 10:
            raise RuntimeError(f"No hay preguntas suficientes para el {day.isoformat()}")

        for q in chosen:
            pools[q["difficulty"]].remove(q)
        recent.append(entities)
        # Orden dentro del reto: dificultad creciente
        ordered = []
        for diff in (1, 2, 3):
            block = [q for q in chosen if q["difficulty"] == diff]
            rng.shuffle(block)
            ordered += block
        calendar.append({"date": day.isoformat(), "kind": kind, "title": title, "theme": theme,
                         "external_ids": [q["external_id"] for q in ordered]})
    return calendar
