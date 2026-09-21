"""doodles -- the hand-drawn marks printed on the paper and stamped in the cloth.

All original drawings: an open-centred, uneven "spark" (eight rays of unequal
length that never meet in the middle), a node-and-line constellation, a wobbly
pen underline, a pencil registration cross, a paper clip, washi tape.

Masks use ``#`` full ink, ``+`` soft ink, ``.`` nothing.
"""

from __future__ import annotations

import numpy as np

from . import palette as P
from .plate import Plate


def _m(art: str) -> np.ndarray:
    rows = [r for r in art.strip("\n").split("\n")]
    w = max(len(r) for r in rows)
    lut = {"#": 1.0, "+": 0.55, ":": 0.28}
    return np.array([[lut.get(k, 0.0) for k in r.ljust(w, ".")] for r in rows], dtype=np.float32)


# a spark drawn with a dip pen: rays of unequal length, open centre
SPARK_13 = _m("""
.....#.......
.....#....+..
.+...#+..#...
..#...#.#+...
...#+...+....
....:.....+##
###+.........
.........+...
...+#...#+...
..#+..#..#...
.#....#...#..
......#+...+.
......+#.....
""")

SPARK_9 = _m("""
...#.....
...#..#..
.#..+#...
..#......
......+##
##+......
...#.+#..
..#..#.#.
....+#...
""")

SPARK_7 = _m("""
..#....
..#..#.
#..+#..
.+...##
##...+.
..#+..#
.#..#..
""")

SPARK_5 = _m("""
.#..#
..+..
#+.+#
..+..
#..#.
""")


def spark(p: Plate, x: int, y: int, size: int = 13, col=P.INK_BODY, a: float = 1.0):
    m = {13: SPARK_13, 9: SPARK_9, 7: SPARK_7, 5: SPARK_5}[size]
    p.mask(x, y, m, col, a)
    return m


def wobble_line(p: Plate, x0: int, x1: int, y: int, col=P.INK_BODY, a: float = 0.9,
                seed: int = 0, amp: int = 1, thick_runs: bool = True):
    """A pen underline that wanders a pixel and swells where the nib slowed."""
    rng = np.random.RandomState(4200 + seed)
    yy = float(y)
    drift = 0
    for x in range(x0, x1 + 1):
        if rng.rand() < 0.16:
            drift = int(np.clip(drift + rng.choice([-1, 1]), -amp, amp))
        k = a * (0.75 + 0.25 * rng.rand())
        p.px(x, int(yy) + drift, col, k)
        if thick_runs and rng.rand() < 0.10:
            p.px(x, int(yy) + drift + 1, col, k * 0.45)
    p.px(x0 - 1, y, col, a * 0.4)
    p.px(x1 + 1, y + drift, col, a * 0.5)


def constellation(p: Plate, x: int, y: int, col=P.INK_BODY, a: float = 0.85,
                  nodes=((0, 5), (6, 1), (12, 6), (19, 2), (24, 8)), ring=(1, 3)):
    """Nodes joined by thin pen lines; some nodes are open rings."""
    pts = [(x + nx, y + ny) for nx, ny in nodes]
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        p.line(ax, ay, bx, by, col, a * 0.55)
    for i, (nx, ny) in enumerate(pts):
        if i in ring:
            for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0)):
                p.px(nx + dx, ny + dy, col, a)
            p.px(nx, ny, P.PAPER_FLAT, 1.0)
        else:
            p.px(nx, ny, col, a)
            p.px(nx + 1, ny, col, a * 0.5)
            p.px(nx, ny + 1, col, a * 0.5)


def registration(p: Plate, x: int, y: int, col=P.PENCIL, a: float = 0.8):
    """A pencil registration cross-in-circle, 7 x 7."""
    m = _m("""
...#...
.+###+.
.#.#.#.
#######
.#.#.#.
.+###+.
...#...
""")
    m2 = _m("""
...#...
..+.+..
.+...+.
#..#..#
.+...+.
..+.+..
...#...
""")
    p.mask(x, y, m2, col, a)
    p.hline(x + 1, x + 5, y + 3, col, a * 0.7)
    p.vline(x + 3, y + 1, y + 5, col, a * 0.7)


def pencil_rule(p: Plate, x0: int, x1: int, y: int, a: float = 0.55, seed: int = 0):
    """A guide-line someone forgot to erase: graphite skips over the tooth."""
    rng = np.random.RandomState(5100 + seed)
    for x in range(x0, x1 + 1):
        if rng.rand() < 0.86:
            p.px(x, y, P.PENCIL, a * (0.55 + 0.45 * rng.rand()))


def paper_clip(p: Plate, x: int, y: int, vertical: bool = True):
    """A steel-wire paper clip seen from above, 5 x 13 (warm grey wire with a
    lit flank and a cast shadow)."""
    art = _m("""
.###.
#...#
#.#.#
#.#.#
#.#.#
#.#.#
#.#.#
#.#.#
#.#.#
#.#.#
..#.#
#...#
.###.
""")
    sh = np.roll(np.roll(art, 1, 0), 1, 1)
    sh[0, :] = 0
    sh[:, 0] = 0
    p.mask(x, y, sh * (1 - (art > 0)), P.SHADOW_ON_PAPER, 0.35)
    p.mask(x, y, art, "#8e8d88")
    hi = art.copy()
    hi[:, 1:] = 0
    hi2 = art.copy()
    hi2[1:, :] = 0
    p.mask(x, y, np.maximum(hi, hi2), "#c9c8c2")
    p.px(x + 2, y + 2, "#e4e3de")


def washi(p: Plate, x: int, y: int, w: int, h: int, col=P.BLUE[2], seed: int = 0,
          horizontal: bool = True, a: float = 0.78):
    """A strip of translucent washi tape with torn (zig-zag) ends and a faint
    printed stripe; what is under it shows through."""
    rng = np.random.RandomState(6100 + seed)
    m = np.full((h, w), a, dtype=np.float32)
    if horizontal:
        for r in range(h):
            k = int(rng.rand() < 0.5)
            if k:
                m[r, 0] = 0
            if rng.rand() < 0.5:
                m[r, -1] = 0
        stripe = (np.arange(w)[None, :] + np.arange(h)[:, None]) % 4 == 0
    else:
        for c in range(w):
            if rng.rand() < 0.5:
                m[0, c] = 0
            if rng.rand() < 0.5:
                m[-1, c] = 0
        stripe = (np.arange(w)[None, :] + np.arange(h)[:, None]) % 4 == 0
    # shadow first
    p.mask(x + 1, y + 1, (m > 0) * 0.16, P.SHADOW_ON_PAPER)
    p.mask(x, y, m, col)
    p.mask(x, y, m * stripe * 0.35, P.PAPER_HI)
    if horizontal:
        p.hline(x + 1, x + w - 2, y, P.PAPER_HI, 0.35)
        p.hline(x + 1, x + w - 2, y + h - 1, P.BLUE[1], 0.30)
    else:
        p.vline(x, y + 1, y + h - 2, P.PAPER_HI, 0.35)
        p.vline(x + w - 1, y + 1, y + h - 2, P.BLUE[1], 0.30)


def coffee_ring(p: Plate, cx: float, cy: float, r: float = 13.0, a: float = 0.16, seed: int = 0,
                clip=None):
    """The ghost of a cup: a thin, broken, slightly doubled ring in pale kraft."""
    rng = np.random.RandomState(6600 + seed)
    R = int(r) + 3
    ys, xs = np.mgrid[-R:R + 1, -R:R + 1].astype(np.float32)
    d = np.sqrt((xs * 1.0) ** 2 + (ys * 1.04) ** 2)
    ang = np.arctan2(ys, xs)
    ring = np.clip(1.0 - np.abs(d - r) / 0.9, 0, 1)
    inner = np.clip(1.0 - np.abs(d - (r - 1.6)) / 0.7, 0, 1) * 0.35
    broken = 0.55 + 0.45 * np.sin(ang * 2.0 + 0.8) * np.sin(ang * 3.0 + 2.0)
    broken = np.clip(broken + (rng.rand(*d.shape) - 0.5) * 0.5, 0, 1)
    m = np.clip((ring + inner) * broken, 0, 1) * a
    x0, y0 = int(round(cx)) - R, int(round(cy)) - R
    if clip is not None:
        X, Y, W_, H_ = clip
        gx = np.arange(x0, x0 + m.shape[1])[None, :]
        gy = np.arange(y0, y0 + m.shape[0])[:, None]
        m = m * ((gx >= X) & (gx < X + W_) & (gy >= Y) & (gy < Y + H_))
    p.mask(x0, y0, m, P.KRAFT_DARK)
