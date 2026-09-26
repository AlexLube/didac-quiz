"""Validación automática de preguntas antes de subirlas.

Una pregunta que no pasa se descarta (el generador produce muchas más de las
necesarias). Las comprobaciones semánticas vuelven a consultar los datos de
Wikidata para asegurar que la respuesta correcta es la única verdadera.
"""
from __future__ import annotations

import re
import unicodedata

from .wikidata import Film

FORMATS = {"choice", "true_false", "order", "intruder", "decade", "clues", "image_choice", "image_reveal"}


def _norm(s: str) -> str:
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", " ", s).strip()


def structural_errors(q: dict) -> list[str]:
    errs = []
    if q.get("format") not in FORMATS:
        errs.append("formato desconocido")
    if q.get("difficulty") not in (1, 2, 3):
        errs.append("dificultad fuera de rango")
    for lang in ("es", "en"):
        if not (q.get("prompt") or {}).get(lang, "").strip():
            errs.append(f"enunciado vacío ({lang})")
        if len((q.get("prompt") or {}).get(lang, "")) > 220:
            errs.append(f"enunciado demasiado largo ({lang})")
    opts = q.get("options") or []
    if not 2 <= len(opts) <= 6:
        errs.append("número de opciones")
    for lang in ("es", "en"):
        labels = [_norm(o.get(lang, "")) for o in opts]
        if any(not x for x in labels):
            errs.append(f"opción vacía ({lang})")
        if len(set(labels)) != len(labels):
            errs.append(f"opciones repetidas ({lang})")
    ans = q.get("answer")
    if q.get("format") == "order":
        if sorted(ans or []) != list(range(len(opts))):
            errs.append("la respuesta de ordenar no es una permutación")
    elif not isinstance(ans, int) or not 0 <= ans < len(opts):
        errs.append("índice de respuesta fuera de rango")
    if q.get("format") == "true_false" and len(opts) != 2:
        errs.append("verdadero/falso con más de 2 opciones")
    return errs


def semantic_errors(q: dict, films: dict[str, Film]) -> list[str]:
    """Comprueba contra los datos que la respuesta correcta es verdadera y el resto no."""
    errs: list[str] = []
    topic, fmt = q.get("topic"), q.get("format")
    ids = q.get("entity_ids") or []
    film = films.get(ids[0]) if ids else None
    names = [o["es"] for o in q["options"]]
    correct = names[q["answer"]] if isinstance(q["answer"], int) else None

    new = _semantic_new_types(q, films, film, names, correct)
    if new is not None:
        return new

    if topic == "director" and fmt == "choice" and film:
        real = {_norm(d.name) for d in film.directors}
        if _norm(correct) not in real:
            errs.append("el director correcto no coincide con Wikidata")
        if any(_norm(n) in real for i, n in enumerate(names) if i != q["answer"]):
            errs.append("una opción incorrecta también dirigió la película")

    elif topic == "cast" and film:
        real = {_norm(p.name) for p in film.cast}
        if _norm(correct) not in real:
            errs.append("el actor correcto no está en el reparto")
        if any(_norm(n) in real for i, n in enumerate(names) if i != q["answer"]):
            errs.append("una opción incorrecta también está en el reparto")

    elif fmt == "decade" and film:
        if str(film.year // 10 * 10) not in q["options"][q["answer"]]["en"]:
            errs.append("la década correcta no coincide")

    elif fmt == "true_false" and topic == "year" and film:
        stated = int(re.findall(r"(\d{4})\.?$", q["prompt"]["en"])[0])
        if (stated == film.year) != (q["answer"] == 0):
            errs.append("verdadero/falso de año incorrecto")

    elif fmt == "true_false" and topic == "awards" and film:
        if ("oscar_best_picture" in film.awards) != (q["answer"] == 0):
            errs.append("verdadero/falso de premio incorrecto")

    elif fmt == "intruder":
        director = ids[0]
        involved = [films[x] for x in ids[1:] if x in films]
        intruders = [f for f in involved if director not in {d.qid for d in f.directors}]
        if len(intruders) != 1:
            errs.append("el intruso no es único")

    elif fmt == "order":
        involved = [films[x] for x in ids if x in films]
        if len(involved) == 4:
            by_title = {_norm(f"«{f.title_es}»"): f.year for f in involved}
            years = [by_title.get(_norm(n)) for n in names]
            ordered = [years[i] for i in q["answer"]]
            if None in years or ordered != sorted(ordered):
                errs.append("el orden cronológico no cuadra")

    elif topic == "awards" and fmt == "choice" and film:
        award = "goya_best_film" if "Goya" in q["prompt"]["en"] else "oscar_best_picture"
        if award not in film.awards:
            errs.append("la película correcta no ganó el premio")
        for x in ids[1:]:
            if x in films and award in films[x].awards:
                errs.append("una opción incorrecta también ganó el premio")
    return errs


def _names_of(people) -> set[str]:
    return {_norm(p.name) for p in people}


def _semantic_new_types(q, films, film, names, correct) -> list[str] | None:
    """Validación de los tipos añadidos. Devuelve None si el tema no es de estos."""
    topic = q.get("topic")
    errs: list[str] = []
    wrong = [n for i, n in enumerate(names) if i != q["answer"]] if isinstance(q["answer"], int) else []
    if topic == "character" and film:
        from .generate import clean_character
        real = {_norm(r.character) for r in film.roles} | {_norm(clean_character(r.character)) for r in film.roles}
        if _norm(correct) not in real:
            errs.append("el personaje no coincide con Wikidata")
        if any(_norm(n) in real for n in wrong):
            errs.append("una opción incorrecta también es personaje de la película")
    elif topic == "actor_by_character" and film:
        cast_names = _names_of(film.cast)
        if _norm(correct) not in cast_names:
            errs.append("el actor no está en el reparto")
        if any(_norm(n) in cast_names for n in wrong):
            errs.append("una opción incorrecta también está en el reparto")
    elif topic in ("composer", "writer") and film:
        real = _names_of(film.composers if topic == "composer" else film.writers)
        if _norm(correct) not in real:
            errs.append(f"el {topic} no coincide con Wikidata")
        if any(_norm(n) in real for n in wrong):
            errs.append(f"una opción incorrecta también es {topic}")
    elif topic == "book_author" and film:
        real = {_norm(a.name) for w in film.based_on for a in w.authors}
        if _norm(correct) not in real or any(_norm(n) in real for n in wrong):
            errs.append("autor de la obra original incorrecto o repetido")
    elif topic == "based_on" and film:
        real = {_norm(f"«{w.title_es}»") for w in film.based_on}
        if _norm(correct) not in real or any(_norm(n) in real for n in wrong):
            errs.append("obra original incorrecta o repetida")
    elif topic == "country" and film:
        from .generate import country_name
        if len(film.countries) != 1 or _norm(correct) != _norm(country_name(film.countries[0], "es")):
            errs.append("país de origen incorrecto")
    elif topic == "filmed_in" and film:
        from .generate import country_name
        shot = {_norm(country_name(c, "es")) for c in film.filming_countries + film.countries}
        if _norm(correct) not in shot or any(_norm(n) in shot for n in wrong):
            errs.append("país de rodaje incorrecto o repetido")
    elif topic == "longest":
        involved = [films[x] for x in q["entity_ids"] if x in films]
        by_title = {_norm(f"«{f.title_es}»"): f.duration for f in involved}
        durs = [by_title.get(_norm(n)) for n in names]
        if None in durs or durs[q["answer"]] != max(durs) or sorted(durs)[-1] == sorted(durs)[-2]:
            errs.append("la más larga no es única o no cuadra")
    elif topic == "cast_intruder" and film:
        intruder_qid = q["entity_ids"][1]
        members = q["entity_ids"][2:]
        if intruder_qid in film.cast_all or not all(m in film.cast_all for m in members):
            errs.append("el intruso de reparto no es correcto")
    elif topic == "clues" and film:
        if _norm(correct) != _norm(f"«{film.title_es}»"):
            errs.append("la película de las pistas no coincide")
        d, star = q["entity_ids"][1], q["entity_ids"][2]
        for f in films.values():
            if (f.qid != film.qid and f.year == film.year and d in {x.qid for x in f.directors}
                    and star in f.cast_all and _norm(f"«{f.title_es}»") in {_norm(n) for n in names}):
                errs.append("otra opción también encaja con las pistas")
    elif topic == "saga_next":
        saga = [films[x] for x in q["entity_ids"][1:] if x in films]
        if not saga:
            errs.append("saga sin datos")
    else:
        return None
    return errs


def validate_all(questions: list[dict], films: list[Film]) -> tuple[list[dict], list[tuple[dict, list[str]]]]:
    index = {f.qid: f for f in films}
    ok, rejected, seen = [], [], set()
    for q in questions:
        errs = structural_errors(q)
        if not errs:
            errs = semantic_errors(q, index)
        key = (_norm(q["prompt"]["es"]), tuple(sorted(_norm(o["es"]) for o in q["options"])))
        if key in seen:
            errs.append("duplicada")
        if errs:
            rejected.append((q, errs))
        else:
            seen.add(key)
            ok.append(q)
    return ok, rejected
