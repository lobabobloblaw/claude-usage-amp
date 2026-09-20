"""fx -- pixel-art-grade effects for skin painting.

Everything here is **deterministic**: every generator that uses randomness
takes a ``seed``, and every noise field is sampled in *window* coordinates
(``canvas.origin``), so a texture painted into a 275x116 background and the
same texture painted into a 23x18 button cut out of it line up pixel for
pixel.  That is the whole trick that makes the baked-widget model seamless.

Nothing here antialiases.  Gradients can be ordered-dithered (Bayer 4x4) and
step-quantised instead, which is what you want at 1x.
"""

from __future__ import annotations

from typing import Iterable, Sequence

import numpy as np

from .canvas import Canvas, Colour, darken, lighten, mix, parse_colour, with_alpha

__all__ = [
    "BAYER4", "bayer_field", "window_grid",
    "value_noise", "fbm", "apply_noise", "speckle",
    "linear_gradient", "radial_gradient", "gradient_fill",
    "bevel_raised", "bevel_sunken", "bevel_double", "bevel",
    "inner_shadow", "drop_shadow", "glow",
    "brushed_metal", "wood_grain", "scanlines", "glass_glare",
    "screw", "rivet", "vent", "grille", "perforation", "led",
    "hazard_stripes", "emboss_text", "engrave_text",
    "quantize", "palette_lock", "heat_colour", "ramp",
]


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

BAYER4 = np.array([
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
], dtype=np.float32) / 16.0


def _rect_view(c: Canvas, rect) -> Canvas:
    return c if rect is None else c.sub(rect)


def window_grid(c: Canvas) -> tuple[np.ndarray, np.ndarray]:
    """``(X, Y)`` float arrays of the **window** coordinate of every pixel."""
    xs = np.arange(c.w, dtype=np.float32) + c.ox
    ys = np.arange(c.h, dtype=np.float32) + c.oy
    return np.meshgrid(xs, ys)


def bayer_field(c: Canvas) -> np.ndarray:
    """Bayer 4x4 threshold matrix tiled in **window** space (values 0..1)."""
    X, Y = window_grid(c)
    return BAYER4[(Y.astype(np.int64) % 4), (X.astype(np.int64) % 4)]


def _window_extent(c: Canvas) -> tuple[int, int]:
    """Size of the window this canvas belongs to (falls back to the canvas)."""
    if c.window:
        try:
            from .spec import window_size
            return window_size(c.window)
        except Exception:
            pass
    return (c.w, c.h)


def ramp(stops: Sequence[tuple[float, Colour]], t: float) -> tuple[int, int, int, int]:
    """Sample a multi-stop colour ramp at ``t`` (0..1)."""
    pts = sorted(((float(p), parse_colour(col)) for p, col in stops), key=lambda s: s[0])
    t = max(pts[0][0], min(pts[-1][0], float(t)))
    for i in range(len(pts) - 1):
        a, ca = pts[i]
        b, cb = pts[i + 1]
        if a <= t <= b:
            f = 0.0 if b == a else (t - a) / (b - a)
            return tuple(int(round(ca[k] + (cb[k] - ca[k]) * f)) for k in range(4))  # type: ignore
    return pts[-1][1]


def heat_colour(t: float, cool: Colour = "#28d24a", warm: Colour = "#e8d43a",
                hot: Colour = "#e0392b", knee: float = 0.62) -> tuple[int, int, int, int]:
    """The classic green -> yellow -> red gauge ramp.  ``t`` is 0..1."""
    return ramp([(0.0, cool), (knee, warm), (1.0, hot)], t)


# ---------------------------------------------------------------------------
# noise
# ---------------------------------------------------------------------------

def _hash01(ix: np.ndarray, iy: np.ndarray, seed: int) -> np.ndarray:
    """Deterministic 0..1 hash of an integer lattice point."""
    n = (ix.astype(np.int64) * np.int64(374761393)
         + iy.astype(np.int64) * np.int64(668265263)
         + np.int64(seed) * np.int64(1442695041))
    n &= np.int64(0xFFFFFFFF)
    n ^= (n >> np.int64(13))
    n = (n * np.int64(1274126177)) & np.int64(0xFFFFFFFF)
    n ^= (n >> np.int64(16))
    return (n & np.int64(0xFFFFFF)).astype(np.float32) / float(0xFFFFFF)


def _smooth(t: np.ndarray) -> np.ndarray:
    return t * t * (3.0 - 2.0 * t)


def value_noise(c: Canvas, scale: float = 8.0, seed: int = 0,
                sx: float | None = None, sy: float | None = None) -> np.ndarray:
    """Smooth value noise in window space -> float array ``(h, w)`` in 0..1.

    ``scale`` is the lattice spacing in skin pixels.  ``sx`` / ``sy`` override
    it per axis (``sx=40, sy=1`` gives horizontal streaks, i.e. brushed metal).
    """
    fx_, fy_ = (scale if sx is None else sx), (scale if sy is None else sy)
    fx_ = max(1e-3, float(fx_))
    fy_ = max(1e-3, float(fy_))
    X, Y = window_grid(c)
    gx, gy = X / fx_, Y / fy_
    ix, iy = np.floor(gx), np.floor(gy)
    tx, ty = _smooth(gx - ix), _smooth(gy - iy)
    ix = ix.astype(np.int64)
    iy = iy.astype(np.int64)
    v00 = _hash01(ix, iy, seed)
    v10 = _hash01(ix + 1, iy, seed)
    v01 = _hash01(ix, iy + 1, seed)
    v11 = _hash01(ix + 1, iy + 1, seed)
    a = v00 + (v10 - v00) * tx
    b = v01 + (v11 - v01) * tx
    return a + (b - a) * ty


def fbm(c: Canvas, scale: float = 16.0, octaves: int = 4, gain: float = 0.5,
        lacunarity: float = 2.0, seed: int = 0,
        sx: float | None = None, sy: float | None = None) -> np.ndarray:
    """Fractal (summed-octave) value noise in window space, normalised 0..1."""
    total = np.zeros((c.h, c.w), dtype=np.float32)
    amp, norm = 1.0, 0.0
    bx = scale if sx is None else sx
    by = scale if sy is None else sy
    for o in range(max(1, int(octaves))):
        total += amp * value_noise(c, seed=seed + o * 101, sx=bx, sy=by)
        norm += amp
        amp *= gain
        bx /= lacunarity
        by /= lacunarity
    return total / max(1e-6, norm)


def apply_noise(c: Canvas, amount: float = 8.0, scale: float = 3.0, seed: int = 0,
                octaves: int = 1, rect=None, sx: float | None = None,
                sy: float | None = None, tint_colour: Colour | None = None) -> Canvas:
    """Modulate brightness by noise.  ``amount`` is peak-to-peak in 0..255 units.

    ``fx.apply_noise(c, amount=6, scale=2.5, seed=7)`` -- fine film grain.
    """
    v = _rect_view(c, rect)
    n = fbm(v, scale=scale, octaves=octaves, seed=seed, sx=sx, sy=sy) if octaves > 1 \
        else value_noise(v, scale=scale, seed=seed, sx=sx, sy=sy)
    d = (n - 0.5) * float(amount)
    cur = v.a[:, :, :3].astype(np.float32)
    if tint_colour is None:
        cur = cur + d[:, :, None]
    else:
        tc = np.array(parse_colour(tint_colour)[:3], dtype=np.float32)
        w = np.clip(d[:, :, None] / max(1e-6, float(amount)) + 0.5, 0, 1)
        cur = cur + (tc - cur) * (w * (float(amount) / 255.0))
    v.a[:, :, :3] = np.clip(np.rint(cur), 0, 255).astype(np.uint8)
    return c


def speckle(c: Canvas, density: float = 0.04, seed: int = 0, rect=None,
            light: Colour | None = None, dark: Colour | None = None,
            strength: float = 0.5) -> Canvas:
    """Sprinkle single-pixel highlights/pits.  ``density`` is 0..1 per pixel."""
    v = _rect_view(c, rect)
    X, Y = window_grid(v)
    r = _hash01(X.astype(np.int64), Y.astype(np.int64), seed * 7919 + 13)
    d = max(0.0, min(1.0, float(density)))
    hi = r < d * 0.5
    lo = (r >= d * 0.5) & (r < d)
    cur = v.a[:, :, :3].astype(np.float32)
    lc = np.array(parse_colour(light)[:3], dtype=np.float32) if light is not None else None
    dc = np.array(parse_colour(dark)[:3], dtype=np.float32) if dark is not None else None
    s = max(0.0, min(1.0, float(strength)))
    if lc is None:
        cur[hi] = np.clip(cur[hi] + 255.0 * s * 0.18, 0, 255)
    else:
        cur[hi] = cur[hi] + (lc - cur[hi]) * s
    if dc is None:
        cur[lo] = np.clip(cur[lo] - 255.0 * s * 0.18, 0, 255)
    else:
        cur[lo] = cur[lo] + (dc - cur[lo]) * s
    v.a[:, :, :3] = np.clip(np.rint(cur), 0, 255).astype(np.uint8)
    return c


# ---------------------------------------------------------------------------
# gradients
# ---------------------------------------------------------------------------

def _gradient_t(c: Canvas, direction, window_space: bool) -> np.ndarray:
    """Normalised gradient parameter per pixel."""
    if window_space:
        ww, wh = _window_extent(c)
        X, Y = window_grid(c)
        wspan, hspan = max(1, ww - 1), max(1, wh - 1)
    else:
        X, Y = np.meshgrid(np.arange(c.w, dtype=np.float32), np.arange(c.h, dtype=np.float32))
        wspan, hspan = max(1, c.w - 1), max(1, c.h - 1)
    if isinstance(direction, (tuple, list)):
        dx, dy = float(direction[0]), float(direction[1])
        n = (abs(dx) * wspan + abs(dy) * hspan) or 1.0
        t = (X * dx + Y * dy) / n
        if dx < 0:
            t += abs(dx) * wspan / n
        if dy < 0:
            t += abs(dy) * hspan / n
        return np.clip(t, 0.0, 1.0)
    d = str(direction).lower()
    if d in ("v", "vertical", "down"):
        return np.clip(Y / hspan, 0, 1)
    if d in ("up",):
        return np.clip(1.0 - Y / hspan, 0, 1)
    if d in ("h", "horizontal", "right"):
        return np.clip(X / wspan, 0, 1)
    if d in ("left",):
        return np.clip(1.0 - X / wspan, 0, 1)
    if d in ("d", "diagonal", "dr"):
        return np.clip((X / wspan + Y / hspan) * 0.5, 0, 1)
    if d in ("dl",):
        return np.clip((1.0 - X / wspan + Y / hspan) * 0.5, 0, 1)
    raise ValueError(f"skinkit.fx: unknown gradient direction {direction!r}")


def _ramp_lut(stops, n: int = 256) -> np.ndarray:
    lut = np.zeros((n, 4), dtype=np.float32)
    for i in range(n):
        lut[i] = ramp(stops, i / (n - 1))
    return lut


def _paint_t(v: Canvas, t: np.ndarray, stops, dither: float, steps: int | None,
             alpha: float) -> None:
    if dither:
        t = t + (bayer_field(v) - 0.5) * float(dither)
    if steps:
        k = max(2, int(steps))
        t = np.round(np.clip(t, 0, 1) * (k - 1)) / (k - 1)
    t = np.clip(t, 0.0, 1.0)
    lut = _ramp_lut(stops)
    idx = np.clip(np.rint(t * 255).astype(np.int32), 0, 255)
    col = lut[idx]
    if alpha >= 1.0:
        v.a[:, :, :3] = np.clip(np.rint(col[:, :, :3]), 0, 255).astype(np.uint8)
        v.a[:, :, 3] = np.clip(np.rint(col[:, :, 3]), 0, 255).astype(np.uint8)
    else:
        cur = v.a[:, :, :3].astype(np.float32)
        out = cur + (col[:, :, :3] - cur) * float(alpha)
        v.a[:, :, :3] = np.clip(np.rint(out), 0, 255).astype(np.uint8)


def linear_gradient(c: Canvas, top: Colour = None, bottom: Colour = None, *,
                    direction="v", stops: Sequence[tuple[float, Colour]] | None = None,
                    rect=None, dither: float = 0.0, steps: int | None = None,
                    window_space: bool = True, alpha: float = 1.0) -> Canvas:
    """Straight gradient.

    ``direction`` is ``"v"``, ``"h"``, ``"up"``, ``"left"``, ``"d"``, ``"dl"``
    or a ``(dx, dy)`` vector.  With ``window_space=True`` (the default) the
    gradient spans the whole **window**, so a widget cut out of the background
    gets exactly the background's slice of it.

    ``dither`` (try 0.06) adds ordered Bayer 4x4 dithering; ``steps`` snaps the
    ramp to N bands for a retro banded look.

    ``fx.linear_gradient(c, "#3a3f46", "#20242a", dither=0.05)``
    """
    v = _rect_view(c, rect)
    st = stops if stops is not None else [(0.0, top), (1.0, bottom if bottom is not None else top)]
    _paint_t(v, _gradient_t(v, direction, window_space), st, dither, steps, alpha)
    return c


def radial_gradient(c: Canvas, cx: float, cy: float, radius: float,
                    inner: Colour = None, outer: Colour = None, *,
                    stops: Sequence[tuple[float, Colour]] | None = None,
                    rect=None, dither: float = 0.0, steps: int | None = None,
                    window_space: bool = False, alpha: float = 1.0,
                    aspect: float = 1.0) -> Canvas:
    """Radial gradient centred on ``(cx, cy)``.

    Centre is in **local** coordinates unless ``window_space=True``.
    ``aspect`` > 1 stretches the falloff horizontally.
    """
    v = _rect_view(c, rect)
    if window_space:
        X, Y = window_grid(v)
    else:
        X, Y = np.meshgrid(np.arange(v.w, dtype=np.float32), np.arange(v.h, dtype=np.float32))
    dx = (X - float(cx)) / max(1e-6, float(aspect))
    dy = (Y - float(cy))
    t = np.sqrt(dx * dx + dy * dy) / max(1e-6, float(radius))
    st = stops if stops is not None else [(0.0, inner), (1.0, outer if outer is not None else inner)]
    _paint_t(v, np.clip(t, 0, 1), st, dither, steps, alpha)
    return c


def gradient_fill(c: Canvas, stops: Sequence[tuple[float, Colour]], **kw) -> Canvas:
    """Multi-stop convenience wrapper over :func:`linear_gradient`."""
    return linear_gradient(c, stops=stops, **kw)


# ---------------------------------------------------------------------------
# bevels
# ---------------------------------------------------------------------------

def _bevel_edges(v: Canvas, x, y, w, h, tl: Colour, br: Colour, corner: str) -> None:
    """One bevel ring: top+left get ``tl``, bottom+right get ``br``."""
    if w <= 0 or h <= 0:
        return
    x1, y1 = x + w - 1, y + h - 1
    v.hline(x, x1 - 1, y, tl)
    v.vline(x, y, y1 - 1, tl)
    v.hline(x + 1, x1, y1, br)
    v.vline(x1, y + 1, y1, br)
    # the two "ambiguous" corners: top-right and bottom-left
    if corner in (None, "none", "skip"):
        return
    if corner == "light":
        tr = bl = tl
    elif corner == "shadow":
        tr = bl = br
    elif corner == "split":
        tr, bl = tl, br
    else:  # "mix" (default): average of the two, reads as a rounded corner
        tr = bl = mix(tl, br, 0.5)
    v.px(x1, y, tr)
    v.px(x, y1, bl)


def bevel(c: Canvas, rect=None, *, light: Colour = "#ffffff66", shadow: Colour = "#00000080",
          raised: bool = True, n: int = 1, corner: str = "mix", inset: int = 0) -> Canvas:
    """``n`` nested bevel rings.  ``raised`` puts the light at the top-left."""
    v = _rect_view(c, rect)
    tl, br = (light, shadow) if raised else (shadow, light)
    for i in range(int(n)):
        k = int(inset) + i
        _bevel_edges(v, k, k, v.w - 2 * k, v.h - 2 * k, tl, br, corner)
    return c


def bevel_raised(c: Canvas, rect=None, *, light: Colour = "#ffffff66",
                 shadow: Colour = "#00000080", n: int = 1, corner: str = "mix",
                 inset: int = 0) -> Canvas:
    """Light on top/left, shadow on bottom/right -- a button that sticks out.

    ``fx.bevel_raised(c, light="#8e98a6", shadow="#14171b")``
    """
    return bevel(c, rect, light=light, shadow=shadow, raised=True, n=n, corner=corner, inset=inset)


def bevel_sunken(c: Canvas, rect=None, *, light: Colour = "#ffffff66",
                 shadow: Colour = "#00000080", n: int = 1, corner: str = "mix",
                 inset: int = 0) -> Canvas:
    """Shadow on top/left -- a well, a groove, or a pressed button."""
    return bevel(c, rect, light=light, shadow=shadow, raised=False, n=n, corner=corner, inset=inset)


def bevel_double(c: Canvas, rect=None, *, outer_light: Colour = "#8a94a2",
                 outer_shadow: Colour = "#12151a", inner_light: Colour = "#5c6672",
                 inner_shadow: Colour = "#272c33", raised: bool = True,
                 corner: str = "mix", inset: int = 0) -> Canvas:
    """Two rings: an outer bevel and an inner counter-bevel.

    The classic hi-fi faceplate edge.  ``raised=True`` gives outer-raised /
    inner-sunken (a plate standing proud with a lip); ``raised=False`` inverts
    both, which is what a *pressed* button should look like.
    """
    v = _rect_view(c, rect)
    otl, obr = (outer_light, outer_shadow) if raised else (outer_shadow, outer_light)
    itl, ibr = (inner_shadow, inner_light) if raised else (inner_light, inner_shadow)
    k = int(inset)
    _bevel_edges(v, k, k, v.w - 2 * k, v.h - 2 * k, otl, obr, corner)
    _bevel_edges(v, k + 1, k + 1, v.w - 2 * k - 2, v.h - 2 * k - 2, itl, ibr, corner)
    return c


# ---------------------------------------------------------------------------
# shadows and glow
# ---------------------------------------------------------------------------

def inner_shadow(c: Canvas, rect=None, colour: Colour = "#000000", depth: int = 3,
                 strength: float = 0.55, sides: str = "tlbr") -> Canvas:
    """Darkening that falls off inward from the chosen edges of a well.

    ``sides`` is any subset of ``"t"``, ``"l"``, ``"b"``, ``"r"``.
    """
    v = _rect_view(c, rect)
    depth = max(1, int(depth))
    col = np.array(parse_colour(colour)[:3], dtype=np.float32)
    acc = np.zeros((v.h, v.w), dtype=np.float32)
    yy, xx = np.mgrid[0:v.h, 0:v.w].astype(np.float32)
    if "t" in sides:
        acc = np.maximum(acc, np.clip(1.0 - yy / depth, 0, 1))
    if "b" in sides:
        acc = np.maximum(acc, np.clip(1.0 - (v.h - 1 - yy) / depth, 0, 1))
    if "l" in sides:
        acc = np.maximum(acc, np.clip(1.0 - xx / depth, 0, 1))
    if "r" in sides:
        acc = np.maximum(acc, np.clip(1.0 - (v.w - 1 - xx) / depth, 0, 1))
    w = (acc * float(strength))[:, :, None]
    cur = v.a[:, :, :3].astype(np.float32)
    v.a[:, :, :3] = np.clip(np.rint(cur + (col - cur) * w), 0, 255).astype(np.uint8)
    return c


def _box_blur(m: np.ndarray, r: int) -> np.ndarray:
    if r <= 0:
        return m
    out = m.astype(np.float32)
    k = 2 * r + 1
    pad = np.pad(out, ((0, 0), (r, r)), mode="edge")
    out = np.add.reduce([pad[:, i:i + out.shape[1]] for i in range(k)]) / k
    pad = np.pad(out, ((r, r), (0, 0)), mode="edge")
    out = np.add.reduce([pad[i:i + out.shape[0], :] for i in range(k)]) / k
    return out


def drop_shadow(c: Canvas, mask: np.ndarray | None = None, colour: Colour = "#00000099",
                dx: int = 1, dy: int = 1, blur: int = 0, rect=None) -> Canvas:
    """Offset shadow *under* the shape given by ``mask`` (default: the canvas's
    own alpha).  Drawn behind existing pixels, so call it before the art or on
    a copy."""
    v = _rect_view(c, rect)
    m = v.alpha_mask() if mask is None else np.asarray(mask, dtype=bool)
    f = _box_blur(m.astype(np.float32), int(blur))
    shifted = np.zeros_like(f)
    ys = slice(max(0, dy), v.h + min(0, dy))
    yd = slice(max(0, -dy), v.h + min(0, -dy))
    xs = slice(max(0, dx), v.w + min(0, dx))
    xd = slice(max(0, -dx), v.w + min(0, -dx))
    shifted[ys, xs] = f[yd, xd]
    col = parse_colour(colour)
    a = (shifted * (col[3] / 255.0))[:, :, None]
    cur = v.a[:, :, :3].astype(np.float32)
    keep = (v.a[:, :, 3:4].astype(np.float32) / 255.0)
    w = a * (1.0 - keep)
    v.a[:, :, :3] = np.clip(np.rint(cur + (np.array(col[:3], dtype=np.float32) - cur) * w), 0, 255).astype(np.uint8)
    v.a[:, :, 3] = np.clip(np.rint(np.maximum(v.a[:, :, 3].astype(np.float32), w[:, :, 0] * 255)), 0, 255).astype(np.uint8)
    return c


def glow(c: Canvas, mask_or_points, colour: Colour = "#7cff9a", radius: int = 2,
         strength: float = 0.8, rect=None) -> Canvas:
    """Additive bloom around lit pixels.

    ``mask_or_points`` is either a boolean ``(h, w)`` mask or an iterable of
    ``(x, y)`` points.

    ``fx.glow(c, [(4, 4)], "#6bff8f", radius=3)``
    """
    v = _rect_view(c, rect)
    if isinstance(mask_or_points, np.ndarray):
        m = mask_or_points.astype(np.float32)
    else:
        m = np.zeros((v.h, v.w), dtype=np.float32)
        for p in mask_or_points:
            x, y = int(p[0]), int(p[1])
            if 0 <= x < v.w and 0 <= y < v.h:
                m[y, x] = 1.0
    f = _box_blur(m, max(1, int(radius)))
    if f.max() > 0:
        f = f / f.max()
    col = np.array(parse_colour(colour)[:3], dtype=np.float32)
    cur = v.a[:, :, :3].astype(np.float32)
    w = (f * float(strength))[:, :, None]
    v.a[:, :, :3] = np.clip(np.rint(cur + (col - cur) * w), 0, 255).astype(np.uint8)
    return c


# ---------------------------------------------------------------------------
# material generators
# ---------------------------------------------------------------------------

def brushed_metal(c: Canvas, base: Colour = "#8d949c", direction: str = "h",
                  strength: float = 0.16, seed: int = 0, rect=None,
                  streak: float = 48.0, grain: float = 1.0,
                  sheen: float = 0.10) -> Canvas:
    """Anisotropic brushed-metal texture, continuous in window space.

    ``direction`` ``"h"`` or ``"v"`` is the brushing direction; ``streak`` is
    how long the streaks are; ``strength`` is their contrast (0..1); ``sheen``
    adds a broad cross-gradient.

    ``fx.brushed_metal(c, "#9aa2ab", "h", strength=0.2, seed=3)``
    """
    v = _rect_view(c, rect)
    if direction in ("h", "horizontal"):
        n = fbm(v, octaves=3, seed=seed, sx=float(streak), sy=max(0.6, float(grain)))
        n2 = value_noise(v, seed=seed + 991, sx=float(streak) * 4, sy=max(0.9, float(grain) * 2.5))
        cross = np.linspace(-1.0, 1.0, v.h, dtype=np.float32)[:, None] * np.ones((1, v.w), dtype=np.float32)
    else:
        n = fbm(v, octaves=3, seed=seed, sx=max(0.6, float(grain)), sy=float(streak))
        n2 = value_noise(v, seed=seed + 991, sx=max(0.9, float(grain) * 2.5), sy=float(streak) * 4)
        cross = np.linspace(-1.0, 1.0, v.w, dtype=np.float32)[None, :] * np.ones((v.h, 1), dtype=np.float32)
    field = (n - 0.5) * 0.75 + (n2 - 0.5) * 0.25
    b = np.array(parse_colour(base)[:3], dtype=np.float32)
    out = b[None, None, :] * (1.0 + field[:, :, None] * float(strength) * 2.0)
    out = out * (1.0 + (1.0 - np.abs(cross))[:, :, None] * float(sheen))
    v.a[:, :, :3] = np.clip(np.rint(out), 0, 255).astype(np.uint8)
    v.a[:, :, 3] = 255
    return c


def wood_grain(c: Canvas, palette: Sequence[Colour] | None = None, seed: int = 0,
               rect=None, direction: str = "h", rings: float = 5.0,
               warp: float = 6.0, pore_density: float = 0.05,
               contrast: float = 1.0) -> Canvas:
    """Ring-porous wood.  ``palette`` runs light -> dark (3+ colours is good).

    ``fx.wood_grain(c, ["#c49a68", "#8a5a30", "#4a2d16"], seed=5, rings=7)``
    """
    pal = list(palette or ["#c8a070", "#9a6a3c", "#5c3518"])
    stops = [(i / max(1, len(pal) - 1), col) for i, col in enumerate(pal)]
    v = _rect_view(c, rect)
    X, Y = window_grid(v)
    wobble = (fbm(v, octaves=4, seed=seed + 5, sx=28.0, sy=9.0) - 0.5) * float(warp)
    axis = (Y if direction in ("h", "horizontal") else X) + wobble * 2.0
    span = max(1.0, (v.h if direction in ("h", "horizontal") else v.w))
    t = (np.sin(axis / span * float(rings) * np.pi * 2.0) * 0.5 + 0.5)
    t = np.clip((t - 0.5) * float(contrast) + 0.5, 0, 1)
    t = t * 0.75 + fbm(v, octaves=3, seed=seed + 17, sx=40.0, sy=6.0) * 0.25
    _paint_t(v, np.clip(t, 0, 1), stops, 0.04, None, 1.0)
    if pore_density > 0:
        speckle(v, density=float(pore_density), seed=seed + 77,
                dark=darken(pal[-1], 0.35), light=lighten(pal[0], 0.12), strength=0.45)
    return c


def scanlines(c: Canvas, rect=None, every: int = 2, amount: float = 0.18,
              colour: Colour | None = None, phase: int = 0,
              window_space: bool = True) -> Canvas:
    """Darken (or tint) every ``every``-th row.  Phase follows window y so the
    lines never jump at a sprite boundary."""
    v = _rect_view(c, rect)
    base = v.oy if window_space else 0
    rows = [y for y in range(v.h) if (y + base + int(phase)) % max(1, int(every)) == 0]
    if not rows:
        return c
    idx = np.array(rows, dtype=np.int64)
    cur = v.a[idx, :, :3].astype(np.float32)
    if colour is None:
        out = cur * (1.0 - float(amount))
    else:
        col = np.array(parse_colour(colour)[:3], dtype=np.float32)
        out = cur + (col - cur) * float(amount)
    v.a[idx, :, :3] = np.clip(np.rint(out), 0, 255).astype(np.uint8)
    return c


def glass_glare(c: Canvas, rect=None, colour: Colour = "#ffffff", strength: float = 0.18,
                angle: float = -0.6, width: float = 0.32, offset: float = -0.15,
                window_space: bool = True, second: bool = True) -> Canvas:
    """A soft diagonal highlight band, as if light fell across glass.

    ``angle`` is the band's slope (negative leans right-up), ``width`` its
    thickness as a fraction of the diagonal, ``offset`` slides it.
    """
    v = _rect_view(c, rect)
    if window_space:
        X, Y = window_grid(v)
        ww, wh = _window_extent(v)
    else:
        X, Y = np.meshgrid(np.arange(v.w, dtype=np.float32), np.arange(v.h, dtype=np.float32))
        ww, wh = v.w, v.h
    u = (X / max(1, ww - 1)) + (Y / max(1, wh - 1)) * float(angle)
    u = u - u.min() if u.size else u
    span = max(1e-6, float(u.max() - u.min())) if u.size else 1.0
    u = (u - u.min()) / span if u.size else u
    band = np.clip(1.0 - np.abs(u - (0.5 + float(offset))) / max(1e-6, float(width)), 0, 1)
    band = band ** 1.6
    if second:
        band = np.maximum(band * 1.0,
                          np.clip(1.0 - np.abs(u - (0.5 + float(offset) + width * 1.4))
                                  / max(1e-6, float(width) * 0.35), 0, 1) ** 2 * 0.55)
    col = np.array(parse_colour(colour)[:3], dtype=np.float32)
    cur = v.a[:, :, :3].astype(np.float32)
    w = (band * float(strength))[:, :, None]
    v.a[:, :, :3] = np.clip(np.rint(cur + (col - cur) * w), 0, 255).astype(np.uint8)
    return c


# ---------------------------------------------------------------------------
# hardware details
# ---------------------------------------------------------------------------

def screw(c: Canvas, cx: int, cy: int, r: int = 2, style: str = "slot",
          body: Colour = "#7b838d", light: Colour = "#c8d0d8", shadow: Colour = "#1b1e23",
          slot_colour: Colour | None = None, angle: int = 0) -> Canvas:
    """A countersunk screw head.

    ``style`` is ``"slot"``, ``"phillips"`` or ``"hex"``.  ``angle`` is the
    slot rotation in degrees (0, 45, 90, 135 read cleanly at r<=3).

    ``fx.screw(c, 6, 6, r=2, style="phillips")``
    """
    cx, cy, r = int(cx), int(cy), int(r)
    if r < 1:
        c.px(cx, cy, shadow)
        return c
    slot_colour = slot_colour if slot_colour is not None else shadow
    if style == "hex":
        pts = []
        for k in range(6):
            a = np.deg2rad(angle + 60 * k + 30)
            pts.append((int(round(cx + r * np.cos(a))), int(round(cy + r * np.sin(a)))))
        c.polygon(pts, body)
        c.polyline(pts, darken(body, 0.25), closed=True)
    else:
        c.disc(cx, cy, r, body)
    # lit rim top-left, dark rim bottom-right (screen y is down, so the lit
    # arc is the one whose angle points up-left: 135deg..315deg)
    for k in range(0, 360, 6):
        a = np.deg2rad(k)
        px_ = int(round(cx + r * np.cos(a)))
        py_ = int(round(cy + r * np.sin(a)))
        c.px(px_, py_, light if (135 <= k <= 315) else shadow)
    if style == "slot":
        a = np.deg2rad(angle)
        dx, dy = np.cos(a), np.sin(a)
        c.line(int(round(cx - dx * r)), int(round(cy - dy * r)),
               int(round(cx + dx * r)), int(round(cy + dy * r)), slot_colour)
    elif style == "phillips":
        c.line(cx - r, cy, cx + r, cy, slot_colour)
        c.line(cx, cy - r, cx, cy + r, slot_colour)
        c.px(cx, cy, darken(slot_colour, 0.3))
    elif style == "hex":
        c.disc(cx, cy, max(0, r - 2), slot_colour)
    return c


def rivet(c: Canvas, cx: int, cy: int, r: int = 2, body: Colour = "#98a0a9",
          light: Colour = "#dfe6ec", shadow: Colour = "#20242a") -> Canvas:
    """A domed rivet: bright top-left quadrant, dark bottom-right rim."""
    c.disc(cx, cy, r, body)
    for k in range(0, 360, 8):
        a = np.deg2rad(k)
        px_ = int(round(cx + r * np.cos(a)))
        py_ = int(round(cy + r * np.sin(a)))
        # bottom-right arc (0..135 deg in screen space) is the shadowed rim
        c.px(px_, py_, shadow if (0 <= k <= 135) else light)
    if r >= 2:
        c.px(cx - r + 1, cy - r + 1, light)
        c.px(cx, cy - r + 1, lighten(body, 0.35))
    return c


def vent(c: Canvas, rect=None, slots: int = 4, direction: str = "h", gap: int = 2,
         slot_thickness: int = 2, margin: int = 1,
         dark: Colour = "#14171b", light: Colour = "#9aa3ad",
         face: Colour | None = None) -> Canvas:
    """Recessed louvres.  Slots run along ``direction`` and are stacked across it.

    ``fx.vent(c, (4, 3, 20, 12), slots=3)``
    """
    v = _rect_view(c, rect)
    if face is not None:
        v.fill(face)
    n = max(1, int(slots))
    st = max(1, int(slot_thickness))
    if direction in ("h", "horizontal"):
        total = n * st + (n - 1) * int(gap)
        y0 = (v.h - total) // 2
        for i in range(n):
            y = y0 + i * (st + int(gap))
            v.box(margin, y, v.w - 2 * margin, st, dark)
            v.hline(margin, v.w - 1 - margin, y + st, light)
    else:
        total = n * st + (n - 1) * int(gap)
        x0 = (v.w - total) // 2
        for i in range(n):
            x = x0 + i * (st + int(gap))
            v.box(x, margin, st, v.h - 2 * margin, dark)
            v.vline(x + st, margin, v.h - 1 - margin, light)
    return c


def grille(c: Canvas, rect=None, pitch: int = 2, direction: str = "h",
           dark: Colour = "#1a1d22", light: Colour | None = None,
           window_space: bool = True) -> Canvas:
    """A fine line grille.  Phase follows window coords so it tiles across cuts."""
    v = _rect_view(c, rect)
    p = max(2, int(pitch))
    if direction in ("h", "horizontal"):
        for y in range(v.h):
            if (y + (v.oy if window_space else 0)) % p == 0:
                v.hline(0, v.w - 1, y, dark)
                if light is not None and y + 1 < v.h:
                    v.hline(0, v.w - 1, y + 1, light)
    else:
        for x in range(v.w):
            if (x + (v.ox if window_space else 0)) % p == 0:
                v.vline(x, 0, v.h - 1, dark)
                if light is not None and x + 1 < v.w:
                    v.vline(x + 1, 0, v.h - 1, light)
    return c


def perforation(c: Canvas, rect=None, pitch: int = 3, r: int = 0,
                dark: Colour = "#15181c", light: Colour | None = "#6e7680",
                stagger: bool = True, window_space: bool = True) -> Canvas:
    """A punched-hole pattern (speaker grille).  ``r=0`` gives single pixels."""
    v = _rect_view(c, rect)
    p = max(2, int(pitch))
    bx = v.ox if window_space else 0
    by = v.oy if window_space else 0
    for y in range(v.h):
        wy = y + by
        if wy % p:
            continue
        shift = (p // 2) if (stagger and (wy // p) % 2) else 0
        for x in range(v.w):
            wx = x + bx + shift
            if wx % p:
                continue
            if r <= 0:
                v.px(x, y, dark)
                if light is not None:
                    v.px(x + 1, y + 1, light)
            else:
                v.disc(x, y, int(r), dark)
                if light is not None:
                    v.px(x + r, y + r, light)
    return c


def led(c: Canvas, x: int, y: int, w: int, h: int, colour: Colour = "#5fe07a",
        on: bool = True, bloom: int = 1, off_colour: Colour | None = None,
        bezel: Colour | None = "#0d0f12", strength: float = 0.7) -> Canvas:
    """A small indicator lamp.  Off state is a dim version of ``colour``
    unless ``off_colour`` is given; on state gets a bloom halo.

    ``fx.led(c, 3, 4, 4, 3, "#ff5533", on=True)``
    """
    x, y, w, h = int(x), int(y), int(w), int(h)
    body = parse_colour(colour) if on else (off_colour if off_colour is not None else darken(colour, 0.72))
    if bezel is not None:
        c.box(x - 1, y - 1, w + 2, h + 2, bezel)
    c.box(x, y, w, h, body)
    if on:
        if w >= 3 and h >= 2:
            c.hline(x, x + w - 1, y, lighten(body, 0.4))
            c.px(x, y, lighten(body, 0.6))
        if bloom > 0:
            m = np.zeros((c.h, c.w), dtype=np.float32)
            x0, y0 = max(0, x), max(0, y)
            x1, y1 = min(c.w, x + w), min(c.h, y + h)
            if x1 > x0 and y1 > y0:
                m[y0:y1, x0:x1] = 1.0
                glow(c, m, colour, radius=int(bloom), strength=float(strength) * 0.5)
    else:
        c.hline(x, x + w - 1, y, lighten(body, 0.15))
    return c


def hazard_stripes(c: Canvas, rect=None, a: Colour = "#e8c62a", b: Colour = "#1a1c20",
                   width: int = 4, slope: int = 1, window_space: bool = True) -> Canvas:
    """Diagonal warning stripes.  ``slope`` 1 or -1; ``width`` in pixels."""
    v = _rect_view(c, rect)
    w = max(1, int(width))
    bx = v.ox if window_space else 0
    by = v.oy if window_space else 0
    X, Y = np.meshgrid(np.arange(v.w) + bx, np.arange(v.h) + by)
    k = ((X + int(slope) * Y) // w) % 2
    ca = np.array(parse_colour(a), dtype=np.uint8)
    cb = np.array(parse_colour(b), dtype=np.uint8)
    v.a[k == 0] = ca
    v.a[k == 1] = cb
    return c


# ---------------------------------------------------------------------------
# text relief
# ---------------------------------------------------------------------------

def emboss_text(c: Canvas, x: int, y: int, text: str, font=None, colour: Colour = "#c9d2dc",
                light: Colour | None = "#ffffff55", shadow: Colour | None = "#00000099",
                spacing: int = 1) -> Canvas:
    """Text that stands proud: shadow down-right, highlight up-left, face on top."""
    from . import fonts
    f = font if font is not None else fonts.MICRO_4x5
    if shadow is not None:
        fonts.draw_text(c, x + 1, y + 1, text, f, shadow, spacing=spacing)
    if light is not None:
        fonts.draw_text(c, x - 1, y - 1, text, f, light, spacing=spacing)
    fonts.draw_text(c, x, y, text, f, colour, spacing=spacing)
    return c


def engrave_text(c: Canvas, x: int, y: int, text: str, font=None, colour: Colour = "#161a1f",
                 light: Colour | None = "#ffffff40", spacing: int = 1) -> Canvas:
    """Text cut into the surface: dark face with a 1px lit lip below-right.

    ``fx.engrave_text(c, 2, 2, "SESSION", fonts.MICRO_3x5, "#0e1114")``
    """
    from . import fonts
    f = font if font is not None else fonts.MICRO_3x5
    if light is not None:
        fonts.draw_text(c, x, y + 1, text, f, light, spacing=spacing)
    fonts.draw_text(c, x, y, text, f, colour, spacing=spacing)
    return c


# ---------------------------------------------------------------------------
# palette control
# ---------------------------------------------------------------------------

def quantize(c: Canvas, n_colours: int = 32, rect=None, dither: bool = False) -> Canvas:
    """Reduce to ``n_colours`` using PIL's adaptive palette (alpha preserved)."""
    from PIL import Image
    v = _rect_view(c, rect)
    rgb_img = Image.fromarray(v.a[:, :, :3].copy(), "RGB")
    q = rgb_img.quantize(colors=max(2, min(256, int(n_colours))),
                         method=Image.Quantize.MEDIANCUT,
                         dither=Image.Dither.FLOYDSTEINBERG if dither else Image.Dither.NONE)
    v.a[:, :, :3] = np.array(q.convert("RGB"), dtype=np.uint8)
    return c


def palette_lock(c: Canvas, palette: Sequence[Colour], rect=None) -> Canvas:
    """Snap every pixel to its nearest colour in ``palette`` (no dithering).

    Use this last, to guarantee a skin only ever uses its declared colours.
    """
    v = _rect_view(c, rect)
    pal = np.array([parse_colour(p)[:3] for p in palette], dtype=np.float32)
    if len(pal) == 0:
        return c
    cur = v.a[:, :, :3].astype(np.float32)
    d = ((cur[:, :, None, :] - pal[None, None, :, :]) ** 2).sum(axis=3)
    idx = d.argmin(axis=2)
    v.a[:, :, :3] = pal[idx].astype(np.uint8)
    return c
