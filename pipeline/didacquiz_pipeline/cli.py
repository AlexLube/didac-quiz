"""Línea de órdenes del generador de preguntas de Didac-Quiz.

  python -m didacquiz_pipeline fetch                    # descarga datos de Wikidata
  python -m didacquiz_pipeline build [--ai]             # genera y valida preguntas
  python -m didacquiz_pipeline schedule --days 365      # planifica el calendario
  python -m didacquiz_pipeline upload                   # sube preguntas y calendario a Supabase
  python -m didacquiz_pipeline yearly --days 365 [--ai] # todo lo anterior seguido
  python -m didacquiz_pipeline check --min-days 45      # avisa si quedan pocos retos
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from collections import Counter
from pathlib import Path

from . import ai
from .generate import Generator
from .schedule import plan
from .validate import validate_all
from .wikidata import fetch_films, load_films, resolve_music, save_films

DATA = Path("data")
OUT = Path("out")


def _write(path: Path, obj) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=1), encoding="utf-8")


def cmd_fetch(args) -> None:
    print("Descargando películas de Wikidata…")
    films = fetch_films(min_links=args.min_links)
    save_films(films, DATA / "films.json")
    print(f"{len(films)} películas guardadas en {DATA / 'films.json'}")
    _write(DATA / "music.json", resolve_music(films))


def cmd_build(args) -> None:
    films = load_films(DATA / "films.json")
    music = json.loads((DATA / "music.json").read_text(encoding="utf-8")) if (DATA / "music.json").exists() else []
    cache_path = DATA / "emoji.json"
    cache = json.loads(cache_path.read_text(encoding="utf-8")) if cache_path.exists() else {}
    emojis = ai.build_emojis(films, cache) if args.ai else {k: v for k, v in cache.items() if v}
    if args.ai:
        _write(cache_path, cache)
    raw = Generator(films, seed=args.seed, music=music, emojis=emojis).generate_all()
    ok, rejected = validate_all(raw, films)
    review = []
    if args.ai:
        print(f"Revisando {len(ok)} preguntas con IA…")
        ok, flagged = ai.enrich(ok)
        review = [{"question": q, "reason": r} for q, r in flagged]
    _write(OUT / "questions.json", ok)
    _write(OUT / "rejected.json", [{"question": q, "errors": e} for q, e in rejected])
    _write(OUT / "review.json", review)
    by_diff = Counter(q["difficulty"] for q in ok)
    by_fmt = Counter(q["format"] for q in ok)
    print(f"Válidas: {len(ok)} · descartadas: {len(rejected)} · para revisar a mano: {len(review)}")
    print(f"Por dificultad: {dict(sorted(by_diff.items()))} · por formato: {dict(by_fmt)}")


def _supabase():
    from .upload import Supabase
    return Supabase()


def cmd_schedule(args) -> None:
    questions = json.loads((OUT / "questions.json").read_text(encoding="utf-8"))
    used: set[str] = set()
    start = dt.date.fromisoformat(args.start) if args.start else None
    if args.remote:
        sb = _supabase()
        if args.replace_from:
            day = (dt.datetime.now(dt.timezone.utc).date() + dt.timedelta(days=1)
                   if args.replace_from == "tomorrow" else dt.date.fromisoformat(args.replace_from))
            # Los retos de esos días se sobrescriben al subir (upsert por fecha);
            # el de hoy y los pasados no se tocan.
            print(f"Se sustituirán los retos desde el {day}.")
            start = day
        used = sb.used_external_ids()
        if start is None:
            last = sb.last_challenge_date()
            start = dt.date.fromisoformat(last) + dt.timedelta(days=1) if last else None
    today = dt.datetime.now(dt.timezone.utc).date()
    start = max(start or today, today)
    calendar = plan(questions, start, args.days, spacing=args.spacing, used_external_ids=used)
    _write(OUT / "calendar.json", calendar)
    print(f"Calendario: {calendar[0]['date']} → {calendar[-1]['date']} ({len(calendar)} retos)")


def cmd_upload(args) -> None:
    questions = json.loads((OUT / "questions.json").read_text(encoding="utf-8"))
    calendar = json.loads((OUT / "calendar.json").read_text(encoding="utf-8"))
    needed = {x for c in calendar for x in c["external_ids"]}
    to_upload = [q for q in questions if q["external_id"] in needed] if not args.all_questions else questions
    sb = _supabase()
    ids = sb.upsert_questions(to_upload)
    sb.insert_challenges(calendar, ids)
    print(f"Subidas {len(ids)} preguntas y {len(calendar)} retos.")


def cmd_media(args) -> None:
    """Copia a Supabase Storage las imágenes y audios de las preguntas (descarta las que fallan)."""
    questions = json.loads((OUT / "questions.json").read_text(encoding="utf-8"))
    kept = _supabase().mirror_media(questions)
    _write(OUT / "questions.json", kept)
    print(f"Preguntas tras copiar medios: {len(kept)}")


def cmd_yearly(args) -> None:
    cmd_fetch(args)
    cmd_build(args)
    cmd_media(args)
    args.remote = True
    cmd_schedule(args)
    cmd_upload(args)


def cmd_check(args) -> None:
    left = _supabase().challenges_remaining()
    print(f"Quedan {left} días con reto programado.")
    if left < args.min_days:
        print(f"::warning::Solo quedan {left} días de retos. Ejecuta la generación anual.")
        sys.exit(1)


def main(argv=None) -> None:
    p = argparse.ArgumentParser(prog="didacquiz_pipeline")
    sub = p.add_subparsers(dest="cmd", required=True)

    def common(sp):
        sp.add_argument("--min-links", type=int, default=20, help="mínimo de Wikipedias por película")
        sp.add_argument("--seed", type=int, default=2026)
        sp.add_argument("--ai", action="store_true", help="revisar y redactar curiosidades con IA")
        sp.add_argument("--days", type=int, default=365)
        sp.add_argument("--start", help="primer día (AAAA-MM-DD); por defecto, tras el último programado")
        sp.add_argument("--spacing", type=int, default=60)
        sp.add_argument("--remote", action="store_true", help="consultar Supabase al planificar")
        sp.add_argument("--all-questions", action="store_true", help="subir también la reserva")
        sp.add_argument("--replace-from", help="'tomorrow' o AAAA-MM-DD: rehace los retos desde esa fecha")

    for name, fn in [("fetch", cmd_fetch), ("build", cmd_build), ("media", cmd_media),
                     ("schedule", cmd_schedule), ("upload", cmd_upload), ("yearly", cmd_yearly)]:
        sp = sub.add_parser(name)
        common(sp)
        sp.set_defaults(fn=fn)
    sp = sub.add_parser("check")
    sp.add_argument("--min-days", type=int, default=45)
    sp.set_defaults(fn=cmd_check)
    args = p.parse_args(argv)
    args.fn(args)


if __name__ == "__main__":
    main()
