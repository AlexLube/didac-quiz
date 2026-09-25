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
