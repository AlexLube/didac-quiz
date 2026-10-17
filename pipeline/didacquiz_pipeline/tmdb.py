"""Fotogramas, fotos del reparto y tráileres (TMDB) y bandas sonoras (Deezer).

- TMDB: https://www.themoviedb.org (clave gratuita en el secreto TMDB_TOKEN).
  La película se localiza por su identificador de Wikidata, así que no hay
  confusiones entre títulos parecidos.
- Deezer: fragmentos de 30 s de la banda sonora oficial (sin clave).

Todo se guarda en data/tmdb.json para no repetir consultas entre ejecuciones.
"""
from __future__ import annotations

import json
import os
import re
import time
import unicodedata
from pathlib import Path

import requests

from .wikidata import Film

API = "https://api.themoviedb.org/3"
IMG = "https://image.tmdb.org/t/p/"
DEEZER = "https://api.deezer.com"
UA = {"User-Agent": "DidacQuiz/1.0 (https://didacine.com)"}
CACHE_VERSION = 1


def _auth() -> tuple[dict, dict] | None:
    token = os.environ.get("TMDB_TOKEN", "").strip()
    key = os.environ.get("TMDB_API_KEY", "").strip()
    if token:
        return {**UA, "Authorization": f"Bearer {token}"}, {}
    if key:
        return dict(UA), {"api_key": key}
    return None


def _get(url: str, headers: dict, params: dict, retries: int = 4) -> dict | None:
    for i in range(retries):
        try:
            r = requests.get(url, headers=headers, params=params, timeout=20)
        except requests.RequestException:
            time.sleep(2 ** i)
            continue
        if r.status_code == 429:
            time.sleep(int(r.headers.get("Retry-After", 2 ** i)))
            continue
        if r.status_code == 404:
            return None
        if r.ok:
            return r.json()
        time.sleep(2 ** i)
    return None


def norm(s: str) -> str:
    s = unicodedata.normalize("NFKD", s or "").encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", " ", s).strip()


def parse_movie(data: dict) -> dict:
    """Se queda con lo útil de la ficha de TMDB."""
    images = data.get("images") or {}
    # Fotogramas sin texto (iso_639_1 nulo): no delatan el título.
    backdrops = sorted((b for b in images.get("backdrops") or [] if not b.get("iso_639_1")),
                       key=lambda b: -(b.get("vote_average") or 0))
    videos = [v for v in (data.get("videos") or {}).get("results") or []
              if v.get("site") == "YouTube" and v.get("type") == "Trailer" and v.get("official")]
    videos.sort(key=lambda v: (v.get("iso_639_1") != "es", v.get("iso_639_1") != "en"))
    cast = [{"name": c["name"], "profile": c["profile_path"]}
            for c in ((data.get("credits") or {}).get("cast") or [])[:10] if c.get("profile_path")]
    return {
        "id": data.get("id"),
        "backdrops": [b["file_path"] for b in backdrops[:4]],
        "videos": [{"key": v["key"], "lang": v.get("iso_639_1")} for v in videos[:2]],
        "cast": cast,
    }


def fetch_movie(qid: str, auth: tuple[dict, dict]) -> dict:
    headers, base = auth
    found = _get(f"{API}/find/{qid}", headers, {**base, "external_source": "wikidata_id"})
    results = (found or {}).get("movie_results") or []
    if not results:
        return {}
    data = _get(f"{API}/movie/{results[0]['id']}", headers,
                {**base, "append_to_response": "images,videos,credits",
                 "include_image_language": "null,es,en", "include_video_language": "es,en"})
    return parse_movie(data) if data else {}


def _soundtrack_album(film: Film) -> dict | None:
    """Álbum de la banda sonora en Deezer cuyo título contiene el de la película."""
    titles = {norm(film.title_en), norm(film.title_es)} - {""}
    data = _get(f"{DEEZER}/search/album", UA, {"q": f"{film.title_en} soundtrack", "limit": 10})
    for alb in (data or {}).get("data") or []:
        name = norm(alb.get("title", ""))
        if not re.search(r"soundtrack|original|banda sonora|bso|score|motion picture", name):
            continue
        if any(re.search(rf"\b{re.escape(t)}\b", name) for t in titles):
            return alb
    return None


def fetch_soundtrack(film: Film) -> dict:
    alb = _soundtrack_album(film)
    if not alb:
        return {}
    tracks = _get(f"{DEEZER}/album/{alb['id']}/tracks", UA, {"limit": 25})
    for t in (tracks or {}).get("data") or []:
        # La primera pista con fragmento y que no repita el título de la película
        if t.get("preview") and not any(x and x in norm(t.get("title", "")) for x in
                                        (norm(film.title_en), norm(film.title_es))):
            artist = (t.get("artist") or {}).get("name") or (alb.get("artist") or {}).get("name") or ""
            return {"album_id": alb["id"], "track_id": t["id"], "artist": artist[:80]}
    return {}


def enrich(films: list[Film], cache_path: Path, max_films: int = 2500) -> None:
    """Añade film.tmdb y film.soundtrack a las películas más conocidas.

    Solo consulta internet si hay clave de TMDB; sin ella usa lo que ya haya en caché."""
    auth = _auth()
    cache = {}
    if cache_path.exists():
        cache = json.loads(cache_path.read_text(encoding="utf-8"))
        if cache.get("_v") != CACHE_VERSION:
            cache = {}
    cache["_v"] = CACHE_VERSION
    ranked = sorted(films, key=lambda f: -f.popularity)[:max_films]
    asked = 0
    for i, f in enumerate(ranked):
        entry = cache.get(f.qid)
        if entry is None and not auth:
            continue
        if entry is None:
            entry = {}
            entry["tmdb"] = fetch_movie(f.qid, auth)
            if i < 800:                       # bandas sonoras solo de las muy conocidas
                entry["soundtrack"] = fetch_soundtrack(f)
            cache[f.qid] = entry
            asked += 1
            if asked % 100 == 0:
                cache_path.write_text(json.dumps(cache, ensure_ascii=False), encoding="utf-8")
                print(f"  multimedia: {asked} películas consultadas…")
        elif auth and "tmdb" not in entry:
            entry["tmdb"] = fetch_movie(f.qid, auth)
        f.tmdb = entry.get("tmdb") or None
        f.soundtrack = entry.get("soundtrack") or None
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    cache_path.write_text(json.dumps(cache, ensure_ascii=False), encoding="utf-8")
    print(f"  multimedia: TMDB en {sum(1 for f in films if f.tmdb)} películas, "
          f"bandas sonoras en {sum(1 for f in films if f.soundtrack)}"
          + ("" if auth else " (sin TMDB_TOKEN: no hay fotogramas ni tráileres)"))


def image_url(path: str, size: str = "w780") -> str:
    return f"{IMG}{size}{path}"


def deezer_preview(track_id: int) -> str | None:
    """Los enlaces de fragmento de Deezer caducan: se piden justo antes de copiarlos."""
    data = _get(f"{DEEZER}/track/{track_id}", UA, {})
    return (data or {}).get("preview") or None
