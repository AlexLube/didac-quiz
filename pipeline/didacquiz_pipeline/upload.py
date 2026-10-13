"""Subida de preguntas y retos a Supabase (API REST con la clave service_role).

Variables de entorno: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
"""
from __future__ import annotations

import os

import requests


class Supabase:
    def __init__(self, url: str | None = None, key: str | None = None):
        self.url = (url or os.environ["SUPABASE_URL"]).rstrip("/")
        key = key or os.environ["SUPABASE_SERVICE_ROLE_KEY"]
        self.h = {"apikey": key, "Content-Type": "application/json"}
        # Las claves antiguas (JWT, "eyJ...") también van en Authorization; las nuevas
        # (sb_secret_...) solo en "apikey".
        if key.startswith("eyJ"):
            self.h["Authorization"] = f"Bearer {key}"

    def _post(self, table: str, rows: list[dict], on_conflict: str, returning: bool) -> list[dict]:
        prefer = "resolution=merge-duplicates," + ("return=representation" if returning else "return=minimal")
        r = requests.post(f"{self.url}/rest/v1/{table}", params={"on_conflict": on_conflict},
                          headers={**self.h, "Prefer": prefer}, json=rows, timeout=120)
        if r.status_code >= 300:
            raise RuntimeError(f"Supabase {table}: {r.status_code} {r.text[:500]}")
        return r.json() if returning else []

    def upsert_questions(self, questions: list[dict]) -> dict[str, int]:
        cols = ("external_id", "format", "difficulty", "topic", "entity_ids", "prompt", "options",
                "answer", "explanation", "image_url", "image_attribution", "audio_url",
                "audio_attribution", "media_start_ms", "source", "max_points", "extra", "time_limit_ms")
        questions = self.mirror_media(questions)
        ids: dict[str, int] = {}
        for i in range(0, len(questions), 500):
            rows = [{c: q.get(c) for c in cols} for q in questions[i : i + 500]]
            for row in rows:  # columnas NOT NULL con valor por defecto
                row["media_start_ms"] = row.get("media_start_ms") or 0
                row["entity_ids"] = row.get("entity_ids") or []
                row["extra"] = row.get("extra") or {}
                row["max_points"] = row.get("max_points") or row.get("difficulty") or 1
            for row in self._post("questions", rows, "external_id", returning=True):
                ids[row["external_id"]] = row["id"]
        return ids

    def upsert_titles(self, rows: list[dict]) -> int:
        """Títulos de películas para el autocompletado de «escribe el título»."""
        for i in range(0, len(rows), 1000):
            self._post("film_titles", rows[i : i + 1000], "qid,norm", returning=False)
        return len(rows)

    def mirror_media(self, questions: list[dict]) -> list[dict]:
        """Copia imágenes y audios de Commons a Supabase Storage (y recorta los audios)."""
        needs = [q for q in questions if q.get("image_url") or q.get("audio_url")
                 or any(o.get("image") for o in q.get("options") or [])]
        if not needs:
            return questions
        from .media import MediaStore
        store = MediaStore(self.url, self.h)
        out = []
        for q in questions:
            q = dict(q)
            try:
                if q.get("image_url") and "supabase" not in q["image_url"]:
                    q["image_url"] = store.mirror_image(q["image_url"])
                if any(o.get("image") for o in q.get("options") or []):
                    q["options"] = [dict(o, image=store.mirror_image(o["image"]))
                                    if o.get("image") and "supabase" not in o["image"] else o
                                    for o in q["options"]]
                if q.get("audio_url") and "supabase" not in q["audio_url"]:
                    q["audio_url"] = store.mirror_clip(q["audio_url"], q.get("_audio_start_s", 0))
                    q["media_start_ms"] = 0
            except Exception as e:  # noqa: BLE001 - sin su medio, la pregunta no se usa
                print(f"  aviso: no se pudo copiar el medio de {q['external_id']}: {e}")
                continue
            out.append(q)
        print(f"  medios copiados: {len(needs) - (len(questions) - len(out))}/{len(needs)}")
        return out

    def used_external_ids(self) -> set[str]:
        """Preguntas ya programadas en algún reto (para no repetirlas)."""
        r = requests.get(f"{self.url}/rest/v1/challenges", params={"select": "question_ids"},
                         headers=self.h, timeout=120)
        r.raise_for_status()
        qids = {q for row in r.json() for q in row["question_ids"]}
        if not qids:
            return set()
        out: set[str] = set()
        qlist = sorted(qids)
        for i in range(0, len(qlist), 300):
            chunk = ",".join(map(str, qlist[i : i + 300]))
            r = requests.get(f"{self.url}/rest/v1/questions",
                             params={"select": "external_id", "id": f"in.({chunk})"},
                             headers=self.h, timeout=120)
            r.raise_for_status()
            out |= {row["external_id"] for row in r.json()}
        return out

    def recent_entity_sets(self, before: str, days: int = 60) -> list[set[str]]:
        """Entidades (películas, personas) de los últimos `days` retos anteriores a `before`,
        en orden cronológico, para que un lote nuevo no repita las del anterior."""
        r = requests.get(f"{self.url}/rest/v1/challenges",
                         params={"select": "challenge_date,question_ids", "challenge_date": f"lt.{before}",
                                 "order": "challenge_date.desc", "limit": days},
                         headers=self.h, timeout=120)
        r.raise_for_status()
        rows = list(reversed(r.json()))
        ids = sorted({q for d in rows for q in d["question_ids"]})
        ents: dict[int, set[str]] = {}
        for i in range(0, len(ids), 300):
            chunk = ",".join(map(str, ids[i : i + 300]))
            q = requests.get(f"{self.url}/rest/v1/questions",
                             params={"select": "id,entity_ids", "id": f"in.({chunk})"},
                             headers=self.h, timeout=120)
            q.raise_for_status()
            ents.update({row["id"]: set(row["entity_ids"] or []) for row in q.json()})
        return [set().union(*(ents.get(x, set()) for x in d["question_ids"])) for d in rows]

    def last_challenge_date(self) -> str | None:
        r = requests.get(f"{self.url}/rest/v1/challenges",
                         params={"select": "challenge_date", "order": "challenge_date.desc", "limit": 1},
                         headers=self.h, timeout=60)
        r.raise_for_status()
        rows = r.json()
        return rows[0]["challenge_date"] if rows else None

    def insert_challenges(self, calendar: list[dict], ids: dict[str, int]) -> None:
        rows = [{"challenge_date": c["date"], "kind": c["kind"], "title": c["title"], "theme": c.get("theme"),
                 "question_ids": [ids[x] for x in c["external_ids"]]} for c in calendar]
        for i in range(0, len(rows), 200):
            self._post("challenges", rows[i : i + 200], "challenge_date", returning=False)

    def delete_challenges_from(self, day: str) -> None:
        """Borra los retos desde `day` (incluido). Solo retos futuros, que nadie ha jugado."""
        r = requests.delete(f"{self.url}/rest/v1/challenges", params={"challenge_date": f"gte.{day}"},
                            headers={**self.h, "Prefer": "return=minimal"}, timeout=120)
        if r.status_code >= 300:
            raise RuntimeError(f"No se pudieron borrar los retos futuros: {r.status_code} {r.text[:300]}")

    def challenge_report(self, start: str, end: str) -> list[dict]:
        """Formatos y temas de las preguntas de cada reto entre dos fechas."""
        r = requests.get(f"{self.url}/rest/v1/challenges",
                         params={"select": "challenge_date,question_ids",
                                 "and": f"(challenge_date.gte.{start},challenge_date.lte.{end})",
                                 "order": "challenge_date"}, headers=self.h, timeout=120)
        r.raise_for_status()
        days = r.json()
        ids = sorted({q for d in days for q in d["question_ids"]})
        info: dict[int, dict] = {}
        for i in range(0, len(ids), 300):
            chunk = ",".join(map(str, ids[i : i + 300]))
            q = requests.get(f"{self.url}/rest/v1/questions",
                             params={"select": "id,format,topic,image_url,audio_url", "id": f"in.({chunk})"},
                             headers=self.h, timeout=120)
            q.raise_for_status()
            info.update({row["id"]: row for row in q.json()})
        return [{"date": d["challenge_date"], "questions": [info.get(x, {}) for x in d["question_ids"]]}
                for d in days]

    def challenges_remaining(self) -> int:
        r = requests.post(f"{self.url}/rest/v1/rpc/challenges_remaining", headers=self.h, json={}, timeout=60)
        r.raise_for_status()
        return int(r.json())
