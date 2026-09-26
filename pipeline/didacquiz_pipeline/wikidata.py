"""Descarga de datos de películas desde Wikidata (licencia CC0).

Todas las respuestas correctas del juego salen de aquí: la IA nunca inventa datos.
"""
from __future__ import annotations

import json
import re
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
class Role:
    actor_qid: str
    actor: str
    character: str


@dataclass
class Work:
    qid: str
    title_es: str
    title_en: str
    authors: list[Person] = field(default_factory=list)


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
    roles: list[Role] = field(default_factory=list)        # personaje de cada actor principal
    composers: list[Person] = field(default_factory=list)  # banda sonora
    writers: list[Person] = field(default_factory=list)    # guion
    based_on: list[Work] = field(default_factory=list)     # obra literaria original
    series: str | None = None                              # QID de la saga
    series_es: str | None = None
    series_en: str | None = None
    series_ordinal: float | None = None                    # posición en la saga (si consta)
    duration: int | None = None                            # minutos
    filming_countries: list[str] = field(default_factory=list)
    location_photos: list[dict] = field(default_factory=list)  # fotos libres de lugares de rodaje
    still: dict | None = None             # imagen de dominio público (solo cine antiguo)

    @staticmethod
    def from_dict(d: dict) -> "Film":
        d = dict(d)
        for k in ("directors", "cast", "composers", "writers"):
            d[k] = [Person(**p) for p in d.get(k, [])]
        d["roles"] = [Role(**r) for r in d.get("roles", [])]
        d["based_on"] = [Work(qid=w["qid"], title_es=w["title_es"], title_en=w["title_en"],
                              authors=[Person(**a) for a in w.get("authors", [])])
                         for w in d.get("based_on", [])]
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
  VALUES ?type {{ wd:Q11424 wd:Q202866 wd:Q29168811 wd:Q24869 }}   # película, animación, largometraje
  ?film wdt:P31 ?type ;
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

# isActor: solo actores de profesión (evita políticos o cantantes que salen en
# imágenes de archivo, como Kennedy en «The Man from U.N.C.L.E.»)
CAST_QUERY = """
SELECT ?film ?actor ?es ?en ?links (SAMPLE(?flag) AS ?isActor) WHERE {{
  VALUES ?film {{ {values} }}
  ?film wdt:P161 ?actor .
  ?actor wikibase:sitelinks ?links .
  OPTIONAL {{ ?actor rdfs:label ?es FILTER(LANG(?es) = "es") }}
  OPTIONAL {{ ?actor rdfs:label ?en FILTER(LANG(?en) = "en") }}
  OPTIONAL {{
    ?actor wdt:P106 ?occ .
    VALUES ?occ {{ wd:Q33999 wd:Q10800557 wd:Q10798782 wd:Q2259451 wd:Q2405480 wd:Q970153
                  wd:Q948329 wd:Q245068 wd:Q465501 }}
    BIND(1 AS ?flag)
  }}
}} GROUP BY ?film ?actor ?es ?en ?links
"""

ROLES_QUERY = """
SELECT ?film ?actor ?charEs ?charEn ?charStr WHERE {{
  VALUES ?film {{ {values} }}
  ?film p:P161 ?st . ?st ps:P161 ?actor .
  {{ ?st pq:P453 ?char .
     OPTIONAL {{ ?char rdfs:label ?charEs FILTER(LANG(?charEs) = "es") }}
     OPTIONAL {{ ?char rdfs:label ?charEn FILTER(LANG(?charEn) = "en") }} }}
  UNION
  {{ ?st pq:P4633 ?charStr }}
}}
"""

CREW_QUERY = """
SELECT ?film ?prop ?p ?es ?en ?links WHERE {{
  VALUES ?film {{ {values} }}
  VALUES ?prop {{ wdt:P86 wdt:P58 }}
  ?film ?prop ?p .
  ?p wikibase:sitelinks ?links .
  OPTIONAL {{ ?p rdfs:label ?es FILTER(LANG(?es) = "es") }}
  OPTIONAL {{ ?p rdfs:label ?en FILTER(LANG(?en) = "en") }}
}}
"""

BASED_ON_QUERY = """
SELECT ?film ?work ?wEs ?wEn ?author ?aEs ?aEn ?aLinks WHERE {{
  VALUES ?film {{ {values} }}
  ?film wdt:P144 ?work .
  ?work wdt:P50 ?author .
  ?author wikibase:sitelinks ?aLinks .
  OPTIONAL {{ ?work rdfs:label ?wEs FILTER(LANG(?wEs) = "es") }}
  OPTIONAL {{ ?work rdfs:label ?wEn FILTER(LANG(?wEn) = "en") }}
  OPTIONAL {{ ?author rdfs:label ?aEs FILTER(LANG(?aEs) = "es") }}
  OPTIONAL {{ ?author rdfs:label ?aEn FILTER(LANG(?aEn) = "en") }}
}}
"""

SERIES_QUERY = """
SELECT ?film ?series ?sEs ?sEn ?ord WHERE {{
  VALUES ?film {{ {values} }}
  ?film p:P179 ?st . ?st ps:P179 ?series .
  OPTIONAL {{ ?st pq:P1545 ?ord }}
  OPTIONAL {{ ?series rdfs:label ?sEs FILTER(LANG(?sEs) = "es") }}
  OPTIONAL {{ ?series rdfs:label ?sEn FILTER(LANG(?sEn) = "en") }}
}}
"""

DURATION_QUERY = """
SELECT ?film ?amount WHERE {{
  VALUES ?film {{ {values} }}
  ?film p:P2047/psv:P2047 ?v .
  ?v wikibase:quantityAmount ?amount ; wikibase:quantityUnit wd:Q7727 .
}}
"""

FILMING_QUERY = """
SELECT DISTINCT ?film ?iso WHERE {{
  VALUES ?film {{ {values} }}
  ?film wdt:P915 ?loc .
  {{ ?loc wdt:P297 ?iso }} UNION {{ ?loc wdt:P17 ?c . ?c wdt:P297 ?iso }}
}}
"""

LOCATION_PHOTO_QUERY = """
SELECT ?film ?loc ?lEs ?lEn ?img WHERE {{
  VALUES ?film {{ {values} }}
  ?film wdt:P915 ?loc .
  ?loc wdt:P18 ?img .
  OPTIONAL {{ ?loc rdfs:label ?lEs FILTER(LANG(?lEs) = "es") }}
  OPTIONAL {{ ?loc rdfs:label ?lEn FILTER(LANG(?lEn) = "en") }}
}}
"""

STILL_QUERY = """
SELECT ?film ?img WHERE {{
  VALUES ?film {{ {values} }}
  ?film wdt:P18 ?img .
}}
"""

DEATHS_QUERY = """
SELECT ?p ?death WHERE {{
  VALUES ?p {{ {values} }}
  ?p wdt:P570 ?death .
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
            if name and _val(b, "isActor"):
                per_film[fq][aq] = Person(aq, name, int(_val(b, "links")))
            films[fq].cast_all.append(aq)
        for fq, people in per_film.items():
            films[fq].cast = sorted(people.values(), key=lambda p: -p.popularity)[:cast_per_film]
            films[fq].cast_all = sorted(set(films[fq].cast_all))

    fetch_details(films, ids, verbose=verbose)
    fetch_media(films, verbose=verbose)

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


_BAD_ROLE = ("himself", "herself", "themselves", "él mismo", "ella misma", "narrator", "narrador",
             "voice", "voz", "cameo", "uncredited", "extra", "self")


def _good_character(name: str | None, actor: str) -> bool:
    if not name or not 2 <= len(name) <= 40:
        return False
    low = name.lower()
    if any(b in low for b in _BAD_ROLE) or name.startswith("Q"):
        return False
    return actor.split()[-1].lower() not in low  # "Tom Hanks" en "Tom Hanks (voz)"


def _chunks(ids: list[str], n: int = 100):
    for i in range(0, len(ids), n):
        yield ids[i : i + n]


def fetch_details(films: dict[str, "Film"], ids: list[str], verbose: bool = True) -> None:
    """Personajes, compositor, guionista, obra original, saga, duración y rodaje."""
    named = {fq: {p.qid: p.name for p in f.cast} for fq, f in films.items()}
    for n, chunk in enumerate(_chunks(ids)):
        for b in _sparql_chunked(ROLES_QUERY, chunk):
            fq, aq = _qid(_val(b, "film")), _qid(_val(b, "actor"))
            actor = named.get(fq, {}).get(aq)
            char = _val(b, "charEs") or _val(b, "charEn") or _val(b, "charStr")
            if actor and _good_character(char, actor) and all(r.actor_qid != aq for r in films[fq].roles):
                films[fq].roles.append(Role(aq, actor, char))

        for b in _sparql_chunked(CREW_QUERY, chunk):
            fq, pq = _qid(_val(b, "film")), _qid(_val(b, "p"))
            name = _val(b, "es") or _val(b, "en")
            if not name or name.startswith("Q"):
                continue
            target = films[fq].composers if _val(b, "prop").endswith("P86") else films[fq].writers
            if all(x.qid != pq for x in target):
                target.append(Person(pq, name, int(_val(b, "links"))))

        for b in _sparql_chunked(BASED_ON_QUERY, chunk):
            fq, wq = _qid(_val(b, "film")), _qid(_val(b, "work"))
            wen = _val(b, "wEn") or _val(b, "wEs")
            aname = _val(b, "aEs") or _val(b, "aEn")
            if not wen or not aname:
                continue
            work = next((w for w in films[fq].based_on if w.qid == wq), None)
            if work is None:
                work = Work(wq, _val(b, "wEs") or wen, wen)
                films[fq].based_on.append(work)
            aq = _qid(_val(b, "author"))
            if all(a.qid != aq for a in work.authors):
                work.authors.append(Person(aq, aname, int(_val(b, "aLinks"))))

        for b in _sparql_chunked(SERIES_QUERY, chunk):
            fq = _qid(_val(b, "film"))
            f = films[fq]
            if f.series:
                continue  # una sola saga por película
            name_en = _val(b, "sEn") or _val(b, "sEs")
            if not name_en:
                continue
            f.series = _qid(_val(b, "series"))
            f.series_en, f.series_es = name_en, _val(b, "sEs") or name_en
            try:
                f.series_ordinal = float(_val(b, "ord")) if _val(b, "ord") else None
            except ValueError:
                f.series_ordinal = None

        for b in _sparql_chunked(DURATION_QUERY, chunk):
            fq = _qid(_val(b, "film"))
            try:
                minutes = round(float(_val(b, "amount")))
            except (TypeError, ValueError):
                continue
            if 40 <= minutes <= 400 and films[fq].duration is None:
                films[fq].duration = minutes

        for b in _sparql_chunked(FILMING_QUERY, chunk):
            fq, iso = _qid(_val(b, "film")), _val(b, "iso")
            if iso and iso not in films[fq].filming_countries:
                films[fq].filming_countries.append(iso)
        if verbose and n % 20 == 0:
            print(f"  detalles: {min((n + 1) * 100, len(ids))}/{len(ids)}")


_POSTER = re.compile(r"poster|affiche|cartel|plakat|lobby|card|title|locandina|cartaz", re.I)


def fetch_media(films: dict[str, "Film"], verbose: bool = True) -> None:
    """Fotos libres de lugares de rodaje e imágenes de cine antiguo en dominio público."""
    from . import media

    # 1) Lugares de rodaje con foto (solo películas conocidas y lugares concretos)
    known = [fq for fq, f in films.items() if f.popularity >= 45]
    raw: dict[str, list[dict]] = {}
    loc_use: dict[str, int] = {}
    for chunk in _chunks(known):
        for b in _sparql_chunked(LOCATION_PHOTO_QUERY, chunk):
            fq, lq = _qid(_val(b, "film")), _qid(_val(b, "loc"))
            name_en = _val(b, "lEn") or _val(b, "lEs")
            if not name_en:
                continue
            raw.setdefault(fq, []).append({"qid": lq, "name_es": _val(b, "lEs") or name_en, "name_en": name_en,
                                           "file": media.filename_from_url(_val(b, "img"))})
    for items in raw.values():
        for lq in {i["qid"] for i in items}:
            loc_use[lq] = loc_use.get(lq, 0) + 1
    files = [i["file"] for items in raw.values() for i in items if loc_use[i["qid"]] <= 2]
    infos = media.file_infos(files)
    for fq, items in raw.items():
        seen = set()
        for i in items:
            info = infos.get(i["file"])
            if loc_use[i["qid"]] > 2 or not info or not info["ok"] or i["qid"] in seen:
                continue
            seen.add(i["qid"])
            films[fq].location_photos.append({**i, "url": info["thumb"], "license": info["license"],
                                              "artist": info["artist"], "mime": info["mime"]})
    if verbose:
        print(f"  fotos de lugares de rodaje: {sum(len(f.location_photos) for f in films.values())}")

    # 2) Cine antiguo en dominio público en la UE: autores fallecidos hace más de 70 años
    limit_year = time.gmtime().tm_year - 71
    old = [fq for fq, f in films.items() if f.year <= 1950]
    people = sorted({p.qid for fq in old for p in films[fq].directors + films[fq].writers
                     + films[fq].composers})
    deaths: dict[str, int] = {}
    for chunk in _chunks(people):
        for b in _sparql_chunked(DEATHS_QUERY.replace("?film", "?p"), chunk):
            try:
                deaths[_qid(_val(b, "p"))] = int(_val(b, "death")[:4])
            except (TypeError, ValueError):
                pass
    pd_films = [fq for fq in old
                if all(deaths.get(p.qid, 9999) <= limit_year
                       for p in films[fq].directors + films[fq].writers + films[fq].composers)]
    stills: dict[str, str] = {}
    for chunk in _chunks(pd_films):
        for b in _sparql_chunked(STILL_QUERY, chunk):
            name = media.filename_from_url(_val(b, "img"))
            if not _POSTER.search(name):
                stills.setdefault(_qid(_val(b, "film")), name)
    infos = media.file_infos(list(stills.values()))
    for fq, name in stills.items():
        info = infos.get(name)
        if info and info["ok"] and info["mime"].startswith("image"):
            films[fq].still = {"file": name, "url": info["thumb"], "license": info["license"],
                               "artist": info["artist"], "mime": info["mime"]}
    if verbose:
        print(f"  imágenes de dominio público: {sum(1 for f in films.values() if f.still)}")


def resolve_music(films: list["Film"], path: Path | None = None) -> list[dict]:
    """Lista curada de música clásica de cine: busca grabaciones libres en Commons."""
    from . import media
    path = path or Path(__file__).with_name("music.json")
    items = json.loads(path.read_text(encoding="utf-8"))
    by_title = {}
    for f in films:
        for t in (f.title_en, f.title_es):
            by_title.setdefault((t.lower(), f.year), f)
    out = []
    for it in items:
        qids = []
        for title, year in it["films"]:
            f = next((by_title.get((title.lower(), y)) for y in (year, year - 1, year + 1)
                      if by_title.get((title.lower(), y))), None)
            if f:
                qids.append(f.qid)
        if not qids:
            print(f"  música: no encuentro la película de «{it['piece_es']}»")
            continue
        recs = media.search_audio(it["search"])
        if not recs:
            print(f"  música: sin grabación libre para «{it['piece_es']}»")
            continue
        out.append({**it, "film_qids": qids, "recording": recs[0]})
    print(f"  música: {len(out)} piezas con grabación libre")
    return out


def save_films(films: list[Film], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps([asdict(f) for f in films], ensure_ascii=False, indent=1), encoding="utf-8")


def load_films(path: Path) -> list[Film]:
    return [Film.from_dict(d) for d in json.loads(path.read_text(encoding="utf-8"))]
