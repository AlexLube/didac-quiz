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
                "audio_attribution", "media_start_ms", "source")
        questions = self.mirror_media(questions)
        ids: dict[str, int] = {}
        for i in range(0, len(questions), 500):
            rows = [{c: q.get(c) for c in cols} for q in questions[i : i + 500]]
            for row in rows:  # columnas NOT NULL con valor por defecto
                row["media_start_ms"] = row.get("media_start_ms") or 0
                row["entity_ids"] = row.get("entity_ids") or []
            for row in self._post("questions", rows, "external_id", returning=True):
                ids[row["external_id"]] = row["id"]
        return ids

    def mirror_media(self, questions: list[dict]) -> list[dict]:
        """Copia imágenes y audios de Commons a Supabase Storage (y recorta los audios)."""
        needs = [q for q in questions if q.get("image_url") or q.get("audio_url")]
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

    def last_challenge_date(self) -> str | None:
        r = requests.get(f"{self.url}/rest/v1/challenges",
                         params={"select": "challenge_date", "order": "challenge_date.desc", "limit": 1},
                         headers=self.h, timeout=60)
        r.raise_for_status()
        rows = r.json()
        return rows[0]["challenge_date"] if rows else None

    def insert_challenges(self, calendar: list[dict], ids: dict[str, int]) -> None:
        rows = [{"challenge_date": c["date"], "kind": c["kind"], "title": c["title"],
                 "question_ids": [ids[x] for x in c["external_ids"]]} for c in calendar]
        for i in range(0, len(rows), 200):
            self._post("challenges", rows[i : i + 200], "challenge_date", returning=False)

    def delete_challenges_from(self, day: str) -> None:
        """Borra los retos desde `day` (incluido). Solo retos futuros, que nadie ha jugado."""
        r = requests.delete(f"{self.url}/rest/v1/challenges", params={"challenge_date": f"gte.{day}"},
                            headers={**self.h, "Prefer": "return=minimal"}, timeout=120)
        if r.status_code >= 300:
            raise RuntimeError(f"No se pudieron borrar los retos futuros: {r.status_code} {r.text[:300]}")

    def challenges_remaining(self) -> int:
        r = requests.post(f"{self.url}/rest/v1/rpc/challenges_remaining", headers=self.h, json={}, timeout=60)
        r.raise_for_status()
        return int(r.json())
