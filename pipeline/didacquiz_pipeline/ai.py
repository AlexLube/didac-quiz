"""Uso opcional de IA (API de Anthropic) sobre preguntas ya validadas.

1. Redacción: reescribe la curiosidad de cada pregunta de forma más atractiva,
   usando SOLO los datos que se le dan. Si introduce cifras o nombres nuevos,
   se descarta y se conserva el texto original.
2. Comprobación cruzada: la IA responde la pregunta sin ver la solución. Si
   falla una pregunta fácil o elige otra opción con seguridad, la pregunta se
   marca para revisión humana (no se borra).

Sin ANTHROPIC_API_KEY, este paso se omite y las preguntas se quedan como están.
"""
from __future__ import annotations

import json
import os
import re
import time

import requests

API_URL = "https://api.anthropic.com/v1/messages"
DEFAULT_MODEL = os.environ.get("DIDACQUIZ_AI_MODEL", "claude-haiku-4-5-20251001")


def available() -> bool:
    return bool(os.environ.get("ANTHROPIC_API_KEY"))


def _ask(prompt: str, max_tokens: int = 400) -> str:
    for attempt in range(4):
        r = requests.post(
            API_URL,
            headers={
                "x-api-key": os.environ["ANTHROPIC_API_KEY"],
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            json={"model": DEFAULT_MODEL, "max_tokens": max_tokens,
                  "messages": [{"role": "user", "content": prompt}]},
            timeout=60,
        )
        if r.status_code == 200:
            return "".join(b.get("text", "") for b in r.json()["content"])
        if r.status_code in (429, 500, 529):
            time.sleep(5 * (attempt + 1))
            continue
        r.raise_for_status()
    raise RuntimeError("La API de IA no respondió")


def _tokens(text: str) -> set[str]:
    """Números y palabras con mayúscula: lo que la IA no debe inventar."""
    return set(re.findall(r"\d+", text)) | set(re.findall(r"\b[A-ZÁÉÍÓÚÑ][\wáéíóúñ'’-]+", text))


def polish_explanation(q: dict) -> dict:
    facts = q.get("explanation") or {}
    if not facts.get("es"):
        return q
    prompt = (
        "Eres redactor de un juego de preguntas de cine. Reescribe estas dos frases (español e inglés) "
        "para que suenen naturales y atractivas, en un máximo de 30 palabras cada una. "
        "Usa EXCLUSIVAMENTE los datos que aparecen: no añadas fechas, cifras, nombres ni hechos nuevos.\n\n"
        f"ES: {facts['es']}\nEN: {facts['en']}\n\n"
        'Responde solo con JSON: {"es": "...", "en": "..."}'
    )
    try:
        out = json.loads(re.search(r"\{.*\}", _ask(prompt), re.S).group(0))
    except Exception:  # noqa: BLE001 - cualquier fallo conserva el original
        return q
    allowed = _tokens(facts["es"] + " " + facts["en"] + " " + q["prompt"]["es"] + " " + q["prompt"]["en"])
    for lang in ("es", "en"):
        new = out.get(lang, "")
        extra = {t for t in _tokens(new) if t not in allowed and not new.startswith(t)}
        if not new or len(new) > 260 or extra:
            return q
    q = dict(q)
    q["explanation"] = {"es": out["es"], "en": out["en"]}
    return q


def cross_check(q: dict) -> str | None:
    """Devuelve un motivo de revisión, o None si la IA coincide con la solución."""
    if q["format"] == "order":
        return None
    letters = "ABCDEF"
    options = "\n".join(f"{letters[i]}) {o['es']}" for i, o in enumerate(q["options"]))
    prompt = (f"Pregunta de cine: {q['prompt']['es']}\n{options}\n\n"
              "Responde solo con la letra correcta y tu seguridad (alta/media/baja), p. ej.: B alta")
    try:
        text = _ask(prompt, max_tokens=20).strip().upper()
    except Exception:  # noqa: BLE001
        return None
    if not text or text[0] not in letters:
        return None
    guess = letters.index(text[0])
    if guess != q["answer"]:
        if "ALTA" in text or q["difficulty"] == 1:
            return f"la IA eligió {text[0]} con seguridad"
    return None


def enrich(questions: list[dict], cross: bool = True, log=print) -> tuple[list[dict], list[tuple[dict, str]]]:
    if not available():
        log("  IA: sin ANTHROPIC_API_KEY, se omite la redacción y la comprobación cruzada")
        return questions, []
    out, review = [], []
    for i, q in enumerate(questions):
        q = polish_explanation(q)
        reason = cross_check(q) if cross else None
        if reason:
            review.append((q, reason))
        else:
            out.append(q)
        if (i + 1) % 100 == 0:
            log(f"  IA: {i + 1}/{len(questions)}")
    return out, review


# ---------------------------------------------------------------------------
# Adivina la película por emojis
# ---------------------------------------------------------------------------
_TEXTY = re.compile(r"[A-Za-z0-9\u00C0-\u024F]")


def _emoji_ok(text: str) -> bool:
    text = text.strip()
    return 2 <= len(text) <= 24 and not _TEXTY.search(text)


def make_emoji(film, distractor_titles: list[str]) -> str | None:
    """Pide 3-5 emojis para la película y comprueba que otra consulta la adivina."""
    facts = (f"Título: {film.title_en} ({film.year}). Director: {film.directors[0].name}. "
             f"Reparto: {', '.join(p.name for p in film.cast[:3])}. "
             f"Personajes: {', '.join(r.character for r in film.roles[:3])}.")
    prompt = ("Juego de adivinar películas con emojis. Escribe entre 3 y 5 emojis que representen la trama "
              "o los elementos más icónicos de esta película, en orden. Sin letras, números, banderas ni "
              "texto. Responde SOLO con los emojis.\n" + facts)
    try:
        emo = _ask(prompt, max_tokens=40).strip().split("\n")[0].strip()
    except Exception:  # noqa: BLE001
        return None
    if not _emoji_ok(emo):
        return None
    letters = "ABCD"
    titles = distractor_titles[:3] + [film.title_en]
    order = sorted(range(4), key=lambda i: hash((film.qid, i)) % 97)
    shown = [titles[i] for i in order]
    check = ("¿Qué película representan estos emojis? " + emo + "\n"
             + "\n".join(f"{letters[i]}) {t}" for i, t in enumerate(shown))
             + "\nResponde solo con la letra.")
    try:
        ans = _ask(check, max_tokens=5).strip().upper()[:1]
    except Exception:  # noqa: BLE001
        return None
    return emo if ans and ans in letters and shown[letters.index(ans)] == film.title_en else None


def build_emojis(films, cache: dict[str, str], limit: int = 900, log=print) -> dict[str, str]:
    """Emojis para las películas más conocidas (con caché para no pagar dos veces)."""
    if not available():
        log("  emojis: sin ANTHROPIC_API_KEY, se omiten")
        return cache
    famous = sorted([f for f in films if f.cast], key=lambda f: -f.popularity)[:limit]
    by_year = sorted(films, key=lambda f: f.year)
    done = 0
    for f in famous:
        if f.qid in cache:
            continue
        near = [o.title_en for o in by_year if abs(o.year - f.year) <= 5 and o.qid != f.qid
                and o.popularity >= f.popularity * 0.5][:40]
        emo = make_emoji(f, near[::max(1, len(near) // 3)][:3] if len(near) >= 3 else near)
        cache[f.qid] = emo or ""
        done += 1
        if done % 100 == 0:
            log(f"  emojis: {done} películas procesadas")
    return {k: v for k, v in cache.items() if v}
