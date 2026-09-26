"""Generación de preguntas a partir de datos verificados de Wikidata.

Cada pregunta se construye desde un dato concreto. Las respuestas incorrectas
también son datos reales (otros directores, otras décadas...), comprobados para
que ninguna sea también verdadera.
"""
from __future__ import annotations

import bisect
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


def clean_character(name: str) -> str:
    """'Norman Osborn (trilogía de Sam Raimi)' -> 'Norman Osborn'."""
    return re.sub(r"\s*[\(\[].*?[\)\]]\s*", " ", name).strip() or name


def titles_overlap(work, film) -> bool:
    film_keys = {title_key(film.title_es), title_key(film.title_en)}
    for t in (work.title_es, work.title_en):
        k = title_key(t)
        if not k:
            continue
        if any(k == f or k in f or f in k for f in film_keys if f):
            return True
        words = {w for w in k.split() if len(w) > 3}
        if any(words & {w for w in f.split() if len(w) > 3} for f in film_keys):
            return True
    return False


COMMON_COUNTRIES = ["US", "GB", "FR", "IT", "ES", "DE", "JP", "IN", "KR", "MX", "AR", "CA",
                    "AU", "SE", "DK", "CN", "HK", "BR", "RU", "IE", "NZ", "PL", "IR", "BE"]


def country_name(iso: str, lang: str) -> str:
    try:
        from babel import Locale
        return Locale(lang).territories.get(iso, iso)
    except Exception:  # noqa: BLE001 - sin Babel, el código ISO
        return iso


def _media_credit(info: dict, kind: str) -> str:
    return f"{kind}: {info['artist']} · {info['license']} · Wikimedia Commons"


class Generator:
    def __init__(self, films: list[Film], seed: int = 2026, music: list[dict] | None = None,
                 emojis: dict[str, str] | None = None):
        self.music = music or []
        self.emojis = emojis or {}
        self.films = films
        self.rng = random.Random(seed)
        set_tier_cuts(films)
        counts: dict[str, int] = defaultdict(int)
        for f in films:
            for k in {title_key(f.title_es), title_key(f.title_en)}:
                counts[k] += 1
        self.ambiguous = {f.qid for f in films
                          if counts[title_key(f.title_es)] > 1 or counts[title_key(f.title_en)] > 1}
        self._by_year = sorted(films, key=lambda f: f.year)
        self._years = [f.year for f in self._by_year]
        self.series: dict[str, list[Film]] = defaultdict(list)
        for f in films:
            if f.series:
                self.series[f.series].append(f)
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
        lo = bisect.bisect_left(self._years, film.year - span)
        hi = bisect.bisect_right(self._years, film.year + span)
        return [f for f in self._by_year[lo:hi] if f.qid != film.qid]

    def _similar_people(self, correct: Person, pool: dict[str, Person], banned: set[str],
                        k: int = 3) -> list[Person]:
        """Distractores reales de popularidad parecida, con nombres distintos."""
        names = {title_key(correct.name)}
        cands = [p for q, p in pool.items() if q not in banned and title_key(p.name) not in names]
        cands.sort(key=lambda p: abs(p.popularity - correct.popularity))
        out: list[Person] = []
        for p in self._pick(cands[:14], min(len(cands[:14]), 14)):
            if title_key(p.name) not in names:
                out.append(p)
                names.add(title_key(p.name))
            if len(out) == k:
                return out
        return []

    def _base(self, kind: str, film: Film, fmt: str, difficulty: int, topic: str, entities: list[str],
              prompt: dict, options: list[dict], answer, explanation: dict | None = None,
              key: str = "") -> Question:
        return {
            "external_id": _xid(kind, film.qid, key),
            "format": fmt,
            "difficulty": max(1, min(3, difficulty)),
            "topic": topic,
            "entity_ids": entities,
            "prompt": prompt,
            "options": options,
            "answer": answer,
            "explanation": explanation or _explanation(film),
            "source": f"wikidata:{film.qid}",
        }

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


    # -- tipos nuevos -----------------------------------------------------
    def q_character(self, film: Film) -> Question | None:
        """¿A quién interpreta X en la película?"""
        if not film.roles:
            return None
        role = film.roles[0]
        own = {title_key(r.character) for r in film.roles}
        tier = film_tier(film)
        pool = [clean_character(r.character) for f in self._era_films(film, 15)
                if f.qid != film.qid and abs(film_tier(f) - tier) <= 1
                for r in f.roles if title_key(r.character) not in own]
        wrong = self._pick(sorted(set(pool)), 3)
        if len({title_key(w) for w in wrong}) < 3:
            return None
        opts, idx = _shuffle_with_answer(self.rng, _opt(clean_character(role.character)),
                                         [_opt(w) for w in wrong])
        return self._base("character", film, "choice", 1 + film_tier(film), "character",
                          [film.qid, role.actor_qid],
                          {"es": f"¿A qué personaje interpreta {role.actor} en {_t(film, 'es')}?",
                           "en": f"Who does {role.actor} play in {_t(film, 'en')}?"},
                          opts, idx,
                          {"es": f"{role.actor} es {role.character} en {_t(film, 'es')} ({film.year}).",
                           "en": f"{role.actor} plays {role.character} in {_t(film, 'en')} ({film.year})."},
                          key=role.actor_qid)

    def q_actor_by_character(self, film: Film) -> Question | None:
        """¿Qué actor interpreta a <personaje>?"""
        if not film.roles:
            return None
        role = film.roles[-1] if len(film.roles) > 1 else film.roles[0]
        correct = next((p for p in film.cast if p.qid == role.actor_qid), None)
        if correct is None:
            return None
        pool = {p.qid: p for f in self._era_films(film, 8) for p in f.cast}
        wrong = self._similar_people(correct, pool, set(film.cast_all) | {p.qid for p in film.cast})
        if not wrong:
            return None
        opts, idx = _shuffle_with_answer(self.rng, _opt(correct.name), [_opt(p.name) for p in wrong])
        return self._base("actor_by_character", film, "choice", 1 + film_tier(film), "actor_by_character",
                          [film.qid, correct.qid],
                          {"es": f"¿Quién da vida a {role.character} en {_t(film, 'es')}?",
                           "en": f"Who plays {role.character} in {_t(film, 'en')}?"},
                          opts, idx,
                          {"es": f"{role.character} es {correct.name} en {_t(film, 'es')} ({film.year}).",
                           "en": f"{role.character} is played by {correct.name} in {_t(film, 'en')} ({film.year})."},
                          key=role.actor_qid)

    def _crew_question(self, film: Film, people: list[Person], kind: str, span: int,
                       prompt: dict, expl: tuple[str, str]) -> Question | None:
        if not people:
            return None
        correct = max(people, key=lambda p: p.popularity)
        attr = "composers" if kind == "composer" else "writers"
        pool = {p.qid: p for f in self._era_films(film, span) for p in getattr(f, attr)}
        banned = {p.qid for p in people}
        wrong = self._similar_people(correct, pool, banned)
        if not wrong:
            return None
        opts, idx = _shuffle_with_answer(self.rng, _opt(correct.name), [_opt(p.name) for p in wrong])
        return self._base(kind, film, "choice", 2 + film_tier(film) - (1 if correct.popularity >= 60 else 0),
                          kind, [film.qid, correct.qid], prompt, opts, idx,
                          {"es": expl[0].format(n=correct.name), "en": expl[1].format(n=correct.name)})

    def q_composer(self, film: Film) -> Question | None:
        return self._crew_question(
            film, film.composers, "composer", 15,
            {"es": f"¿Quién compuso la banda sonora de {_t(film, 'es')} ({film.year})?",
             "en": f"Who composed the score for {_t(film, 'en')} ({film.year})?"},
            (f"La música de {_t(film, 'es')} es de {{n}}.", f"The score of {_t(film, 'en')} is by {{n}}."))

    def q_writer(self, film: Film) -> Question | None:
        # Si el guionista es también el director, la pregunta es demasiado obvia
        writers = [w for w in film.writers if w.qid not in {d.qid for d in film.directors}]
        if not writers or len(writers) != len(film.writers):
            return None
        return self._crew_question(
            film, film.writers, "writer", 12,
            {"es": f"¿Quién escribió el guion de {_t(film, 'es')} ({film.year})?",
             "en": f"Who wrote the screenplay for {_t(film, 'en')} ({film.year})?"},
            (f"El guion de {_t(film, 'es')} es de {{n}}.", f"The screenplay of {_t(film, 'en')} is by {{n}}."))

    def q_book_author(self, film: Film) -> Question | None:
        """¿Quién escribió la obra en la que se basa la película?"""
        if len(film.based_on) != 1:
            return None
        work = film.based_on[0]
        if not work.authors:
            return None
        correct = max(work.authors, key=lambda p: p.popularity)
        pool = {a.qid: a for f in self._era_films(film, 25) for w in f.based_on for a in w.authors}
        wrong = self._similar_people(correct, pool, {a.qid for a in work.authors})
        if not wrong:
            return None
        opts, idx = _shuffle_with_answer(self.rng, _opt(correct.name), [_opt(p.name) for p in wrong])
        return self._base("book_author", film, "choice", 2 + film_tier(film), "book_author",
                          [film.qid, correct.qid, work.qid],
                          {"es": f"{_t(film, 'es')} ({film.year}) adapta una obra literaria. ¿Quién la escribió?",
                           "en": f"{_t(film, 'en')} ({film.year}) is based on a literary work. Who wrote it?"},
                          opts, idx,
                          {"es": f"Se basa en «{work.title_es}», de {correct.name}.",
                           "en": f"It is based on \u201c{work.title_en}\u201d by {correct.name}."})

    def q_based_on(self, film: Film) -> Question | None:
        """¿En qué obra se basa la película?"""
        if len(film.based_on) != 1:
            return None
        work = film.based_on[0]
        if titles_overlap(work, film):
            return None  # título parecido al de la película: sería regalada
        pool = {w.qid: w for f in self._era_films(film, 25) if f.qid != film.qid for w in f.based_on
                if title_key(w.title_es) != title_key(work.title_es)}
        wrong = self._pick(sorted(pool.values(), key=lambda w: w.qid), 3)
        if len({title_key(w.title_es) for w in wrong}) < 3:
            return None
        lab = lambda w: _opt(f"«{w.title_es}»", f"\u201c{w.title_en}\u201d")  # noqa: E731
        opts, idx = _shuffle_with_answer(self.rng, lab(work), [lab(w) for w in wrong])
        return self._base("based_on", film, "choice", 2 + film_tier(film), "based_on",
                          [film.qid, work.qid], 
                          {"es": f"¿En qué obra literaria se basa {_t(film, 'es')} ({film.year})?",
                           "en": f"Which literary work is {_t(film, 'en')} ({film.year}) based on?"},
                          opts, idx,
                          {"es": f"Adapta «{work.title_es}», de {', '.join(a.name for a in work.authors[:2])}.",
                           "en": f"It adapts \u201c{work.title_en}\u201d by {', '.join(a.name for a in work.authors[:2])}."})

    def _saga_sorted(self, sq: str) -> list[Film]:
        films = self.series.get(sq, [])
        if all(f.series_ordinal is not None for f in films):
            return sorted(films, key=lambda f: (f.series_ordinal, f.year))
        return sorted(films, key=lambda f: f.year)

    def q_saga_order(self, sq: str) -> Question | None:
        saga = self._saga_sorted(sq)
        years = [f.year for f in saga]
        if len(saga) < 3 or len(set(years)) != len(years):
            return None
        picks = sorted(self._pick(saga, min(4, len(saga))), key=lambda f: f.year)
        shown = picks[:]
        self.rng.shuffle(shown)
        answer = sorted(range(len(shown)), key=lambda i: shown[i].year)
        head = picks[0]
        return {
            "external_id": _xid("saga_order", sq, *sorted(f.qid for f in picks)),
            "format": "order",
            "difficulty": 2 if max(film_tier(f) for f in picks) <= 1 else 3,
            "topic": "saga_order",
            "entity_ids": [sq] + [f.qid for f in picks],
            "prompt": {"es": f"Saga «{head.series_es}»: ordena estas películas por fecha de estreno.",
                       "en": f"\u201c{head.series_en}\u201d: put these films in release order."},
            "options": [_opt(_t(f, "es"), _t(f, "en")) for f in shown],
            "answer": answer,
            "explanation": {
                "es": " → ".join(f"{_t(shown[i], 'es')} ({shown[i].year})" for i in answer),
                "en": " → ".join(f"{_t(shown[i], 'en')} ({shown[i].year})" for i in answer),
            },
            "source": f"wikidata:{sq}",
        }

    def q_saga_next(self, sq: str) -> Question | None:
        saga = self._saga_sorted(sq)
        if len(saga) < 4 or len({f.year for f in saga}) != len(saga):
            return None
        i = self.rng.randrange(0, len(saga) - 1)
        film, nxt = saga[i], saga[i + 1]
        others = [f for f in saga if f.qid not in (film.qid, nxt.qid)]
        wrong = self._pick(others, min(3, len(others)))
        if len(wrong) < 3:  # sagas cortas: se completa con películas de la misma época
            fill = [f for f in self._era_films(nxt, 5) if f.series != film.series
                    and title_key(f.title_es) not in {title_key(x.title_es) for x in saga}]
            wrong += self._pick(fill, 3 - len(wrong)) if len(fill) >= 3 - len(wrong) else []
        if len(wrong) < 3:
            return None
        lab = lambda f: _opt(_t(f, "es"), _t(f, "en"))  # noqa: E731
        opts, idx = _shuffle_with_answer(self.rng, lab(nxt), [lab(f) for f in wrong])
        return {
            "external_id": _xid("saga_next", sq, film.qid),
            "format": "choice",
            "difficulty": 2 if film_tier(film) == 0 else 3,
            "topic": "saga_next",
            "entity_ids": [sq] + [f.qid for f in saga],
            "prompt": {"es": f"En la saga «{film.series_es}», ¿qué película llegó justo después de {_t(film, 'es')} ({film.year})?",
                       "en": f"In the \u201c{film.series_en}\u201d series, which film came right after {_t(film, 'en')} ({film.year})?"},
            "options": opts,
            "answer": idx,
            "explanation": {"es": f"Después llegó {_t(nxt, 'es')} ({nxt.year}).",
                            "en": f"Next came {_t(nxt, 'en')} ({nxt.year})."},
            "source": f"wikidata:{sq}",
        }

    def q_country(self, film: Film) -> Question | None:
        if len(film.countries) != 1:
            return None
        iso = film.countries[0]
        if iso == "US" and self.rng.random() < 0.8:
            return None  # evitar que casi siempre la respuesta sea EE. UU.
        wrong = [c for c in self.rng.sample(COMMON_COUNTRIES, len(COMMON_COUNTRIES)) if c != iso][:3]
        opts, idx = _shuffle_with_answer(self.rng, _opt(country_name(iso, "es"), country_name(iso, "en")),
                                         [_opt(country_name(c, "es"), country_name(c, "en")) for c in wrong])
        return self._base("country", film, "choice", 1 + film_tier(film) + (1 if iso == "US" else 0),
                          "country", [film.qid],
                          {"es": f"¿De qué país es {self._tt(film, 'es').rstrip(',')} ({film.year})?",
                           "en": f"Which country is {self._tt(film, 'en').rstrip(',')} ({film.year}) from?"},
                          opts, idx)

    def q_filmed_in(self, film: Film) -> Question | None:
        shot = [c for c in film.filming_countries if c not in film.countries]
        if not shot:
            return None
        iso = self.rng.choice(shot)
        banned = set(film.filming_countries) | set(film.countries)
        wrong = [c for c in self.rng.sample(COMMON_COUNTRIES, len(COMMON_COUNTRIES)) if c not in banned][:3]
        opts, idx = _shuffle_with_answer(self.rng, _opt(country_name(iso, "es"), country_name(iso, "en")),
                                         [_opt(country_name(c, "es"), country_name(c, "en")) for c in wrong])
        return self._base("filmed_in", film, "choice", 2 + film_tier(film), "filmed_in", [film.qid],
                          {"es": f"¿En cuál de estos países se rodó parte de {_t(film, 'es')} ({film.year})?",
                           "en": f"In which of these countries was part of {_t(film, 'en')} ({film.year}) filmed?"},
                          opts, idx,
                          {"es": f"Parte del rodaje fue en {country_name(iso, 'es')}.",
                           "en": f"Part of it was filmed in {country_name(iso, 'en')}."}, key=iso)

    def q_longest(self, films: list[Film]) -> Question | None:
        if len(films) != 4 or any(f.duration is None for f in films):
            return None
        durs = sorted(f.duration for f in films)
        if durs[-1] - durs[-2] < 12:
            return None  # diferencia clara
        longest = max(films, key=lambda f: f.duration)
        shown = films[:]
        self.rng.shuffle(shown)
        return {
            "external_id": _xid("longest", *sorted(f.qid for f in films)),
            "format": "choice",
            "difficulty": 2 if durs[-1] - durs[-2] >= 25 else 3,
            "topic": "longest",
            "entity_ids": [f.qid for f in films],
            "prompt": {"es": "¿Cuál de estas películas dura más?",
                       "en": "Which of these films is the longest?"},
            "options": [_opt(_t(f, "es"), _t(f, "en")) for f in shown],
            "answer": shown.index(longest),
            "explanation": {"es": ", ".join(f"{_t(f, 'es')}: {f.duration} min" for f in shown),
                            "en": ", ".join(f"{_t(f, 'en')}: {f.duration} min" for f in shown)},
            "source": "wikidata",
        }

    def q_cast_intruder(self, film: Film) -> Question | None:
        directors = {d.qid for d in film.directors}
        actors = [p for p in film.cast if p.qid not in directors]
        if len(actors) < 3:
            return None
        members = actors[:3]
        pool = {p.qid: p for f in self._era_films(film, 6) for p in f.cast}
        banned = set(film.cast_all) | {p.qid for p in film.cast}
        top = max(members, key=lambda p: p.popularity)
        intruder = self._similar_people(top, pool, banned, k=1)
        if not intruder:
            return None
        if title_key(intruder[0].name) in {title_key(p.name) for p in members}:
            return None
        opts, idx = _shuffle_with_answer(self.rng, _opt(intruder[0].name), [_opt(p.name) for p in members])
        return self._base("cast_intruder", film, "intruder", 1 + film_tier(film), "cast_intruder",
                          [film.qid, intruder[0].qid] + [p.qid for p in members],
                          {"es": f"¿Qué actor o actriz NO aparece en {_t(film, 'es')} ({film.year})?",
                           "en": f"Which actor is NOT in {_t(film, 'en')} ({film.year})?"},
                          opts, idx,
                          {"es": f"En {_t(film, 'es')} actúan {', '.join(p.name for p in members)}.",
                           "en": f"{_t(film, 'en')} stars {', '.join(p.name for p in members)}."})

    def q_clues(self, film: Film) -> Question | None:
        """Adivina la película con tres pistas (año, director y protagonista)."""
        if not film.cast or film.qid in self.ambiguous:
            return None
        d, star = film.directors[0], film.cast[0]
        others = [f for f in self._era_films(film, 3)
                  if d.qid not in {x.qid for x in f.directors} and star.qid not in f.cast_all
                  and title_key(f.title_es) != title_key(film.title_es)]
        others.sort(key=lambda f: abs(f.popularity - film.popularity))
        wrong = self._pick(others[:12], 3)
        if not wrong:
            return None
        lab = lambda f: _opt(_t(f, "es"), _t(f, "en"))  # noqa: E731
        opts, idx = _shuffle_with_answer(self.rng, lab(film), [lab(f) for f in wrong])
        return self._base("clues", film, "clues", 1 + film_tier(film), "clues",
                          [film.qid, d.qid, star.qid],
                          {"es": f"🎬 {film.year} · 🎥 Dirigida por {d.name} · ⭐ Con {star.name}. ¿Qué película es?",
                           "en": f"🎬 {film.year} · 🎥 Directed by {d.name} · ⭐ Starring {star.name}. Which film is it?"},
                          opts, idx)

    # -- multimedia -------------------------------------------------------
    def _film_options(self, film: Film, exclude: set[str], span: int = 6,
                      extra_ok=lambda f: True) -> tuple[list[dict], int] | None:
        others = [f for f in self._era_films(film, span)
                  if f.qid not in exclude and extra_ok(f)
                  and title_key(f.title_es) != title_key(film.title_es)]
        others.sort(key=lambda f: abs(f.popularity - film.popularity))
        wrong = self._pick(others[:12], 3)
        if len({title_key(f.title_es) for f in wrong}) < 3:
            return None
        lab = lambda f: _opt(_t(f, "es"), _t(f, "en"))  # noqa: E731
        return _shuffle_with_answer(self.rng, lab(film), [lab(f) for f in wrong])

    def q_location_photo(self, film: Film) -> Question | None:
        if not film.location_photos or film_tier(film) > 1:
            return None
        loc = film.location_photos[0]
        res = self._film_options(film, {film.qid}, span=10,
                                 extra_ok=lambda f: loc["qid"] not in {l["qid"] for l in f.location_photos})
        if not res:
            return None
        opts, idx = res
        q = self._base("location_photo", film, "image_choice", 2 + film_tier(film), "location_photo",
                       [film.qid, loc["qid"]],
                       {"es": "📍 ¿Qué película se rodó en este lugar?",
                        "en": "📍 Which film was shot at this location?"},
                       opts, idx,
                       {"es": f"Es {loc['name_es']}, escenario de {_t(film, 'es')} ({film.year}).",
                        "en": f"This is {loc['name_en']}, a filming location of {_t(film, 'en')} ({film.year})."},
                       key=loc["qid"])
        q["image_url"] = loc["url"]
        q["image_attribution"] = _media_credit(loc, "Foto")
        return q

    def q_still(self, film: Film) -> Question | None:
        if not film.still:
            return None
        res = self._film_options(film, {film.qid}, span=8)
        if not res:
            return None
        opts, idx = res
        q = self._base("still", film, "image_reveal", 2 + (1 if film_tier(film) == 2 else 0), "still",
                       [film.qid],
                       {"es": "🎞️ ¿A qué película pertenece esta imagen?",
                        "en": "🎞️ Which film is this image from?"},
                       opts, idx)
        q["image_url"] = film.still["url"]
        q["image_attribution"] = _media_credit(film.still, "Imagen") + " · Dominio público"
        return q

    def q_emoji(self, film: Film) -> Question | None:
        emo = self.emojis.get(film.qid)
        if not emo:
            return None
        res = self._film_options(film, {film.qid}, span=10, extra_ok=lambda f: film_tier(f) <= 1)
        if not res:
            return None
        opts, idx = res
        return self._base("emoji", film, "emoji", 1 + film_tier(film), "emoji", [film.qid],
                          {"es": f"{emo}\n¿Qué película es?", "en": f"{emo}\nWhich film is it?"},
                          opts, idx)

    def _music_questions(self) -> list[Question]:
        out: list[Question] = []
        by_qid = {f.qid: f for f in self.films}
        for it in self.music:
            film = by_qid.get(it["film_qids"][0])
            if not film:
                continue
            rec = it["recording"]
            credit = f"{it['composer']} · {_media_credit(rec, 'Grabación')}"
            expl = {"es": f"Es «{it['piece_es']}», de {it['composer']}, que suena en {_t(film, 'es')} ({film.year}).",
                    "en": f"It is \u201c{it['piece_en']}\u201d by {it['composer']}, heard in {_t(film, 'en')} ({film.year})."}
            res = self._film_options(film, set(it["film_qids"]), span=15, extra_ok=lambda f: film_tier(f) <= 1)
            if res:
                opts, idx = res
                q = self._base("music_film", film, "audio", 2, "music_film", [film.qid, "music:" + it["search"]],
                               {"es": "🎵 Escucha: ¿en qué película famosa suena esta pieza?",
                                "en": "🎵 Listen: which famous film features this piece?"},
                               opts, idx, expl, key=it["search"])
                q.update(audio_url=rec["url"], audio_attribution=credit, _audio_start_s=it.get("start_s", 0))
                out.append(q)
            others = [m for m in self.music if m is not it and m["composer"] != it["composer"]]
            wrong = self._pick(others, 3)
            if len(wrong) == 3:
                lab = lambda m: _opt(f"{m['piece_es']} ({m['composer']})", f"{m['piece_en']} ({m['composer']})")  # noqa: E731
                opts, idx = _shuffle_with_answer(self.rng, lab(it), [lab(m) for m in wrong])
                q = self._base("music_piece", film, "audio", 2, "music_piece", ["music:" + it["search"]],
                               {"es": f"🎵 Suena en {_t(film, 'es')}. ¿Qué pieza es?",
                                "en": f"🎵 Heard in {_t(film, 'en')}. Which piece is this?"},
                               opts, idx, expl, key="piece" + it["search"])
                q.update(audio_url=rec["url"], audio_attribution=credit, _audio_start_s=it.get("start_s", 0))
                out.append(q)
        return out

    # -- generación masiva ------------------------------------------------
    def generate_all(self) -> list[Question]:
        out: list[Question] = []
        per_film: list[Callable[[Film], Question | None]] = [
            self.q_director, self.q_decade, self.q_true_false_year, self.q_cast, self.q_true_false_oscar,
            self.q_character, self.q_actor_by_character, self.q_composer, self.q_writer,
            self.q_book_author, self.q_based_on, self.q_country, self.q_filmed_in,
            self.q_cast_intruder, self.q_clues, self.q_location_photo, self.q_still, self.q_emoji,
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
        out += self._music_questions()
        for sq in self.series:
            for fn in (self.q_saga_order, self.q_saga_next):
                q = fn(sq)
                if q:
                    out.append(q)
        # ¿Cuál dura más?: grupos de 4 películas conocidas de la misma época
        timed = [f for f in self._by_year if f.duration and film_tier(f) <= 1]
        for i in range(0, len(timed) - 8, 3):
            q = self.q_longest(self._pick(timed[i : i + 8], 4))
            if q:
                out.append(q)
        uniq = {q["external_id"]: q for q in out}
        return list(uniq.values())
