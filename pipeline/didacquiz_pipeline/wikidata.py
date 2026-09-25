"""Descarga de datos de películas desde Wikidata (licencia CC0).

Todas las respuestas correctas del juego salen de aquí: la IA nunca inventa datos.
"""
from __future__ import annotations

import json
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path

import requests

ENDPOINT = "https://query.wikidata.org/sparql"
USER_AGENT = "DidacQuizPipeline/1.0 (https://github.com/AlexLube/didac-quiz)"

BEST_PICTURE_OSCAR = "Q102427"  # Academy Award for Best Picture


@dataclass
class Person:
    qid: str
    name: str
    popularity: int = 0


@dataclass
class Film:
    qid: str
    title_es: str
    title_en: str
    year: int
    popularity: int                       # nº de Wikipedias con artículo (sitelinks)
    directors: list[Person] = field(default_factory=list)
    cast: list[Person] = field(default_factory=list)       # principales, por popularidad
    cast_all: list[str] = field(default_factory=list)      # QIDs de todo el reparto conocido
    countries: list[str] = field(default_factory=list)     # códigos ISO
    awards: list[str] = field(default_factory=list)        # 'oscar_best_picture', 'goya_best_film'

    @staticmethod
    def from_dict(d: dict) -> "Film":
        d = dict(d)
        d["directors"] = [Person(**p) for p in d.get("directors", [])]
        d["cast"] = [Person(**p) for p in d.get("cast", [])]
        return Film(**d)


def _sparql(query: str, retries: int = 5) -> list[dict]:
    """Consulta con reintentos. Wikidata a veces corta la respuesta (JSON incompleto)."""
    last_error: Exception | None = None
    for attempt in range(retries):
        try:
            r = requests.get(
                ENDPOINT,
                params={"query": query, "format": "json"},
                headers={"User-Agent": USER_AGENT, "Accept": "application/sparql-results+json"},
                timeout=120,
            )
            if r.status_code == 200:
                return json.loads(r.text, strict=False)["results"]["bindings"]
            if r.status_code not in (429, 500, 502, 503, 504):
                r.raise_for_status()
            last_error = RuntimeError(f"HTTP {r.status_code}")
        except (ValueError, requests.RequestException) as e:  # JSON cortado o red
            last_error = e
        time.sleep(10 * (attempt + 1))
    raise RuntimeError(f"Wikidata no respondió tras varios intentos: {last_error}")


def _sparql_chunked(template: str, ids: list[str]) -> list[dict]:
    """Si un bloque falla, lo divide en dos; si un solo elemento falla, lo omite."""
    try:
        return _sparql(template.format(values=" ".join(f"wd:{q}" for q in ids)), retries=3)
    except RuntimeError:
        if len(ids) == 1:
            print(f"  aviso: se omite {ids[0]} (Wikidata no respondió)")
            return []
        mid = len(ids) // 2
        return _sparql_chunked(template, ids[:mid]) + _sparql_chunked(template, ids[mid:])


def _val(b: dict, k: str) -> str | None:
    return b[k]["value"] if k in b else None


def _qid(uri: str) -> str:
    return uri.rsplit("/", 1)[-1]


FILMS_QUERY = """
SELECT ?film ?es ?en ?date ?links ?dir ?dirEs ?dirEn ?dirLinks ?iso WHERE {{
  ?film wdt:P31 wd:Q11424 ;
        wikibase:sitelinks ?links ;
        wdt:P577 ?date ;
        wdt:P57 ?dir .
  FILTER(?links >= {min_links})
  FILTER(YEAR(?date) >= {y0} && YEAR(?date) < {y1})
  ?dir wikibase:sitelinks ?dirLinks .
  OPTIONAL {{ ?film rdfs:label ?es FILTER(LANG(?es) = "es") }}
  OPTIONAL {{ ?film rdfs:label ?en FILTER(LANG(?en) = "en") }}
  OPTIONAL {{ ?dir rdfs:label ?dirEs FILTER(LANG(?dirEs) = "es") }}
  OPTIONAL {{ ?dir rdfs:label ?dirEn FILTER(LANG(?dirEn) = "en") }}
  OPTIONAL {{ ?film wdt:P495 ?country . ?country wdt:P297 ?iso }}
}}
"""

CAST_QUERY = """
SELECT ?film ?actor ?es ?en ?links WHERE {{
  VALUES ?film {{ {values} }}
  ?film wdt:P161 ?actor .
  ?actor wikibase:sitelinks ?links .
  OPTIONAL {{ ?actor rdfs:label ?es FILTER(LANG(?es) = "es") }}
  OPTIONAL {{ ?actor rdfs:label ?en FILTER(LANG(?en) = "en") }}
}}
"""

AWARDS_QUERY = """
SELECT ?film ?award WHERE {{
  VALUES ?award {{ {awards} }}
  ?film p:P166 ?st . ?st ps:P166 ?award .
}}
"""

GOYA_LOOKUP = """
SELECT ?award WHERE { ?award rdfs:label "Goya Award for Best Film"@en } LIMIT 1
"""


def fetch_films(min_links: int = 20, cast_per_film: int = 4, verbose: bool = True) -> list[Film]:
    films: dict[str, Film] = {}
    decades = [(1895, 1930)] + [(y, y + 10) for y in range(1930, 2030, 10)]
    for y0, y1 in decades:
        rows = _sparql(FILMS_QUERY.format(min_links=min_links, y0=y0, y1=y1))
        for b in rows:
            fq = _qid(_val(b, "film"))
            title_en = _val(b, "en") or _val(b, "es")
            if not title_en:
                continue
            year = int(_val(b, "date")[:4])
            f = films.get(fq)
            if f is None:
                f = films[fq] = Film(
                    qid=fq,
                    title_es=_val(b, "es") or title_en,
                    title_en=title_en,
                    year=year,
                    popularity=int(_val(b, "links")),
                )
            f.year = min(f.year, year)  # primera fecha de estreno
            dq = _qid(_val(b, "dir"))
            dname = _val(b, "dirEs") or _val(b, "dirEn")
            if dname and all(d.qid != dq for d in f.directors):
                f.directors.append(Person(dq, dname, int(_val(b, "dirLinks"))))
            iso = _val(b, "iso")
            if iso and iso not in f.countries:
                f.countries.append(iso)
        if verbose:
            print(f"  {y0}-{y1}: {len(films)} películas acumuladas")

    ids = list(films)
    for i in range(0, len(ids), 100):
        chunk = ids[i : i + 100]
        rows = _sparql_chunked(CAST_QUERY, chunk)
        per_film: dict[str, dict[str, Person]] = {}
        for b in rows:
            fq, aq = _qid(_val(b, "film")), _qid(_val(b, "actor"))
            name = _val(b, "es") or _val(b, "en")
            per_film.setdefault(fq, {})
            if name:
                per_film[fq][aq] = Person(aq, name, int(_val(b, "links")))
            films[fq].cast_all.append(aq)
        for fq, people in per_film.items():
            films[fq].cast = sorted(people.values(), key=lambda p: -p.popularity)[:cast_per_film]
            films[fq].cast_all = sorted(set(films[fq].cast_all))

    goya = _sparql(GOYA_LOOKUP)
    award_ids = {BEST_PICTURE_OSCAR: "oscar_best_picture"}
    if goya:
        award_ids[_qid(_val(goya[0], "award"))] = "goya_best_film"
    rows = _sparql(AWARDS_QUERY.format(awards=" ".join(f"wd:{a}" for a in award_ids)))
    for b in rows:
        fq = _qid(_val(b, "film"))
        if fq in films:
            tag = award_ids[_qid(_val(b, "award"))]
            if tag not in films[fq].awards:
                films[fq].awards.append(tag)
    return [f for f in films.values() if f.directors]


def save_films(films: list[Film], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps([asdict(f) for f in films], ensure_ascii=False, indent=1), encoding="utf-8")


def load_films(path: Path) -> list[Film]:
    return [Film.from_dict(d) for d in json.loads(path.read_text(encoding="utf-8"))]
