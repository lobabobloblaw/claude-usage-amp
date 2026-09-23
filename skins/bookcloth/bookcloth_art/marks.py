"""marks -- the skin's maker's mark: a letterpress monogram and its lozenge.

Bookcloth signs itself the way a private press signs its books.  The primary
mark, at the foot of the cover, is a monogram: a bold serif capital ``T`` (for
Tokenamp) printed in clay ink on a disc of ivory stock let into a round
opening in the cloth, inside a blind-struck ring.  The T is cut for the pixel
grid rather than traced from any typeface: a three-pixel stem, a two-row bar
whose ends drop into bracketed beak serifs, and a bracketed slab foot.  A
hand-fed press squeezes the ink to the edges of an impression, so its outline
prints a shade heavier and a trace of ink fills its inner corners.

Everywhere the mark has to be small, nothing figurative survives, so the
press's second ornament stands in: a solid clay lozenge.  It is set at the cap
height of the small capitals it keeps company with -- beside FIG.1 TOKEN FLOW
and the CLAUDE USAGE running head, on the equaliser page, rubber-stamped ahead
of LIVE, foil-stamped either side of the title on the easter-egg spine, in a
miniature roundel on the shade strip, and squeezed into the two visible
columns of the work indicator.  The Sessions colophon has the room for a
small T, so it carries the monogram again.

Masks use ``#`` full, ``+`` soft, ``:`` a trace, ``.`` nothing.
"""

from __future__ import annotations

import numpy as np

from . import materials as M
from . import palette as P
from . import typeset as T
from .plate import Plate


def _m(art: str) -> np.ndarray:
    rows = [r.strip() for r in art.strip("\n").split("\n")]
    w = max(len(r) for r in rows)
    lut = {"#": 1.0, "+": 0.55, ":": 0.28}
    return np.array([[lut.get(k, 0.0) for k in r.ljust(w, ".")] for r in rows],
                    dtype=np.float32)


# ===========================================================================
# the monogram
# ===========================================================================
#: 11 x 13 -- the cover roundel
T_HERO = _m("""
###########
###########
##::###::##
#+..###..+#
+...###...+
....###....
....###....
....###....
....###....
....###....
....###....
..:+###+:..
..#######..
""")

#: 9 x 10 -- the Sessions colophon
T_COLOPHON = _m("""
#########
#########
#+:###:+#
+..###..+
...###...
...###...
...###...
...###...
.:+###+:.
.#######.
""")

# ===========================================================================
# the lozenge
# ===========================================================================
#: 5 x 5 -- every other mark, at the cap height of the small capitals
LOZENGE_5 = _m("""
..#..
.###.
#####
.###.
..#..
""")

#: the work indicator shows only two columns (the play-state icon covers its
#: third), so its lozenge is two wide and gets its points from soft ink:
#: solid at the waist, tapering to a trace above and below
LOZENGE_WORK = _m("""
::
++
##
++
::
""")

MASKS = {
    "hero": T_HERO,
    "colophon": T_COLOPHON,
    "tiny": LOZENGE_5,
    "work": LOZENGE_WORK,
}


def mask(size: str) -> np.ndarray:
    return MASKS[size]


def centred(m: np.ndarray, cx: int, cy: int) -> tuple[int, int]:
    return cx - m.shape[1] // 2, cy - m.shape[0] // 2


def _field(a: np.ndarray, x0: int, y0: int, w: int, h: int) -> np.ndarray:
    """Slice a window-sized field at a rect that may hang off the window;
    the part outside is filled from the nearest edge."""
    H, W = a.shape[:2]
    ys = np.clip(np.arange(y0, y0 + h), 0, H - 1)
    xs = np.clip(np.arange(x0, x0 + w), 0, W - 1)
    return a[ys[:, None], xs[None, :]]


# ===========================================================================
# the ways the mark is worn
# ===========================================================================
#: the sizes that carry the monogram rather than the lozenge
MONOGRAMS = ("hero", "colophon")
#: how much heavier the monogram's outline prints (see :func:`_rim`)
SQUASH = 0.28


def _rim(m: np.ndarray) -> np.ndarray:
    """The solid pixels on the outline of ``m``: where the platen squeezes
    the ink to the edge of the impression and it prints a shade heavier."""
    solid = np.pad(m >= 0.5, 1)
    core = (solid[1:-1, 1:-1] & solid[:-2, 1:-1] & solid[2:, 1:-1]
            & solid[1:-1, :-2] & solid[1:-1, 2:])
    return (solid[1:-1, 1:-1] & ~core).astype(np.float32)


def print_on_paper(p: Plate, x: int, y: int, m: np.ndarray, a: float = 1.0,
                   ink=P.CLAY_DEEP, lip: float = 0.85, squash: float = 0.0) -> None:
    """Letterpress ``m`` in clay with its top-left at (x, y); ``squash``
    darkens the outline of the solids, as a hand-fed press does."""
    T.letterpress(p, x, y, "", cov=m * a, ink=ink, lip=lip * a)
    if squash > 0:
        p.mask(x, y, _rim(m), P.CLAY_DARK, squash * a)


def mark(p: Plate, cx: int, cy: int, size: str = "tiny", a: float = 1.0) -> None:
    """A secondary mark printed on paper, centred on (cx, cy)."""
    m = mask(size)
    x, y = centred(m, cx, cy)
    print_on_paper(p, x, y, m, a=a, squash=SQUASH if size in MONOGRAMS else 0.0)


def stamp_mark(p: Plate, cx: int, cy: int, seed: int = 0) -> None:
    """The lozenge cut into the LIVE rubber stamp, inked with it."""
    m = mask("tiny")
    x, y = centred(m, cx, cy)
    T.rubber_stamp(p, x, y, m, ink=P.CLAY_DEEP, seed=seed, starve=0.15)


def foil_mark(p: Plate, cx: int, cy: int, size: str = "tiny", dull: float = 0.0) -> None:
    """The lozenge foil-stamped into cloth (the easter-egg title bar)."""
    m = mask(size)
    x, y = centred(m, cx, cy)
    T.foil(p, x, y, "", cov=m, dull=dull, seed=41)


def work(p: Plate, x: int, y: int, h: int) -> None:
    """The work indicator: the lozenge in the two visible columns of its
    slot at (x, y), vertically centred in its height ``h``."""
    m = mask("work")
    print_on_paper(p, x, y + (h - m.shape[0]) // 2, m, lip=0.8)


# ===========================================================================
# the monogram roundel at the foot of the cover
# ===========================================================================
#: centre of the primary mark: the clear cloth right of ALERT and under the
#: seek slot, over the classic about-logo hot spot
HERO_C = (256, 98)


def _disc(cx: float, cy: float, r: float, x0: int, y0: int, w: int, h: int) -> np.ndarray:
    """Anti-aliased disc coverage over a window rect (pixel centres)."""
    ss = 4
    ys = (np.arange(h * ss, dtype=np.float32) + 0.5) / ss + y0 - 0.5
    xs = (np.arange(w * ss, dtype=np.float32) + 0.5) / ss + x0 - 0.5
    d = np.sqrt((xs[None, :] - cx) ** 2 + (ys[:, None] - cy) ** 2)
    return (d <= r).astype(np.float32).reshape(h, ss, w, ss).mean(axis=(1, 3))


def _roundel(p: Plate, cx: int, cy: int, R: float, window: str = "main",
             ring: bool = True) -> None:
    """A disc of ivory stock let into a round opening in the cloth-covered
    board, lit from the top left like the label panels."""
    n = int(np.ceil(R)) * 2 + 7
    x0, y0 = cx - n // 2, cy - n // 2
    disc = _disc(cx, cy, R, x0, y0, n, n)
    out1 = _disc(cx, cy, R + 1.0, x0, y0, n, n)
    out2 = _disc(cx, cy, R + 2.0, x0, y0, n, n)
    wall = np.clip(out1 - disc, 0, 1)
    lip = np.clip(out2 - out1, 0, 1)
    yy, xx = np.mgrid[y0:y0 + n, x0:x0 + n].astype(np.float32)
    # +1 where an edge faces down-right (into the light), -1 up-left
    face = np.clip(((xx - cx) + (yy - cy)) / (R * 0.8), -1, 1)
    # the cloth turning over the edge: a lit lip up-left, a crease down-right
    p.mask(x0, y0, lip * np.clip(-face, 0, 1), P.CLAY_LIGHT, 0.32)
    p.mask(x0, y0, lip * np.clip(face, 0, 1), P.SHADOW_ON_CLOTH, 0.24)
    # the wall of the opening: in shadow up-left, pale board core down-right
    p.mask(x0, y0, wall * np.clip(0.6 - face, 0, 1), P.CLAY_SHADOW, 1.0)
    p.mask(x0, y0, wall * np.clip(face - 0.1, 0, 1), P.BOARD_CORE, 0.85)
    # the paper
    d = _field(M.paper_delta(window), x0, y0, n, n)
    p.paste(x0, y0, M.paper_rgb(d, base=P.PAPER_FLAT), alpha=disc)
    # the wall's cast shadow on the paper, inside the up-left edge
    s1 = np.clip(disc - _disc(cx + 1, cy + 1, R, x0, y0, n, n), 0, 1)
    s2 = np.clip(_disc(cx + 1, cy + 1, R, x0, y0, n, n)
                 - _disc(cx + 2, cy + 2, R, x0, y0, n, n), 0, 1) * disc
    p.mask(x0, y0, s1, P.SHADOW_ON_PAPER, 0.36)
    p.mask(x0, y0, s2, P.SHADOW_ON_PAPER, 0.12)
    if ring:
        # a blind-struck border: pressed without ink, lit on its lower lip
        rr = np.clip(_disc(cx, cy, R - 1.9, x0, y0, n, n)
                     - _disc(cx, cy, R - 2.9, x0, y0, n, n), 0, 1)
        lit = np.clip(_disc(cx - 0.9, cy - 0.9, R - 1.9, x0, y0, n, n)
                      - _disc(cx, cy, R - 1.9, x0, y0, n, n), 0, 1)
        p.mask(x0, y0, rr, P.PAPER_DEEP, 0.50)
        p.mask(x0, y0, np.clip(lit - rr, 0, 1) * disc, P.PAPER_HI, 0.9)


def hero(p: Plate) -> None:
    """The monogram roundel: the T printed in clay on the ivory disc."""
    cx, cy = HERO_C
    _roundel(p, cx, cy, 12.6)
    m = mask("hero")
    x, y = centred(m, cx, cy)
    print_on_paper(p, x, y, m, lip=0.9, squash=SQUASH)


# ===========================================================================
# the shade strip: the device in miniature
# ===========================================================================
#: centre of the shade-strip device, after the foil T and before the stitches
SHADE_C = (38, 7)


def shade_mark(p: Plate) -> None:
    """A miniature roundel with the lozenge printed in it.  The same in the
    active and inactive strips: the stock does not fade.  It keeps off the
    strip's top and bottom rows, which the two shade backgrounds share
    inside titlebar.bmp."""
    cx, cy = SHADE_C
    p = Plate(p.c.sub(0, 1, p.w, p.h - 2), origin=(p.ox, p.oy + 1))
    _roundel(p, cx, cy, 5.0, window="shade", ring=False)
    m = mask("tiny")
    x, y = centred(m, cx, cy)
    print_on_paper(p, x, y, m, lip=0.8)
