"""Preguntas multimedia de TMDB y Deezer (sin conexión: datos de ejemplo)."""
from __future__ import annotations

import datetime as dt

import pytest

from didacquiz_pipeline import tmdb
from didacquiz_pipeline.generate import Generator
from didacquiz_pipeline.schedule import is_media, plan
from didacquiz_pipeline.validate import semantic_errors, validate_all

from test_pipeline import synthetic_films


def _with_media(films):
    for i, f in enumerate(films):
        f.tmdb = {
            "id": i,
            "backdrops": [f"/b{i}a.jpg", f"/b{i}b.jpg"],
            "videos": [{"key": f"yt{i}", "lang": "es"}] if i % 2 == 0 else [],
            "cast": [{"name": p.name, "profile": f"/p{p.qid}.jpg"} for p in f.cast],
        }
        if i % 3 == 0:
            f.soundtrack = {"album_id": i, "track_id": 1000 + i, "artist": "Orquesta"}
    return films


@pytest.fixture(scope="module")
def data():
    films = _with_media(synthetic_films())
    qs = Generator(films).generate_all()
    ok, rejected = validate_all(qs, films)
    return films, qs, ok, rejected


def test_media_types_generated_and_valid(data):
    films, qs, ok, rejected = data
    topics = {q["topic"] for q in ok}
    assert {"still", "actor_photo", "trailer_director", "trailer_year", "soundtrack"} <= topics
    new = {"actor_photo", "trailer_director", "trailer_year", "soundtrack"}
    assert not [(q["topic"], e) for q, e in rejected if q["topic"] in new and e != ["duplicada"]]
    video = next(q for q in ok if q["format"] == "video")
    assert video["extra"]["youtube"].startswith("yt") and video["time_limit_ms"] == 45000
    assert video["extra"]["end"] > video["extra"]["start"]
    st = next(q for q in ok if q["topic"] == "soundtrack")
    assert st["audio_url"].startswith("deezer:") and st["format"] == "audio"
    actor = next(q for q in ok if q["topic"] == "actor_photo")
    assert actor["image_url"].startswith("https://image.tmdb.org/t/p/w500/p")
    stills = [q for q in ok if q.get("image_url", "").startswith("https://image.tmdb.org")]
    assert {"image_choice", "image_reveal"} <= {q["format"] for q in stills}


def test_media_types_catch_wrong_answers(data):
    films, _, ok, _ = data
    index = {f.qid: f for f in films}
    for topic in ("actor_photo", "trailer_director", "trailer_year", "soundtrack"):
        q = dict(next(x for x in ok if x["topic"] == topic))
        q["answer"] = (q["answer"] + 1) % len(q["options"])
        assert semantic_errors(q, index), topic
    q = dict(next(x for x in ok if x["topic"] == "trailer_year"), extra={})
    assert semantic_errors(q, index)


def test_five_media_per_day_and_seven_on_thursday(data):
    _, _, ok, _ = data
    by_id = {q["external_id"]: q for q in ok}
    cal = plan(ok, dt.date(2027, 1, 4), days=28, spacing=10)
    for c in cal:
        n = sum(is_media(by_id[x]) for x in c["external_ids"])
        thursday = dt.date.fromisoformat(c["date"]).weekday() == 3
        assert n >= (7 if thursday else 5), (c["date"], n)


def test_emoji_and_map_do_not_count_as_media():
    assert not is_media({"format": "emoji"}) and not is_media({"format": "map"})
    assert all(is_media({"format": f}) for f in ("image_choice", "image_reveal", "audio", "video"))


def test_parse_movie_keeps_textless_stills_and_official_trailers():
    data = {
        "id": 5,
        "images": {"backdrops": [{"file_path": "/con_texto.jpg", "iso_639_1": "en", "vote_average": 9},
                                 {"file_path": "/limpia.jpg", "iso_639_1": None, "vote_average": 5}]},
        "videos": {"results": [
            {"site": "YouTube", "type": "Teaser", "official": True, "key": "teaser"},
            {"site": "YouTube", "type": "Trailer", "official": False, "key": "fan"},
            {"site": "YouTube", "type": "Trailer", "official": True, "key": "en1", "iso_639_1": "en"},
            {"site": "YouTube", "type": "Trailer", "official": True, "key": "es1", "iso_639_1": "es"}]},
        "credits": {"cast": [{"name": "A", "profile_path": "/a.jpg"}, {"name": "B", "profile_path": None}]},
    }
    m = tmdb.parse_movie(data)
    assert m["backdrops"] == ["/limpia.jpg"]
    assert [v["key"] for v in m["videos"]] == ["es1", "en1"]
    assert m["cast"] == [{"name": "A", "profile": "/a.jpg"}]


def test_enrich_uses_cache_and_skips_network_without_key(tmp_path, monkeypatch):
    films = synthetic_films(n=5)
    calls = []
    monkeypatch.setattr(tmdb, "fetch_soundtrack", lambda f: calls.append(f.qid) or {"track_id": 1, "artist": "x"})
    monkeypatch.setattr(tmdb, "fetch_movie", lambda qid, auth: calls.append(qid) or
                        {"id": 1, "backdrops": ["/x.jpg"], "videos": [], "cast": []})
    cache = tmp_path / "tmdb.json"
    monkeypatch.delenv("TMDB_TOKEN", raising=False)
    monkeypatch.delenv("TMDB_API_KEY", raising=False)
    tmdb.enrich(films, cache)
    assert not calls and not any(f.tmdb or f.soundtrack for f in films)
    monkeypatch.setenv("TMDB_TOKEN", "t")
    tmdb.enrich(films, cache)
    assert len(calls) == 10 and all(f.tmdb and f.soundtrack for f in films)
    monkeypatch.delenv("TMDB_TOKEN")
    for f in films:
        f.tmdb = f.soundtrack = None
    tmdb.enrich(films, cache)               # sin clave, pero con caché
    assert len(calls) == 10 and all(f.tmdb and f.soundtrack for f in films)


def test_deezer_audio_is_resolved_when_copied(monkeypatch):
    from didacquiz_pipeline import media, upload
    got = {}

    class FakeStore:
        def __init__(self, *a, **k):
            pass

        def mirror_clip(self, url, start=0, seconds=20, key=None):
            got["url"], got["key"] = (url() if callable(url) else url), key
            return "https://x.supabase.co/storage/v1/object/public/media/audio/a.mp3"

    monkeypatch.setattr(media, "MediaStore", FakeStore)
    monkeypatch.setattr(tmdb, "deezer_preview", lambda t: f"https://cdn.deezer.com/{t}.mp3")
    sb = upload.Supabase("https://x.supabase.co", "sb_secret_x")
    out = sb.mirror_media([{"external_id": "s", "audio_url": "deezer:42"}])
    assert out[0]["audio_url"].endswith("a.mp3")
    assert got == {"url": "https://cdn.deezer.com/42.mp3", "key": "deezer:42"}
