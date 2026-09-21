"""Display typography: the red seven-segment digits, the 5x6 LCD glyphs and
the 5x8 character-LCD list face."""

from __future__ import annotations

import numpy as np

from . import palette as P
from . import type_plfont
from .type_small import LCD56

# ---- seven-segment, hand-placed on an 8x13 grid, upper half leaning 1 px ----
# Segments are solid 2 px bars with clipped ends (real segment shape), a hot
# core line down the middle of each bar, dark ghosts, and bloom that only ever
# lands on bare face -- never on a ghost -- so unlit never reads as lit.
def _bar_h(y_out, y_in, x0=1, x1=6):
    pts = [(x, y_out, 1) for x in range(x0 + 1, x1)] + [(x, y_in, 2) for x in range(x0, x1 + 1)]
    return pts


def _bar_v(x_out, x_in, y0, y1):
    return [(x_out, y, 1) for y in range(y0 + 1, y1)] + [(x_in, y, 2) for y in range(y0, y1 + 1)]


_SEGS = {
    "a": _bar_h(0, 1, 1, 6),
    "d": _bar_h(12, 11, 1, 6),
    "g": [(x, 6, 2) for x in range(1, 7)] + [(x, 5, 1) for x in range(2, 6)] + [(x, 7, 1) for x in range(2, 6)],
    "f": _bar_v(0, 1, 1, 5),
    "b": _bar_v(7, 6, 1, 5),
    "e": _bar_v(0, 1, 7, 11),
    "c": _bar_v(7, 6, 7, 11),
}
_MAP = {0: "abcdef", 1: "bc", 2: "abged", 3: "abgcd", 4: "fgbc", 5: "afgcd", 6: "afgedc",
        7: "abc", 8: "abcdefg", 9: "abcfgd", "minus": "g", "blank": ""}


def _shift(y):
    return 1 if y <= 5 else 0


DIGIT_ON = P.SEG[3]          # colour of the g segment's core row (legacy minus strip)
_GHOST = P.SEG_GHOST


_HOT = {"a": (4, 1), "d": (3, 11), "g": (4, 6), "f": (1, 3), "b": (6, 3), "e": (1, 9), "c": (6, 9)}


def _hot(lit):
    return [(_HOT[n][0] + _shift(_HOT[n][1]), _HOT[n][1]) for n in lit]


def digit(c, d):
    """9x13 cell on the flat module face."""
    c.fill(P.SEG_FACE)
    lit = set(_MAP[d])
    ghost_px, lit_px = set(), {}
    for name, pts in _SEGS.items():
        for x, y, tone in pts:
            xx = x + _shift(y)
            if name in lit:
                lit_px[(xx, y)] = max(lit_px.get((xx, y), 0), tone)
            else:
                ghost_px.add((xx, y))
    for (x, y) in ghost_px:
        if (x, y) not in lit_px:
            c.px(x, y, _GHOST)
    for (x, y), tone in lit_px.items():
        c.px(x, y, DIGIT_ON if tone == 2 else P.SEG[2])
    for (x, y) in _hot(lit):
        c.px(x, y, P.SEG[4])
    for (x, y) in lit_px:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + dx, y + dy)
            if 0 <= q[0] < 9 and 0 <= q[1] < 13 and q not in lit_px and q not in ghost_px:
                c.px(q[0], q[1], P.lerp(P.SEG_FACE, P.SEG[1], 0.30))
    c.a[:, :, 3] = 255


def glyph(c, ch):
    c.fill(P.LCD_FIELD)
    m = LCD56.mask(ch)
    for y in range(6):
        for x in range(5):
            if m[y, x]:
                c.px(x, y, P.LCD_PIXEL)
    c.a[:, :, 3] = 255


# ---- plfont: 6x10 cell, dots in columns 0..4, rows 1..8 ---------------------
PL_CELL = (6, 10)
GHOST = 0.085               # unlit-dot coverage: the STN grid seen at an angle


def pl_glyph(c, ch):
    rows = type_plfont.rows(ch)
    g = int(round(GHOST * 255))
    for j, row in enumerate(rows):
        for i, bit in enumerate(row):
            v = 255 if bit == "#" else g
            c.px(i, j + 1, (v, v, v, 255))
    c.a[:, :, 3] = 255
