#!/usr/bin/env python3
"""Render palette ramps and material swatches for the Bookcloth skin at 8x.

    python3 skins/bookcloth/swatches.py        -> skins/bookcloth/crops/swatches_8x.png
"""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))

import numpy as np
from PIL import Image

from skinkit.canvas import Canvas
from bookcloth_art import materials as M, palette as P
from bookcloth_art.plate import Plate


def main() -> None:
    W, H = 200, 110
    c = Canvas(W, H, origin=(0, 0), window="main", fill="#808080")
    p = Plate(c)
    # ramps
    y = 1
    for ramp in (P.PAPER, P.INK, P.CLOTH, P.KRAFT, P.BLUE, P.GREEN, P.THREAD):
        for i, col in enumerate(ramp):
            p.box(1 + i * 7, y, 7, 5, col)
        y += 6
    for i in range(28):
        p.box(50 + i * 3, 1, 3, 5, P.heat(i / 27))
    # cloth: plain, spine dye, faded
    M.lay_cloth(p, 0, 44, 200, 66)
    M.lay_cloth(p, 50, 8, 60, 14, dye=-0.17)
    M.lay_cloth(p, 112, 8, 60, 14, fade=0.55)
    M.lay_cloth(p, 50, 23, 60, 14, dye=-0.10)
    M.lay_cloth(p, 112, 23, 60, 14, dye=-0.17, fade=0.5)
    # opening with paper + plate mark
    M.cut_opening(p, 8, 52, 70, 34)
    M.plate_mark(p, 14, 60, 40, 13)
    p.box(16, 62, 2, 9, P.INK_BODY)
    # cards
    M.card(p, 90, 54, 21, 16)
    M.card(p, 114, 55, 21, 16, pressed=True)
    M.card(p, 140, 54, 21, 16, tone="manilla")
    M.card(p, 60, 66, 14, 10, tone="manilla", on="paper")
    # stitches
    M.stitch_run(p, 170, 50, 50, vertical=True, pitch=7, stitch=4)
    M.stitch_run(p, 90, 80, 70, vertical=False, pitch=7, stitch=4, seed=3)
    # wash
    cols = np.stack([P.heat(i / 59) for i in range(60)])
    M.lay_paper(p, 86, 92, 70, 12)
    M.wash_band(p, 90, 95, 60, 5, cols)
    out = HERE / "crops"
    out.mkdir(exist_ok=True)
    img = Image.fromarray(c.a, "RGBA").convert("RGB")
    img.resize((W * 8, H * 8), Image.Resampling.NEAREST).save(out / "swatches_8x.png")
    print(out / "swatches_8x.png")


if __name__ == "__main__":
    main()
