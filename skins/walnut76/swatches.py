#!/usr/bin/env python3
"""Render palette ramps and material swatches to preview/swatches_8x.png."""
from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE))

from PIL import Image  # noqa: E402

from skinkit.canvas import Canvas  # noqa: E402
import w76_materials as M  # noqa: E402
import w76_palette as P  # noqa: E402


def main() -> None:
    W, H = 150, 118
    c = Canvas(W, H, fill="#404040", window="main")
    c.a[:, :, 3] = 255
    # ramps
    y = 2
    for ramp in (P.WALNUT, P.ALU, P.GLASS, P.TEAL, P.RED, P.PILOT, P.CHROME, P.PLASTIC):
        for i, col in enumerate(ramp):
            c.box(2 + i * 6, y, 6, 4, col)
        y += 5
    # walnut, vertical grain (cheek) with a knot, and horizontal (rail)
    M.walnut(c.sub(50, 2, 9, 60), "v", knots=[(54, 40, 1.6)])
    M.walnut(c.sub(62, 2, 86, 14), "h", knots=[(100, 9, 1.8)])
    # aluminium with screws and an engraved line
    al = c.sub(62, 18, 86, 44)
    M.aluminium(al)
    M.screw(al, 6, 6, 45)
    M.screw(al, 16, 6, 0)
    M.screw(al, 28, 7, 135, big=True)
    M.engrave_line_h(al, 4, 80, 14)
    M.jewel(al, 44, 7, False)
    M.jewel(al, 56, 7, True)
    M.jewel(al, 68, 7, True, colour="red")
    # glass in chrome with glare
    M.chrome_ring(al, 4, 20, 78, 20)
    al.rect(5, 21, 76, 18, "#000000")
    g = al.sub(6, 22, 74, 16)
    M.glass(g)
    M.glare(g, 140, strength=0.22)
    # plastic
    pl = c.sub(2, 66, 40, 14)
    M.plastic(pl)
    M.jewel(pl, 6, 7, True, r=2)
    M.jewel(pl, 30, 7, False, r=2)
    # periodic walnut: a 25-px tile repeated 4x and a 29-px tile repeated 3x
    t = Canvas(25, 14, origin=(25, 0), window="playlist")
    M.walnut(t, "h", period=25)
    for k in range(4):
        c.sub(2 + 25 * k, 84, 25, 14).a[:, :] = t.a
    t = Canvas(7, 29, origin=(0, 20), window="playlist")
    M.walnut(t, "v", period=29)
    for k in range(3):
        c.sub(110, 20 + 0 * k + 64 - 0, 7, 1)  # no-op keep simple
    for k in range(1):
        pass
    col = Canvas(7, 29 * 1, origin=(0, 20), window="playlist")
    M.walnut(col, "v", period=29)
    for k in range(1):
        c.sub(140, 84, 7, 29).a[:, :] = col.a
    out = HERE / "preview"
    out.mkdir(exist_ok=True)
    im = c.to_pil().convert("RGB")
    im = im.resize((W * 8, H * 8), Image.Resampling.NEAREST)
    im.save(out / "swatches_8x.png")
    print(out / "swatches_8x.png")


if __name__ == "__main__":
    main()
