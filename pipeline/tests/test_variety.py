"""Pruebas de los formatos interactivos (slider, mapa, emparejar, ráfagas...)."""
from __future__ import annotations

import random
from collections import Counter

import pytest
from test_pipeline import synthetic_films

from didacquiz_pipeline.generate import Generator
from didacquiz_pipeline.wikidata import Role
from didacquiz_pipeline.validate import semantic_errors, structural_errors, validate_all


def enriched_films():
    films = synthetic_films(900, seed=3)
    rng = random.Random(5)
    for i, f in enumerate(films):
        f.popularity = max(f.popularity, 50) if i % 2 else f.popularity
        if i % 3 == 0:
            f.locations = [{"qid": f"QL{i}", "name_es": f"Lugar {i}", "name_en": f"Place {i}",
                            "lat": rng.uniform(-60, 60), "lon": rng.uniform(-170, 170)}]
            if i % 6 == 0:
                f.locations.append({"qid": f"QM{i}", "name_es": f"Otro {i}", "name_en": f"Other {i}",
                                    "lat": rng.uniform(-60, 60), "lon": rng.uniform(-170, 170)})
        if i % 2 == 0:
            f.roles = [Role(p.qid, p.name, f"Personaje {i}-{k}") for k, p in enumerate(f.cast[:4])]
        if i % 4 == 0:
            f.location_photos = [{"qid": f"QP{i}-{k}", "name_es": f"Foto {k}", "name_en": f"Photo {k}",
                                  "url": f"https://example.org/{i}-{k}.jpg", "license": "CC BY 4.0",
                                  "artist": "Autor", "mime": "image/jpeg", "file": f"{i}{k}.jpg"} for k in range(3)]
    emojis = {f.qid: "🎬🔥" for f in films[::5]}
    return films, emojis


@pytest.fixture(scope="module")
def data():
    films, emojis = enriched_films()
    qs = Generator(films, emojis=emojis).generate_all()
    return films, qs


def test_all_new_formats_are_generated_and_valid(data):
    films, qs = data
    fmts = Counter(q["format"] for q in qs)
    for f in ("year_slider", "versus", "match", "map", "burst", "typed_title", "pick_two", "odd_images"):
        assert fmts[f] > 0, (f, fmts)
    ok, rejected = validate_all(qs, films)
    bad = [(q["topic"], e) for q, e in rejected]
    assert len(ok) > 0.97 * len(qs), Counter(map(str, bad)).most_common(5)
    assert any(q["format"] == "image_reveal" and q["extra"].get("mode") for q in ok)
    assert any(q["format"] == "clues" and q["extra"].get("clues") for q in ok)


def test_new_formats_catch_wrong_answers(data):
    films, qs = data
    index = {f.qid: f for f in films}
    for topic in ("year_slider", "versus_year", "match_cast", "match_dir", "map", "clues_prog",
                  "burst_director", "burst_oscar", "typed_emoji", "pick2_director", "pick2_cast"):
        q = next((q for q in qs if q["topic"] == topic), None)
        assert q, topic
        assert not semantic_errors(q, index), (topic, semantic_errors(q, index))
        a = q["answer"]
        if topic == "year_slider":
            broken = dict(q, answer={"year": a["year"] + 3})
        elif topic == "map":
            broken = dict(q, answer={"lat": a["lat"] + 1, "lon": a["lon"], "alts": a["alts"]})
        elif topic == "typed_emoji":
            broken = dict(q, answer={"accept": ["Otra cosa"]})
        elif topic in ("match_cast", "match_dir"):
            broken = dict(q, answer=[a[1], a[0]] + a[2:])  # cambia dos parejas
        elif topic.startswith("burst"):
            broken = dict(q, answer=[not a[0]] + a[1:])
        elif topic.startswith("pick2"):
            broken = dict(q, answer=[x for x in range(5) if x not in a][:2])
        else:
            broken = dict(q, answer=(a + 1) % 2 if topic.startswith("versus") else (a + 1) % 4)
        assert semantic_errors(broken, index), topic


def test_structural_rules_for_new_formats():
    base = {"difficulty": 2, "prompt": {"es": "x", "en": "x"}}
    assert structural_errors(dict(base, format="year_slider", options=[], answer={"year": 1990},
                                  extra={"min": 1950, "max": 2010}))  == []
    assert structural_errors(dict(base, format="year_slider", options=[], answer={"year": 2020},
                                  extra={"min": 1950, "max": 2010}))
    assert structural_errors(dict(base, format="map", options=[], answer={"lat": 100, "lon": 0}))
    assert structural_errors(dict(base, format="typed_title", options=[], answer={"accept": []}))
    assert structural_errors(dict(base, format="burst", options=[{"es": str(i), "en": str(i)} for i in range(5)],
                                  answer=[True] * 5))  # todas verdaderas: no mezcla


def test_option_labels_unique_for_match(data):
    _, qs = data
    for q in (q for q in qs if q["format"] == "match"):
        n = len(q["options"])
        assert n in (3, 4) and len({o["es"] for o in q["options"]}) == n
        assert sorted(q["answer"]) == list(range(n))


def test_schedule_daily_variety_and_sunday_theme(data):
    import datetime as dt

    from didacquiz_pipeline.schedule import is_interactive, is_media, plan
    films, qs = data
    ok, _ = validate_all(qs, films)
    cal = plan(ok, dt.date(2027, 1, 4), days=21, spacing=10)      # empieza en lunes
    by_id = {q["external_id"]: q for q in ok}
    kinds = {}
    for c in cal:
        day = dt.date.fromisoformat(c["date"])
        chosen = [by_id[x] for x in c["external_ids"]]
        assert len(chosen) == 10
        assert sum(map(is_media, chosen)) >= 2, c["date"]
        assert sum(map(is_interactive, chosen)) >= 2, c["date"]
        assert [q["difficulty"] for q in chosen] == sorted(q["difficulty"] for q in chosen)
        kinds[day.weekday()] = c["kind"]
        if c["kind"] == "special":
            assert c["theme"] and c["title"]["es"]
            assert all(c["theme"] in q["_tags"] for q in chosen)
        if c["kind"] == "spotlight" and day.weekday() == 3:
            assert sum(map(is_media, chosen)) >= 5
        if c["kind"] == "spotlight" and day.weekday() == 2:
            assert sum(map(is_interactive, chosen)) >= 5
    assert kinds[6] == "special" and kinds[0] == "general"


def test_title_normalisation_matches_sql():
    from didacquiz_pipeline.generate import norm_title
    assert norm_title("El Padrino") == "padrino"
    assert norm_title("¡Átame!") == "atame"
    assert norm_title("L'avventura") == "avventura"
    assert norm_title("The Godfather: Part II") == "godfather part ii"
