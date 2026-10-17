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
from .generate import Generator, film_title_rows
from .schedule import plan
from .validate import validate_all
from .wikidata import fetch_films, load_films, resolve_music, save_films

DATA = Path("data")
OUT = Path("out")


def _write(path: Path, obj) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=1), encoding="utf-8")


DATA_VERSION = "2"   # sube el número cuando cambie qué datos se descargan (invalida la caché)


def cmd_fetch(args) -> None:
    cached = DATA / "films.json"
    version = DATA / "VERSION"
    if cached.exists() and version.exists() and version.read_text().strip() == DATA_VERSION and (dt.datetime.now().timestamp() - cached.stat().st_mtime) < 6 * 86400 \
            and (DATA / "music.json").exists():
        print("Usando los datos de Wikidata descargados hace menos de 6 días (caché).")
        return
    print("Descargando películas de Wikidata…")
    films = fetch_films(min_links=args.min_links)
    save_films(films, DATA / "films.json")
    print(f"{len(films)} películas guardadas en {DATA / 'films.json'}")
    _write(DATA / "music.json", resolve_music(films))
    version.write_text(DATA_VERSION)


def cmd_build(args) -> None:
    films = load_films(DATA / "films.json")
    from .tmdb import enrich
    enrich(films, DATA / "tmdb.json")
    music = json.loads((DATA / "music.json").read_text(encoding="utf-8")) if (DATA / "music.json").exists() else []
    cache_path = DATA / "emoji.json"
    cache = json.loads(cache_path.read_text(encoding="utf-8")) if cache_path.exists() else {}
    emojis = ai.build_emojis(films, cache) if args.ai else {k: v for k, v in cache.items() if v}
    if args.ai:
        _write(cache_path, cache)
    raw = Generator(films, seed=args.seed, music=music, emojis=emojis).generate_all()
    ok, rejected = validate_all(raw, films)
    review = []
    if args.ai and args.ai_review:
        # Revisión con IA de todas las preguntas (lenta con cuentas nuevas: ~50 consultas/min)
        print(f"Revisando {len(ok)} preguntas con IA…")
        ok, flagged = ai.enrich(ok)
        review = [{"question": q, "reason": r} for q, r in flagged]
    _write(OUT / "questions.json", ok)
    _write(OUT / "titles.json", film_title_rows(films))
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
    recent = None
    if args.remote:
        recent = sb.recent_entity_sets(max(start, today).isoformat(), args.spacing)
    calendar = plan(questions, start, args.days, spacing=args.spacing, used_external_ids=used,
                    recent_entities=recent)
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
    titles = OUT / "titles.json"
    if titles.exists():
        print(f"Títulos para el autocompletado: {sb.upsert_titles(json.loads(titles.read_text(encoding='utf-8')))}")


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


from .variety import MEDIA_FORMATS  # noqa: E402


def cmd_report(args) -> None:
    today = dt.datetime.now(dt.timezone.utc).date()
    start = today - dt.timedelta(days=args.past)
    end = today + dt.timedelta(days=args.future)
    rows = _supabase().challenge_report(start.isoformat(), end.isoformat())
    total = 0
    for d in rows:
        media = [q for q in d["questions"] if q.get("format") in MEDIA_FORMATS]
        total += len(media)
        tag = ", ".join(f"{q['format']}({q.get('topic')})" for q in media) or "—"
        mark = "  <- hoy" if d["date"] == today.isoformat() else ""
        print(f"{d['date']}: {len(media)} multimedia: {tag}{mark}")
    print(f"TOTAL multimedia en {len(rows)} retos: {total}")


def cmd_monthly(args) -> None:
    """Rutina automática: si quedan pocos días de retos, genera el siguiente mes y lo anota
    en out/mensual.md (el flujo de trabajo lo publica como aviso en GitHub)."""
    left = _supabase().challenges_remaining()
    print(f"Quedan {left} días con reto programado (mínimo para esperar: {args.min_days}).")
    if left >= args.min_days:
        print("Hay reservas de sobra: no hace falta generar nada.")
        _write(OUT / "mensual.json", {"generated": False, "left": left})
        return
    args.remote = True
    args.replace_from = None
    cmd_yearly(args)
    cal = json.loads((OUT / "calendar.json").read_text(encoding="utf-8"))
    kinds = Counter(c["kind"] for c in cal)
    _write(OUT / "mensual.json", {"generated": True, "left_before": left, "from": cal[0]["date"],
                                  "to": cal[-1]["date"], "days": len(cal), "kinds": dict(kinds)})


def main(argv=None) -> None:
    p = argparse.ArgumentParser(prog="didacquiz_pipeline")
    sub = p.add_subparsers(dest="cmd", required=True)

    def common(sp):
        sp.add_argument("--min-links", type=int, default=20, help="mínimo de Wikipedias por película")
        sp.add_argument("--seed", type=int, default=2026)
        sp.add_argument("--ai", action="store_true", help="usar IA para las preguntas de emojis")
        sp.add_argument("--ai-review", action="store_true", help="además, revisar todas las preguntas con IA (lento)")
        sp.add_argument("--days", type=int, default=365)
        sp.add_argument("--start", help="primer día (AAAA-MM-DD); por defecto, tras el último programado")
        sp.add_argument("--spacing", type=int, default=60)
        sp.add_argument("--remote", action="store_true", help="consultar Supabase al planificar")
        sp.add_argument("--all-questions", action="store_true", help="subir también la reserva")
        sp.add_argument("--replace-from", help="'tomorrow' o AAAA-MM-DD: rehace los retos desde esa fecha")

    for name, fn in [("fetch", cmd_fetch), ("build", cmd_build), ("media", cmd_media),
                     ("schedule", cmd_schedule), ("upload", cmd_upload), ("yearly", cmd_yearly),
                     ("monthly", cmd_monthly)]:
        sp = sub.add_parser(name)
        common(sp)
        if name == "monthly":
            sp.add_argument("--min-days", type=int, default=15,
                            help="si quedan menos días de retos que estos, genera el mes siguiente")
            sp.set_defaults(days=30)
        sp.set_defaults(fn=fn)
    sp = sub.add_parser("report")
    sp.add_argument("--past", type=int, default=15)
    sp.add_argument("--future", type=int, default=30)
    sp.set_defaults(fn=cmd_report)
    sp = sub.add_parser("check")
    sp.add_argument("--min-days", type=int, default=45)
    sp.set_defaults(fn=cmd_check)
    args = p.parse_args(argv)
    args.fn(args)


if __name__ == "__main__":
    main()
