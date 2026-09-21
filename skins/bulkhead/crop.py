#!/usr/bin/env python3
"""8x nearest-neighbour crops of any rect of any preview window or built sheet.

    python3 skins/bulkhead/crop.py main 0 0 140 60            # preview/main.png
    python3 skins/bulkhead/crop.py sheet:cbuttons 0 0 136 36  # out/cbuttons.bmp
    python3 skins/bulkhead/crop.py eq 60 30 120 80 --scale 6 --name rods

Writes skins/bulkhead/preview/crops/<name>.png and prints the path.
"""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("x", type=int)
    ap.add_argument("y", type=int)
    ap.add_argument("w", type=int)
    ap.add_argument("h", type=int)
    ap.add_argument("--scale", type=int, default=8)
    ap.add_argument("--name", default=None)
    a = ap.parse_args()
    if a.src.startswith("sheet:"):
        stem = a.src.split(":", 1)[1]
        p = HERE / "out" / (stem + ".bmp")
    elif a.src.startswith("file:"):
        p = Path(a.src.split(":", 1)[1])
    else:
        p = HERE / "preview" / (a.src + ".png")
    img = Image.open(p).convert("RGB")
    x1, y1 = min(img.width, a.x + a.w), min(img.height, a.y + a.h)
    crop = img.crop((a.x, a.y, x1, y1))
    crop = crop.resize((crop.width * a.scale, crop.height * a.scale), Image.NEAREST)
    out = HERE / "preview" / "crops"
    out.mkdir(parents=True, exist_ok=True)
    name = a.name or f"{a.src.replace(':', '_')}_{a.x}_{a.y}_{a.w}_{a.h}"
    dst = out / (name + ".png")
    crop.save(dst)
    print(dst)


if __name__ == "__main__":
    main()
