"""Preguntas multimedia con TMDB y Deezer (ver tmdb.py).

· Fotograma: «¿de qué película es esta imagen?» (con opciones o revelándose).
· Foto del reparto: «¿quién es?» (la persona sale en la película indicada).
· Tráiler oficial de YouTube: «¿quién la dirigió?» y «¿en qué año se estrenó?».
  El reproductor de YouTube enseña el título del vídeo, así que nunca se pregunta
  por el título de la película del tráiler.
· Banda sonora: «¿de qué película es esta música?».
"""
from __future__ import annotations

from typing import TYPE_CHECKING

from . import generate as G
from . import variety as V
from .tmdb import image_url, norm
from .wikidata import Film

if TYPE_CHECKING:
    from .generate import Generator

Question = dict
VIDEO_TIME_MS = 45000
TRAILER_START_S = 20      # se salta el arranque del tráiler (logos y rótulos)
TRAILER_SECONDS = 25


def _credit_tmdb() -> str:
    return "Imagen: TMDB (themoviedb.org)"


def q_stills(g: "Generator", film: Film) -> list[Question]:
    tm = film.tmdb or {}
    out: list[Question] = []
    tier = G.film_tier(film)
    for i, path in enumerate(tm.get("backdrops", [])[:2]):
        res = g._film_options(film, {film.qid}, span=8)
        if not res:
            break
        opts, idx = res
        q = V._mk("tmdb_still", film, "image_choice", 1 + tier, "still", [film.qid],
                  {"es": "🎞️ ¿A qué película pertenece este fotograma?",
                   "en": "🎞️ Which film is this still from?"},
                  opts, idx, G._explanation(film), key=f"{film.qid}:{path}")
        q["image_url"] = image_url(path)
        q["image_attribution"] = _credit_tmdb()
        if i == 1:
            q = V.Variety(g).reveal_variant(q)
        out.append(q)
    return out


def q_actor_photo(g: "Generator", film: Film) -> Question | None:
    tm = film.tmdb or {}
    profiles = {norm(c["name"]): c["profile"] for c in tm.get("cast", [])}
    person = next((p for p in film.cast[:4] if norm(p.name) in profiles), None)
    if not person or G.film_tier(film) > 1:
        return None
    banned = set(film.cast_all) | {p.qid for p in film.cast}
    pool = {p.qid: p for f in g._era_films(film, span=10) for p in f.cast if p.qid not in banned}
    wrong = g._similar_people(person, pool, banned)
    if len(wrong) < 3:
        return None
    opts, idx = G._shuffle_with_answer(g.rng, G._opt(person.name), [G._opt(p.name) for p in wrong])
    q = V._mk("actor_photo", film, "image_choice", 1 + G.film_tier(film), "actor_photo",
              [person.qid, film.qid],
              {"es": f"🎭 Sale en {G._t(film, 'es')} ({film.year}). ¿Quién es?",
               "en": f"🎭 Appears in {G._t(film, 'en')} ({film.year}). Who is it?"},
              opts, idx,
              {"es": f"Es {person.name}, en el reparto de {G._t(film, 'es')} ({film.year}).",
               "en": f"It's {person.name}, in the cast of {G._t(film, 'en')} ({film.year})."},
              key=person.qid)
    q["image_url"] = image_url(profiles[norm(person.name)], "w500")
    q["image_attribution"] = _credit_tmdb()
    return q


def _video_extra(film: Film) -> dict | None:
    videos = (film.tmdb or {}).get("videos") or []
    if not videos:
        return None
    return {"youtube": videos[0]["key"], "start": TRAILER_START_S, "end": TRAILER_START_S + TRAILER_SECONDS}


def q_trailer_director(g: "Generator", film: Film) -> Question | None:
    extra = _video_extra(film)
    base = g.q_director(film) if extra and film.directors else None
    if not base:
        return None
    q = V._mk("trailer_director", film, "video", base["difficulty"], "trailer_director",
              base["entity_ids"],
              {"es": "🎬 Mira el tráiler. ¿Quién dirigió esta película?",
               "en": "🎬 Watch the trailer. Who directed this film?"},
              base["options"], base["answer"], G._explanation(film),
              extra=extra, time_limit_ms=VIDEO_TIME_MS)
    q["image_attribution"] = "Tráiler oficial · YouTube"
    return q


def q_trailer_year(g: "Generator", film: Film) -> Question | None:
    extra = _video_extra(film)
    if not extra or G.film_tier(film) > 1:
        return None
    deltas = g._pick([-6, -4, -3, -2, 2, 3, 4, 6], 3)
    years = sorted([film.year] + [film.year + d for d in deltas])
    if len(set(years)) != 4 or max(years) > 2030:
        return None
    opts = [G._opt(str(y)) for y in years]
    return V._mk("trailer_year", film, "video", 2, "trailer_year", [film.qid],
                 {"es": "🎬 Mira el tráiler. ¿En qué año se estrenó esta película?",
                  "en": "🎬 Watch the trailer. What year was this film released?"},
                 opts, years.index(film.year), G._explanation(film),
                 extra=extra, time_limit_ms=VIDEO_TIME_MS)


def q_soundtrack(g: "Generator", film: Film) -> Question | None:
    st = film.soundtrack
    if not st or G.film_tier(film) > 1:
        return None
    res = g._film_options(film, {film.qid}, span=12, extra_ok=lambda f: G.film_tier(f) <= 1)
    if not res:
        return None
    opts, idx = res
    q = V._mk("soundtrack", film, "audio", 2, "soundtrack", [film.qid],
              {"es": "🎵 Escucha la banda sonora. ¿De qué película es?",
               "en": "🎵 Listen to the soundtrack. Which film is it from?"},
              opts, idx, G._explanation(film), key=str(st["track_id"]))
    q["audio_url"] = f"deezer:{st['track_id']}"
    q["audio_attribution"] = f"Banda sonora: {st['artist']} · Deezer" if st.get("artist") else "Banda sonora · Deezer"
    return q


def generate(g: "Generator") -> list[Question]:
    out: list[Question] = []
    for f in g.films:
        if f.qid in g.ambiguous:
            continue
        if f.tmdb:
            out += q_stills(g, f)
            for fn in (q_actor_photo, q_trailer_director, q_trailer_year):
                q = fn(g, f)
                if q:
                    out.append(q)
        q = q_soundtrack(g, f)
        if q:
            out.append(q)
    return out
