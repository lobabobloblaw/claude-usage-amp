"""Canvas -- an exact-pixel RGBA drawing surface over a numpy uint8 array.

Two things make this different from "just use PIL":

* **No antialiasing, ever.**  Every primitive writes whole pixels.  A skin is
  read at 1x on a 275-pixel-wide window; a single soft edge looks like dirt.
* **Every canvas knows where it is.**  ``canvas.origin`` is the *window*
  coordinate of the canvas's own pixel (0, 0), and ``canvas.window`` says which
  window it belongs to.  Texture generators in :mod:`skinkit.fx` sample noise in
  window space, so a brushed-metal grain runs straight across the seam between
  ``main.bmp`` and the transport button that is cut out of it.

Coordinates are local to the canvas.  ``c.wx(x)`` / ``c.wy(y)`` convert to
window space; ``c.lx(wx)`` / ``c.ly(wy)`` convert back.
"""

from __future__ import annotations

from typing import Iterable, Sequence

import numpy as np

__all__ = [
    "Colour", "parse_colour", "rgb", "rgba_tuple", "mix", "lighten", "darken",
    "with_alpha", "hsv_shift", "Canvas",
]

Colour = "tuple[int, int, int] | tuple[int, int, int, int] | str"


# ---------------------------------------------------------------------------
# colour handling
# ---------------------------------------------------------------------------

def parse_colour(c: Colour) -> tuple[int, int, int, int]:
    """Accept ``(r,g,b)``, ``(r,g,b,a)``, ``"#rrggbb"``, ``"#rrggbbaa"``,
    ``"#rgb"`` or ``"#rgba"`` and return an ``(r, g, b, a)`` int tuple."""
    if isinstance(c, str):
        s = c.strip()
        if s.startswith("#"):
            s = s[1:]
        if len(s) in (3, 4):
            s = "".join(ch * 2 for ch in s)
        if len(s) == 6:
            s += "ff"
        if len(s) != 8:
            raise ValueError(f"skinkit: bad colour string {c!r}")
        try:
            v = int(s, 16)
        except ValueError:
            raise ValueError(f"skinkit: bad colour string {c!r}") from None
        return ((v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255)
    if isinstance(c, (tuple, list, np.ndarray)):
        vals = [int(round(float(x))) for x in c]
        if len(vals) == 3:
            vals.append(255)
        if len(vals) != 4:
            raise ValueError(f"skinkit: colour needs 3 or 4 components, got {c!r}")
        return tuple(max(0, min(255, v)) for v in vals)  # type: ignore[return-value]
    raise TypeError(f"skinkit: cannot read colour {c!r}")


def rgb(c: Colour) -> tuple[int, int, int]:
    """Drop the alpha channel."""
    r, g, b, _ = parse_colour(c)
    return (r, g, b)


def rgba_tuple(c: Colour) -> tuple[int, int, int, int]:
    return parse_colour(c)


def mix(a: Colour, b: Colour, t: float) -> tuple[int, int, int, int]:
    """Linear blend; ``t=0`` -> ``a``, ``t=1`` -> ``b``."""
    ca, cb = parse_colour(a), parse_colour(b)
    t = max(0.0, min(1.0, float(t)))
    return tuple(int(round(ca[i] + (cb[i] - ca[i]) * t)) for i in range(4))  # type: ignore[return-value]


def lighten(c: Colour, amount: float) -> tuple[int, int, int, int]:
    """Move ``amount`` (0..1) of the way toward white, alpha preserved."""
    r, g, b, a = parse_colour(c)
    t = max(0.0, min(1.0, float(amount)))
    return (int(round(r + (255 - r) * t)), int(round(g + (255 - g) * t)),
            int(round(b + (255 - b) * t)), a)


def darken(c: Colour, amount: float) -> tuple[int, int, int, int]:
    """Move ``amount`` (0..1) of the way toward black, alpha preserved."""
    r, g, b, a = parse_colour(c)
    t = max(0.0, min(1.0, float(amount)))
    return (int(round(r * (1 - t))), int(round(g * (1 - t))), int(round(b * (1 - t))), a)


def with_alpha(c: Colour, a: int) -> tuple[int, int, int, int]:
    r, g, b, _ = parse_colour(c)
    return (r, g, b, max(0, min(255, int(a))))


def hsv_shift(c: Colour, dh: float = 0.0, ds: float = 1.0, dv: float = 1.0):
    """Rotate hue by ``dh`` (0..1), scale saturation by ``ds`` and value by ``dv``."""
    import colorsys
    r, g, b, a = parse_colour(c)
    h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    h = (h + dh) % 1.0
    s = max(0.0, min(1.0, s * ds))
    v = max(0.0, min(1.0, v * dv))
    nr, ng, nb = colorsys.hsv_to_rgb(h, s, v)
    return (int(round(nr * 255)), int(round(ng * 255)), int(round(nb * 255)), a)


# ---------------------------------------------------------------------------
# Canvas
# ---------------------------------------------------------------------------

class Canvas:
    """An RGBA pixel buffer that knows its position inside a skin window.

    :param w, h: size in skin pixels.
    :param origin: window coordinate of this canvas's pixel (0, 0).
    :param window: ``"main"``, ``"eq"``, ``"playlist"``, ``"shade"``, or
        ``None`` for free-floating sprites (digits, glyphs, thumbs).
    :param fill: initial colour; default fully transparent black.
    :param array: wrap an existing ``(h, w, 4)`` uint8 array *by reference*.
    """

    __slots__ = ("a", "origin", "window", "_parent")

    # -- construction --------------------------------------------------
    def __init__(self, w: int = 0, h: int = 0, origin: tuple[int, int] = (0, 0),
                 window: str | None = None, fill: Colour | None = None,
                 array: np.ndarray | None = None):
        if array is not None:
            if array.dtype != np.uint8 or array.ndim != 3 or array.shape[2] != 4:
                raise ValueError("skinkit.Canvas: array must be uint8 (h, w, 4)")
            self.a = array
        else:
            if w <= 0 or h <= 0:
                raise ValueError(f"skinkit.Canvas: bad size {w}x{h}")
            self.a = np.zeros((h, w, 4), dtype=np.uint8)
            if fill is not None:
                self.a[:, :] = parse_colour(fill)
        self.origin = (int(origin[0]), int(origin[1]))
        self.window = window
        self._parent: "Canvas | None" = None

    @classmethod
    def from_rect(cls, rect, window: str | None = None, fill: Colour | None = None) -> "Canvas":
        """A canvas sized and positioned like a :class:`skinkit.spec.Rect`."""
        return cls(rect.w, rect.h, origin=(rect.x, rect.y), window=window, fill=fill)

    # -- geometry ------------------------------------------------------
    @property
    def w(self) -> int:
        return int(self.a.shape[1])

    @property
    def h(self) -> int:
        return int(self.a.shape[0])

    @property
    def size(self) -> tuple[int, int]:
        return (self.w, self.h)

    @property
    def ox(self) -> int:
        """Window x of this canvas's pixel column 0."""
        return self.origin[0]

    @property
    def oy(self) -> int:
        """Window y of this canvas's pixel row 0."""
        return self.origin[1]

    def wx(self, x: int | float) -> int | float:
        """Local x -> window x."""
        return x + self.origin[0]

    def wy(self, y: int | float) -> int | float:
        """Local y -> window y."""
        return y + self.origin[1]

    def lx(self, wx: int | float) -> int | float:
        """Window x -> local x."""
        return wx - self.origin[0]

    def ly(self, wy: int | float) -> int | float:
        """Window y -> local y."""
        return wy - self.origin[1]

    def in_bounds(self, x: int, y: int) -> bool:
        return 0 <= x < self.w and 0 <= y < self.h

    # -- views and copies ----------------------------------------------
    def sub(self, x, y=None, w=None, h=None) -> "Canvas":
        """A view of a rectangle **sharing memory** with this canvas.

        Accepts ``sub(rect)`` or ``sub(x, y, w, h)``.  The view's ``origin`` is
        this canvas's origin plus the rectangle's top-left, so textures stay
        continuous.  Drawing into the view draws into the parent.
        """
        if y is None:
            x, y, w, h = int(x[0]), int(x[1]), int(x[2]), int(x[3])
        x, y, w, h = int(x), int(y), int(w), int(h)
        x0, y0 = max(0, x), max(0, y)
        x1, y1 = min(self.w, x + w), min(self.h, y + h)
        if x1 <= x0 or y1 <= y0:
            raise ValueError(f"skinkit.Canvas.sub: rect [{x},{y} {w}x{h}] is outside {self.w}x{self.h}")
        v = Canvas(array=self.a[y0:y1, x0:x1],
                   origin=(self.origin[0] + x0, self.origin[1] + y0),
                   window=self.window)
        v._parent = self
        return v

    def crop(self, x, y=None, w=None, h=None) -> "Canvas":
        """Like :meth:`sub` but an independent **copy**."""
        v = self.sub(x, y, w, h)
        return Canvas(array=v.a.copy(), origin=v.origin, window=v.window)

    def copy(self) -> "Canvas":
        """Independent duplicate, same origin and window."""
        return Canvas(array=self.a.copy(), origin=self.origin, window=self.window)

    def resized_view(self, window: str | None = None, origin: tuple[int, int] | None = None) -> "Canvas":
        """Same pixels (shared), different origin/window metadata."""
        return Canvas(array=self.a,
                      origin=self.origin if origin is None else origin,
                      window=self.window if window is None else window)

    # -- pixel access --------------------------------------------------
    def poke(self, x: int, y: int, colour: Colour) -> None:
        """Write a pixel with **no** blending (replaces alpha too)."""
        if 0 <= x < self.w and 0 <= y < self.h:
            self.a[int(y), int(x)] = parse_colour(colour)

    def px(self, x: int, y: int, colour: Colour) -> None:
        """Write a pixel.  Opaque colours replace; translucent ones composite."""
        x, y = int(x), int(y)
        if not (0 <= x < self.w and 0 <= y < self.h):
            return
        c = parse_colour(colour)
        if c[3] >= 255:
            self.a[y, x] = c
        elif c[3] > 0:
            self._over_px(x, y, c)

    def _over_px(self, x: int, y: int, c: tuple[int, int, int, int]) -> None:
        sa = c[3] / 255.0
        dst = self.a[y, x].astype(np.float32)
        da = dst[3] / 255.0
        oa = sa + da * (1 - sa)
        if oa <= 0:
            self.a[y, x] = (0, 0, 0, 0)
            return
        for i in range(3):
            self.a[y, x, i] = int(round((c[i] * sa + dst[i] * da * (1 - sa)) / oa))
        self.a[y, x, 3] = int(round(oa * 255))

    def get(self, x: int, y: int) -> tuple[int, int, int, int]:
        """Read a pixel as ``(r, g, b, a)``; out of bounds -> transparent."""
        if not (0 <= x < self.w and 0 <= y < self.h):
            return (0, 0, 0, 0)
        return tuple(int(v) for v in self.a[int(y), int(x)])  # type: ignore[return-value]

    def get_rgb(self, x: int, y: int) -> tuple[int, int, int]:
        r, g, b, _ = self.get(x, y)
        return (r, g, b)

    # -- fills and rectangles ------------------------------------------
    def fill(self, colour: Colour, rect=None) -> "Canvas":
        """Flood the canvas (or ``rect``) with a colour, no blending."""
        c = parse_colour(colour)
        if rect is None:
            self.a[:, :] = c
        else:
            self.sub(rect).a[:, :] = c
        return self

    def clear(self) -> "Canvas":
        self.a[:, :] = 0
        return self

    def box(self, x: int, y: int, w: int, h: int, colour: Colour) -> "Canvas":
        """Filled rectangle (blends if the colour is translucent)."""
        c = parse_colour(colour)
        x0, y0 = max(0, int(x)), max(0, int(y))
        x1, y1 = min(self.w, int(x) + int(w)), min(self.h, int(y) + int(h))
        if x1 <= x0 or y1 <= y0:
            return self
        if c[3] >= 255:
            self.a[y0:y1, x0:x1] = c
        elif c[3] > 0:
            self._over_region(x0, y0, x1, y1, c)
        return self

    def _over_region(self, x0, y0, x1, y1, c) -> None:
        sa = c[3] / 255.0
        dst = self.a[y0:y1, x0:x1].astype(np.float32)
        da = dst[:, :, 3:4] / 255.0
        oa = sa + da * (1 - sa)
        safe = np.where(oa <= 0, 1.0, oa)
        src = np.array(c[:3], dtype=np.float32)
        out = (src * sa + dst[:, :, :3] * da * (1 - sa)) / safe
        self.a[y0:y1, x0:x1, :3] = np.clip(np.rint(out), 0, 255).astype(np.uint8)
        self.a[y0:y1, x0:x1, 3:4] = np.clip(np.rint(oa * 255), 0, 255).astype(np.uint8)

    def rect(self, x: int, y: int, w: int, h: int, colour: Colour) -> "Canvas":
        """1-pixel rectangle outline."""
        x, y, w, h = int(x), int(y), int(w), int(h)
        if w <= 0 or h <= 0:
            return self
        self.hline(x, x + w - 1, y, colour)
        self.hline(x, x + w - 1, y + h - 1, colour)
        self.vline(x, y, y + h - 1, colour)
        self.vline(x + w - 1, y, y + h - 1, colour)
        return self

    def frame(self, colour: Colour, n: int = 1, rect=None) -> "Canvas":
        """``n`` nested 1px outlines starting at the canvas (or ``rect``) edge."""
        if rect is None:
            x, y, w, h = 0, 0, self.w, self.h
        else:
            x, y, w, h = int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3])
        for i in range(int(n)):
            self.rect(x + i, y + i, w - 2 * i, h - 2 * i, colour)
        return self

    # -- lines ---------------------------------------------------------
    def hline(self, x0: int, x1: int, y: int, colour: Colour) -> "Canvas":
        """Horizontal run from ``x0`` to ``x1`` **inclusive** (order-free)."""
        if x0 > x1:
            x0, x1 = x1, x0
        return self.box(x0, y, x1 - x0 + 1, 1, colour)

    def vline(self, x: int, y0: int, y1: int, colour: Colour) -> "Canvas":
        """Vertical run from ``y0`` to ``y1`` **inclusive** (order-free)."""
        if y0 > y1:
            y0, y1 = y1, y0
        return self.box(x, y0, 1, y1 - y0 + 1, colour)

    def line(self, x0: int, y0: int, x1: int, y1: int, colour: Colour) -> "Canvas":
        """Bresenham line, endpoints inclusive, exactly one pixel per step."""
        x0, y0, x1, y1 = int(x0), int(y0), int(x1), int(y1)
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx + dy
        while True:
            self.px(x0, y0, colour)
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

    def polyline(self, points: Sequence[Sequence[int]], colour: Colour, closed: bool = False) -> "Canvas":
        """Connected lines through ``[(x, y), ...]``."""
        pts = [(int(p[0]), int(p[1])) for p in points]
        if len(pts) == 1:
            self.px(pts[0][0], pts[0][1], colour)
            return self
        for i in range(len(pts) - 1):
            self.line(pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], colour)
        if closed and len(pts) > 2:
            self.line(pts[-1][0], pts[-1][1], pts[0][0], pts[0][1], colour)
        return self

    def polygon(self, points: Sequence[Sequence[int]], colour: Colour, outline: Colour | None = None) -> "Canvas":
        """Scanline-filled polygon (even-odd), then an optional 1px outline."""
        pts = [(float(p[0]), float(p[1])) for p in points]
        if len(pts) >= 3:
            ys = [p[1] for p in pts]
            y_lo, y_hi = int(np.floor(min(ys))), int(np.ceil(max(ys)))
            for y in range(max(0, y_lo), min(self.h, y_hi + 1)):
                yc = y + 0.5
                xs: list[float] = []
                for i in range(len(pts)):
                    ax, ay = pts[i]
                    bx, by = pts[(i + 1) % len(pts)]
                    if (ay <= yc < by) or (by <= yc < ay):
                        xs.append(ax + (yc - ay) * (bx - ax) / (by - ay))
                xs.sort()
                for i in range(0, len(xs) - 1, 2):
                    a = int(np.ceil(xs[i] - 0.5))
                    b = int(np.floor(xs[i + 1] - 0.5))
                    if b >= a:
                        self.hline(a, b, y, colour)
        if outline is not None:
            self.polyline(points, outline, closed=True)
        return self

    # -- circles (pixel-perfect midpoint) ------------------------------
    def circle(self, cx: int, cy: int, r: int, colour: Colour) -> "Canvas":
        """1px midpoint circle outline."""
        cx, cy, r = int(cx), int(cy), int(r)
        if r < 0:
            return self
        if r == 0:
            self.px(cx, cy, colour)
            return self
        x, y, d = r, 0, 1 - r
        while x >= y:
            for sx, sy in ((x, y), (y, x), (-x, y), (-y, x), (x, -y), (y, -x), (-x, -y), (-y, -x)):
                self.px(cx + sx, cy + sy, colour)
            y += 1
            if d < 0:
                d += 2 * y + 1
            else:
                x -= 1
                d += 2 * (y - x) + 1
        return self

    def disc(self, cx: int, cy: int, r: int, colour: Colour) -> "Canvas":
        """Filled midpoint circle."""
        cx, cy, r = int(cx), int(cy), int(r)
        if r < 0:
            return self
        if r == 0:
            self.px(cx, cy, colour)
            return self
        x, y, d = r, 0, 1 - r
        while x >= y:
            self.hline(cx - x, cx + x, cy + y, colour)
            self.hline(cx - x, cx + x, cy - y, colour)
            self.hline(cx - y, cx + y, cy + x, colour)
            self.hline(cx - y, cx + y, cy - x, colour)
            y += 1
            if d < 0:
                d += 2 * y + 1
            else:
                x -= 1
                d += 2 * (y - x) + 1
        return self

    def ellipse(self, x: int, y: int, w: int, h: int, colour: Colour, fill: bool = False) -> "Canvas":
        """Axis-aligned ellipse inscribed in the given box (integer midpoint)."""
        x, y, w, h = int(x), int(y), int(w), int(h)
        if w <= 0 or h <= 0:
            return self
        rx, ry = (w - 1) / 2.0, (h - 1) / 2.0
        cx, cy = x + rx, y + ry
        for py in range(y, y + h):
            dy = (py - cy) / ry if ry > 0 else 0.0
            v = 1.0 - dy * dy
            if v < 0:
                continue
            half = rx * (v ** 0.5)
            a, b = int(round(cx - half)), int(round(cx + half))
            if fill:
                self.hline(a, b, py, colour)
            else:
                self.px(a, py, colour)
                self.px(b, py, colour)
        if not fill:
            for px_ in range(x, x + w):
                dx = (px_ - cx) / rx if rx > 0 else 0.0
                v = 1.0 - dx * dx
                if v < 0:
                    continue
                half = ry * (v ** 0.5)
                self.px(px_, int(round(cy - half)), colour)
                self.px(px_, int(round(cy + half)), colour)
        return self

    # -- compositing ---------------------------------------------------
    def blit(self, other: "Canvas", x: int = 0, y: int = 0, alpha: bool = True) -> "Canvas":
        """Draw ``other`` at local ``(x, y)``.

        ``alpha=True`` composites source-over; ``alpha=False`` copies the raw
        RGBA rows (used when a sprite must land byte-exact, e.g. baking a
        widget back into its sheet).
        """
        x, y = int(x), int(y)
        sx0, sy0 = max(0, -x), max(0, -y)
        dx0, dy0 = max(0, x), max(0, y)
        w = min(other.w - sx0, self.w - dx0)
        h = min(other.h - sy0, self.h - dy0)
        if w <= 0 or h <= 0:
            return self
        src = other.a[sy0:sy0 + h, sx0:sx0 + w]
        if not alpha:
            self.a[dy0:dy0 + h, dx0:dx0 + w] = src
            return self
        self._composite(src, dx0, dy0, w, h)
        return self

    def _composite(self, src: np.ndarray, dx0: int, dy0: int, w: int, h: int) -> None:
        s = src.astype(np.float32)
        d = self.a[dy0:dy0 + h, dx0:dx0 + w].astype(np.float32)
        sa = s[:, :, 3:4] / 255.0
        da = d[:, :, 3:4] / 255.0
        oa = sa + da * (1 - sa)
        safe = np.where(oa <= 0, 1.0, oa)
        out = (s[:, :, :3] * sa + d[:, :, :3] * da * (1 - sa)) / safe
        self.a[dy0:dy0 + h, dx0:dx0 + w, :3] = np.clip(np.rint(out), 0, 255).astype(np.uint8)
        self.a[dy0:dy0 + h, dx0:dx0 + w, 3:4] = np.clip(np.rint(oa * 255), 0, 255).astype(np.uint8)

    def over(self, other: "Canvas", x: int = 0, y: int = 0) -> "Canvas":
        """Alias for ``blit(other, x, y, alpha=True)``."""
        return self.blit(other, x, y, alpha=True)

    def paste_array(self, arr: np.ndarray, x: int = 0, y: int = 0, alpha: bool = False) -> "Canvas":
        """Paste a numpy array.

        Accepts ``(h, w, 4)`` RGBA, ``(h, w, 3)`` RGB (alpha 255) or
        ``(h, w)`` greyscale (expanded to opaque grey).
        """
        a = np.asarray(arr)
        if a.ndim == 2:
            a = np.dstack([a, a, a, np.full(a.shape, 255)])
        elif a.ndim == 3 and a.shape[2] == 3:
            a = np.dstack([a, np.full(a.shape[:2], 255)])
        if a.ndim != 3 or a.shape[2] != 4:
            raise ValueError("skinkit.Canvas.paste_array: need (h,w), (h,w,3) or (h,w,4)")
        a = np.clip(a, 0, 255).astype(np.uint8)
        tmp = Canvas(array=a)
        return self.blit(tmp, x, y, alpha=alpha)

    # -- whole-surface adjustments -------------------------------------
    def tint(self, colour: Colour, amount: float = 0.5, rect=None) -> "Canvas":
        """Blend every pixel ``amount`` (0..1) toward ``colour``; alpha kept."""
        t = max(0.0, min(1.0, float(amount)))
        c = np.array(parse_colour(colour)[:3], dtype=np.float32)
        v = self if rect is None else self.sub(rect)
        cur = v.a[:, :, :3].astype(np.float32)
        v.a[:, :, :3] = np.clip(np.rint(cur + (c - cur) * t), 0, 255).astype(np.uint8)
        return self

    def adjust(self, brightness: float = 0.0, contrast: float = 1.0,
               saturation: float = 1.0, rect=None) -> "Canvas":
        """``brightness`` is added in 0..255 units, ``contrast`` and
        ``saturation`` are multipliers around mid-grey / luma."""
        v = self if rect is None else self.sub(rect)
        cur = v.a[:, :, :3].astype(np.float32)
        if saturation != 1.0:
            luma = (cur * np.array([0.299, 0.587, 0.114], dtype=np.float32)).sum(axis=2, keepdims=True)
            cur = luma + (cur - luma) * float(saturation)
        if contrast != 1.0:
            cur = (cur - 128.0) * float(contrast) + 128.0
        if brightness:
            cur = cur + float(brightness)
        v.a[:, :, :3] = np.clip(np.rint(cur), 0, 255).astype(np.uint8)
        return self

    def multiply(self, factor: float, rect=None) -> "Canvas":
        v = self if rect is None else self.sub(rect)
        cur = v.a[:, :, :3].astype(np.float32) * float(factor)
        v.a[:, :, :3] = np.clip(np.rint(cur), 0, 255).astype(np.uint8)
        return self

    def set_alpha(self, a: int, rect=None) -> "Canvas":
        v = self if rect is None else self.sub(rect)
        v.a[:, :, 3] = max(0, min(255, int(a)))
        return self

    def opaque(self, background: Colour = (0, 0, 0)) -> "Canvas":
        """Composite this canvas onto a solid colour; result is fully opaque."""
        out = Canvas(self.w, self.h, origin=self.origin, window=self.window, fill=background)
        out.blit(self, 0, 0, alpha=True)
        out.a[:, :, 3] = 255
        return out

    # -- masks ---------------------------------------------------------
    def alpha_mask(self, threshold: int = 128) -> np.ndarray:
        """Boolean mask of pixels whose alpha is ``>= threshold``."""
        return self.a[:, :, 3] >= int(threshold)

    def colour_mask(self, colour: Colour, tolerance: int = 0) -> np.ndarray:
        """Boolean mask of pixels matching ``colour`` within ``tolerance``."""
        c = np.array(parse_colour(colour)[:3], dtype=np.int16)
        d = np.abs(self.a[:, :, :3].astype(np.int16) - c).max(axis=2)
        return d <= int(tolerance)

    def luma(self) -> np.ndarray:
        """Float32 luminance array, 0..255."""
        return (self.a[:, :, :3].astype(np.float32)
                * np.array([0.299, 0.587, 0.114], dtype=np.float32)).sum(axis=2)

    def apply_mask(self, mask: np.ndarray, colour: Colour, rect=None) -> "Canvas":
        """Paint ``colour`` everywhere ``mask`` is true."""
        v = self if rect is None else self.sub(rect)
        m = np.asarray(mask, dtype=bool)
        if m.shape != v.a.shape[:2]:
            raise ValueError(f"skinkit.Canvas.apply_mask: mask {m.shape} != canvas {v.a.shape[:2]}")
        c = parse_colour(colour)
        if c[3] >= 255:
            v.a[m] = c
        else:
            ys, xs = np.nonzero(m)
            for y, x in zip(ys.tolist(), xs.tolist()):
                v._over_px(x, y, c)
        return self

    def mask_keep(self, mask: np.ndarray) -> "Canvas":
        """Zero the alpha of every pixel outside ``mask``."""
        m = np.asarray(mask, dtype=bool)
        self.a[:, :, 3] = np.where(m, self.a[:, :, 3], 0)
        return self

    def masked_copy(self, mask: np.ndarray) -> "Canvas":
        out = self.copy()
        out.mask_keep(mask)
        return out

    # -- interchange ---------------------------------------------------
    def to_pil(self):
        from PIL import Image
        return Image.fromarray(self.a.copy(), "RGBA")

    @classmethod
    def from_pil(cls, img, origin=(0, 0), window=None) -> "Canvas":
        arr = np.array(img.convert("RGBA"), dtype=np.uint8)
        return cls(array=arr, origin=origin, window=window)

    def save_png(self, path) -> None:
        self.to_pil().save(str(path))

    def __repr__(self) -> str:  # pragma: no cover - debug aid
        return (f"<Canvas {self.w}x{self.h} origin={self.origin} "
                f"window={self.window!r}>")


def new_canvas(rect, window: str | None = None, fill: Colour | None = None) -> Canvas:
    """Shorthand for :meth:`Canvas.from_rect`."""
    return Canvas.from_rect(rect, window=window, fill=fill)
