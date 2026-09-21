#!/usr/bin/env python3
"""8x nearest-neighbour crops of any rect of any preview window or built sheet.

    python3 skins/walnut76/crop.py main 0 0 120 60          # preview/main.png
    python3 skins/walnut76/crop.py sheet:cbuttons 0 0 136 36
    python3 skins/walnut76/crop.py eq 60 30 120 80 6         # custom scale

Writes ``preview/crops/<name>_<x>_<y>_<w>_<h>.png`` and prints the path.
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent


def crop(name: str, x: int, y: int, w: int, h: int, scale: int = 8) -> Path:
    if name.startswith("sheet:"):
        stem = name.split(":", 1)[1]
        src = HERE / "out" / f"{stem}.bmp"
    else:
        src = HERE / "preview" / f"{name}.png"
    im = Image.open(src).convert("RGB")
    x, y = max(0, x), max(0, y)
    w, h = min(w, im.width - x), min(h, im.height - y)
    im = im.crop((x, y, x + w, y + h)).resize((w * scale, h * scale), Image.Resampling.NEAREST)
    out = HERE / "preview" / "crops"
    out.mkdir(parents=True, exist_ok=True)
    p = out / f"{name.replace(':', '_')}_{x}_{y}_{w}_{h}.png"
    im.save(p)
    return p


if __name__ == "__main__":
    a = sys.argv[1:]
    if len(a) < 5:
        print(__doc__)
        raise SystemExit(2)
    print(crop(a[0], int(a[1]), int(a[2]), int(a[3]), int(a[4]), int(a[5]) if len(a) > 5 else 8))
