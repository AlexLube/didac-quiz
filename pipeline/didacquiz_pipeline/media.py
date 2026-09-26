"""Imágenes y audio de Wikimedia Commons.

- Solo se aceptan licencias libres (CC0, CC BY, CC BY-SA) o dominio público.
- Cada archivo lleva su atribución (autor y licencia), que la app muestra.
- Al subir los retos, los archivos se copian a Supabase Storage (bucket público
  "media"): la app no depende de Commons y los audios se recortan a 20 s.
"""
from __future__ import annotations

import hashlib
import html
import re
import shutil
import subprocess
import tempfile
import time
from pathlib import Path
from urllib.parse import unquote

import requests

API = "https://commons.wikimedia.org/w/api.php"
UA = {"User-Agent": "DidacQuizPipeline/1.0 (https://github.com/AlexLube/didac-quiz)"}

_OK_LICENSE = re.compile(r"^(cc0|cc[- ]by(-sa)?[- ][\d.]+|cc[- ]by(-sa)?|public domain|pd\b|pd-.*)", re.I)
_BAD_LICENSE = re.compile(r"\b(nc|nd|fair use|non-free)\b", re.I)


def filename_from_url(url: str) -> str:
    """'http://commons.wikimedia.org/wiki/Special:FilePath/Foo%20bar.jpg' -> 'Foo bar.jpg'."""
    return unquote(url.rsplit("/", 1)[-1]).replace("_", " ")


def _plain(text: str | None) -> str:
    text = re.sub(r"<[^>]+>", "", text or "")
    return re.sub(r"\s+", " ", html.unescape(text)).strip()


def license_ok(short_name: str) -> bool:
    return bool(short_name) and bool(_OK_LICENSE.match(short_name.strip())) \
        and not _BAD_LICENSE.search(short_name)


def _get(params: dict, retries: int = 4) -> dict:
    for attempt in range(retries):
        try:
            r = requests.get(API, params={**params, "format": "json"}, headers=UA, timeout=60)
            if r.status_code == 200:
                return r.json()
        except requests.RequestException:
            pass
        time.sleep(5 * (attempt + 1))
    return {}


def file_infos(filenames: list[str], width: int = 800) -> dict[str, dict]:
    """Licencia, autor y URLs de hasta muchos archivos (en bloques de 40)."""
    out: dict[str, dict] = {}
    names = sorted(set(filenames))
    for i in range(0, len(names), 40):
        chunk = names[i : i + 40]
        data = _get({
            "action": "query", "titles": "|".join(f"File:{n}" for n in chunk),
            "prop": "imageinfo", "iiprop": "url|extmetadata|mime|size", "iiurlwidth": width,
        })
        norm = {n["to"]: n["from"] for n in data.get("query", {}).get("normalized", [])}
        for page in data.get("query", {}).get("pages", {}).values():
            info = (page.get("imageinfo") or [None])[0]
            if not info:
                continue
            title = page["title"]
            original = norm.get(title, title).removeprefix("File:")
            meta = info.get("extmetadata", {})
            lic = _plain(meta.get("LicenseShortName", {}).get("value"))
            artist = _plain(meta.get("Artist", {}).get("value")) or "Wikimedia Commons"
            out[original] = {
                "file": original,
                "url": info.get("url"),
                "thumb": info.get("thumburl") or info.get("url"),
                "mime": info.get("mime", ""),
                "license": lic,
                "artist": artist[:80],
                "ok": license_ok(lic),
            }
    return out


def search_audio(query: str, limit: int = 15) -> list[dict]:
    """Busca grabaciones libres en Commons (ogg, oga, flac, mp3, wav; no MIDI)."""
    data = _get({"action": "query", "list": "search", "srnamespace": 6,
                 "srsearch": f"{query} filetype:audio", "srlimit": limit})
    names = [h["title"].removeprefix("File:") for h in data.get("query", {}).get("search", [])]
    names = [n for n in names if re.search(r"\.(ogg|oga|flac|mp3|wav|opus)$", n, re.I)]
    infos = file_infos(names)
    return [infos[n] for n in names if n in infos and infos[n]["ok"]
            and not infos[n]["mime"].endswith("midi")]


def attribution(info: dict, lang: str = "es") -> str:
    lic = info["license"]
    who = info["artist"]
    return f"{'Foto' if info['mime'].startswith('image') else 'Grabación'}: {who} · {lic} · Wikimedia Commons" \
        if lang == "es" else f"{who} · {lic} · Wikimedia Commons"


# ---------------------------------------------------------------------------
# Copia a Supabase Storage
# ---------------------------------------------------------------------------
class MediaStore:
    def __init__(self, supabase_url: str, headers: dict, bucket: str = "media"):
        self.url = supabase_url.rstrip("/")
        self.h = {k: v for k, v in headers.items() if k.lower() != "content-type"}
        self.bucket = bucket
        self._ensure_bucket()

    def _ensure_bucket(self) -> None:
        r = requests.post(f"{self.url}/storage/v1/bucket", headers={**self.h, "Content-Type": "application/json"},
                          json={"id": self.bucket, "name": self.bucket, "public": True}, timeout=60)
        if r.status_code >= 300 and "already exists" not in r.text.lower() and r.status_code != 409:
            raise RuntimeError(f"No se pudo crear el bucket de medios: {r.status_code} {r.text[:200]}")

    def public_url(self, path: str) -> str:
        return f"{self.url}/storage/v1/object/public/{self.bucket}/{path}"

    def exists(self, path: str) -> bool:
        r = requests.head(self.public_url(path), timeout=30)
        return r.status_code == 200

    def put(self, path: str, data: bytes, content_type: str) -> str:
        r = requests.post(f"{self.url}/storage/v1/object/{self.bucket}/{path}",
                          headers={**self.h, "Content-Type": content_type, "x-upsert": "true"},
                          data=data, timeout=120)
        if r.status_code >= 300:
            raise RuntimeError(f"Error subiendo {path}: {r.status_code} {r.text[:200]}")
        return self.public_url(path)

    def mirror_image(self, url: str) -> str:
        path = "img/" + hashlib.sha1(url.encode()).hexdigest()[:20] + ".jpg"
        if self.exists(path):
            return self.public_url(path)
        r = requests.get(url, headers=UA, timeout=60)
        r.raise_for_status()
        ctype = r.headers.get("Content-Type", "image/jpeg").split(";")[0]
        return self.put(path, r.content, ctype)

    def mirror_clip(self, url: str, start_s: float = 0, seconds: int = 20) -> str:
        """Descarga, recorta con ffmpeg a `seconds` y sube como MP3."""
        path = "audio/" + hashlib.sha1(f"{url}|{start_s}|{seconds}".encode()).hexdigest()[:20] + ".mp3"
        if self.exists(path):
            return self.public_url(path)
        if not shutil.which("ffmpeg"):
            raise RuntimeError("Falta ffmpeg para recortar el audio")
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / ("src" + Path(url).suffix)
            dst = Path(tmp) / "clip.mp3"
            with requests.get(url, headers=UA, timeout=120, stream=True) as r:
                r.raise_for_status()
                with open(src, "wb") as fh:
                    for chunk in r.iter_content(1 << 16):
                        fh.write(chunk)
            subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-ss", str(start_s), "-t", str(seconds),
                            "-i", str(src), "-vn", "-ac", "2", "-ar", "44100", "-b:a", "128k",
                            "-af", f"afade=t=out:st={seconds - 2}:d=2", str(dst)], check=True)
            return self.put(path, dst.read_bytes(), "audio/mpeg")
