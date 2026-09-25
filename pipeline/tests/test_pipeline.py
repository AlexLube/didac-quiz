"""Pruebas del generador con datos sintéticos (sin conexión a Wikidata)."""
from __future__ import annotations

import datetime as dt
import random

import pytest

from didacquiz_pipeline.generate import Generator
from didacquiz_pipeline.schedule import plan
from didacquiz_pipeline.validate import semantic_errors, structural_errors, validate_all
from didacquiz_pipeline.wikidata import Film, Person


def synthetic_films(n=900, seed=1) -> list[Film]:
    rng = random.Random(seed)
    directors = [Person(f"QD{i}", f"Director {i}", rng.randint(10, 120)) for i in range(160)]
    actors = [Person(f"QA{i}", f"Actor {i}", rng.randint(10, 150)) for i in range(600)]
    films = []
    for i in range(n):
        cast = rng.sample(actors, 6)
        cast.sort(key=lambda p: -p.popularity)
        awards = []
        if i % 25 == 0:
            awards.append("oscar_best_picture")
        if i % 30 == 3:
            awards.append("goya_best_film")
        films.append(Film(
            qid=f"QF{i}", title_es=f"Película {i}", title_en=f"Movie {i}",
            year=rng.randint(1925, 2024), popularity=rng.randint(20, 140),
            directors=[rng.choice(directors)], cast=cast[:4], cast_all=[p.qid for p in cast],
            countries=["ES"] if i % 3 == 0 else ["US"], awards=awards,
        ))
    return films


@pytest.fixture(scope="module")
def films():
    return synthetic_films()


@pytest.fixture(scope="module")
def questions(films):
    return Generator(films).generate_all()


def test_generates_every_format(questions):
    formats = {q["format"] for q in questions}
    assert {"choice", "decade", "true_false", "intruder", "order"} <= formats
    assert {q["difficulty"] for q in questions} == {1, 2, 3}


def test_all_generated_questions_are_valid(questions, films):
    ok, rejected = validate_all(questions, films)
    assert len(ok) > 0.95 * len(questions), rejected[:3]


def test_validation_catches_wrong_answer(questions, films):
    index = {f.qid: f for f in films}
    q = next(q for q in questions if q["topic"] == "director" and q["format"] == "choice")
    broken = dict(q, answer=(q["answer"] + 1) % 4)
    assert semantic_errors(broken, index)

    tf = next(q for q in questions if q["format"] == "true_false" and q["topic"] == "year")
    assert semantic_errors(dict(tf, answer=1 - tf["answer"]), index)

    order = next(q for q in questions if q["format"] == "order")
    assert not semantic_errors(order, index)
    assert semantic_errors(dict(order, answer=list(reversed(order["answer"]))), index)


def test_structural_checks():
    q = {"format": "choice", "difficulty": 2, "prompt": {"es": "¿?", "en": "?"},
         "options": [{"es": "A", "en": "A"}, {"es": "A", "en": "A"}], "answer": 5}
    errs = structural_errors(q)
    assert any("repetidas" in e for e in errs) and any("fuera de rango" in e for e in errs)


def test_distractors_never_true(questions, films):
    index = {f.qid: f for f in films}
    for q in questions:
        if q["topic"] == "director" and q["format"] == "choice":
            real = {d.name for d in index[q["entity_ids"][0]].directors}
            wrong = [o["es"] for i, o in enumerate(q["options"]) if i != q["answer"]]
            assert not real & set(wrong)


def test_schedule_rules(questions, films):
    ok, _ = validate_all(questions, films)
    cal = plan(ok, dt.date(2027, 1, 1), days=60, spacing=20)
    by_id = {q["external_id"]: q for q in ok}
    used = [x for c in cal for x in c["external_ids"]]
    assert len(used) == len(set(used)) == 600
    last_seen: dict[str, int] = {}
    for n, c in enumerate(cal):
        qs = [by_id[x] for x in c["external_ids"]]
        assert [q["difficulty"] for q in qs] == [1, 1, 1, 1, 2, 2, 2, 2, 3, 3]
        assert len({q["format"] for q in qs}) >= 3
        for q in qs:
            for e in q["entity_ids"]:
                assert n - last_seen.get(e, -999) >= 20 or last_seen.get(e) == n
        for q in qs:
            for e in q["entity_ids"]:
                last_seen[e] = n


def test_schedule_fails_loudly_when_short(questions, films):
    ok, _ = validate_all(questions, films)
    with pytest.raises(RuntimeError, match="No hay preguntas suficientes"):
        plan(ok[:40], dt.date(2027, 1, 1), days=30)


def test_ai_is_skipped_without_key(questions, monkeypatch):
    from didacquiz_pipeline import ai
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    out, review = ai.enrich(questions[:5], log=lambda *_: None)
    assert out == questions[:5] and review == []


def test_ai_rewrite_rejects_invented_facts(questions, monkeypatch):
    from didacquiz_pipeline import ai
    q = next(q for q in questions if q["topic"] == "director")
    monkeypatch.setattr(ai, "_ask", lambda *a, **k:
        '{"es": "Una joya de 1999 rodada por Kubrick.", "en": "A 1999 gem shot by Kubrick."}')
    assert ai.polish_explanation(q)["explanation"] == q["explanation"]
    faithful = q["explanation"]["es"].replace("fue dirigida por", "la firmó")
    monkeypatch.setattr(ai, "_ask", lambda *a, **k:
        '{"es": "%s", "en": "%s"}' % (faithful, q["explanation"]["en"]))
    assert ai.polish_explanation(q)["explanation"]["es"] == faithful


def test_ai_cross_check_flags_disagreement(questions, monkeypatch):
    from didacquiz_pipeline import ai
    q = next(q for q in questions if q["format"] == "choice")
    wrong_letter = "ABCD"[(q["answer"] + 1) % 4]
    monkeypatch.setattr(ai, "_ask", lambda *a, **k: f"{wrong_letter} alta")
    assert ai.cross_check(q)
    monkeypatch.setattr(ai, "_ask", lambda *a, **k: "ABCD"[q["answer"]] + " alta")
    assert ai.cross_check(q) is None


def test_cli_build_and_schedule_offline(tmp_path, monkeypatch, films):
    from didacquiz_pipeline import cli
    from didacquiz_pipeline.wikidata import save_films
    monkeypatch.chdir(tmp_path)
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    save_films(films, tmp_path / "data" / "films.json")
    cli.main(["build"])
    cli.main(["schedule", "--days", "30", "--start", "2030-01-01", "--spacing", "15"])
    import json as _json
    cal = _json.loads((tmp_path / "out" / "calendar.json").read_text())
    assert len(cal) == 30 and cal[0]["date"] == "2030-01-01"


def test_ambiguous_titles_mention_director():
    from didacquiz_pipeline.generate import Generator, title_key
    assert title_key("El cisne negro") == title_key("Cisne negro")
    films = synthetic_films(200)
    films[0].title_es, films[0].title_en = "El cisne negro", "The Black Swan"
    films[1].title_es, films[1].title_en = "Cisne negro", "Black Swan"
    g = Generator(films)
    q = g.q_decade(films[0])
    assert films[0].directors[0].name in q["prompt"]["es"]
    assert g.q_true_false_year(films[1])["prompt"]["en"].count(films[1].directors[0].name) == 1


def test_sparql_retries_and_splits(monkeypatch):
    from didacquiz_pipeline import wikidata
    monkeypatch.setattr(wikidata.time, "sleep", lambda *_: None)

    class Resp:
        def __init__(self, text, code=200):
            self.text, self.status_code = text, code

    calls = {"n": 0}

    def fake_get(url, params, headers, timeout):
        calls["n"] += 1
        q = params["query"]
        if "wd:BAD" in q:
            return Resp('{"results": {"bindings": [ {"x": "cortado')
        return Resp('{"results": {"bindings": [{"ok": {"value": "1\\u0001"}}]}}')

    monkeypatch.setattr(wikidata.requests, "get", fake_get)
    rows = wikidata._sparql_chunked("VALUES {{ {values} }}", ["Q1", "BAD", "Q2", "Q3"])
    assert len(rows) == 2  # los bloques sanos se recuperan, BAD se omite
