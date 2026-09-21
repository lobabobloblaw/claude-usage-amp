"""plate -- draw on a skinkit Canvas in *window* coordinates, clipped.

Every Bookcloth painter wraps its canvas in a :class:`Plate` and then draws at
the coordinates the thing has in the window.  A widget canvas is just a small
porthole onto the same window: the identical drawing code, run through a
23x18 porthole at (16, 88), reproduces exactly the pixels the full-window pass
would have made there.  That is what keeps every seam invisible.

Colours are ``"#rrggbb"`` strings or float/int RGB triples.  ``a`` is opacity.
"""

from __future__ import annotations

import numpy as np

from .palette import rgb as _hex


def _col(c) -> np.ndarray:
    if isinstance(c, str):
        return _hex(c)
    return np.asarray(c, dtype=np.float32)[:3]


class Plate:
    def __init__(self, canvas, origin=None):
        self.c = canvas
        self.a = canvas.a
        ox, oy = canvas.origin if origin is None else origin
        self.ox, self.oy = int(ox), int(oy)
        self.h, self.w = int(self.a.shape[0]), int(self.a.shape[1])

    # -- clipping ------------------------------------------------------
    def _clip(self, x, y, w, h):
        """Window rect -> (lx0, ly0, lx1, ly1, sx0, sy0) or None."""
        lx0, ly0 = int(x) - self.ox, int(y) - self.oy
        lx1, ly1 = lx0 + int(w), ly0 + int(h)
        cx0, cy0 = max(0, lx0), max(0, ly0)
        cx1, cy1 = min(self.w, lx1), min(self.h, ly1)
        if cx1 <= cx0 or cy1 <= cy0:
            return None
        return cx0, cy0, cx1, cy1, cx0 - lx0, cy0 - ly0

    def visible(self, x, y, w=1, h=1) -> bool:
        return self._clip(x, y, w, h) is not None

    # -- primitives ----------------------------------------------------
    def px(self, x, y, col, a: float = 1.0):
        lx, ly = int(x) - self.ox, int(y) - self.oy
        if 0 <= lx < self.w and 0 <= ly < self.h and a > 0:
            c = _col(col)
            if a >= 1.0:
                self.a[ly, lx, :3] = np.clip(np.rint(c), 0, 255)
            else:
                d = self.a[ly, lx, :3].astype(np.float32)
                self.a[ly, lx, :3] = np.clip(np.rint(d + (c - d) * a), 0, 255)
            self.a[ly, lx, 3] = 255
        return self

    def box(self, x, y, w, h, col, a: float = 1.0):
        k = self._clip(x, y, w, h)
        if k is None or a <= 0:
            return self
        x0, y0, x1, y1, _, _ = k
        c = _col(col)
        if a >= 1.0:
            self.a[y0:y1, x0:x1, :3] = np.clip(np.rint(c), 0, 255)
        else:
            d = self.a[y0:y1, x0:x1, :3].astype(np.float32)
            self.a[y0:y1, x0:x1, :3] = np.clip(np.rint(d + (c - d) * a), 0, 255)
        self.a[y0:y1, x0:x1, 3] = 255
        return self

    def hline(self, x0, x1, y, col, a: float = 1.0):
        if x1 < x0:
            x0, x1 = x1, x0
        return self.box(x0, y, x1 - x0 + 1, 1, col, a)

    def vline(self, x, y0, y1, col, a: float = 1.0):
        if y1 < y0:
            y0, y1 = y1, y0
        return self.box(x, y0, 1, y1 - y0 + 1, col, a)

    def rect(self, x, y, w, h, col, a: float = 1.0):
        self.hline(x, x + w - 1, y, col, a)
        self.hline(x, x + w - 1, y + h - 1, col, a)
        self.vline(x, y + 1, y + h - 2, col, a)
        self.vline(x + w - 1, y + 1, y + h - 2, col, a)
        return self

    def line(self, x0, y0, x1, y1, col, a: float = 1.0):
        x0, y0, x1, y1 = int(x0), int(y0), int(x1), int(y1)
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
        err = dx + dy
        while True:
            self.px(x0, y0, col, a)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy
        return self

    # -- arrays --------------------------------------------------------
    def paste(self, x, y, rgb_arr, alpha=None, a: float = 1.0):
        """Composite an (h, w, 3) float/uint8 array; ``alpha`` is an optional
        (h, w) coverage array in 0..1."""
        rgb_arr = np.asarray(rgb_arr)
        h, w = rgb_arr.shape[0], rgb_arr.shape[1]
        k = self._clip(x, y, w, h)
        if k is None:
            return self
        x0, y0, x1, y1, sx, sy = k
        src = rgb_arr[sy:sy + (y1 - y0), sx:sx + (x1 - x0)].astype(np.float32)
        if alpha is None and a >= 1.0:
            self.a[y0:y1, x0:x1, :3] = np.clip(np.rint(src), 0, 255)
        else:
            if alpha is None:
                al = np.full((y1 - y0, x1 - x0, 1), float(a), dtype=np.float32)
            else:
                al = (np.asarray(alpha, dtype=np.float32)[sy:sy + (y1 - y0),
                                                          sx:sx + (x1 - x0)] * a)[..., None]
            d = self.a[y0:y1, x0:x1, :3].astype(np.float32)
            self.a[y0:y1, x0:x1, :3] = np.clip(np.rint(d + (src - d) * al), 0, 255)
        self.a[y0:y1, x0:x1, 3] = 255
        return self

    def mask(self, x, y, m, col, a: float = 1.0):
        """Composite a flat colour through an (h, w) coverage mask."""
        m = np.asarray(m, dtype=np.float32)
        k = self._clip(x, y, m.shape[1], m.shape[0])
        if k is None:
            return self
        x0, y0, x1, y1, sx, sy = k
        al = (m[sy:sy + (y1 - y0), sx:sx + (x1 - x0)] * a)[..., None]
        c = _col(col)
        d = self.a[y0:y1, x0:x1, :3].astype(np.float32)
        self.a[y0:y1, x0:x1, :3] = np.clip(np.rint(d + (c - d) * al), 0, 255)
        self.a[y0:y1, x0:x1, 3] = 255
        return self

    def mul(self, x, y, w, h, factor):
        """Multiply RGB by a scalar, an RGB triple or an (h, w) array."""
        k = self._clip(x, y, w, h)
        if k is None:
            return self
        x0, y0, x1, y1, sx, sy = k
        f = np.asarray(factor, dtype=np.float32)
        if f.ndim == 2:
            f = f[sy:sy + (y1 - y0), sx:sx + (x1 - x0)][..., None]
        d = self.a[y0:y1, x0:x1, :3].astype(np.float32)
        self.a[y0:y1, x0:x1, :3] = np.clip(np.rint(d * f), 0, 255)
        return self

    def get(self, x, y):
        lx, ly = int(x) - self.ox, int(y) - self.oy
        if 0 <= lx < self.w and 0 <= ly < self.h:
            return self.a[ly, lx, :3].astype(np.float32)
        return None

    def opaque(self):
        self.a[:, :, 3] = 255
        return self
