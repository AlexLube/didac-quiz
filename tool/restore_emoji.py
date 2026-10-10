"""Recupera emoji.json y music.json de un artefacto anterior (solo CI)."""
import pathlib
import sys
import zipfile

src, dest = sys.argv[1], pathlib.Path(sys.argv[2])
dest.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(src) as z:
    for name in z.namelist():
        base = pathlib.Path(name).name
        if base in ("emoji.json", "music.json") and not (dest / base).exists():
            (dest / base).write_bytes(z.read(name))
            print("recuperado", base)
