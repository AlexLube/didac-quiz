"""Dibuja el mapamundi del juego (proyección equirrectangular, 2:1).

Datos: Natural Earth (dominio público), https://www.naturalearthdata.com
Uso:  python3 tool/build_world_map.py countries.geojson app/assets/world_map.png
"""
import json
import sys

from PIL import Image, ImageDraw

W, H = 2048, 1024
SEA, LAND, BORDER, GRID = (20, 14, 40), (58, 42, 107), (118, 98, 190), (34, 26, 66)


def project(lon, lat):
    return ((lon + 180) / 360 * W, (90 - lat) / 180 * H)


def main(src, dst):
    data = json.load(open(src, encoding="utf-8"))
    img = Image.new("RGB", (W, H), SEA)
    d = ImageDraw.Draw(img)
    for lon in range(-180, 181, 30):
        x, _ = project(lon, 0)
        d.line([(x, 0), (x, H)], fill=GRID, width=2)
    for lat in range(-90, 91, 30):
        _, y = project(0, lat)
        d.line([(0, y), (W, y)], fill=GRID, width=2)
    for feat in data["features"]:
        geom = feat["geometry"]
        polys = geom["coordinates"] if geom["type"] == "MultiPolygon" else [geom["coordinates"]]
        for poly in polys:
            ring = [project(lon, lat) for lon, lat in poly[0]]
            d.polygon(ring, fill=LAND)
            d.line(ring + [ring[0]], fill=BORDER, width=2)
    img.save(dst, optimize=True)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
