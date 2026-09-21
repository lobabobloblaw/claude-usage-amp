"""typeset -- setting the skin's own faces onto paper and cloth.

``coverage(text, face)`` sets a line and returns an ink-coverage array.  The
style functions then print it:

* :func:`letterpress` -- slate (or clay) ink bitten into paper: the ink, a
  hair of ink-spread, and the lit lower lip of the impression;
* :func:`foil` -- ivory foil stamped into cloth: pressed-in shadow above/left,
  foil with worn and bright spots, lit lip below/right;
* :func:`blind` -- an impression with no ink at all;
* :func:`rubber_stamp` -- unevenly inked, slightly starved in places.
"""

from __future__ import annotations

import numpy as np

from . import palette as P
from . import type_list, type_marquee, type_micro
from .plate import Plate

_SOFT = 0.55


def _rows_to_cov(rows, soft=_SOFT) -> np.ndarray:
    lut = {"#": 1.0, "+": soft, ":": 0.30, ".": 0.0}
    return np.array([[lut[k] for k in row] for row in rows], dtype=np.float32)


def glyph_cov(ch: str, face: str) -> np.ndarray:
    if face == "micro":
        g = type_micro.GLYPHS
        rows = g.get(ch) or g.get(ch.upper()) or g[" "]
        return _rows_to_cov(rows)
    if face == "marquee":
        g = type_marquee.GLYPHS
        rows = g.get(ch) or g.get(ch.upper()) or g[" "]
        a = _rows_to_cov(rows)
        return a[:, :4] if ch != "…" else a
    if face == "list":
        c = type_list.cell(ch)
        cols = np.nonzero((c >= 0.5).any(axis=0))[0]
        if cols.size == 0:
            return np.zeros((type_list.CELL_H, 3), dtype=np.float32)
        lo, hi = max(0, int(cols[0]) - 1), min(type_list.CELL_W - 1, int(cols[-1]) + 1)
        return c[:, lo:hi + 1]
    raise ValueError(face)


def coverage(text: str, face: str = "micro", spacing: int = 1, space: int | None = None) -> np.ndarray:
    """Set ``text``; returns (h, w) coverage.  For the list face the glyph
    images carry a 1-px soft margin each side which overlaps the spacing."""
    parts = []
    pen = 0
    h = {"micro": 5, "marquee": 6, "list": type_list.CELL_H}[face]
    if space is None:
        space = {"micro": 3, "marquee": 5, "list": 3}[face]
    places = []
    for ch in text:
        if ch == " ":
            pen += space
            continue
        g = glyph_cov(ch, face)
        if face == "list":
            places.append((pen - 1, g))
            pen += g.shape[1] - 2 + spacing
        else:
            places.append((pen, g))
            pen += g.shape[1] + spacing
    width = max(1, pen - spacing + (2 if face == "list" else 0))
    off = 1 if face == "list" else 0
    out = np.zeros((h, width + 2), dtype=np.float32)
    for x, g in places:
        xx = x + off
        seg = out[:, xx:xx + g.shape[1]]
        gg = g[:, :seg.shape[1]]
        out[:, xx:xx + gg.shape[1]] = 1 - (1 - seg) * (1 - gg)
    return out[:, :width + (1 if face == "list" else 0)]


def width(text: str, face: str = "micro", spacing: int = 1, space: int | None = None) -> int:
    return coverage(text, face, spacing, space).shape[1]


def _lip(cov: np.ndarray, dx: int, dy: int) -> np.ndarray:
    """Pixels that are paper but have ink at (-dx, -dy): where a lip falls."""
    ink = cov >= 0.5
    sh = np.zeros_like(ink)
    h, w = ink.shape
    ys, xs = slice(max(0, dy), h + min(0, dy)), slice(max(0, dx), w + min(0, dx))
    yd, xd = slice(max(0, -dy), h + min(0, -dy)), slice(max(0, -dx), w + min(0, -dx))
    sh[ys, xs] = ink[yd, xd]
    return (sh & ~ink).astype(np.float32)


def _pad(cov: np.ndarray, n: int = 1) -> np.ndarray:
    return np.pad(cov, n)


def letterpress(p: Plate, x: int, y: int, text: str, face: str = "micro",
                ink=P.INK_BODY, a: float = 1.0, spacing: int = 1, space=None,
                lip: float = 0.85, lip_col=P.PAPER_HI, cov: np.ndarray | None = None) -> int:
    c = _pad(coverage(text, face, spacing, space) if cov is None else cov)
    if lip > 0:
        p.mask(x - 1, y - 1, _lip(c, 0, 1), lip_col, lip)
        p.mask(x - 1, y - 1, _lip(c, 1, 0) * (1 - _lip(c, 0, 1)), lip_col, lip * 0.45)
    p.mask(x - 1, y - 1, c, ink, a)
    return c.shape[1] - 2


def foil(p: Plate, x: int, y: int, text: str, face: str = "list", spacing: int = 1,
         space=None, tone=P.PAPER_FLAT, dull: float = 0.0, seed: int = 0,
         cov: np.ndarray | None = None) -> int:
    c = _pad(coverage(text, face, spacing, space) if cov is None else cov)
    rng = np.random.RandomState(9000 + seed)
    # pressed-in shadow above and to the left, lit lip below and to the right
    p.mask(x - 1, y - 1, _lip(c, 0, -1), P.SHADOW_ON_CLOTH, 0.50)
    p.mask(x - 1, y - 1, _lip(c, -1, 0) * (1 - _lip(c, 0, -1)), P.SHADOW_ON_CLOTH, 0.32)
    p.mask(x - 1, y - 1, _lip(c, 0, 1), P.CLAY_LIGHT, 0.35)
    # foil: mostly ivory, some bright flecks, some worn-through
    n = rng.rand(*c.shape).astype(np.float32)
    base = P.mix(tone, P.KRAFT[3], dull * 0.8)
    p.mask(x - 1, y - 1, c * (1.0 - 0.30 * dull), base)
    p.mask(x - 1, y - 1, c * (n > 0.80), P.PAPER_HI, 0.9 * (1 - dull))
    p.mask(x - 1, y - 1, c * (n < 0.14), P.CLAY_LIGHT, 0.45)
    return c.shape[1] - 2


def blind(p: Plate, x: int, y: int, text: str, face: str = "micro", spacing: int = 1,
          space=None, on: str = "cloth", strength: float = 1.0,
          cov: np.ndarray | None = None) -> int:
    c = _pad(coverage(text, face, spacing, space) if cov is None else cov)
    if on == "cloth":
        p.mask(x - 1, y - 1, c, P.SHADOW_ON_CLOTH, 0.34 * strength)
        p.mask(x - 1, y - 1, _lip(c, 0, 1), P.CLAY_LIGHT, 0.40 * strength)
        p.mask(x - 1, y - 1, _lip(c, 1, 0) * (1 - _lip(c, 0, 1)), P.CLAY_LIGHT, 0.22 * strength)
    else:
        p.mask(x - 1, y - 1, c, P.PAPER_DEEP, 0.50 * strength)
        p.mask(x - 1, y - 1, _lip(c, 0, 1), P.PAPER_HI, 0.95 * strength)
        p.mask(x - 1, y - 1, _lip(c, 1, 0) * (1 - _lip(c, 0, 1)), P.PAPER_HI, 0.5 * strength)
    return c.shape[1] - 2


def rubber_stamp(p: Plate, x: int, y: int, cov: np.ndarray, ink=P.INK_BODY,
                 seed: int = 0, starve: float = 0.35) -> None:
    """Print a coverage mask the way a rubber stamp does: unevenly."""
    rng = np.random.RandomState(7000 + seed)
    h, w = cov.shape
    # low-frequency pressure variation plus pinholes
    gx = np.linspace(0, 1, w, dtype=np.float32)[None, :]
    gy = np.linspace(0, 1, h, dtype=np.float32)[:, None]
    tilt = 0.80 + 0.20 * np.cos((gx * 1.3 + gy * 0.9 + rng.rand()) * 3.1)
    holes = (rng.rand(h, w) > starve * 0.33).astype(np.float32) * 0.45 + 0.55
    p.mask(x, y, cov * np.clip(tilt * holes, 0, 1), ink)
