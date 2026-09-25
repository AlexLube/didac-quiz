"""Generación de preguntas a partir de datos verificados de Wikidata.

Cada pregunta se construye desde un dato concreto. Las respuestas incorrectas
también son datos reales (otros directores, otras décadas...), comprobados para
que ninguna sea también verdadera.
"""
from __future__ import annotations

import hashlib
import random
import re
import unicodedata
from collections import defaultdict
from typing import Callable

from .wikidata import Film, Person

Question = dict


def _t(film: Film, lang: str) -> str:
    return f"«{film.title_es}»" if lang == "es" else f"“{film.title_en}”"


_ARTICLES = re.compile(r"^(el|la|los|las|un|una|the|a|an|le|les|il|lo|der|die|das)\s+", re.I)


def title_key(title: str) -> str:
    t = unicodedata.normalize("NFKD", title).encode("ascii", "ignore").decode().lower()
    t = re.sub(r"[^a-z0-9 ]+", " ", t).strip()
    return _ARTICLES.sub("", t).strip()


def _opt(es: str, en: str | None = None) -> dict:
    return {"es": es, "en": en if en is not None else es}


def _xid(*parts: object) -> str:
    return hashlib.sha1("|".join(map(str, parts)).encode()).hexdigest()[:16]


# Umbrales de popularidad (nº de Wikipedias). Se recalculan por percentiles al
# crear el Generator, para que haya suficientes preguntas fáciles y medias.
_TIER_CUTS = [80, 45]


def film_tier(film: Film) -> int:
    """0 = muy conocida, 1 = conocida, 2 = poco conocida."""
    if film.popularity >= _TIER_CUTS[0]:
        return 0
    if film.popularity >= _TIER_CUTS[1]:
        return 1
    return 2


def set_tier_cuts(films: list[Film], top: float = 0.12, known: float = 0.40) -> None:
    """El 12 % más popular es 'muy conocida'; hasta el 40 %, 'conocida'."""
    pops = sorted((f.popularity for f in films), reverse=True)
    if len(pops) >= 20:
        _TIER_CUTS[0] = pops[int(len(pops) * top)]
        _TIER_CUTS[1] = pops[int(len(pops) * known)]


def _difficulty(base: int, film: Film) -> int:
    return max(1, min(3, base + film_tier(film)))


def _shuffle_with_answer(rng: random.Random, correct: dict, wrong: list[dict]) -> tuple[list[dict], int]:
    opts = [correct] + wrong
    rng.shuffle(opts)
    return opts, opts.index(correct)


def _explanation(film: Film) -> dict:
    d = " y ".join(p.name for p in film.directors[:2])
    d_en = " and ".join(p.name for p in film.directors[:2])
    es = f"{_t(film, 'es')} ({film.year}) fue dirigida por {d}."
    en = f"{_t(film, 'en')} ({film.year}) was directed by {d_en}."
    if "oscar_best_picture" in film.awards:
        es += " Ganó el Oscar a la mejor película."
        en += " It won the Academy Award for Best Picture."
    if "goya_best_film" in film.awards:
        es += " Ganó el Goya a la mejor película."
        en += " It won the Goya Award for Best Film."
    return {"es": es, "en": en}


class Generator:
    def __init__(self, films: list[Film], seed: int = 2026):
        self.films = films
        self.rng = random.Random(seed)
        set_tier_cuts(films)
        counts: dict[str, int] = defaultdict(int)
        for f in films:
            for k in {title_key(f.title_es), title_key(f.title_en)}:
                counts[k] += 1
        self.ambiguous = {f.qid for f in films
                          if counts[title_key(f.title_es)] > 1 or counts[title_key(f.title_en)] > 1}
        self.by_director: dict[str, list[Film]] = defaultdict(list)
        self.directors: dict[str, Person] = {}
        for f in films:
            for d in f.directors:
                self.by_director[d.qid].append(f)
                self.directors[d.qid] = d

    # -- utilidades -------------------------------------------------------
    def _tt(self, film: Film, lang: str) -> str:
        """Título; si hay otra película con un título parecido, añade el director."""
        if film.qid in self.ambiguous and film.directors:
            by = "de" if lang == "es" else "by"
            return f"{_t(film, lang)}, {by} {film.directors[0].name},"
        return _t(film, lang)

    def _era_films(self, film: Film, span: int = 12) -> list[Film]:
        return [f for f in self.films if f.qid != film.qid and abs(f.year - film.year) <= span]

    def _pick(self, pool: list, k: int) -> list:
        return self.rng.sample(pool, k) if len(pool) >= k else []

    # -- tipos de pregunta ------------------------------------------------
    def q_director(self, film: Film) -> Question | None:
        correct = film.directors[0]
        own = {d.qid for d in film.directors}
        pool = {}
        for f in self._era_films(film):
            for d in f.directors:
                if d.qid not in own and d.name != correct.name:
                    pool[d.qid] = d
        # Distractores de popularidad parecida para que sean plausibles
        cands = sorted(pool.values(), key=lambda p: abs(p.popularity - correct.popularity))[:12]
        wrong = self._pick(cands, 3)
        if not wrong or len({p.name for p in wrong}) < 3:
            return None
        opts, idx = _shuffle_with_answer(self.rng, _opt(correct.name), [_opt(p.name) for p in wrong])
        return {
            "external_id": _xid("director", film.qid),
            "format": "choice",
            "difficulty": _difficulty(1, film),
            "topic": "director",
            "entity_ids": [film.qid, correct.qid],
            "prompt": {"es": f"¿Quién dirigió {_t(film, 'es')} ({film.year})?",
                       "en": f"Who directed {_t(film, 'en')} ({film.year})?"},
            "options": opts,
            "answer": idx,
            "explanation": _explanation(film),
        }

    def q_decade(self, film: Film) -> Question | None:
        dec = film.year // 10 * 10
        others = [d for d in range(max(1900, dec - 40), min(2020, dec + 40) + 1, 10) if d != dec]
        wrong = self._pick(sorted(others, key=lambda d: abs(d - dec))[:5], 3)
        if not wrong:
            return None
        lab = lambda d: _opt(f"Años {str(d)[2:]} ({d})", f"{d}s")  # noqa: E731
        opts, idx = _shuffle_with_answer(self.rng, lab(dec), [lab(d) for d in wrong])
        # orden cronológico de las opciones: más natural para décadas
        order = sorted(range(4), key=lambda i: opts[i]["en"])
        opts = [opts[i] for i in order]
        idx = order.index(idx)
        return {
            "external_id": _xid("decade", film.qid),
            "format": "decade",
            "difficulty": _difficulty(1, film),
            "topic": "year",
            "entity_ids": [film.qid],
            "prompt": {"es": f"¿En qué década se estrenó {self._tt(film, 'es').rstrip(',')}?",
                       "en": f"In which decade was {self._tt(film, 'en').rstrip(',')} released?"},
            "options": opts,
            "answer": idx,
            "explanation": _explanation(film),
        }

    def q_true_false_year(self, film: Film) -> Question:
        truth = self.rng.random() < 0.5
        year = film.year if truth else film.year + self.rng.choice([-5, -4, -3, 3, 4, 5])
        return {
            "external_id": _xid("tf_year", film.qid, truth),
            "format": "true_false",
            "difficulty": _difficulty(1, film),
            "topic": "year",
            "entity_ids": [film.qid],
            "prompt": {"es": f"{self._tt(film, 'es')} se estrenó en {year}.",
                       "en": f"{self._tt(film, 'en')} was released in {year}."},
            "options": [_opt("Verdadero", "True"), _opt("Falso", "False")],
            "answer": 0 if truth else 1,
            "explanation": _explanation(film),
        }

    def q_true_false_oscar(self, film: Film) -> Question | None:
        truth = "oscar_best_picture" in film.awards
        if not truth and film_tier(film) > 0:
            return None  # solo afirmaciones falsas sobre películas muy conocidas
        return {
            "external_id": _xid("tf_oscar", film.qid),
            "format": "true_false",
            "difficulty": 2 if truth else 1,
            "topic": "awards",
            "entity_ids": [film.qid],
            "prompt": {"es": f"{self._tt(film, 'es')} ganó el Oscar a la mejor película.",
                       "en": f"{self._tt(film, 'en')} won the Academy Award for Best Picture."},
            "options": [_opt("Verdadero", "True"), _opt("Falso", "False")],
            "answer": 0 if truth else 1,
            "explanation": _explanation(film),
        }

    def q_cast(self, film: Film) -> Question | None:
        if not film.cast:
            return None
        correct = film.cast[0]
        banned = set(film.cast_all) | {p.qid for p in film.cast}
        pool = {}
        for f in self._era_films(film, span=8):
            for p in f.cast:
                if p.qid not in banned and p.name != correct.name:
                    pool[p.qid] = p
        cands = sorted(pool.values(), key=lambda p: abs(p.popularity - correct.popularity))[:12]
        wrong = self._pick(cands, 3)
        if not wrong or len({p.name for p in wrong}) < 3:
            return None
        opts, idx = _shuffle_with_answer(self.rng, _opt(correct.name), [_opt(p.name) for p in wrong])
        return {
            "external_id": _xid("cast", film.qid, correct.qid),
            "format": "choice",
            "difficulty": _difficulty(1, film),
            "topic": "cast",
            "entity_ids": [film.qid, correct.qid],
            "prompt": {"es": f"¿Quién aparece en el reparto de {_t(film, 'es')} ({film.year})?",
                       "en": f"Who is in the cast of {_t(film, 'en')} ({film.year})?"},
            "options": opts,
            "answer": idx,
            "explanation": _explanation(film),
        }

    def q_intruder(self, director_qid: str) -> Question | None:
        own = [f for f in self.by_director[director_qid]]
        if len(own) < 3:
            return None
        d = self.directors[director_qid]
        picks = self._pick(own, 3)
        years = [f.year for f in picks]
        others = [f for f in self.films
                  if director_qid not in {x.qid for x in f.directors}
                  and min(years) - 5 <= f.year <= max(years) + 5
                  and f.title_es not in {p.title_es for p in picks}]
        if not others:
            return None
        intruder = self.rng.choice(sorted(others, key=lambda f: -f.popularity)[:15])
        opts = [_opt(f"{_t(f, 'es')} ({f.year})", f"{_t(f, 'en')} ({f.year})") for f in picks]
        correct = _opt(f"{_t(intruder, 'es')} ({intruder.year})", f"{_t(intruder, 'en')} ({intruder.year})")
        opts, idx = _shuffle_with_answer(self.rng, correct, opts)
        tier = min(film_tier(f) for f in picks + [intruder])
        return {
            "external_id": _xid("intruder", director_qid, *sorted(f.qid for f in picks), intruder.qid),
            "format": "intruder",
            "difficulty": max(1, min(3, 2 + tier - (1 if d.popularity >= 80 else 0))),
            "topic": "director",
            "entity_ids": [director_qid, intruder.qid] + [f.qid for f in picks],
            "prompt": {"es": f"¿Cuál de estas películas NO dirigió {d.name}?",
                       "en": f"Which of these films was NOT directed by {d.name}?"},
            "options": opts,
            "answer": idx,
            "explanation": {"es": f"{_t(intruder, 'es')} es de {', '.join(p.name for p in intruder.directors[:2])}.",
                            "en": f"{_t(intruder, 'en')} is by {', '.join(p.name for p in intruder.directors[:2])}."},
        }

    def q_order(self, films: list[Film]) -> Question | None:
        years = [f.year for f in films]
        if len(films) != 4 or len(set(years)) < 4 or min(abs(a - b) for i, a in enumerate(years)
                                                         for b in years[i + 1:]) < 2:
            return None
        shown = films[:]
        self.rng.shuffle(shown)
        answer = sorted(range(4), key=lambda i: shown[i].year)
        spread = max(years) - min(years)
        tier = max(film_tier(f) for f in films)
        return {
            "external_id": _xid("order", *sorted(f.qid for f in films)),
            "format": "order",
            "difficulty": max(1, min(3, (2 if spread >= 20 else 3) + (1 if tier == 2 else 0))),
            "topic": "year",
            "entity_ids": [f.qid for f in films],
            "prompt": {"es": "Ordena estas películas de la más antigua a la más reciente.",
                       "en": "Put these films in order, from oldest to newest."},
            "options": [_opt(_t(f, "es"), _t(f, "en")) for f in shown],
            "answer": answer,
            "explanation": {
                "es": " → ".join(f"{_t(shown[i], 'es')} ({shown[i].year})" for i in answer),
                "en": " → ".join(f"{_t(shown[i], 'en')} ({shown[i].year})" for i in answer),
            },
        }

    def q_award_winner(self, film: Film, award: str) -> Question | None:
        label = {
            "oscar_best_picture": ("ganó el Oscar a la mejor película", "won the Academy Award for Best Picture"),
            "goya_best_film": ("ganó el Goya a la mejor película", "won the Goya Award for Best Film"),
        }[award]
        needs_es = award == "goya_best_film"
        pool = [f for f in self._era_films(film, span=6)
                if award not in f.awards and (not needs_es or "ES" in f.countries)]
        wrong = self._pick(sorted(pool, key=lambda f: -f.popularity)[:10], 3)
        if not wrong:
            return None
        opts, idx = _shuffle_with_answer(self.rng, _opt(_t(film, "es"), _t(film, "en")),
                                         [_opt(_t(f, "es"), _t(f, "en")) for f in wrong])
        return {
            "external_id": _xid("award", award, film.qid),
            "format": "choice",
            "difficulty": _difficulty(2 if award == "goya_best_film" else 1, film),
            "topic": "awards",
            "entity_ids": [film.qid] + [f.qid for f in wrong],
            "prompt": {"es": f"¿Cuál de estas películas {label[0]}?",
                       "en": f"Which of these films {label[1]}?"},
            "options": opts,
            "answer": idx,
            "explanation": _explanation(film),
        }

    # -- generación masiva ------------------------------------------------
    def generate_all(self) -> list[Question]:
        out: list[Question] = []
        per_film: list[Callable[[Film], Question | None]] = [
            self.q_director, self.q_decade, self.q_true_false_year, self.q_cast, self.q_true_false_oscar,
        ]
        for f in self.films:
            for fn in per_film:
                q = fn(f)
                if q:
                    q["source"] = f"wikidata:{f.qid}"
                    out.append(q)
            for award in f.awards:
                q = self.q_award_winner(f, award)
                if q:
                    q["source"] = f"wikidata:{f.qid}"
                    out.append(q)
        for dq in self.by_director:
            for _ in range(min(3, len(self.by_director[dq]) // 3)):
                q = self.q_intruder(dq)
                if q:
                    q["source"] = f"wikidata:{dq}"
                    out.append(q)
        # Preguntas de ordenar: grupos de 4 películas conocidas de épocas distintas
        known = [f for f in self.films if film_tier(f) <= 1]
        for _ in range(max(1, len(known) // 4)):
            q = self.q_order(self._pick(known, 4))
            if q:
                q["source"] = "wikidata"
                out.append(q)
        uniq = {q["external_id"]: q for q in out}
        return list(uniq.values())
