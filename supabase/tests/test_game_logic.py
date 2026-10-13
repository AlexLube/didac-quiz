"""Pruebas de la lógica de juego contra un Postgres local.

Requiere un servidor Postgres 15+ accesible. Variables:
  PGHOST, PGPORT, PGUSER (superusuario). Crea y borra la base 'didacquiz_test'.

  pip install pytest "psycopg[binary]"
  pytest supabase/tests
"""
from __future__ import annotations

import json
import os
import uuid
from pathlib import Path

import psycopg
import pytest

ROOT = Path(__file__).resolve().parents[1]
DB = "didacquiz_test"


def _admin_conn(dbname="postgres"):
    return psycopg.connect(dbname=dbname, autocommit=True)


@pytest.fixture(scope="module")
def db():
    if not os.environ.get("PGHOST"):
        pytest.skip("PGHOST no definido: no hay Postgres local")
    with _admin_conn() as c:
        c.execute(f"drop database if exists {DB}")
        c.execute(f"create database {DB}")
    conn = psycopg.connect(dbname=DB, autocommit=True)
    conn.execute((ROOT / "tests" / "local_stubs.sql").read_text())
    for f in sorted((ROOT / "migrations").glob("*.sql")):
        conn.execute(f.read_text())
    conn.execute((ROOT / "seed" / "banned_words.sql").read_text())
    # Lugares mínimos para las pruebas
    conn.execute("""
      insert into countries values ('ES','España','Spain'), ('FR','Francia','France');
      insert into cities values
        (1,'ES','Valencia','ES-60',800000),(2,'ES','Torrent','ES-60',80000),
        (3,'ES','Madrid','ES-29',3000000),(4,'FR','Paris','FR-11',2000000);
    """)
    # Reloj controlable: la fecha "de hoy" se lee de un ajuste de sesión.
    conn.execute("""
      create or replace function public._today() returns date language sql stable as $$
        select coalesce(nullif(current_setting('test.today', true), '')::date,
                        (now() at time zone 'utc')::date) $$;
    """)
    yield conn
    conn.close()
    with _admin_conn() as c:
        c.execute(f"drop database if exists {DB} with (force)")


def make_questions(conn, n=10, start=0):
    ids = []
    for i in range(start, start + n):
        difficulty = 1 if i % 10 < 4 else (2 if i % 10 < 8 else 3)
        fmt = "order" if i % 10 == 5 else "choice"
        answer = [2, 0, 3, 1] if fmt == "order" else 2
        row = conn.execute(
            """insert into questions (external_id, format, difficulty, prompt, options, answer, explanation)
               values (%s, %s, %s, %s, %s, %s, %s) returning id""",
            (
                f"t{i}", fmt, difficulty,
                json.dumps({"es": f"Pregunta {i}", "en": f"Question {i}"}),
                json.dumps([{"es": f"O{k}", "en": f"O{k}"} for k in range(4)]),
                json.dumps(answer),
                json.dumps({"es": "Curiosidad", "en": "Fun fact"}),
            ),
        ).fetchone()
        ids.append(row[0])
    return ids


def make_challenge(conn, day: str, qids):
    conn.execute(
        "insert into challenges (challenge_date, question_ids) values (%s, %s) on conflict do nothing",
        (day, qids),
    )


class Player:
    def __init__(self, conn, anonymous=False):
        self.conn = conn
        self.id = str(uuid.uuid4())
        conn.execute("insert into auth.users (id, is_anonymous) values (%s, %s)", (self.id, anonymous))

    def call(self, sql, params=(), today=None):
        with self.conn.transaction():
            self.conn.execute("set local role authenticated")
            self.conn.execute("select set_config('request.jwt.claim.sub', %s, true)", (self.id,))
            if today:
                self.conn.execute("select set_config('test.today', %s, true)", (today,))
            row = self.conn.execute(sql, params).fetchone()
            return row[0] if row else None

    def register(self, alias, city=1, country="ES", year=1990, today=None):
        return self.call("select register_profile(%s, %s, %s, %s, 'password')",
                         (alias, country, city, year), today=today)

    def play(self, day, answers):
        """answers: lista de respuestas (o None para dejar pasar el tiempo)."""
        results = []
        for pos in range(10):
            q = self.call("select next_question()", today=day)
            assert q["finished"] is False
            assert "answer" not in q["question"], "la respuesta nunca debe viajar a la app"
            assert q["question"]["position"] == pos
            results.append(self.call("select submit_answer(%s, %s)",
                                     (pos, json.dumps(answers[pos])), today=day))
        return results


PERFECT = [2, 2, 2, 2, 2, [2, 0, 3, 1], 2, 2, 2, 2]


def test_full_game_and_scoring(db):
    qids = make_questions(db)
    make_challenge(db, "2026-10-01", qids)
    p = Player(db)
    p.register("cinefilo", today="2026-10-01")

    today = p.call("select get_today()", today="2026-10-01")
    assert today["status"] == "not_started" and today["jokers_left"] == 3

    res = p.play("2026-10-01", PERFECT)
    assert all(r["correct"] for r in res)
    assert res[-1]["finished"] is True and res[-1]["total_points"] == 18

    summary = p.call("select get_game_summary(%s)", ("2026-10-01",), today="2026-10-01")
    assert summary["total_points"] == 18 and summary["max_points"] == 18
    assert len(summary["answers"]) == 10

    # No se puede volver a jugar
    again = p.call("select next_question()", today="2026-10-01")
    assert again["finished"] is True
    prof = p.call("select get_my_profile()", today="2026-10-01")
    assert prof["streak_current"] == 1


def test_wrong_answers_and_order_question(db):
    make_challenge(db, "2026-10-02", make_questions(db, start=100))
    p = Player(db)
    p.register("errores")
    answers = [0, 2, 2, 2, 2, [0, 1, 2, 3], 2, 2, 2, 0]  # falla 1 fácil, el orden y 1 difícil
    res = p.play("2026-10-02", answers)
    assert [r["correct"] for r in res].count(False) == 3
    assert res[-1]["total_points"] == 18 - 1 - 2 - 3


def test_timeout_counts_as_miss(db):
    make_challenge(db, "2026-10-03", make_questions(db, start=200))
    p = Player(db)
    p.register("lento")
    p.call("select next_question()", today="2026-10-03")
    # Simula que el jugador cerró la app y volvió 30 s después
    db.execute("""update game_answers a set served_at = served_at - interval '30 seconds'
                  from games g where g.id = a.game_id and g.user_id = %s""", (p.id,))
    q = p.call("select next_question()", today="2026-10-03")
    assert q["question"]["position"] == 1
    s = p.call("select get_game_summary(%s)", ("2026-10-03",), today="2026-10-03")
    assert s["answers"][0]["correct"] is False and s["answers"][0]["elapsed_ms"] == 20000

    # Responder tarde también es fallo aunque la respuesta sea buena
    db.execute("""update game_answers a set served_at = served_at - interval '25 seconds'
                  from games g where g.id = a.game_id and g.user_id = %s and a.position = 1""", (p.id,))
    r = p.call("select submit_answer(1, '2')", today="2026-10-03")
    assert r["timeout"] is True and r["correct"] is False


def test_cannot_answer_other_position(db):
    make_challenge(db, "2026-10-04", make_questions(db, start=300))
    p = Player(db)
    p.register("tramposo")
    p.call("select next_question()", today="2026-10-04")
    with pytest.raises(psycopg.errors.RaiseException, match="wrong_position"):
        p.call("select submit_answer(3, '2')", today="2026-10-04")


def test_direct_table_access_is_blocked(db):
    p = Player(db)
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        p.call("select answer from questions limit 1")
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        p.call("select recalibrate_questions(1)")


def test_jokers_three_per_week(db):
    # 2026-10-05 es lunes
    days = ["2026-10-05", "2026-10-06"]
    for i, d in enumerate(days):
        make_challenge(db, d, make_questions(db, start=400 + i * 10))
    p = Player(db)
    p.register("comodines")
    for pos in range(3):
        p.call("select next_question()", today=days[0])
        if pos == 0:
            j = p.call("select use_joker(0)", today=days[0])
            assert len(j["removed_options"]) == 2 and 2 not in j["removed_options"]
            assert j["jokers_left"] == 2
            with pytest.raises(psycopg.errors.RaiseException, match="joker_already_used"):
                p.call("select use_joker(0)", today=days[0])
        else:
            p.call("select use_joker(%s)", (pos,), today=days[0])
        p.call("select submit_answer(%s, '2')", (pos,), today=days[0])
    p.call("select next_question()", today=days[0])
    with pytest.raises(psycopg.errors.RaiseException, match="no_jokers_left"):
        p.call("select use_joker(3)", today=days[0])
    # Pregunta de ordenar: no admite comodín (y además no quedan)
    t = p.call("select get_today()", today=days[1])
    assert t["jokers_left"] == 0


def test_streaks_and_restore(db):
    days = ["2026-11-02", "2026-11-03", "2026-11-05"]
    for i, d in enumerate(days):
        make_challenge(db, d, make_questions(db, start=500 + i * 10))
    p = Player(db)
    p.register("constante", today=days[0])
    p.play(days[0], PERFECT)
    p.play(days[1], PERFECT)
    assert p.call("select get_my_profile()", today=days[1])["streak_current"] == 2
    p.play(days[2], PERFECT)  # se saltó el día 4
    prof = p.call("select get_my_profile()", today=days[2])
    assert prof["streak_current"] == 1 and prof["can_restore_streak"] is True
    prof = p.call("select restore_streak()", today=days[2])
    assert prof["streak_current"] == 3 and prof["streak_best"] == 3
    with pytest.raises(psycopg.errors.RaiseException, match="streak_restore_unavailable"):
        p.call("select restore_streak()", today=days[2])


def test_guest_then_register_keeps_game(db):
    make_challenge(db, "2026-12-01", make_questions(db, start=600))
    g = Player(db, anonymous=True)
    g.play("2026-12-01", PERFECT)
    with pytest.raises(psycopg.errors.RaiseException, match="account_not_permanent"):
        g.register("invitado", today="2026-12-01")
    # La app convierte al invitado en cuenta permanente (Supabase Auth)
    db.execute("update auth.users set is_anonymous = false where id = %s", (g.id,))
    out = g.register("invitado", today="2026-12-01")
    assert out["recovery_code"] and len(out["recovery_code"]) == 14
    assert out["profile"]["streak_current"] == 1
    board = g.call("select get_leaderboard('world', 'day', '2026-12-01')", today="2026-12-01")
    assert board["me"]["points"] == 18


def test_alias_rules(db):
    p = Player(db)
    assert p.call("select is_alias_available('ab')") == "invalid"
    assert p.call("select is_alias_available('con espacio')") == "invalid"
    assert p.call("select is_alias_available('El_Nazi_99')") == "banned"
    assert p.call("select is_alias_available('CINEFILO')") == "taken"
    assert p.call("select is_alias_available('nuevo.alias')") == "ok"
    with pytest.raises(psycopg.errors.RaiseException, match="invalid_location"):
        p.register("sitioraro", city=4, country="ES")
    with pytest.raises(psycopg.errors.RaiseException, match="invalid_birth_year"):
        p.register("muyjoven", year=2030)


def test_recovery_flow(db):
    p = Player(db)
    code = p.register("olvidadizo")["recovery_code"]
    anon_call = "select recover_account(%s, %s, %s)"
    bad = p.call(anon_call, ("olvidadizo", "AAAA-BBBB-CCCC", "nuevaclave1"))
    assert bad["ok"] is False
    ok = p.call(anon_call, ("OLVIDADIZO", code.lower().replace("-", " "), "nuevaclave1"))
    assert ok["ok"] is True and ok["recovery_code"] != code
    pw_ok = db.execute(
        "select encrypted_password = extensions.crypt('nuevaclave1', encrypted_password) from auth.users where id = %s",
        (p.id,),
    ).fetchone()[0]
    assert pw_ok
    # El código antiguo ya no sirve y 5 fallos bloquean
    for _ in range(5):
        assert p.call(anon_call, ("olvidadizo", code, "otraclave22"))["ok"] is False
    with pytest.raises(psycopg.errors.RaiseException, match="recovery_locked"):
        p.call(anon_call, ("olvidadizo", ok["recovery_code"], "otraclave22"))


def test_leaderboards_scopes_and_tiebreak(db):
    day = "2027-01-04"
    make_challenge(db, day, make_questions(db, start=700))
    a, b, c, d = Player(db), Player(db), Player(db), Player(db)
    a.register("rapido", city=1)
    b.register("lentito", city=2)
    c.register("madrileno", city=3)
    d.register("parisien", city=4, country="FR", year=2016)  # menor: ciudad oculta
    for pl in (a, b, c, d):
        pl.play(day, PERFECT)
    db.execute("update games set total_ms = 50000 where user_id = %s", (a.id,))
    db.execute("update games set total_ms = 90000 where user_id = %s", (b.id,))
    db.execute("update games set total_ms = 70000, total_points = 10 where user_id = %s", (c.id,))

    world = a.call("select get_leaderboard('world', 'day', %s)", (day,), today=day)
    order = [r["alias"] for r in world["top"]]
    assert order.index("rapido") < order.index("lentito") < order.index("madrileno")
    assert world["me"]["alias"] == "rapido" and world["me"]["is_me"] is True
    minor_row = next(r for r in world["top"] if r["alias"] == "parisien")
    assert minor_row["city"] is None

    country = a.call("select get_leaderboard('country', 'week', %s)", (day,), today=day)
    assert {r["alias"] for r in country["top"]} >= {"rapido", "lentito", "madrileno"}
    assert "parisien" not in {r["alias"] for r in country["top"]}

    # Valencia tiene menos de 20 jugadores: se agrupa con Torrent (misma región)
    local = a.call("select get_leaderboard('city', 'month', %s)", (day,), today=day)
    assert local["label"]["type"] == "region" and local["label"]["name"] == "Valencia"
    assert {r["alias"] for r in local["top"]} >= {"rapido", "lentito"}
    assert "madrileno" not in {r["alias"] for r in local["top"]}

    hist = a.call("select get_leaderboard('world', 'all', %s)", (day,), today=day)
    assert hist["total_players"] >= 4


def test_solutions_only_after_day_closes(db):
    day = "2027-02-01"
    make_challenge(db, day, make_questions(db, start=800))
    p = Player(db)
    p.register("curioso")
    p.play(day, PERFECT)
    with pytest.raises(psycopg.errors.RaiseException, match="challenge_still_open"):
        p.call("select get_solutions(%s)", (day,), today=day)
    sol = p.call("select get_solutions(%s)", (day,), today="2027-02-02")
    assert len(sol["questions"]) == 10 and sol["questions"][0]["answer"] == 2
    assert sol["questions"][0]["my_correct"] is True


def test_report_and_delete_account(db):
    day = "2027-03-01"
    qids = make_questions(db, start=900)
    make_challenge(db, day, qids)
    p = Player(db)
    p.register("borrame")
    p.call("select next_question()", today=day)
    p.call("select report_question(%s, 'La respuesta está mal')", (qids[0],), today=day)
    with pytest.raises(psycopg.errors.RaiseException, match="question_not_seen"):
        p.call("select report_question(%s, 'x')", (qids[5],), today=day)
    p.call("select delete_my_account()", today=day)
    assert db.execute("select count(*) from profiles where id = %s", (p.id,)).fetchone()[0] == 0
    assert db.execute("select count(*) from games where user_id = %s", (p.id,)).fetchone()[0] == 0
    assert db.execute("select count(*) from reports where question_id = %s", (qids[0],)).fetchone()[0] == 1


def test_maintenance_functions(db):
    assert db.execute("select challenges_remaining()").fetchone()[0] >= 0
    db.execute("update questions set times_shown = 300, times_correct = 290 where external_id = 't9'")
    assert db.execute("select recalibrate_questions(200)").fetchone()[0] >= 1
    assert db.execute("select difficulty from questions where external_id = 't9'").fetchone()[0] == 1


def test_private_leagues(db):
    day = "2027-04-05"
    make_challenge(db, day, make_questions(db, start=1000))
    ana, ben, cris, guest = Player(db), Player(db), Player(db), Player(db, anonymous=True)
    ana.register("ana_liga")
    ben.register("ben_liga", city=3)
    cris.register("cris_liga", city=4, country="FR")

    with pytest.raises(psycopg.errors.RaiseException, match="profile_required"):
        guest.call("select create_league('Invitados')")
    with pytest.raises(psycopg.errors.RaiseException, match="invalid_league_name"):
        ana.call("select create_league('xx')")

    league = ana.call("select create_league('Cinéfilos del barrio')")
    code = league["invite_code"]
    assert len(code) == 6 and league["is_owner"] is True and league["members"] == 1

    joined = ben.call("select join_league(%s)", (code.lower(),))  # admite minúsculas
    assert joined["id"] == league["id"] and joined["members"] == 2 and joined["is_owner"] is False
    cris.call("select join_league(%s)", (code,))
    with pytest.raises(psycopg.errors.RaiseException, match="league_not_found"):
        cris.call("select join_league('ZZZZZZ')")

    ana.play(day, PERFECT)
    ben.play(day, [0, 2, 2, 2, 2, [2, 0, 3, 1], 2, 2, 2, 2])   # 17 puntos
    # cris no juega hoy: aparece al final con 0

    board = ben.call("select league_leaderboard(%s, 'day', %s)", (league["id"], day), today=day)
    assert [r["alias"] for r in board["top"]] == ["ana_liga", "ben_liga", "cris_liga"]
    assert board["top"][2]["points"] == 0 and board["me"]["alias"] == "ben_liga"
    assert board["label"]["name"] == "Cinéfilos del barrio"
    # Los rankings generales no cambian por estar en una liga
    assert ben.call("select get_leaderboard('world', 'day', %s)", (day,), today=day)["total_players"] >= 2

    outsider = Player(db)
    outsider.register("miron")
    with pytest.raises(psycopg.errors.RaiseException, match="not_a_member"):
        outsider.call("select league_leaderboard(%s, 'day')", (league["id"],))

    with pytest.raises(psycopg.errors.RaiseException, match="not_league_owner"):
        ben.call("select remove_league_member(%s, 'cris_liga')", (league["id"],))
    ana.call("select remove_league_member(%s, 'cris_liga')", (league["id"],))
    assert cris.call("select my_leagues()") == []

    # Si el creador borra su cuenta, la liga pasa a ben
    ana.call("select delete_my_account()")
    mine = ben.call("select my_leagues()")
    assert mine[0]["is_owner"] is True and mine[0]["members"] == 1
    ben.call("select leave_league(%s)", (league["id"],))
    assert db.execute("select count(*) from leagues where id = %s", (league["id"],)).fetchone()[0] == 0


def test_media_questions(db):
    day = "2027-05-03"
    qids = make_questions(db, start=1100)
    db.execute("""update questions set format = 'audio', audio_url = 'https://upload.wikimedia.org/x.mp3',
                  audio_attribution = 'Orquesta X · Dominio público', media_start_ms = 1500 where id = %s""",
               (qids[0],))
    db.execute("""update questions set format = 'emoji', prompt = '{"es": "🦈🚤\\n¿Qué película es?", "en": "x"}'
                  where id = %s""", (qids[1],))
    db.execute("""update questions set format = 'image_choice', image_url = 'https://commons/x.jpg',
                  image_attribution = 'Foto: Y · CC BY-SA 4.0' where id = %s""", (qids[2],))
    make_challenge(db, day, qids)
    p = Player(db)
    p.register("multimedia")
    q = p.call("select next_question()", today=day)["question"]
    assert q["format"] == "audio" and q["audio_url"].endswith(".mp3") and q["media_start_ms"] == 1500
    assert p.call("select use_joker(0)", today=day)["jokers_left"] == 2
    p.call("select submit_answer(0, '2')", today=day)
    q = p.call("select next_question()", today=day)["question"]
    assert q["format"] == "emoji"
    p.call("select submit_answer(1, '2')", today=day)
    q = p.call("select next_question()", today=day)["question"]
    assert q["image_attribution"].startswith("Foto")
    with pytest.raises(psycopg.errors.CheckViolation):
        db.execute("update questions set format = 'video' where id = %s", (qids[3],))


# ---------------------------------------------------------------------------
# Variedad: formatos nuevos y puntuación variable
# ---------------------------------------------------------------------------
def _q(conn, ext, fmt, difficulty, options, answer, extra=None, max_points=None):
    row = conn.execute(
        """insert into questions (external_id, format, difficulty, max_points, prompt, options, answer, extra)
           values (%s,%s,%s,%s,%s,%s,%s,%s) returning id""",
        (ext, fmt, difficulty, max_points, json.dumps({"es": ext, "en": ext}), json.dumps(options),
         json.dumps(answer), json.dumps(extra or {}))).fetchone()
    return row[0]


def _score(conn, qid, given, elapsed=1000, limit=20000):
    return conn.execute("select _score_answer(q, %s, %s, %s) from questions q where id = %s",
                        (json.dumps(given), elapsed, limit, qid)).fetchone()[0]


def test_score_year_slider_and_map(db):
    s = _q(db, "v-slider", "year_slider", 3, [], {"year": 1994}, {"min": 1920, "max": 2025})
    assert _score(db, s, 1994)["points"] == 3
    assert _score(db, s, 1995)["points"] == 3
    assert _score(db, s, 1997)["points"] == 2
    assert _score(db, s, 2001)["points"] == 1
    assert _score(db, s, 2010)["points"] == 0
    assert _score(db, s, "abc")["points"] == 0
    assert _score(db, s, None)["points"] == 0
    m = _q(db, "v-map", "map", 3, [], {"lat": 48.8566, "lon": 2.3522}, max_points=3)
    assert _score(db, m, {"lat": 48.9, "lon": 2.4})["points"] == 3          # ~5 km
    assert _score(db, m, {"lat": 51.5, "lon": -0.12})["points"] == 2        # Londres ~340 km
    assert _score(db, m, {"lat": 40.4, "lon": -3.7})["points"] == 1         # Madrid ~1050 km
    assert _score(db, m, {"lat": 35.7, "lon": 139.7})["points"] == 0        # Tokio
    assert _score(db, m, {"lat": "x"})["points"] == 0
    m2 = _q(db, "v-map2", "map", 3, [], {"lat": 48.8566, "lon": 2.3522, "alts": [{"lat": 35.7, "lon": 139.7}]}, max_points=3)
    assert _score(db, m2, {"lat": 35.69, "lon": 139.69})["points"] == 3      # vale un lugar alternativo


def test_score_match_burst_pick_two_typed(db):
    mt = _q(db, "v-match", "match", 3, [{"es": "a", "en": "a"}] * 4, [2, 0, 3, 1],
            {"right": ["w", "x", "y", "z"]}, max_points=3)
    assert _score(db, mt, [2, 0, 3, 1]) == {"points": 3, "correct": True, "partial": False}
    r = _score(db, mt, [2, 0, 1, 3])
    assert r["points"] == 1 and r["partial"] is True and r["correct"] is False
    assert _score(db, mt, [2, 0, 3])["points"] == 0                          # longitud errónea
    bu = _q(db, "v-burst", "burst", 2, [{"es": str(i), "en": str(i)} for i in range(5)],
            [True, False, True, True, False], max_points=3)
    assert _score(db, bu, [True, False, True, True, False])["points"] == 3
    assert _score(db, bu, [True, False, True, True, True])["points"] == 2    # 4 de 5 -> 12/5 = 2
    p2 = _q(db, "v-pick2", "pick_two", 3, [{"es": str(i), "en": str(i)} for i in range(5)], [1, 4])
    assert _score(db, p2, [4, 1])["points"] == 3
    assert _score(db, p2, [1, 2])["points"] == 1
    assert _score(db, p2, [0, 2])["points"] == 0
    assert _score(db, p2, [1, 1])["points"] == 0
    ty = _q(db, "v-typed", "typed_title", 2, [], {"accept": ["El Padrino", "The Godfather"]})
    assert _score(db, ty, "padrino  ")["points"] == 2   # el artículo inicial es opcional
    assert _score(db, ty, "padrinos")["points"] == 0
    assert _score(db, ty, "el  padrino!")["points"] == 2
    assert _score(db, ty, "The godfather")["points"] == 2
    assert _score(db, ty, 5)["points"] == 0


def test_speed_scoring(db):
    c = _q(db, "v-speed", "clues", 3, [{"es": str(i), "en": str(i)} for i in range(4)], 1,
           {"speed": True, "clues": ["a", "b", "c"]})
    assert _score(db, c, 1, elapsed=2000)["points"] == 3
    assert _score(db, c, 1, elapsed=10000)["points"] == 2
    assert _score(db, c, 1, elapsed=19000)["points"] == 1
    assert _score(db, c, 0, elapsed=1000)["points"] == 0


def test_variable_game_and_titles(db):
    qs = [
        _q(db, "g1", "choice", 1, [{"es": "A", "en": "A"}] * 4, 2),
        _q(db, "g2", "year_slider", 3, [], {"year": 2000}, max_points=3),
        _q(db, "g3", "versus", 1, [{"es": "A", "en": "A"}, {"es": "B", "en": "B"}], 1),
        _q(db, "g4", "match", 3, [{"es": "a", "en": "a"}] * 3, [1, 0, 2], {"right": ["x", "y", "z"]}, max_points=2),
        _q(db, "g5", "map", 3, [], {"lat": 0, "lon": 0}, max_points=3),
        _q(db, "g6", "burst", 2, [{"es": str(i), "en": str(i)} for i in range(5)], [True] * 5, max_points=2),
        _q(db, "g7", "typed_title", 2, [], {"accept": ["Alien"]}),
        _q(db, "g8", "odd_images", 1, [{"image": "u", "es": "a", "en": "a"}] * 4, 3),
        _q(db, "g9", "pick_two", 3, [{"es": str(i), "en": str(i)} for i in range(5)], [0, 1], max_points=2),
        _q(db, "g10", "choice", 2, [{"es": "A", "en": "A"}] * 4, 0),
    ]
    db.execute("update questions set time_limit_ms = 30000 where external_id = 'g6'")
    make_challenge(db, "2027-03-02", qs)
    db.execute("update challenges set theme = 'Terror' where challenge_date = '2027-03-02'")
    p = Player(db)
    p.register("variado")
    t = p.call("select get_today()", today="2027-03-02")
    assert t["game"] is None and t["theme"] == "Terror"
    answers = [2, 1999, 0, [1, 0, 2], {"lat": 0.1, "lon": 0.1}, [True] * 5, "alien", 3, [0, 1], 0]
    seen = []
    for pos in range(10):
        q = p.call("select next_question()", today="2027-03-02")["question"]
        assert "answer" not in q
        seen.append((q["format"], q["max_points"], q["time_limit_ms"]))
        p.call("select submit_answer(%s, %s)", (pos, json.dumps(answers[pos])), today="2027-03-02")
    assert seen[5][2] == 30000 and seen[1][1] == 3 and seen[3][1] == 2
    s = p.call("select get_game_summary(%s)", ("2027-03-02",), today="2027-03-02")
    # g1:1 g2:3 g3(versus, answer 1, enviado 0):0 g4:2 g5:3 g6:2 g7:2 g8:1 g9:2 g10:2
    assert s["total_points"] == 1 + 3 + 0 + 2 + 3 + 2 + 2 + 1 + 2 + 2
    assert s["max_points"] == 1 + 3 + 1 + 2 + 3 + 2 + 2 + 1 + 2 + 2

    # Autocompletado
    db.execute("""insert into film_titles (qid, title, norm, year, popularity) values
        ('Q1','Alien, el octavo pasajero','alien el octavo pasajero',1979,90),
        ('Q2','Aliens','aliens',1986,80), ('Q3','El Padrino','padrino',1972,95)""")
    found = p.call("select search_titles('ali')")
    assert [f["title"] for f in found][:2] == ["Alien, el octavo pasajero", "Aliens"]
    assert p.call("select search_titles('el padrino')")[0]["title"] == "El Padrino"
    assert p.call("select search_titles('a')") == []
