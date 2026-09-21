"""Pen -- draw in WINDOW coordinates on any skinkit Canvas.

Every part of the board is described once, in window coordinates.  A Pen maps
those onto whatever canvas a painter was handed (the full background, or a
widget cut out of it) and clips silently, so the same ``draw_tact_switch`` call
paints the baked background and the sprite.
"""

from __future__ import annotations

import numpy as np

from . import palette as P


class Pen:
    __slots__ = ("c", "ox", "oy", "a")

    def __init__(self, c, origin=None):
        self.c = c
        self.ox, self.oy = c.origin if origin is None else origin
        self.a = c.a

    # -- basic marks ----------------------------------------------------
    def px(self, x, y, col):
        self.c.px(x - self.ox, y - self.oy, col)

    def box(self, x, y, w, h, col):
        self.c.box(x - self.ox, y - self.oy, w, h, col)

    def hline(self, x0, x1, y, col):
        self.c.hline(x0 - self.ox, x1 - self.ox, y - self.oy, col)

    def vline(self, x, y0, y1, col):
        self.c.vline(x - self.ox, y0 - self.oy, y1 - self.oy, col)

    def rect(self, x, y, w, h, col):
        self.c.rect(x - self.ox, y - self.oy, w, h, col)

    def line(self, x0, y0, x1, y1, col):
        self.c.line(x0 - self.ox, y0 - self.oy, x1 - self.ox, y1 - self.oy, col)

    def get(self, x, y):
        return self.c.get(x - self.ox, y - self.oy)

    def rows(self, x, y, rows, cmap):
        """Stamp an ASCII sprite: ``rows`` of chars, ``cmap`` char -> colour."""
        for j, row in enumerate(rows):
            for i, ch in enumerate(row):
                col = cmap.get(ch)
                if col is not None:
                    self.c.px(x + i - self.ox, y + j - self.oy, col)

    # -- region arithmetic ---------------------------------------------
    def _clip(self, x, y, w, h):
        x0, y0 = max(0, x - self.ox), max(0, y - self.oy)
        x1 = min(self.c.w, x - self.ox + w)
        y1 = min(self.c.h, y - self.oy + h)
        return (x0, y0, x1, y1) if (x1 > x0 and y1 > y0) else None

    def shade(self, x, y, w, h, f):
        """Multiply a region's RGB by ``f`` (a contact shadow, a dimmed state)."""
        r = self._clip(x, y, w, h)
        if r:
            x0, y0, x1, y1 = r
            v = self.a[y0:y1, x0:x1, :3].astype(np.float32) * f
            self.a[y0:y1, x0:x1, :3] = np.clip(v, 0, 255).astype(np.uint8)

    def tint(self, x, y, w, h, col, t):
        r = self._clip(x, y, w, h)
        if r:
            x0, y0, x1, y1 = r
            v = self.a[y0:y1, x0:x1, :3].astype(np.float32)
            v += (np.array(col[:3], np.float32) - v) * t
            self.a[y0:y1, x0:x1, :3] = np.clip(v, 0, 255).astype(np.uint8)

    def cast(self, x, y, w, h, depth=2, strength=0.45):
        """Contact shadow of a raised w*h body: falls down-right (light is
        top-left), darkest next to the body."""
        for d in range(1, depth + 1):
            f = 1.0 - strength * (1.0 - (d - 1) / depth)
            self.shade(x + d, y + h + d - 1, w, 1, f)          # under
            self.shade(x + w + d - 1, y + d, 1, h - 1, f)      # right

    def light(self, cx, cy, col, radius=2.5, strength=0.8, aspect=1.0):
        """Screen-blend a soft pool of light centred on (cx, cy)."""
        r = int(np.ceil(radius)) + 1
        k = self._clip(int(cx) - r, int(cy) - r, 2 * r + 1, 2 * r + 1)
        if not k:
            return
        x0, y0, x1, y1 = k
        ys, xs = np.mgrid[y0:y1, x0:x1].astype(np.float32)
        d = np.hypot((xs + self.ox - cx), (ys + self.oy - cy) * aspect)
        wgt = np.clip(1.0 - d / (radius + 0.5), 0, 1) ** 1.7 * strength
        v = self.a[y0:y1, x0:x1, :3].astype(np.float32)
        colv = np.array(col[:3], np.float32) / 255.0
        v = 255.0 - (255.0 - v) * (1.0 - wgt[:, :, None] * colv)
        self.a[y0:y1, x0:x1, :3] = np.clip(v, 0, 255).astype(np.uint8)

    def text(self, x, y, s, font, col, spacing=None):
        from skinkit import fonts
        return fonts.draw_text(self.c, x - self.ox, y - self.oy, s, font, col,
                               spacing=spacing) + self.ox


# ---------------------------------------------------------------------------
# textures (all sampled in window space, so cuts are seamless)
# ---------------------------------------------------------------------------

def _grid(c):
    xs = np.arange(c.w, dtype=np.float32) + c.ox
    ys = np.arange(c.h, dtype=np.float32) + c.oy
    return np.meshgrid(xs, ys)


def _lut(r, n=256):
    return np.array([P.sample(r, i / (n - 1))[:3] for i in range(n)], np.uint8)


_MASK_LUT = _lut(P.MASK)
_POUR_LUT = _lut(P.POUR)


def mask_value(c, seed=0, mottle=1.0, invariant=None, weave=True):
    """The solder-mask tone field t(x, y) in 0..1 for every pixel of ``c``.

    * a slow top-left -> bottom-right falloff (one light source),
    * fbm mottling (mask thickness varying over the laminate),
    * a faint 4 px fibreglass weave, periodic so tiles can carry it.

    ``invariant`` = "x" / "y" freezes the field along that axis (playlist
    tiles); ``mottle`` may be a scalar or an (h, w) array (0 = flat).
    """
    from skinkit import fx
    X, Y = _grid(c)
    t = np.full((c.h, c.w), 0.50, np.float32)
    if invariant is None:
        t -= 0.05 * ((X / 275.0) + (Y / 116.0) - 1.0)
        n = fx.fbm(c, scale=17.0, octaves=3, seed=seed) - 0.5
        n2 = fx.value_noise(c, scale=2.6, seed=seed + 5) - 0.5
        t += (n * 0.34 + n2 * 0.07) * mottle
    elif invariant == "y":     # varies with x only
        n = fx.value_noise(c, seed=seed + 9, sx=3.0, sy=1e6) - 0.5
        t += n * 0.10
    else:                      # varies with y only
        n = fx.value_noise(c, seed=seed + 9, sx=1e6, sy=3.0) - 0.5
        t += n * 0.10
    if weave:
        xi, yi = X.astype(np.int64), Y.astype(np.int64)
        if invariant == "y":
            w = ((xi % 4) < 2).astype(np.float32) - 0.5
        elif invariant == "x":
            w = ((yi % 4) < 2).astype(np.float32) - 0.5
        else:
            w = (((xi % 4) < 2) ^ ((yi % 4) < 2)).astype(np.float32) - 0.5
        t += w * 0.030
    return t


def paint_mask(c, t, lut=None):
    lut = _MASK_LUT if lut is None else lut
    idx = np.clip(np.rint(t * 255), 0, 255).astype(np.int64)
    c.a[:, :, :3] = lut[idx]
    c.a[:, :, 3] = 255


def pour(c, t, region, hatch=True):
    """Repaint ``region`` (bool array) as mask-over-copper: lighter, and
    optionally cross-hatched like a hatched ground pour."""
    X, Y = _grid(c)
    xi, yi = X.astype(np.int64), Y.astype(np.int64)
    tt = t * 0.9 + 0.12
    if hatch:
        lattice = (((xi + yi) % 4) == 0) | (((xi - yi) % 4) == 0)
        tt = np.where(lattice, tt + 0.10, tt - 0.16)
    idx = np.clip(np.rint(tt * 255), 0, 255).astype(np.int64)
    col = _POUR_LUT[idx]
    c.a[:, :, :3] = np.where(region[:, :, None], col, c.a[:, :, :3])
    # the pour's edge: light catches the top/left lip of the copper step
    up = np.roll(region, 1, axis=0); up[0, :] = region[0, :]
    lf = np.roll(region, 1, axis=1); lf[:, 0] = region[:, 0]
    lip = region & (~up | ~lf)
    c.a[:, :, :3] = np.where(lip[:, :, None],
                             np.clip(c.a[:, :, :3].astype(np.int16) + 14, 0, 255).astype(np.uint8),
                             c.a[:, :, :3])


def metal(c, x, y, w, h, r=None, seed=3, direction="h", lo=0.42, hi=0.80):
    """Brushed tin plate in window coords (local rect on canvas ``c``)."""
    from skinkit import fx
    r = P.TIN if r is None else r
    v = c.sub(x, y, w, h)
    if direction == "h":
        n = fx.value_noise(v, seed=seed, sx=26.0, sy=1.0)
        g = np.linspace(hi, lo, v.h, dtype=np.float32)[:, None]
    else:
        n = fx.value_noise(v, seed=seed, sx=1.0, sy=26.0)
        g = np.linspace(hi, lo, v.w, dtype=np.float32)[None, :]
    t = g + (n - 0.5) * 0.16
    idx = np.clip(np.rint(t * 255), 0, 255).astype(np.int64)
    v.a[:, :, :3] = _lut(r)[idx]
    v.a[:, :, 3] = 255
