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
        if len((q.get("prompt") or {}).get(lang, "")) > 160:
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
