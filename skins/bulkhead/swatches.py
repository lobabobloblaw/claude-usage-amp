#!/usr/bin/env python3
"""Render palette ramps + material swatches to preview/swatches_8x.png."""
from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))

from PIL import Image  # noqa: E402

from skinkit.canvas import Canvas  # noqa: E402

import bh_materials as M  # noqa: E402
import bh_palette as P  # noqa: E402


def main() -> None:
    c = Canvas(200, 120, origin=(0, 0), window="main", fill="#000000")
    # ramps
    ramps = [P.GUN, P.STEEL, P.ORANGE, P.HAZ_Y + P.HAZ_K, P.AMBER, P.RED, P.GREEN,
             P.LAMP_AMBER, P.RUBBER, P.LEGEND]
    for j, r in enumerate(ramps):
        for i, col in enumerate(r):
            M.box(c, 2 + i * 6, 2 + j * 5, 6, 4, col)
    # plate
    v = c.sub(60, 2, 70, 40)
    M.plate(v, seed=5)
    M.raised(c, 66, 8, 20, 10)
    M.recessed(c, 96, 8, 20, 10)
    M.box(c, 96, 8, 20, 10, P.AMBER_WELL)
    M.hex_bolt(c, 68, 31, 0, mark=0)
    M.hex_bolt(c, 81, 31, 1, mark=1)
    M.hex_bolt(c, 94, 31, 2, mark=2)
    M.hex_bolt(c, 107, 31, 3, mark=0)
    M.oil_streak(c, 81, 37, 5, seed=2)
    M.rivet(c, 114, 28)
    M.rivet(c, 120, 28, big=True)
    for k in range(4):
        M.slot_screw(c, 116 + k * 0, 22, k)
    M.scratch(c, 100, 22, 112, 20)
    # steel
    M.steel(c, 134, 2, 40, 14, seed=3)
    M.raised(c, 134, 2, 40, 14)
    M.steel(c, 134, 20, 40, 14, seed=3, base=0.42, direction="v")
    # rubber
    M.rubber(c, 178, 2, 20, 14, seed=1)
    M.rubber(c, 178, 20, 20, 14, seed=1, base=0.6)
    # paint
    v = c.sub(60, 46, 60, 34)
    M.plate(v, seed=5)
    M.paint_layer(c, 62, 48, 26, 30, seed=9)
    M.paint_layer(c, 92, 48, 26, 30, seed=19, chip=0.9)
    # hazard
    v = c.sub(124, 46, 50, 34)
    M.plate(v, seed=5)
    M.hazard(c, 126, 48, 46, 8, width=3, seed=3)
    M.hazard(c, 126, 60, 46, 14, width=4, seed=7, chip=0.7)
    img = c.to_pil().convert("RGB")
    img = img.resize((img.width * 8, img.height * 8), Image.NEAREST)
    out = HERE / "preview"
    out.mkdir(exist_ok=True)
    img.save(out / "swatches_8x.png")
    print(out / "swatches_8x.png")


if __name__ == "__main__":
    main()
