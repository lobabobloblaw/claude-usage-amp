"""Walnut 76 -- material generators.

Everything samples in *window* coordinates (``c.ox`` / ``c.oy``) so a texture
runs continuously under and across widgets, and everything is deterministic.

The noise here can be made **periodic** along either axis, which is what lets
the playlist's walnut rails tile every 25 px / 29 px without a seam while the
same function, evaluated in the corner pieces, meets the tiles exactly.
"""

from __future__ import annotations

import numpy as np

from skinkit.canvas import Canvas, parse_colour

import w76_palette as P

# per-window seed offsets, so the three components are three different planks
WINDOW_SEED = {"main": 0, "shade": 0, "eq": 4000, "playlist": 9000, None: 0}


# ---------------------------------------------------------------------------
# noise
# ---------------------------------------------------------------------------

def _hash01(ix, iy, seed):
    n = (ix.astype(np.int64) * np.int64(374761393)
         + iy.astype(np.int64) * np.int64(668265263)
         + np.int64(seed) * np.int64(1442695041))
    n &= np.int64(0xFFFFFFFF)
    n ^= (n >> np.int64(13))
    n = (n * np.int64(1274126177)) & np.int64(0xFFFFFFFF)
    n ^= (n >> np.int64(16))
    return (n & np.int64(0xFFFFFF)).astype(np.float32) / float(0xFFFFFF)


def _smooth(t):
    return t * t * (3.0 - 2.0 * t)


def vnoise(X, Y, sx, sy, seed, wrap_x=None, wrap_y=None):
    """Smooth value noise at float coords.  ``wrap_x`` / ``wrap_y`` = number of
    lattice cells after which the lattice repeats (periodic noise)."""
    gx, gy = X / float(sx), Y / float(sy)
    ix, iy = np.floor(gx), np.floor(gy)
    tx, ty = _smooth(gx - ix), _smooth(gy - iy)
    ix = ix.astype(np.int64)
    iy = iy.astype(np.int64)
    ix1, iy1 = ix + 1, iy + 1
    if wrap_x:
        ix, ix1 = ix % wrap_x, ix1 % wrap_x
    if wrap_y:
        iy, iy1 = iy % wrap_y, iy1 % wrap_y
    v00 = _hash01(ix, iy, seed)
    v10 = _hash01(ix1, iy, seed)
    v01 = _hash01(ix, iy1, seed)
    v11 = _hash01(ix1, iy1, seed)
    a = v00 + (v10 - v00) * tx
    b = v01 + (v11 - v01) * tx
    return a + (b - a) * ty


def grid(c: Canvas):
    xs = np.arange(c.w, dtype=np.float32) + c.ox
    ys = np.arange(c.h, dtype=np.float32) + c.oy
    return np.meshgrid(xs, ys)


def _put(c: Canvas, rgb: np.ndarray, mask=None) -> None:
    out = np.clip(np.rint(rgb), 0, 255).astype(np.uint8)
    if mask is None:
        c.a[:, :, :3] = out
        c.a[:, :, 3] = 255
    else:
        c.a[:, :, :3][mask] = out[mask]
        c.a[:, :, 3][mask] = 255


def _ramp_map(ramp, t):
    lut = P.ramp_lut(ramp, 512)
    idx = np.clip(np.rint(np.clip(t, 0, 1) * 511).astype(np.int32), 0, 511)
    return lut[idx]


# ---------------------------------------------------------------------------
# walnut
# ---------------------------------------------------------------------------

def walnut(c: Canvas, direction: str = "v", seed: int = 76, period: int | None = None,
           knots=(), tone: float = 0.0, flow: float = 1.0, mask=None) -> None:
    """Oiled walnut.  ``direction`` is the way the grain RUNS: ``"v"`` for the
    cabinet cheeks, ``"h"`` for the top rail.

    ``period`` makes the figure periodic along the grain direction (playlist
    tiles).  ``knots`` is a list of ``(wx, wy, r)`` in window coords: the grain
    parts around each knot and the heart darkens.  ``tone`` shifts the whole
    plank lighter (+) or darker (-) in ramp units (0..1).
    """
    seed = seed + WINDOW_SEED.get(c.window, 0)
    X, Y = grid(c)
    if direction == "v":
        U, V = X.copy(), Y.copy()          # U across the grain, V along it
    else:
        U, V = Y.copy(), X.copy()

    # long correlated wander of the grain lines (in px, across the grain)
    if period:
        n1 = 2
        warp = (vnoise(U, V, 5.0, period / n1, seed + 1, wrap_y=n1) - 0.5) * 3.2 * flow
        warp += (vnoise(U, V, 3.0, period / 4, seed + 2, wrap_y=4) - 0.5) * 1.1 * flow
    else:
        warp = (vnoise(U, V, 6.0, 46.0, seed + 1) - 0.5) * 5.0 * flow
        warp += (vnoise(U, V, 3.0, 17.0, seed + 2) - 0.5) * 1.6 * flow

    heart = np.zeros_like(U)
    for (kx, ky, kr) in knots:
        ku, kv = (kx, ky) if direction == "v" else (ky, kx)
        du, dv = U - ku, (V - kv) * 0.55
        r2 = du * du + dv * dv
        push = np.exp(-r2 / (2.0 * (kr * 1.7) ** 2))
        warp += np.sign(du + 1e-3) * push * kr * 1.25
        heart = np.maximum(heart, np.exp(-r2 / (2.0 * (kr * 0.62) ** 2)))

    S = U + warp
    one = np.ones_like(S)
    fine = vnoise(S, one, 1.15, 1.0, seed + 11)            # 1-2 px grain lines
    broad = vnoise(S, one, 3.6, 1.0, seed + 12)            # wide colour bands
    if period:
        mott = vnoise(U, V, 4.0, period / 3, seed + 13, wrap_y=3)
        dash = vnoise(U, V, 1.0, period / 7, seed + 14, wrap_y=7)
    else:
        mott = vnoise(U, V, 5.0, 30.0, seed + 13)
        dash = vnoise(U, V, 1.0, 4.2, seed + 14)
    t = 0.18 + 0.30 * broad + 0.26 * fine + 0.14 * mott + tone
    # pores: short dark dashes that follow the grain
    pore = (dash > 0.80) & (fine < 0.45)
    t = np.where(pore, t - 0.16, t)
    # rare pale flecks (ray flake catching the oil)
    fleck = (dash < 0.07) & (fine > 0.6)
    t = np.where(fleck, t + 0.10, t)
    t = t * (1.0 - heart * 0.85) + 0.02 * heart
    rgb = _ramp_map(P.WALNUT, np.clip(t, 0.0, 0.92))
    _put(c, rgb, mask)


def shade_rows(c: Canvas, rows: dict[int, float]) -> None:
    """Multiply whole rows (local y -> factor)."""
    for y, f in rows.items():
        if 0 <= y < c.h:
            c.a[y, :, :3] = np.clip(np.rint(c.a[y, :, :3].astype(np.float32) * f), 0, 255).astype(np.uint8)


def shade_cols(c: Canvas, cols: dict[int, float]) -> None:
    for x, f in cols.items():
        if 0 <= x < c.w:
            c.a[:, x, :3] = np.clip(np.rint(c.a[:, x, :3].astype(np.float32) * f), 0, 255).astype(np.uint8)


def shade_px(c: Canvas, x: int, y: int, f: float) -> None:
    if 0 <= x < c.w and 0 <= y < c.h:
        c.a[y, x, :3] = np.clip(np.rint(c.a[y, x, :3].astype(np.float32) * f), 0, 255).astype(np.uint8)


def shade_box(c: Canvas, x: int, y: int, w: int, h: int, f: float) -> None:
    x0, y0 = max(0, x), max(0, y)
    x1, y1 = min(c.w, x + w), min(c.h, y + h)
    if x1 > x0 and y1 > y0:
        c.a[y0:y1, x0:x1, :3] = np.clip(np.rint(
            c.a[y0:y1, x0:x1, :3].astype(np.float32) * f), 0, 255).astype(np.uint8)


# ---------------------------------------------------------------------------
# brushed champagne aluminium
# ---------------------------------------------------------------------------

def aluminium(c: Canvas, seed: int = 31, level: float = 0.60, sheen: float = 1.0,
              fixed_origin=None, direction: str = "h", win_w: int = 275,
              win_h: int = 116, mask=None, streak: float = 1.0) -> None:
    """Horizontally brushed champagne aluminium.

    Streak contrast stays inside one ramp step; the broad vertical sheen band
    (brushed metal smears a light source *across* the brushing) does the work.
    ``fixed_origin`` overrides the canvas origin (for sprites that are reused
    at several window positions and so must not key off their position).
    """
    seed = seed + WINDOW_SEED.get(c.window, 0)
    if fixed_origin is None:
        X, Y = grid(c)
    else:
        xs = np.arange(c.w, dtype=np.float32) + fixed_origin[0]
        ys = np.arange(c.h, dtype=np.float32) + fixed_origin[1]
        X, Y = np.meshgrid(xs, ys)
    if direction == "v":
        A, B = Y, X       # A along the brushing, B across it
    else:
        A, B = X, Y
    rowseed = np.floor(B)
    long_ = vnoise(A + rowseed * 37.3, rowseed, 26.0, 1.0, seed + 1)
    mid = vnoise(A + rowseed * 11.7, rowseed, 7.0, 1.0, seed + 2)
    short = vnoise(A + rowseed * 5.1, rowseed, 2.2, 1.0, seed + 3)
    rowtone = _hash01(np.zeros_like(rowseed), rowseed, seed + 4)
    s = (long_ - 0.5) * 0.085 + (mid - 0.5) * 0.06 + (short - 0.5) * 0.03 \
        + (rowtone - 0.5) * 0.035
    # vertical sheen bands (functions of x) + a gentle top-to-bottom fall-off
    fx_ = X / float(win_w)
    band = np.exp(-((fx_ - 0.30) / 0.17) ** 2) * 0.13 \
        + np.exp(-((fx_ - 0.83) / 0.10) ** 2) * 0.06 \
        - np.exp(-((fx_ - 0.60) / 0.14) ** 2) * 0.05
    fall = (0.5 - Y / float(win_h)) * 0.10
    t = level + s * streak + (band + fall) * sheen
    rgb = _ramp_map(P.ALU, t)
    _put(c, rgb, mask)


# ---------------------------------------------------------------------------
# black glass and black plastic
# ---------------------------------------------------------------------------

def glass(c: Canvas, rect=None) -> None:
    v = c if rect is None else c.sub(rect)
    v.fill(P.GLASS_FLAT)


def glare(c: Canvas, x0: float, slope: float = -0.55, width: float = 9.0,
          strength: float = 0.20, mask=None, colour=P.GLARE) -> None:
    """A diagonal glare streak across static glass, in window coords: the band
    is centred on the line ``x = x0 + slope * y``."""
    X, Y = grid(c)
    d = np.abs(X - (x0 + slope * Y)) / float(width)
    band = np.clip(1.0 - d, 0, 1) ** 1.5 * strength
    d2 = np.abs(X - (x0 + width * 1.9 + slope * Y)) / (width * 0.28)
    band = np.maximum(band, np.clip(1.0 - d2, 0, 1) ** 1.5 * strength * 0.6)
    col = np.array(parse_colour(colour)[:3], dtype=np.float32)
    cur = c.a[:, :, :3].astype(np.float32)
    out = cur + (col - cur) * band[:, :, None]
    if mask is not None:
        out = np.where(mask[:, :, None], out, cur)
    c.a[:, :, :3] = np.clip(np.rint(out), 0, 255).astype(np.uint8)


def plastic(c: Canvas, rect=None, level: float = 0.42, seed: int = 5,
            pressed: bool = False) -> None:
    """Matte black control plastic: fine speckle, soft top-lit gradient."""
    v = c if rect is None else c.sub(rect)
    X, Y = grid(v)
    n = _hash01(X.astype(np.int64), Y.astype(np.int64), seed + 900)
    yy = (np.arange(v.h, dtype=np.float32) / max(1, v.h - 1))[:, None]
    t = level + (0.5 - yy) * (0.22 if not pressed else -0.10) + (n - 0.5) * 0.10
    if pressed:
        t = t - 0.14
    _put(v, _ramp_map(P.PLASTIC, t))


# ---------------------------------------------------------------------------
# light
# ---------------------------------------------------------------------------

def bloom(c: Canvas, cx: float, cy: float, colour, radius: float = 3.0,
          strength: float = 0.6, aspect: float = 1.0, mask=None) -> None:
    """Light spilling from a lamp onto whatever is already painted (screen-ish
    blend, smooth falloff).  ``cx, cy`` are local coords."""
    xs = np.arange(c.w, dtype=np.float32)
    ys = np.arange(c.h, dtype=np.float32)
    X, Y = np.meshgrid(xs, ys)
    d = np.sqrt(((X - cx) / aspect) ** 2 + (Y - cy) ** 2) / float(radius)
    f = np.clip(1.0 - d, 0, 1) ** 2 * float(strength)
    if mask is not None:
        f = f * mask
    col = np.array(parse_colour(colour)[:3], dtype=np.float32)
    cur = c.a[:, :, :3].astype(np.float32)
    out = cur + (col - cur * 0.35) * f[:, :, None]
    c.a[:, :, :3] = np.clip(np.rint(out), 0, 255).astype(np.uint8)


def glow_mask(c: Canvas, m: np.ndarray, colour, strength: float = 0.35,
              diag: float = 0.5, keep=None) -> None:
    """One-pixel phosphor halo around the lit pixels of ``m`` (bool mask).
    Never touches the lit pixels themselves or pixels in ``keep``."""
    f = np.zeros(m.shape, dtype=np.float32)
    mm = m.astype(np.float32)
    pad = np.pad(mm, 1)
    h, w = m.shape
    orth = pad[0:h, 1:w + 1] + pad[2:h + 2, 1:w + 1] + pad[1:h + 1, 0:w] + pad[1:h + 1, 2:w + 2]
    dg = pad[0:h, 0:w] + pad[0:h, 2:w + 2] + pad[2:h + 2, 0:w] + pad[2:h + 2, 2:w + 2]
    f = np.clip(orth * 1.0 + dg * diag, 0, 2.2) / 2.2
    f = np.sqrt(f) * float(strength)
    f[m] = 0.0
    if keep is not None:
        f[keep] = 0.0
    col = np.array(parse_colour(colour)[:3], dtype=np.float32)
    cur = c.a[:, :, :3].astype(np.float32)
    out = cur + (col - cur) * f[:, :, None]
    c.a[:, :, :3] = np.clip(np.rint(out), 0, 255).astype(np.uint8)


# ---------------------------------------------------------------------------
# hardware
# ---------------------------------------------------------------------------

def chrome_ring(c: Canvas, x: int, y: int, w: int, h: int, glints=True) -> None:
    """A 1 px chrome trim ring standing proud: bright top/left, mid bottom/right,
    hand-placed white glints, and a dark reflection break on the top run."""
    hi, mid, lo = P.CHROME[2], P.CHROME[1], P.CHROME[0]
    x1, y1 = x + w - 1, y + h - 1
    c.hline(x, x1, y, hi)
    c.vline(x, y, y1, hi)
    c.hline(x, x1, y1, mid)
    c.vline(x1, y, y1, mid)
    c.px(x1, y, mid)
    c.px(x, y1, mid)
    if glints:
        c.px(x, y, P.CHROME[3])
        c.px(x + 1, y, P.CHROME[3])
        c.px(x, y + 1, P.CHROME[3])
        c.px(x1, y1, P.CHROME[2])
        # reflection breaks: chrome mirrors the dark room in short runs
        for k, fx in enumerate((0.36, 0.71)):
            bx = x + int(w * fx)
            c.hline(bx, bx + 5 + k * 3, y, mid)
            c.px(bx + 6 + k * 3, y, P.CHROME[3])
        bx = x + int(w * 0.18)
        c.hline(bx, bx + 7, y1, lo)
        c.px(bx + 8, y1, hi)


def screw(c: Canvas, cx: int, cy: int, angle: int = 0, big: bool = False) -> None:
    """Countersunk slotted screw in aluminium.  The countersink is *recessed*:
    its top-left inner wall is in shadow, its bottom-right lip catches light."""
    ring_sh, ring_hi = P.ALU[0], P.ALU[6]
    head, head_hi, head_lo = P.ALU[4], P.CHROME[3], P.ALU[1]
    slot = "#15120c"
    if not big:
        pts = [(-1, -2), (0, -2), (1, -2), (-2, -1), (2, -1), (-2, 0), (2, 0),
               (-2, 1), (2, 1), (-1, 2), (0, 2), (1, 2)]
        for dx, dy in pts:
            lit = (dx + dy) > 0
            edge = (dx + dy) == 0
            c.px(cx + dx, cy + dy, ring_hi if lit else (P.ALU[2] if edge else ring_sh))
        c.box(cx - 1, cy - 1, 3, 3, head)
        c.px(cx - 1, cy - 1, head_hi)
        c.px(cx + 1, cy + 1, head_lo)
        a = angle % 180
        if a == 0:
            c.hline(cx - 1, cx + 1, cy, slot)
        elif a == 90:
            c.vline(cx, cy - 1, cy + 1, slot)
        elif a == 45:
            for k in (-1, 0, 1):
                c.px(cx + k, cy - k, slot)
        else:
            for k in (-1, 0, 1):
                c.px(cx + k, cy + k, slot)
        return
    # 7x7
    for dy in range(-3, 4):
        for dx in range(-3, 4):
            r2 = dx * dx + dy * dy
            if r2 > 10:
                continue
            if r2 >= 8 or (abs(dx) == 3 or abs(dy) == 3):
                lit = (dx + dy) > 0
                c.px(cx + dx, cy + dy, ring_hi if lit else (P.ALU[2] if dx + dy == 0 else ring_sh))
            else:
                tcol = head
                if dx + dy <= -2:
                    tcol = P.ALU[5]
                elif dx + dy >= 2:
                    tcol = P.ALU[2]
                c.px(cx + dx, cy + dy, tcol)
    c.px(cx - 1, cy - 2, head_hi)
    a = angle % 180
    for k in (-2, -1, 0, 1, 2):
        if a == 0:
            c.px(cx + k, cy, slot)
        elif a == 90:
            c.px(cx, cy + k, slot)
        elif a == 45:
            c.px(cx + k, cy - k, slot)
        else:
            c.px(cx + k, cy + k, slot)
    # lit lower lip of the slot
    if a == 0:
        c.hline(cx - 1, cx + 1, cy + 1, P.ALU[6])
    elif a == 90:
        c.vline(cx + 1, cy - 1, cy + 1, P.ALU[6])


def jewel(c: Canvas, cx: int, cy: int, on: bool, r: int = 2, colour: str = "amber",
          halo: float = 1.0) -> None:
    """A faceted jewel pilot lamp in a chrome collar.  ``r`` 1 (3x3 bead) or
    2 (5x5 bead).  Off = dark glassy bead with one cold glint; on = near-white
    core, saturated body, warm halo spilling onto whatever surrounds it."""
    ramp = {"amber": P.PILOT, "red": ["#2e0906", P.RED[1], P.RED[2], P.RED_CORE],
            "teal": [P.TEAL[0], P.TEAL[2], P.TEAL[3], P.TEAL[4]]}[colour]
    if on:
        bloom(c, cx, cy, ramp[2], radius=r + 4.2, strength=0.55 * halo)
    if r >= 2:
        # collar
        for dx, dy in [(-1, -2), (0, -2), (1, -2), (-2, -1), (-2, 0), (-2, 1)]:
            c.px(cx + dx, cy + dy, P.CHROME[1] if on else P.CHROME[1])
        for dx, dy in [(2, -1), (2, 0), (2, 1), (-1, 2), (0, 2), (1, 2)]:
            c.px(cx + dx, cy + dy, P.CHROME[2])
        c.px(cx - 2, cy - 2 + 1, P.CHROME[0])
        c.px(cx - 1, cy - 2, P.CHROME[0])
        if on:
            c.box(cx - 1, cy - 1, 3, 3, ramp[2])
            c.px(cx, cy, ramp[3])
            c.px(cx - 1, cy - 1, ramp[3])
            c.px(cx, cy - 1, "#ffe9a8" if colour == "amber" else ramp[3])
            c.px(cx - 1, cy, "#ffe9a8" if colour == "amber" else ramp[3])
            c.px(cx + 1, cy + 1, ramp[1])
        else:
            c.box(cx - 1, cy - 1, 3, 3, ramp[0])
            c.px(cx + 1, cy + 1, "#120802" if colour == "amber" else "#020808")
            c.px(cx, cy + 1, "#241003" if colour == "amber" else ramp[0])
            c.px(cx - 1, cy - 1, "#8a7a66")            # cold window glint
            c.px(cx + 1, cy, ramp[1] if colour != "amber" else "#5a2c06")
    else:
        for dx, dy in [(0, -1), (-1, 0)]:
            c.px(cx + dx, cy + dy, P.CHROME[0])
        for dx, dy in [(1, 0), (0, 1)]:
            c.px(cx + dx, cy + dy, P.CHROME[2])
        c.px(cx, cy, ramp[3] if on else ramp[0])


def engrave_line_h(c: Canvas, x0: int, x1: int, y: int) -> None:
    """A machined hairline groove in aluminium: dark line, lit lower lip."""
    c.hline(x0, x1, y, P.ALU[0])
    c.hline(x0, x1, y + 1, P.ALU[6])


def engrave_line_v(c: Canvas, x: int, y0: int, y1: int) -> None:
    c.vline(x, y0, y1, P.ALU[0])
    c.vline(x + 1, y0, y1, P.ALU[6])
