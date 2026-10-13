"""Preguntas interactivas: slider de año, más/menos, emparejar, mapa, pistas
progresivas, verdadero/falso en ráfaga, escribir el título, intruso en imágenes,
elige dos y revelado de imágenes.

Todas salen de datos de Wikidata (igual que el resto) y se validan después contra
esos mismos datos (ver validate.py).
"""
from __future__ import annotations

import hashlib
from collections import defaultdict

from . import generate as G
from .wikidata import Film

Question = dict

# Formatos que cuentan como "visuales o sonoros" y como "interactivos" en el calendario.
VISUAL_FORMATS = {"emoji", "image_choice", "image_reveal", "audio", "odd_images", "map"}
INTERACTIVE_FORMATS = {"year_slider", "match", "map", "burst", "typed_title", "pick_two", "order", "versus"}

REVEAL_MODES = ("pixel", "blur", "zoom")


def film_tags(film: Film) -> list[str]:
    """Etiquetas para los retos temáticos del domingo."""
    tags = [f"decade:{film.year // 10 * 10}"]
    tags += [f"country:{c}" for c in film.countries]
    if film.awards:
        tags.append("awards")
    if film.year <= 1960:
        tags.append("classic")
    if film.series:
        tags.append("saga")
    return tags


def _mk(kind: str, film: Film | None, fmt: str, difficulty: int, topic: str, entities: list[str],
        prompt: dict, options: list[dict], answer, explanation: dict, *, key: str = "",
        extra: dict | None = None, max_points: int | None = None, time_limit_ms: int | None = None,
        tags: list[str] | None = None, source: str = "wikidata") -> Question:
    d = max(1, min(3, difficulty))
    q = {
        "external_id": G._xid(kind, key or (film.qid if film else "")),
        "format": fmt,
        "difficulty": d,
        "max_points": max(1, min(3, max_points or d)),
        "topic": topic,
        "entity_ids": entities,
        "prompt": prompt,
        "options": options,
        "answer": answer,
        "explanation": explanation,
        "extra": extra or {},
        "source": source,
        "_tags": tags if tags is not None else (film_tags(film) if film else []),
    }
    if time_limit_ms:
        q["time_limit_ms"] = time_limit_ms
    return q


def _lab(film: Film, with_year: bool = False) -> dict:
    es, en = G._t(film, "es"), G._t(film, "en")
    if with_year:
        es, en = f"{es} ({film.year})", f"{en} ({film.year})"
    return G._opt(es, en)


def _titles(film: Film) -> list[str]:
    seen, out = set(), []
    for t in (film.title_es, film.title_en):
        k = G.title_key(t)
        if k and k not in seen:
            seen.add(k)
            out.append(t)
    return out


class Variety:
    """Generadores. `g` es el Generator principal (datos, azar y utilidades)."""

    def __init__(self, g: "G.Generator"):
        self.g = g
        self.rng = g.rng

    # -- año con slider -----------------------------------------------------
    def q_year_slider(self, film: Film) -> Question | None:
        g = self.g
        if film.qid in g.ambiguous and not film.directors:
            return None
        lo = max(1895, film.year - self.rng.randint(8, 42))
        hi = min(2026, max(lo + 50, film.year + 5))
        lo = max(1895, min(lo, hi - 50))
        d = 2 if G.film_tier(film) <= 1 else 3
        return _mk("year_slider", film, "year_slider", d, "year_slider", [film.qid],
                   {"es": f"¿En qué año se estrenó {g._tt(film, 'es')}?",
                    "en": f"In what year was {g._tt(film, 'en')} released?"},
                   [], {"year": film.year}, G._explanation(film),
                   extra={"min": lo, "max": hi, "step": 1, "bands": [1, 3, 7]})

    # -- más / menos --------------------------------------------------------
    def q_versus_duration(self, a: Film, b: Film) -> Question | None:
        if a.duration is None or b.duration is None or abs(a.duration - b.duration) < 20:
            return None
        if G.title_key(a.title_es) == G.title_key(b.title_es):
            return None
        pair = [a, b]
        self.rng.shuffle(pair)
        longer = max(pair, key=lambda f: f.duration)
        easy = G.film_tier(a) == 0 and G.film_tier(b) == 0
        return _mk("versus_dur", None, "versus", 1 if easy else 2, "versus_duration", [a.qid, b.qid],
                   {"es": "¿Cuál de estas dos películas dura más?", "en": "Which of these two films is longer?"},
                   [_lab(f, True) for f in pair], pair.index(longer),
                   {"es": f"{G._t(a, 'es')} dura {a.duration} min y {G._t(b, 'es')}, {b.duration} min.",
                    "en": f"{G._t(a, 'en')} runs {a.duration} min and {G._t(b, 'en')}, {b.duration} min."},
                   key="|".join(sorted([a.qid, b.qid])), tags=film_tags(a) + film_tags(b))

    def q_versus_year(self, a: Film, b: Film) -> Question | None:
        if abs(a.year - b.year) < 6 or G.title_key(a.title_es) == G.title_key(b.title_es):
            return None
        pair = [a, b]
        self.rng.shuffle(pair)
        earlier = min(pair, key=lambda f: f.year)
        gap = abs(a.year - b.year)
        return _mk("versus_year", None, "versus", 1 if gap >= 25 else 2, "versus_year", [a.qid, b.qid],
                   {"es": "¿Cuál de estas dos películas se estrenó antes?",
                    "en": "Which of these two films came out first?"},
                   [_lab(f) for f in pair], pair.index(earlier),
                   {"es": f"{G._t(a, 'es')} es de {a.year} y {G._t(b, 'es')}, de {b.year}.",
                    "en": f"{G._t(a, 'en')} is from {a.year} and {G._t(b, 'en')}, from {b.year}."},
                   key="|".join(sorted([a.qid, b.qid])), tags=film_tags(a) + film_tags(b))

    # -- emparejar -----------------------------------------------------------
    def _match(self, kind: str, film: Film | None, entities: list[str], prompt: dict, lefts: list[dict],
               rights: list[dict], d: int, expl: dict, key: str, tags: list[str]) -> Question:
        order = list(range(len(rights)))
        self.rng.shuffle(order)
        shown = [rights[i] for i in order]
        answer = [order.index(i) for i in range(len(lefts))]  # posición de la pareja de cada elemento
        return _mk(kind, film, "match", d, kind, entities, prompt, lefts, answer, expl, key=key,
                   extra={"right": shown}, tags=tags)

    def q_match_cast(self, film: Film) -> Question | None:
        roles, seen_c, seen_a = [], set(), set()
        for r in film.roles:
            c = G.clean_character(r.character)
            ck, ak = G.title_key(c), G.title_key(r.actor)
            if not ck or ck in seen_c or ak in seen_a or ck == ak or len(c) > 38:
                continue
            seen_c.add(ck)
            seen_a.add(ak)
            roles.append((r, c))
        if len(roles) < 3:
            return None
        roles = roles[:4]
        self.rng.shuffle(roles)
        d = 2 if G.film_tier(film) == 0 else 3
        return self._match(
            "match_cast", film, [film.qid] + [r.actor_qid for r, _ in roles],
            {"es": f"Une cada actor con su personaje en {G._t(film, 'es')} ({film.year})",
             "en": f"Match each actor with their character in {G._t(film, 'en')} ({film.year})"},
            [G._opt(r.actor) for r, _ in roles], [G._opt(c) for _, c in roles], d,
            {"es": "; ".join(f"{r.actor} es {c}" for r, c in roles),
             "en": "; ".join(f"{r.actor} plays {c}" for r, c in roles)},
            key=film.qid, tags=film_tags(film))

    def q_match_directors(self, films: list[Film]) -> Question | None:
        if len(films) != 4:
            return None
        dirs = [f.directors[0] for f in films if f.directors]
        if len(dirs) != 4 or len({d.qid for d in dirs}) != 4:
            return None
        if len({G.title_key(f.title_es) for f in films}) != 4:
            return None
        if any(f.qid in self.g.ambiguous for f in films):
            return None
        tier = max(G.film_tier(f) for f in films)
        return self._match(
            "match_dir", None, [f.qid for f in films],
            {"es": "Une cada película con su director o directora", "en": "Match each film with its director"},
            [_lab(f, True) for f in films], [G._opt(d.name) for d in dirs], 2 if tier == 0 else 3,
            {"es": "; ".join(f"{G._t(f, 'es')}: {f.directors[0].name}" for f in films),
             "en": "; ".join(f"{G._t(f, 'en')}: {f.directors[0].name}" for f in films)},
            key="|".join(sorted(f.qid for f in films)),
            tags=sorted({t for f in films for t in film_tags(f)}))

    # -- mapa ----------------------------------------------------------------
    def q_map(self, film: Film) -> Question | None:
        locs = film.locations
        if not locs or len(locs) > 6 or G.film_tier(film) > 1 or film.qid in self.g.ambiguous:
            return None
        main, alts = locs[0], locs[1:]
        names_es = ", ".join(l["name_es"] for l in locs)
        names_en = ", ".join(l["name_en"] for l in locs)
        return _mk("map", film, "map", 2 if G.film_tier(film) == 0 else 3, "map", [film.qid],
                   {"es": f"🗺️ Sitúa en el mapa un lugar donde se rodó {G._t(film, 'es')} ({film.year})",
                    "en": f"🗺️ Place on the map a location where {G._t(film, 'en')} ({film.year}) was filmed"},
                   [], {"lat": main["lat"], "lon": main["lon"],
                        "alts": [{"lat": a["lat"], "lon": a["lon"]} for a in alts]},
                   {"es": f"Se rodó en: {names_es}.", "en": f"Filmed in: {names_en}."},
                   extra={"scope": "world", "bands": [300, 1000, 2500]})

    # -- pistas progresivas ----------------------------------------------------
    def q_clues_progressive(self, film: Film) -> Question | None:
        g = self.g
        if not film.cast or not film.directors or film.qid in g.ambiguous:
            return None
        d, star = film.directors[0], film.cast[0]
        decade = film.year // 10 * 10
        clues = [{"es": f"🎬 Se estrenó en la década de {decade}", "en": f"🎬 Released in the {decade}s"}]
        if len(film.countries) == 1:
            clues.append({"es": f"🌍 País: {G.country_name(film.countries[0], 'es')}",
                          "en": f"🌍 Country: {G.country_name(film.countries[0], 'en')}"})
        elif film.duration:
            clues.append({"es": f"⏱️ Dura {film.duration} minutos", "en": f"⏱️ Runs {film.duration} minutes"})
        clues.append({"es": f"🎥 Dirigida por {d.name}", "en": f"🎥 Directed by {d.name}"})
        clues.append({"es": f"⭐ Protagonizada por {star.name}", "en": f"⭐ Starring {star.name}"})
        role = next((r for r in film.roles if r.actor_qid != star.qid and G.clean_character(r.character)), None)
        if role:
            c = G.clean_character(role.character)
            clues.append({"es": f"🎭 Un personaje: {c}", "en": f"🎭 A character: {c}"})
        if len(clues) < 4:
            return None
        others = [f for f in g._era_films(film, 4)
                  if d.qid not in {x.qid for x in f.directors} and star.qid not in f.cast_all
                  and G.title_key(f.title_es) != G.title_key(film.title_es)]
        others.sort(key=lambda f: abs(f.popularity - film.popularity))
        wrong = g._pick(others[:12], 3)
        if not wrong:
            return None
        opts, idx = G._shuffle_with_answer(self.rng, _lab(film), [_lab(f) for f in wrong])
        n = len(clues)
        return _mk("clues_prog", film, "clues", 2 + (1 if G.film_tier(film) >= 1 else 0), "clues_prog",
                   [film.qid, d.qid, star.qid],
                   {"es": "Adivina la película: las pistas van apareciendo. ¡Cuanto antes aciertes, más puntos!",
                    "en": "Guess the film: clues appear one by one. The sooner you get it, the more points!"},
                   opts, idx, G._explanation(film), key=film.qid,
                   extra={"clues": clues, "speed": True, "reveal_ms": [i * 18000 // n for i in range(n)]})

    # -- verdadero / falso en ráfaga ------------------------------------------
    def _burst(self, kind: str, entities: list[str], prompt: dict, films: list[Film],
               truth: list[bool], expl: dict, key: str, d: int = 2) -> Question:
        return _mk(kind, None, "burst", d, kind, entities, prompt, [_lab(f, True) for f in films], truth, expl,
                   key=key, max_points=min(d, 3), time_limit_ms=30000,
                   tags=sorted({t for f in films for t in film_tags(f)}))

    def q_burst_director(self, dq: str) -> Question | None:
        g = self.g
        mine = [f for f in g.by_director[dq] if G.film_tier(f) <= 1 and f.qid not in g.ambiguous]
        if len(mine) < 3:
            return None
        director = g.directors[dq]
        n_true = self.rng.choice([2, 3])
        true_f = self.rng.sample(mine, n_true)
        center = true_f[0]
        pool = [f for f in g._era_films(center, 20) if dq not in {x.qid for x in f.directors}
                and G.film_tier(f) <= 1 and f.qid not in g.ambiguous]
        pool.sort(key=lambda f: abs(f.popularity - center.popularity))
        false_f = g._pick(pool[:14], 5 - n_true)
        if not false_f:
            return None
        items = true_f + false_f
        self.rng.shuffle(items)
        if len({G.title_key(f.title_es) for f in items}) != 5:
            return None
        return self._burst(
            "burst_director", [dq] + [f.qid for f in items],
            {"es": f"Verdadero o falso: ¿dirigió {director.name} cada una de estas películas?",
             "en": f"True or false: did {director.name} direct each of these films?"},
            items, [f in true_f for f in items],
            {"es": f"{director.name} dirigió: " + ", ".join(G._t(f, "es") for f in true_f) + ".",
             "en": f"{director.name} directed: " + ", ".join(G._t(f, "en") for f in true_f) + "."},
            key=f"{dq}|{'|'.join(sorted(f.qid for f in items))}")

    def q_burst_actor(self, aq: str, actor_name: str, films: list[Film]) -> Question | None:
        g = self.g
        mine = [f for f in films if G.film_tier(f) <= 1 and f.qid not in g.ambiguous]
        if len(mine) < 3:
            return None
        n_true = self.rng.choice([2, 3])
        true_f = self.rng.sample(mine, n_true)
        pool = [f for f in g._era_films(true_f[0], 15) if aq not in f.cast_all
                and G.film_tier(f) <= 1 and f.qid not in g.ambiguous]
        pool.sort(key=lambda f: abs(f.popularity - true_f[0].popularity))
        false_f = g._pick(pool[:14], 5 - n_true)
        if not false_f:
            return None
        items = true_f + false_f
        self.rng.shuffle(items)
        if len({G.title_key(f.title_es) for f in items}) != 5:
            return None
        return self._burst(
            "burst_actor", [aq] + [f.qid for f in items],
            {"es": f"Verdadero o falso: ¿sale {actor_name} en cada una de estas películas?",
             "en": f"True or false: is {actor_name} in each of these films?"},
            items, [f in true_f for f in items],
            {"es": f"{actor_name} sale en: " + ", ".join(G._t(f, "es") for f in true_f) + ".",
             "en": f"{actor_name} is in: " + ", ".join(G._t(f, "en") for f in true_f) + "."},
            key=f"{aq}|{'|'.join(sorted(f.qid for f in items))}")

    def q_burst_oscar(self, winners: list[Film]) -> Question | None:
        g = self.g
        n_true = self.rng.choice([2, 3])
        if len(winners) < n_true:
            return None
        true_f = self.rng.sample(winners, n_true)
        pool = [f for f in g._era_films(true_f[0], 12) if "oscar_best_picture" not in f.awards
                and G.film_tier(f) == 0 and f.qid not in g.ambiguous]
        false_f = g._pick(pool[:20], 5 - n_true)
        if not false_f:
            return None
        items = true_f + false_f
        self.rng.shuffle(items)
        if len({G.title_key(f.title_es) for f in items}) != 5:
            return None
        return self._burst(
            "burst_oscar", [f.qid for f in items],
            {"es": "Verdadero o falso: ¿ganó el Oscar a la mejor película?",
             "en": "True or false: did it win the Oscar for Best Picture?"},
            items, [f in true_f for f in items],
            {"es": "Ganaron el Oscar: " + ", ".join(G._t(f, "es") for f in true_f) + ".",
             "en": "Winners: " + ", ".join(G._t(f, "en") for f in true_f) + "."},
            key="|".join(sorted(f.qid for f in items)))

    def q_burst_spanish(self, spanish: list[Film], others: list[Film]) -> Question | None:
        n_true = self.rng.choice([2, 3])
        if len(spanish) < n_true or len(others) < 5 - n_true:
            return None
        true_f = self.rng.sample(spanish, n_true)
        false_f = self.rng.sample(others, 5 - n_true)
        items = true_f + false_f
        self.rng.shuffle(items)
        if len({G.title_key(f.title_es) for f in items}) != 5:
            return None
        return self._burst(
            "burst_spanish", [f.qid for f in items],
            {"es": "Verdadero o falso: ¿es una película española?", "en": "True or false: is it a Spanish film?"},
            items, [f in true_f for f in items],
            {"es": "Españolas: " + ", ".join(G._t(f, "es") for f in true_f) + ".",
             "en": "Spanish: " + ", ".join(G._t(f, "en") for f in true_f) + "."},
            key="|".join(sorted(f.qid for f in items)), d=2)

    # -- escribir el título -------------------------------------------------
    def q_typed_emoji(self, film: Film) -> Question | None:
        emo = self.g.emojis.get(film.qid)
        if not emo or G.film_tier(film) > 1 or film.qid in self.g.ambiguous:
            return None
        return _mk("typed_emoji", film, "typed_title", 2 if G.film_tier(film) == 0 else 3, "typed_emoji",
                   [film.qid],
                   {"es": f"{emo}\nEscribe el título de la película", "en": f"{emo}\nType the title of the film"},
                   [], {"accept": _titles(film)}, G._explanation(film), key=film.qid,
                   extra={"hint": {"es": "Empieza a escribir y elige de la lista",
                                   "en": "Start typing and choose from the list"}})

    def q_typed_clues(self, film: Film) -> Question | None:
        if not film.cast or not film.directors or G.film_tier(film) > 1 or film.qid in self.g.ambiguous:
            return None
        d, star = film.directors[0], film.cast[0]
        return _mk("typed_clues", film, "typed_title", 3, "typed_clues", [film.qid, d.qid, star.qid],
                   {"es": f"🎬 {film.year} · 🎥 {d.name} · ⭐ {star.name}\nEscribe el título de la película",
                    "en": f"🎬 {film.year} · 🎥 {d.name} · ⭐ {star.name}\nType the title of the film"},
                   [], {"accept": _titles(film)}, G._explanation(film), key=film.qid,
                   extra={"hint": {"es": "Empieza a escribir y elige de la lista",
                                   "en": "Start typing and choose from the list"}})

    # -- elige dos de cinco ----------------------------------------------------
    def q_pick_two_director(self, dq: str) -> Question | None:
        g = self.g
        mine = [f for f in g.by_director[dq] if G.film_tier(f) <= 1 and f.qid not in g.ambiguous]
        if len(mine) < 2:
            return None
        director = g.directors[dq]
        two = self.rng.sample(mine, 2)
        pool = [f for f in g._era_films(two[0], 20) if dq not in {x.qid for x in f.directors}
                and G.film_tier(f) <= 1 and f.qid not in g.ambiguous]
        pool.sort(key=lambda f: abs(f.popularity - two[0].popularity))
        others = g._pick(pool[:14], 3)
        if not others:
            return None
        items = two + others
        self.rng.shuffle(items)
        if len({G.title_key(f.title_es) for f in items}) != 5:
            return None
        return _mk("pick2_director", None, "pick_two", 2, "pick2_director", [dq] + [f.qid for f in items],
                   {"es": f"Elige las DOS películas dirigidas por {director.name}",
                    "en": f"Pick the TWO films directed by {director.name}"},
                   [_lab(f, True) for f in items], sorted(items.index(f) for f in two),
                   {"es": f"{director.name} dirigió " + " y ".join(G._t(f, "es") for f in two) + ".",
                    "en": f"{director.name} directed " + " and ".join(G._t(f, "en") for f in two) + "."},
                   key=f"{dq}|{'|'.join(sorted(f.qid for f in items))}",
                   tags=sorted({t for f in items for t in film_tags(f)}))

    def q_pick_two_cast(self, film: Film) -> Question | None:
        g = self.g
        directors = {d.qid for d in film.directors}
        actors = [p for p in film.cast if p.qid not in directors]
        if len(actors) < 2 or film.qid in g.ambiguous:
            return None
        two = actors[:2]
        pool = {p.qid: p for f in g._era_films(film, 6) for p in f.cast}
        banned = set(film.cast_all) | {p.qid for p in film.cast} | directors
        top = max(two, key=lambda p: p.popularity)
        wrong = g._similar_people(top, pool, banned, k=3)
        if len(wrong) < 3:
            return None
        items = two + wrong
        self.rng.shuffle(items)
        if len({G.title_key(p.name) for p in items}) != 5:
            return None
        return _mk("pick2_cast", film, "pick_two", 2 + (1 if G.film_tier(film) == 2 else 0), "pick2_cast",
                   [film.qid] + [p.qid for p in items],
                   {"es": f"Elige los DOS actores que salen en {G._t(film, 'es')} ({film.year})",
                    "en": f"Pick the TWO actors in {G._t(film, 'en')} ({film.year})"},
                   [G._opt(p.name) for p in items], sorted(items.index(p) for p in two),
                   {"es": f"En {G._t(film, 'es')} actúan " + " y ".join(p.name for p in two) + ", entre otros.",
                    "en": f"{G._t(film, 'en')} stars " + " and ".join(p.name for p in two) + ", among others."},
                   key=film.qid)

    # -- intruso entre cuatro imágenes ---------------------------------------
    def q_odd_images(self, film: Film, others: list[Film]) -> Question | None:
        photos = film.location_photos
        if len(photos) < 3 or G.film_tier(film) > 1:
            return None
        mine = {p["qid"] for p in photos} | {l["qid"] for l in film.locations}
        cands = [(f, p) for f in others if f.qid != film.qid for p in f.location_photos[:1]
                 if p["qid"] not in mine]
        if not cands:
            return None
        other_film, odd = self.rng.choice(cands)
        three = self.rng.sample(photos, 3)
        items = [(p, False) for p in three] + [(odd, True)]
        self.rng.shuffle(items)
        opts = []
        for i, (p, _) in enumerate(items):
            opts.append({"es": f"Foto {i + 1}", "en": f"Photo {i + 1}", "image": p["url"],
                         "credit": G._media_credit(p, "Foto")})
        q = _mk("odd_images", film, "odd_images", 3, "odd_images", [film.qid, other_film.qid, odd["qid"]],
                {"es": f"📍 Tres de estas fotos son lugares de rodaje de {G._t(film, 'es')} ({film.year}). ¿Cuál NO?",
                 "en": f"📍 Three of these photos are filming locations of {G._t(film, 'en')} ({film.year}). Which one is NOT?"},
                opts, [i for i, (_, is_odd) in enumerate(items) if is_odd][0],
                {"es": f"La intrusa es {odd['name_es']}, que no es de {G._t(film, 'es')}.",
                 "en": f"The odd one is {odd['name_en']}, which isn't from {G._t(film, 'en')}."},
                key=film.qid)
        q["image_attribution"] = "Fotos de Wikimedia Commons (licencias libres)"
        return q

    # -- imagen que se revela --------------------------------------------------
    def reveal_variant(self, q: Question) -> Question:
        """Versión 'revelar' de una pregunta de foto: pixelado, desenfoque o zoom."""
        r = dict(q)
        mode = REVEAL_MODES[int(hashlib.sha1(q["external_id"].encode()).hexdigest(), 16) % len(REVEAL_MODES)]
        r["external_id"] = G._xid("reveal", q["external_id"])
        r["format"] = "image_reveal"
        r["extra"] = {"mode": mode, "speed": True}
        r["difficulty"] = max(2, q["difficulty"])
        r["max_points"] = r["difficulty"]
        r["prompt"] = {"es": q["prompt"]["es"] + " (la imagen se va aclarando)",
                       "en": q["prompt"]["en"] + " (the image gets clearer)"}
        return r


def generate(g: "G.Generator") -> list[Question]:
    v = Variety(g)
    rng = g.rng
    out: list[Question] = []
    films = g.films
    known = [f for f in films if G.film_tier(f) <= 1]

    for f in films:
        for fn in (v.q_year_slider, v.q_match_cast, v.q_map, v.q_clues_progressive, v.q_typed_emoji,
                   v.q_typed_clues, v.q_pick_two_cast):
            q = fn(f)
            if q:
                out.append(q)
        if f.location_photos and G.film_tier(f) <= 1:
            for i in range(min(2, len(f.location_photos))):
                base = g.q_location_photo(f, i)
                if base:
                    out.append(v.reveal_variant(base))
        if f.still:
            base = g.q_still(f)
            if base:
                out.append(v.reveal_variant(base))

    # más / menos: parejas de películas conocidas de épocas distintas
    shuffled = known[:]
    rng.shuffle(shuffled)
    for i in range(0, len(shuffled) - 1, 2):
        a, b = shuffled[i], shuffled[i + 1]
        for fn in (v.q_versus_duration, v.q_versus_year):
            q = fn(a, b)
            if q:
                out.append(q)

    # emparejar películas con su director
    pool = [f for f in known if f.directors and f.qid not in g.ambiguous]
    rng.shuffle(pool)
    for i in range(0, len(pool) - 3, 4):
        q = v.q_match_directors(pool[i : i + 4])
        if q:
            out.append(q)

    # ráfagas de verdadero/falso
    for dq in g.by_director:
        for _ in range(min(2, len(g.by_director[dq]) // 3)):
            q = v.q_burst_director(dq)
            if q:
                out.append(q)
        q = v.q_pick_two_director(dq)
        if q:
            out.append(q)
    by_actor: dict[str, list[Film]] = defaultdict(list)
    names: dict[str, str] = {}
    for f in films:
        for p in f.cast:
            by_actor[p.qid].append(f)
            names[p.qid] = p.name
    for aq, fs in by_actor.items():
        for _ in range(min(2, len(fs) // 3)):
            q = v.q_burst_actor(aq, names[aq], fs)
            if q:
                out.append(q)
    winners = [f for f in films if "oscar_best_picture" in f.awards and f.qid not in g.ambiguous]
    for _ in range(max(0, len(winners))):
        q = v.q_burst_oscar(winners)
        if q:
            out.append(q)
    spanish = [f for f in known if f.countries == ["ES"]]
    others = [f for f in known if "ES" not in f.countries]
    for _ in range(len(spanish) // 2):
        q = v.q_burst_spanish(spanish, others)
        if q:
            out.append(q)

    # intruso entre imágenes
    with_photos = [f for f in films if f.location_photos]
    for f in with_photos:
        q = v.q_odd_images(f, with_photos)
        if q:
            out.append(q)
    return out
