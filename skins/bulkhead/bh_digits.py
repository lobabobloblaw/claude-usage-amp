"""Bulkhead -- the amber CRT time numerals (9x13 cells).

Chunky seven-segment strokes, 2 px thick, drawn the way a tube draws them:
a near-white core down the middle of every lit stroke, bright amber body,
softer rounded ends, a dim halo pixel outside, faint ghosts of the unlit
segments, and the raster running through everything.  The cell varies only
vertically (raster rows), never horizontally, so one sprite works in all four
digit positions.
"""

from __future__ import annotations

import numpy as np

import bh_palette as P

W, H = 9, 13

# level map per segment: 3 = core, 2 = body, 1 = soft end
_SEG = {
    "a": {(2, 0): 1, (3, 0): 2, (4, 0): 2, (5, 0): 2, (6, 0): 1,
          (2, 1): 2, (3, 1): 3, (4, 1): 3, (5, 1): 3, (6, 1): 2},
    "d": {(2, 12): 1, (3, 12): 2, (4, 12): 2, (5, 12): 2, (6, 12): 1,
          (2, 11): 2, (3, 11): 3, (4, 11): 3, (5, 11): 3, (6, 11): 2},
    "g": {(2, 6): 2, (3, 6): 3, (4, 6): 3, (5, 6): 3, (6, 6): 2,
          (3, 5): 1, (4, 5): 1, (5, 5): 1, (3, 7): 1, (4, 7): 1, (5, 7): 1},
    "f": {(1, 1): 1, (1, 2): 2, (1, 3): 2, (1, 4): 2, (1, 5): 2, (1, 6): 1,
          (2, 1): 2, (2, 2): 3, (2, 3): 3, (2, 4): 3, (2, 5): 3, (2, 6): 2},
    "e": {(1, 6): 1, (1, 7): 2, (1, 8): 2, (1, 9): 2, (1, 10): 2, (1, 11): 1,
          (2, 6): 2, (2, 7): 3, (2, 8): 3, (2, 9): 3, (2, 10): 3, (2, 11): 2},
    "b": {(7, 1): 1, (7, 2): 2, (7, 3): 2, (7, 4): 2, (7, 5): 2, (7, 6): 1,
          (6, 1): 2, (6, 2): 3, (6, 3): 3, (6, 4): 3, (6, 5): 3, (6, 6): 2},
    "c": {(7, 6): 1, (7, 7): 2, (7, 8): 2, (7, 9): 2, (7, 10): 2, (7, 11): 1,
          (6, 6): 2, (6, 7): 3, (6, 8): 3, (6, 9): 3, (6, 10): 3, (6, 11): 2},
}

_DIGITS = {
    0: "abcdef", 1: "bc", 2: "abged", 3: "abgcd", 4: "fgbc", 5: "afgcd",
    6: "afgedc", 7: "abc", 8: "abcdefg", 9: "abfgcd", "blank": "", "minus": "g",
}


def raster_dark(wy: int) -> bool:
    """Odd window rows are the dark raster gaps."""
    return (int(wy) % 2) == 1


def glass_row(wy: int):
    return P.AMBER_WELL if not raster_dark(wy) else P.hx("#070401")


def level_maps(d, ghost_all: bool = True):
    lit = np.zeros((H, W), dtype=np.int8)
    ghost = np.zeros((H, W), dtype=bool)
    segs = _DIGITS[d]
    for name, pix in _SEG.items():
        for (x, y), lv in pix.items():
            if name in segs:
                lit[y, x] = max(lit[y, x], lv)
            elif ghost_all or name == "g":
                if lv >= 2:
                    ghost[y, x] = True
    ghost &= (lit == 0)
    return lit, ghost


def cell(d, wy0: int = 26, ghost_all: bool = True) -> np.ndarray:
    """(13, 9, 3) uint8 art for digit ``d`` whose top row is window row ``wy0``."""
    lit, ghost = level_maps(d, ghost_all)
    out = np.zeros((H, W, 3), dtype=np.float32)
    for y in range(H):
        out[y, :, :] = glass_row(wy0 + y)
    # halo: dim outer pixel around lit strokes (4-neighbour), weaker diagonals
    on = (lit >= 2).astype(np.float32)
    pad = np.pad(on, 1)
    n4 = pad[:-2, 1:-1] + pad[2:, 1:-1] + pad[1:-1, :-2] + pad[1:-1, 2:]
    nd = pad[:-2, :-2] + pad[:-2, 2:] + pad[2:, :-2] + pad[2:, 2:]
    halo = np.clip(n4 * 0.20 + nd * 0.06, 0, 0.42)
    dim = np.array(P.AMBER_LOW, dtype=np.float32)
    for y in range(H):
        for x in range(W):
            if lit[y, x] == 0 and halo[y, x] > 0:
                k = halo[y, x] * (0.7 if raster_dark(wy0 + y) else 1.0)
                out[y, x] = out[y, x] + (dim - out[y, x]) * k
    gcol = np.array(P.AMBER_GHOST, dtype=np.float32)
    g2 = np.array(P.AMBER_GHOST2, dtype=np.float32)
    cols = {1: np.array(P.AMBER_MID, dtype=np.float32),
            2: np.array(P.AMBER_BRIGHT, dtype=np.float32),
            3: np.array(P.AMBER_CORE, dtype=np.float32)}
    for y in range(H):
        dark = raster_dark(wy0 + y)
        for x in range(W):
            if lit[y, x]:
                col = cols[int(lit[y, x])]
                if dark:
                    col = col * np.array([0.86, 0.80, 0.70], dtype=np.float32)
                out[y, x] = col
            elif ghost[y, x]:
                base = out[y, x]
                gc = gcol if dark else g2
                out[y, x] = np.maximum(base, gc)
    return np.clip(np.rint(out), 0, 255).astype(np.uint8)


def colon(wy0: int = 26) -> np.ndarray:
    """(13, 4, 3) colon art: two 2x2 lit dots with halo, raster behind."""
    out = np.zeros((H, 4, 3), dtype=np.float32)
    for y in range(H):
        out[y, :, :] = glass_row(wy0 + y)
    dim = np.array(P.AMBER_LOW, dtype=np.float32)
    for (y0) in (3, 8):
        for y in range(y0 - 1, y0 + 3):
            for x in range(0, 4):
                inside = (y0 <= y <= y0 + 1) and (1 <= x <= 2)
                if inside:
                    col = np.array(P.AMBER_CORE if (x == 1 and y == y0) else P.AMBER_BRIGHT,
                                   dtype=np.float32)
                    if raster_dark(wy0 + y):
                        col = col * np.array([0.86, 0.80, 0.70], dtype=np.float32)
                    out[y, x] = col
                else:
                    corner = (y in (y0 - 1, y0 + 2)) and (x in (0, 3))
                    if not corner:
                        out[y, x] = out[y, x] + (dim - out[y, x]) * 0.22
    return np.clip(np.rint(out), 0, 255).astype(np.uint8)
