"""Walnut 76 -- vacuum-fluorescent time digits (9x13).

A hand-placed, slanted seven-segment figure: the upper half of the digit sits
one pixel to the right of the lower half, with the jog hidden in the break at
the middle bar, the way a low-resolution italic VFD actually looks.  Lit
segments are a flat bright phosphor with a one-pixel halo; unlit segments
remain just visible as ghosts.

The middle bar lands on x = 2..6, y = 6, which is exactly the strip the legacy
``numbers.bmp`` reads the minus sign from, and "1" keeps x = 0..4 of that row
clear.
"""

from __future__ import annotations

import numpy as np

from skinkit.canvas import Canvas

import w76_materials as M
import w76_palette as P

SEGMENTS: dict[str, list[tuple[int, int]]] = {}


def _span(row: int, x0: int, x1: int) -> list[tuple[int, int]]:
    return [(x, row) for x in range(x0, x1 + 1)]


def _col(x0: int, x1: int, r0: int, r1: int) -> list[tuple[int, int]]:
    return [(x, y) for y in range(r0, r1 + 1) for x in range(x0, x1 + 1)]


SEGMENTS["a"] = _span(0, 2, 7) + _span(1, 3, 6)
SEGMENTS["f"] = _col(1, 2, 1, 5)
SEGMENTS["b"] = _col(7, 8, 1, 5)
SEGMENTS["g"] = _span(6, 2, 6)
SEGMENTS["e"] = _col(0, 1, 7, 11)
SEGMENTS["c"] = _col(6, 7, 7, 11)
SEGMENTS["d"] = _span(11, 2, 5) + _span(12, 1, 6)

#: dim connector pixels that bridge the break at the middle row when both
#: halves of a side are lit
LINKS = {("f", "e"): (1, 6), ("b", "c"): (7, 6)}

LIT = {
    "0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc",
    "5": "afgcd", "6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcfgd",
    "minus": "g", "-": "g", "blank": "",
}

ON = "#8af3e6"          # flat, fully driven phosphor
LINK = P.TEAL[2]
GHOST = "#07262a"
HALO = P.TEAL[2]


def paint(c: Canvas, d, background) -> None:
    key = str(d) if not isinstance(d, str) else d
    lit = LIT.get(key, "")
    c.fill(background)
    # ghosts first.  The minus cell is a lone bar, not a figure.
    ghosts = "g" if key in ("minus", "-") else "abcdefg"
    for seg in ghosts:
        if seg in lit:
            continue
        if seg == "g" and key == "1":
            continue                      # legacy NO_MINUS strip must stay clear
        for (x, y) in SEGMENTS[seg]:
            c.px(x, y, GHOST)
    m = np.zeros((c.h, c.w), dtype=bool)
    for seg in lit:
        for (x, y) in SEGMENTS[seg]:
            m[y, x] = True
    if m.any():
        keep = None
        if key == "1":
            keep = np.zeros_like(m)
            keep[6, 0:5] = True
        M.glow_mask(c, m, HALO, strength=0.34, diag=0.45, keep=keep)
        for (a, b), (x, y) in LINKS.items():
            if a in lit and b in lit:
                c.px(x, y, LINK)
        ys, xs = np.nonzero(m)
        for x, y in zip(xs, ys):
            c.px(int(x), int(y), ON)
    c.a[:, :, 3] = 255
