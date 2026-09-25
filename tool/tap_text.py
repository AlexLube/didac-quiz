"""Pulsa en el emulador el elemento cuyo texto contiene el indicado (solo CI)."""
import re
import subprocess
import sys

xml = open(sys.argv[1], encoding="utf-8", errors="ignore").read()
target = sys.argv[2]
for m in re.finditer(r'<node [^>]*>', xml):
    node = m.group(0)
    text = " ".join(re.findall(r'(?:text|content-desc)="([^"]*)"', node))
    if target.lower() in text.lower():
        x1, y1, x2, y2 = map(int, re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', node).groups())
        subprocess.run(["adb", "shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2)])
        print("pulsado", text)
        break
else:
    print("no encontrado:", target)
