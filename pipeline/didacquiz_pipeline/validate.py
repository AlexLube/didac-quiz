"""Validación automática de preguntas antes de subirlas.

Una pregunta que no pasa se descarta (el generador produce muchas más de las
necesarias). Las comprobaciones semánticas vuelven a consultar los datos de
Wikidata para asegurar que la respuesta correcta es la única verdadera.
"""
from __future__ import annotations

import re
import unicodedata

from .wikidata import Film

FORMATS = {"choice", "true_false", "order", "intruder", "decade", "clues", "emoji", "image_choice",
           "image_reveal", "audio", "year_slider", "versus", "match", "map", "burst", "typed_title",
           "odd_images", "pick_two"}
NO_OPTIONS = {"year_slider", "map", "typed_title"}


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
    fmt = q.get("format")
    opts = q.get("options") or []
    if fmt in NO_OPTIONS:
        if opts:
            errs.append("este formato no lleva opciones")
    elif not 2 <= len(opts) <= 6:
        errs.append("número de opciones")
    for lang in ("es", "en"):
        labels = [_norm(o.get(lang, "")) for o in opts]
        if any(not x for x in labels):
            errs.append(f"opción vacía ({lang})")
        if len(set(labels)) != len(labels):
            errs.append(f"opciones repetidas ({lang})")
    ans = q.get("answer")
    extra = q.get("extra") or {}
    if not 1 <= q.get("max_points", q.get("difficulty", 1)) <= 3:
        errs.append("puntos máximos fuera de rango")
    if fmt == "order":
        if sorted(ans or []) != list(range(len(opts))):
            errs.append("la respuesta de ordenar no es una permutación")
    elif fmt == "year_slider":
        if not (isinstance(ans, dict) and isinstance(ans.get("year"), int)):
            errs.append("respuesta de año incorrecta")
        elif not (extra.get("min", 9999) <= ans["year"] <= extra.get("max", 0)) or extra["max"] - extra["min"] < 20:
            errs.append("rango del slider incorrecto")
    elif fmt == "map":
        ok = isinstance(ans, dict) and all(isinstance(ans.get(k), (int, float)) for k in ("lat", "lon"))
        if not ok or not (-90 <= ans["lat"] <= 90 and -180 <= ans["lon"] <= 180):
            errs.append("coordenadas incorrectas")
    elif fmt == "match":
        n = len(opts)
        if n not in (3, 4) or len(extra.get("right") or []) != n or sorted(ans or []) != list(range(n)):
            errs.append("emparejar: debe haber 3 o 4 parejas con una permutación válida")
        elif len({_norm(o.get("es", "")) for o in extra["right"]}) != n:
            errs.append("emparejar: columna derecha repetida")
    elif fmt == "burst":
        if len(opts) != 5 or not isinstance(ans, list) or len(ans) != 5 or not all(isinstance(a, bool) for a in ans):
            errs.append("ráfaga: 5 afirmaciones con respuesta verdadero/falso")
        elif not 1 <= sum(ans) <= 4:
            errs.append("ráfaga: debe mezclar verdaderas y falsas")
    elif fmt == "pick_two":
        if len(opts) != 5 or not (isinstance(ans, list) and len(ans) == 2 and len(set(ans)) == 2
                                  and all(isinstance(a, int) and 0 <= a < 5 for a in ans)):
            errs.append("elige dos: 5 opciones y 2 correctas")
    elif fmt == "typed_title":
        acc = (ans or {}).get("accept") if isinstance(ans, dict) else None
        if not acc or not all(isinstance(a, str) and a.strip() for a in acc):
            errs.append("escribir título: faltan respuestas aceptadas")
    elif not isinstance(ans, int) or not 0 <= ans < len(opts):
        errs.append("índice de respuesta fuera de rango")
    if fmt == "true_false" and len(opts) != 2:
        errs.append("verdadero/falso con más de 2 opciones")
    if fmt in ("versus",) and len(opts) != 2:
        errs.append("más/menos necesita 2 opciones")
    if fmt == "odd_images":
        if len(opts) != 4 or not all(o.get("image") for o in opts):
            errs.append("intruso en imágenes: 4 imágenes")
    if fmt == "clues" and extra.get("clues") is not None:
        if not 4 <= len(extra["clues"]) <= 6 or len(extra.get("reveal_ms", [])) != len(extra["clues"]):
            errs.append("pistas progresivas mal formadas")
    return errs


def semantic_errors(q: dict, films: dict[str, Film]) -> list[str]:
    """Comprueba contra los datos que la respuesta correcta es verdadera y el resto no."""
    errs: list[str] = []
    topic, fmt = q.get("topic"), q.get("format")
    ids = q.get("entity_ids") or []
    film = films.get(ids[0]) if ids else None
    names = [o["es"] for o in q["options"]]
    correct = names[q["answer"]] if isinstance(q["answer"], int) else None

    interactive = _semantic_interactive(q, films, film)
    if interactive is not None:
        return interactive
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


def _semantic_interactive(q, films, film) -> list[str] | None:
    """Validación de los formatos interactivos. None si el tema no es de estos."""
    topic, ans, ids = q.get("topic"), q.get("answer"), q.get("entity_ids") or []
    opts = q.get("options") or []
    errs: list[str] = []
    if topic == "year_slider" and film:
        if ans.get("year") != film.year:
            errs.append("el año del slider no coincide")
    elif topic in ("versus_duration", "versus_year"):
        a, b = (films.get(x) for x in ids[:2])
        if not a or not b:
            return ["faltan películas"]
        titles = {_norm(f"«{f.title_es}»"): f for f in (a, b)}
        shown = [titles.get(_norm(re.sub(r"\s*\(\d{4}\)$", "", o["es"]))) for o in opts]
        if None in shown:
            return ["las opciones no coinciden con las películas"]
        key = (lambda f: -f.duration) if topic == "versus_duration" else (lambda f: f.year)
        if topic == "versus_duration" and None in (a.duration, b.duration):
            return ["falta la duración"]
        best = min(shown, key=key)
        if shown.index(best) != ans or key(shown[0]) == key(shown[1]):
            errs.append("la respuesta de más/menos no cuadra")
    elif topic == "match_cast" and film:
        from .generate import clean_character
        truth = {_norm(r.actor): _norm(clean_character(r.character)) for r in film.roles}
        rights = [_norm(o["es"]) for o in q["extra"]["right"]]
        for i, o in enumerate(opts):
            if truth.get(_norm(o["es"])) != rights[ans[i]]:
                errs.append("un personaje no corresponde a su actor")
                break
    elif topic == "match_dir":
        involved = [films.get(x) for x in ids]
        if None in involved:
            return ["faltan películas"]
        by_title = {_norm(f"«{f.title_es}»"): f for f in involved}
        rights = [_norm(o["es"]) for o in q["extra"]["right"]]
        for i, o in enumerate(opts):
            f = by_title.get(_norm(re.sub(r"\s*\(\d{4}\)$", "", o["es"])))
            if f is None or rights[ans[i]] not in {_norm(d.name) for d in f.directors}:
                errs.append("un director no corresponde a su película")
                break
        if len({rights[a] for a in ans}) != len(ans):
            errs.append("directores repetidos")
    elif topic == "map" and film:
        valid = [(l["lat"], l["lon"]) for l in film.locations]
        mine = [(ans["lat"], ans["lon"])] + [(a["lat"], a["lon"]) for a in ans.get("alts", [])]
        if sorted(valid) != sorted(mine):
            errs.append("las coordenadas no coinciden con Wikidata")
    elif topic == "clues_prog" and film:
        if _norm(opts[ans]["es"]) != _norm(f"«{film.title_es}»"):
            errs.append("la película de las pistas no coincide")
        d, star = ids[1], ids[2]
        titles = {_norm(o["es"]) for o in opts}
        for f in films.values():
            if (f.qid != film.qid and d in {x.qid for x in f.directors} and star in f.cast_all
                    and _norm(f"«{f.title_es}»") in titles):
                errs.append("otra opción también encaja con las pistas")
    elif topic in ("burst_director", "burst_actor", "burst_oscar", "burst_spanish"):
        start = 1 if topic in ("burst_director", "burst_actor") else 0
        shown = [films.get(x) for x in ids[start:]]
        if None in shown or len(shown) != 5:
            return ["faltan películas"]
        for f, truth in zip(shown, ans):
            if topic == "burst_director":
                real = ids[0] in {d.qid for d in f.directors}
            elif topic == "burst_actor":
                real = ids[0] in f.cast_all
            elif topic == "burst_oscar":
                real = "oscar_best_picture" in f.awards
            else:
                real = f.countries == ["ES"]
            if topic == "burst_spanish" and not truth and "ES" in f.countries:
                errs.append("una película 'no española' tiene coproducción española")
            if real != truth:
                errs.append(f"afirmación incorrecta sobre {f.title_es}")
        shown_titles = [_norm(re.sub(r"\s*\(\d{4}\)$", "", o["es"])) for o in opts]
        if shown_titles != [_norm(f"«{f.title_es}»") for f in shown]:
            errs.append("el orden de las afirmaciones no coincide")
    elif topic in ("typed_emoji", "typed_clues") and film:
        want = {_norm(film.title_es), _norm(film.title_en)}
        if {_norm(a) for a in ans["accept"]} != want:
            errs.append("títulos aceptados incorrectos")
        for f in films.values():
            if f.qid != film.qid and ({_norm(f.title_es), _norm(f.title_en)} & want):
                errs.append("otra película comparte título")
                break
    elif topic == "pick2_director":
        d = ids[0]
        shown = [films.get(x) for x in ids[1:]]
        if None in shown:
            return ["faltan películas"]
        right = [i for i, f in enumerate(shown) if d in {x.qid for x in f.directors}]
        if right != sorted(ans):
            errs.append("las películas correctas no coinciden con Wikidata")
    elif topic == "pick2_cast" and film:
        shown = [_norm(o["es"]) for o in opts]
        real = {_norm(p.name) for p in film.cast} | {_norm(x.name) for x in film.cast}
        inside = [i for i, n in enumerate(shown) if n in real]
        if inside != sorted(ans):
            errs.append("los actores correctos no coinciden")
        everyone = set(film.cast_all)
        if any(qid in everyone for qid in ids[1:] if qid not in {p.qid for p in film.cast}):
            errs.append("un actor incorrecto sale en la película")
    elif topic == "odd_images" and film:
        mine = {p["qid"] for p in film.location_photos} | {l["qid"] for l in film.locations}
        if ids[2] in mine:
            errs.append("la foto intrusa es de la película")
        if not all(o.get("image") for o in opts):
            errs.append("falta una imagen")
    else:
        return None
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
    elif topic in ("location_photo", "still", "emoji", "music_film") and film:
        if _norm(correct) != _norm(f"«{film.title_es}»"):
            errs.append("la película correcta no coincide")
        if topic in ("location_photo", "still") and not q.get("image_url"):
            errs.append("falta la imagen")
        if topic == "location_photo":
            loc = q["entity_ids"][1]
            titles = {_norm(f"«{f.title_es}»"): f for f in films.values()}
            for n in wrong:
                f = titles.get(_norm(n))
                if f and loc in {l["qid"] for l in f.location_photos}:
                    errs.append("otra opción también se rodó allí")
        if topic == "music_film" and not q.get("audio_url"):
            errs.append("falta el audio")
    elif topic == "music_piece":
        if not q.get("audio_url"):
            errs.append("falta el audio")
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
