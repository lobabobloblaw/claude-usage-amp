"""Bulkhead -- materials, shading primitives and hardware.

Everything here paints into a skinkit ``Canvas`` through its ``.a`` array and
samples textures in *window* coordinates (``c.ox`` / ``c.oy``), so a widget cut
out of a background reproduces the same pixels.  Light is top-left, always.
"""

from __future__ import annotations

import math

import numpy as np

import bh_palette as P

# ---------------------------------------------------------------------------
# deterministic noise (own implementation so tiles can wrap)
# ---------------------------------------------------------------------------


def _hash01(ix, iy, seed: int):
    n = (ix.astype(np.int64) * np.int64(73856093)
         ^ iy.astype(np.int64) * np.int64(19349663)
         ^ np.int64(seed) * np.int64(83492791))
    n &= np.int64(0xFFFFFFFF)
    n ^= (n >> np.int64(15))
    n = (n * np.int64(2246822519)) & np.int64(0xFFFFFFFF)
    n ^= (n >> np.int64(13))
    n = (n * np.int64(3266489917)) & np.int64(0xFFFFFFFF)
    n ^= (n >> np.int64(16))
    return (n & np.int64(0xFFFFFF)).astype(np.float32) / float(0xFFFFFF)


def grid(c):
    xs = np.arange(c.w, dtype=np.float32) + c.ox
    ys = np.arange(c.h, dtype=np.float32) + c.oy
    return np.meshgrid(xs, ys)


def vnoise(X, Y, sx: float, sy: float, seed: int, wrapx: int | None = None,
           wrapy: int | None = None):
    """Smooth value noise, 0..1.  ``wrapx``/``wrapy`` = lattice cells per period."""
    gx, gy = X / sx, Y / sy
    ix, iy = np.floor(gx), np.floor(gy)
    tx, ty = gx - ix, gy - iy
    tx = tx * tx * (3 - 2 * tx)
    ty = ty * ty * (3 - 2 * ty)
    ix = ix.astype(np.int64)
    iy = iy.astype(np.int64)

    def H(i, j):
        if wrapx:
            i = np.mod(i, wrapx)
        if wrapy:
            j = np.mod(j, wrapy)
        return _hash01(i, j, seed)

    a = H(ix, iy) + (H(ix + 1, iy) - H(ix, iy)) * tx
    b = H(ix, iy + 1) + (H(ix + 1, iy + 1) - H(ix, iy + 1)) * tx
    return a + (b - a) * ty


def fbm(X, Y, scale: float, seed: int, octaves: int = 3, wrapx=None, wrapy=None,
        sx=None, sy=None):
    tot = np.zeros_like(X)
    amp, norm = 1.0, 0.0
    bx = scale if sx is None else sx
    by = scale if sy is None else sy
    wx, wy = wrapx, wrapy
    for o in range(octaves):
        tot += amp * vnoise(X, Y, bx, by, seed + o * 131, wx, wy)
        norm += amp
        amp *= 0.5
        bx /= 2.0
        by /= 2.0
        wx = wx * 2 if wx else None
        wy = wy * 2 if wy else None
    return tot / norm


def grain(X, Y, seed: int):
    return _hash01(X.astype(np.int64), Y.astype(np.int64), seed)


# ---------------------------------------------------------------------------
# low level pixel helpers (all clip, all alpha-blend)
# ---------------------------------------------------------------------------

def _col(col):
    if isinstance(col, str):
        return P.hx(col)
    return (int(col[0]), int(col[1]), int(col[2]))


def box(c, x, y, w, h, col, a: float = 1.0):
    x0, y0 = max(0, int(x)), max(0, int(y))
    x1, y1 = min(c.w, int(x) + int(w)), min(c.h, int(y) + int(h))
    if x1 <= x0 or y1 <= y0:
        return
    col = np.array(_col(col), dtype=np.float32)
    if a >= 1.0:
        c.a[y0:y1, x0:x1, :3] = col.astype(np.uint8)
    else:
        cur = c.a[y0:y1, x0:x1, :3].astype(np.float32)
        c.a[y0:y1, x0:x1, :3] = np.clip(np.rint(cur + (col - cur) * a), 0, 255).astype(np.uint8)
    c.a[y0:y1, x0:x1, 3] = 255


def pset(c, x, y, col, a: float = 1.0):
    box(c, x, y, 1, 1, col, a)


def hl(c, x0, x1, y, col, a: float = 1.0):
    """Horizontal line, inclusive ends."""
    if x1 < x0:
        x0, x1 = x1, x0
    box(c, x0, y, x1 - x0 + 1, 1, col, a)


def vl(c, x, y0, y1, col, a: float = 1.0):
    """Vertical line, inclusive ends."""
    if y1 < y0:
        y0, y1 = y1, y0
    box(c, x, y0, 1, y1 - y0 + 1, col, a)


def outline(c, x, y, w, h, col, a: float = 1.0):
    hl(c, x, x + w - 1, y, col, a)
    hl(c, x, x + w - 1, y + h - 1, col, a)
    vl(c, x, y + 1, y + h - 2, col, a)
    vl(c, x + w - 1, y + 1, y + h - 2, col, a)


def blend_mask(c, mask, col, x: int = 0, y: int = 0):
    """Blend ``col`` over the canvas with a float (h, w) alpha ``mask`` placed at x, y."""
    mh, mw = mask.shape
    x0, y0 = max(0, x), max(0, y)
    x1, y1 = min(c.w, x + mw), min(c.h, y + mh)
    if x1 <= x0 or y1 <= y0:
        return
    m = mask[y0 - y:y1 - y, x0 - x:x1 - x][:, :, None].astype(np.float32)
    colv = np.array(_col(col), dtype=np.float32)
    cur = c.a[y0:y1, x0:x1, :3].astype(np.float32)
    c.a[y0:y1, x0:x1, :3] = np.clip(np.rint(cur + (colv - cur) * m), 0, 255).astype(np.uint8)


def put_rgb(c, rgbarr, mask=None, x: int = 0, y: int = 0):
    """Write an (h, w, 3) float/uint8 array, optionally through a bool/float mask."""
    h, w = rgbarr.shape[:2]
    x0, y0 = max(0, x), max(0, y)
    x1, y1 = min(c.w, x + w), min(c.h, y + h)
    if x1 <= x0 or y1 <= y0:
        return
    src = np.asarray(rgbarr, dtype=np.float32)[y0 - y:y1 - y, x0 - x:x1 - x]
    if mask is None:
        c.a[y0:y1, x0:x1, :3] = np.clip(np.rint(src), 0, 255).astype(np.uint8)
    else:
        m = np.asarray(mask, dtype=np.float32)[y0 - y:y1 - y, x0 - x:x1 - x][:, :, None]
        cur = c.a[y0:y1, x0:x1, :3].astype(np.float32)
        c.a[y0:y1, x0:x1, :3] = np.clip(np.rint(cur + (src - cur) * m), 0, 255).astype(np.uint8)
    c.a[y0:y1, x0:x1, 3] = 255


def tone_rgb(tone, lut, levels: int | None = 40):
    """Map a 0..1 tone field through a ramp LUT, quantised to keep it crisp."""
    t = np.clip(tone, 0.0, 1.0)
    if levels:
        t = np.rint(t * levels) / levels
    idx = np.clip(np.rint(t * (len(lut) - 1)).astype(int), 0, len(lut) - 1)
    return lut[idx]


def stamp(c, x, y, rows, legend, a: float = 1.0):
    """Hand-placed pixels: ``rows`` of characters, ``legend`` char -> colour
    (or ``(colour, alpha)``); unknown characters are transparent."""
    for j, row in enumerate(rows):
        for i, ch in enumerate(row):
            v = legend.get(ch)
            if v is None:
                continue
            if isinstance(v, tuple) and len(v) == 2 and not isinstance(v[0], int):
                pset(c, x + i, y + j, v[0], v[1] * a)
            else:
                pset(c, x + i, y + j, v, a)


def shade(c, x, y, w, h, a: float):
    box(c, x, y, w, h, P.SHADOW, a)


def light(c, x, y, w, h, a: float):
    box(c, x, y, w, h, P.HILITE, a)


# ---------------------------------------------------------------------------
# gunmetal plate
# ---------------------------------------------------------------------------

def plate_tone(c, seed: int = 0, base: float = 0.47, wrapx_px: int | None = None,
               wrapy_px: int | None = None, y_phase: int = 0, vgrad: float = 0.035):
    """Tone field (0..1 along the GUN ramp) of the machined, worn gunmetal plate.

    Fine horizontal machining marks + blotchy fbm wear + a little grain.  With
    ``wrapx_px`` / ``wrapy_px`` the field is seamlessly periodic along that
    axis (playlist tiles)."""
    X, Y = grid(c)
    Y = Y - y_phase
    if wrapx_px:
        Xw = np.mod(X, wrapx_px)
    else:
        Xw = X
    if wrapy_px:
        Yw = np.mod(Y, wrapy_px)
    else:
        Yw = Y
    # long machining streaks: per-row values drifting slowly along x
    if wrapx_px:
        m1 = vnoise(Xw, Yw, wrapx_px, 1.0, seed + 1, wrapx=1, wrapy=wrapy_px)
        m2 = vnoise(Xw, Yw, wrapx_px / 5.0, 1.0, seed + 2, wrapx=5, wrapy=wrapy_px)
    else:
        m1 = vnoise(Xw, Yw, 41.0, 1.0, seed + 1, wrapy=wrapy_px)
        m2 = vnoise(Xw, Yw, 7.0, 1.0, seed + 2, wrapy=wrapy_px)
    # blotchy wear
    if wrapx_px or wrapy_px:
        sx = (wrapx_px / 2.0) if wrapx_px else 19.0
        sy = (wrapy_px / 2.0) if wrapy_px else 15.0
        wear = fbm(Xw, Yw, 0, seed + 3, octaves=3, sx=sx, sy=sy,
                   wrapx=2 if wrapx_px else None, wrapy=2 if wrapy_px else None)
    else:
        wear = fbm(Xw, Yw, 0, seed + 3, octaves=3, sx=23.0, sy=15.0)
    g = grain(Xw, Yw, seed + 4)
    t = (base + (m1 - 0.5) * 0.085 + (m2 - 0.5) * 0.05
         + (wear - 0.5) * 0.17 + (g - 0.5) * 0.035)
    if vgrad and c.window in ("main", "eq") and not wrapy_px:
        t = t + vgrad * (1.0 - 2.0 * (Y / 116.0))
    return t.astype(np.float32)


def plate(c, seed: int = 0, base: float = 0.47, **kw):
    put_rgb(c, tone_rgb(plate_tone(c, seed, base, **kw), P.GUN_LUT))


def steel_tone(c, seed: int = 0, base: float = 0.55, direction: str = "h", strength: float = 1.0,
               local: bool = False):
    """Bare brushed steel (machined parts, bezels, knobs)."""
    X, Y = grid(c)
    if local:
        X = X - c.ox
        Y = Y - c.oy
    if direction == "h":
        m1 = vnoise(X, Y, 17.0, 1.0, seed + 11)
        m2 = vnoise(X, Y, 4.0, 1.0, seed + 12)
    else:
        m1 = vnoise(X, Y, 1.0, 17.0, seed + 11)
        m2 = vnoise(X, Y, 1.0, 4.0, seed + 12)
    t = base + ((m1 - 0.5) * 0.11 + (m2 - 0.5) * 0.07) * strength
    return t.astype(np.float32)


def steel(c, x, y, w, h, seed: int = 0, base: float = 0.55, direction: str = "h",
          strength: float = 1.0, local: bool = False):
    v = c.sub(int(x), int(y), int(w), int(h))
    put_rgb(v, tone_rgb(steel_tone(v, seed, base, direction, strength, local), P.STEEL_LUT, 48))


def rubber(c, x, y, w, h, seed: int = 0, base: float = 0.42, local: bool = False):
    """Rubberised keycap / gasket: matte, faint stipple."""
    v = c.sub(int(x), int(y), int(w), int(h))
    X, Y = grid(v)
    if local:
        X = X - v.ox
        Y = Y - v.oy
    g = grain(X, Y, seed + 21)
    b = vnoise(X, Y, 5.0, 5.0, seed + 22)
    t = base + (g - 0.5) * 0.09 + (b - 0.5) * 0.06
    put_rgb(v, tone_rgb(t, P.RUBBER_LUT, 32))


# ---------------------------------------------------------------------------
# chipped paint
# ---------------------------------------------------------------------------

def paint_layer(c, x, y, w, h, lut=None, seed: int = 0, base: float = 0.52, chip: float = 0.5,
                edge_bias: float = 0.35, under_seed: int | None = None, grime: float = 1.0,
                keep=None):
    """A coat of paint over whatever is already on the canvas, chipped back to
    the metal underneath.  Chips get a core shadow on their top/left rim (the
    paint film stands proud of the steel) and a lit paint lip on bottom/right.

    ``chip`` raises/lowers how much is chipped; ``edge_bias`` adds chipping
    toward the rectangle's border.  ``keep`` is an optional bool mask (h, w) of
    pixels that may be painted at all."""
    lut = P.ORANGE_LUT if lut is None else lut
    x, y, w, h = int(x), int(y), int(w), int(h)
    v = c.sub(x, y, w, h)
    X, Y = grid(v)
    n = fbm(X, Y, 0, seed + 31, octaves=3, sx=6.5, sy=5.0)
    n2 = grain(X, Y, seed + 32)
    # distance to the border of the painted rect, 0 at the edge
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy))
    edge = np.clip(1.0 - d / 3.0, 0, 1)
    score = n + edge * edge_bias + (n2 - 0.5) * 0.10
    painted = score < (1.0 - chip * 0.42)
    if keep is not None:
        painted &= np.asarray(keep, dtype=bool)
    # paint tone: dirty, mottled, vertical grime streaks
    mott = fbm(X, Y, 0, seed + 33, octaves=2, sx=9.0, sy=13.0)
    streak = vnoise(X, Y, 1.6, 23.0, seed + 34)
    t = base + (mott - 0.5) * 0.20 * grime + (streak - 0.5) * 0.12 * grime + (n2 - 0.5) * 0.05
    rgb = tone_rgb(t, lut, 36)
    # bare steel inside the chips reads lighter than the plate: lift it a little
    chips = ~painted
    if keep is not None:
        chips &= np.asarray(keep, dtype=bool)
    cur = v.a[:, :, :3].astype(np.float32)
    lift = np.array(P.STEEL[3], dtype=np.float32)
    cur[chips] = cur[chips] + (lift - cur[chips]) * 0.38
    out = np.where(painted[:, :, None], rgb, cur)
    # relief: chip pixel whose up or left neighbour is paint -> core shadow
    up = np.zeros_like(painted)
    up[1:, :] = painted[:-1, :]
    left = np.zeros_like(painted)
    left[:, 1:] = painted[:, :-1]
    sh = chips & (up | left)
    out[sh] = out[sh] * 0.45 + np.array(P.SHADOW, dtype=np.float32) * 0.55
    # paint pixel whose up or left neighbour is a chip -> lit lip of the film
    upc = np.zeros_like(painted)
    upc[1:, :] = chips[:-1, :]
    leftc = np.zeros_like(painted)
    leftc[:, 1:] = chips[:, :-1]
    lip = painted & (upc | leftc)
    hi = tone_rgb(np.clip(t + 0.22, 0, 1), lut, 36)
    out[lip] = hi[lip]
    v.a[:, :, :3] = np.clip(np.rint(out), 0, 255).astype(np.uint8)
    return painted


def hazard(c, x, y, w, h, width: int = 4, seed: int = 0, chip: float = 0.35, phase: int = 0,
           slope: int = 1, keep=None):
    """Diagonal hazard striping, painted (so it chips and gets dirty)."""
    x, y, w, h = int(x), int(y), int(w), int(h)
    v = c.sub(x, y, w, h)
    X, Y = grid(v)
    k = np.mod(np.floor(X + slope * Y + phase), 2 * width) < width
    n = fbm(X, Y, 0, seed + 41, octaves=2, sx=5.0, sy=4.0)
    g = grain(X, Y, seed + 42)
    ty = 0.62 + (n - 0.5) * 0.30 + (g - 0.5) * 0.08
    tk = 0.45 + (n - 0.5) * 0.30 + (g - 0.5) * 0.10
    rgb = np.where(k[:, :, None], tone_rgb(ty, P.HAZ_Y_LUT, 24), tone_rgb(tk, P.HAZ_K_LUT, 24))
    painted = (n + (g - 0.5) * 0.2) < (1.0 - chip * 0.45)
    if keep is not None:
        painted &= np.asarray(keep, dtype=bool)
    cur = v.a[:, :, :3].astype(np.float32)
    out = np.where(painted[:, :, None], rgb, cur)
    v.a[:, :, :3] = np.clip(np.rint(out), 0, 255).astype(np.uint8)


# ---------------------------------------------------------------------------
# bevel / depth primitives (light top-left)
# ---------------------------------------------------------------------------

def raised(c, x, y, w, h, hi=None, lo=None, a_hi: float = 0.55, a_lo: float = 0.6,
           contact: int = 1, a_contact: float = 0.42):
    """Edge treatment of something standing proud: 1px lit top/left, 1px core
    shadow bottom/right, plus a soft contact shadow cast down-right."""
    hi = P.HILITE if hi is None else hi
    lo = P.SHADOW if lo is None else lo
    if contact:
        for k in range(contact, 0, -1):
            a = a_contact * (1.0 if k == 1 else 0.45)
            hl(c, x + k, x + w - 1 + k, y + h - 1 + k, P.SHADOW, a)
            vl(c, x + w - 1 + k, y + k, y + h - 2 + k, P.SHADOW, a)
    hl(c, x, x + w - 2, y, hi, a_hi)
    vl(c, x, y + 1, y + h - 2, hi, a_hi * 0.8)
    hl(c, x + 1, x + w - 1, y + h - 1, lo, a_lo)
    vl(c, x + w - 1, y + 1, y + h - 2, lo, a_lo * 0.85)
    pset(c, x + w - 1, y, P.mixc(_col(hi), _col(lo), 0.5), 0.35)
    pset(c, x, y + h - 1, P.mixc(_col(hi), _col(lo), 0.5), 0.35)


def recessed(c, x, y, w, h, depth: int = 2, a_sh: float = 0.75, a_lip: float = 0.35):
    """Edge treatment of a hole: inner shadow on top/left, lit lip bottom/right.
    (x, y, w, h) is the *interior* of the hole; the lip is drawn just outside."""
    # outer lip: bottom/right catch light, top/left go dark
    hl(c, x - 1, x + w, y + h, P.HILITE, a_lip)
    vl(c, x + w, y - 1, y + h - 1, P.HILITE, a_lip * 0.8)
    hl(c, x - 1, x + w - 1, y - 1, P.SHADOW, 0.7)
    vl(c, x - 1, y, y + h, P.SHADOW, 0.6)
    for k in range(depth):
        a = a_sh * (1.0 - k / depth) ** 1.3
        hl(c, x + k, x + w - 1, y + k, P.SHADOW, a)
        vl(c, x + k, y + k + 1, y + h - 1, P.SHADOW, a * 0.85)


def round_mask(w: int, h: int, r: int = 2):
    """Bool mask of a w x h rounded rectangle (pixel-art corners, radius 1..3)."""
    m = np.ones((h, w), dtype=bool)
    cuts = {0: [], 1: [1], 2: [2, 1], 3: [3, 2, 1, 1], 4: [4, 3, 2, 1, 1]}[r]
    for j, n in enumerate(cuts):
        if j >= h:
            break
        m[j, :n] = False
        m[j, w - n:] = False
        m[h - 1 - j, :n] = False
        m[h - 1 - j, w - n:] = False
    return m


# ---------------------------------------------------------------------------
# fasteners
# ---------------------------------------------------------------------------

HEX_HEADS = {
    # flats top/bottom, points left/right (0 deg)
    0: ["..5555..",
        ".644443.",
        "66444433",
        "64444443",
        "33444322",
        ".344432.",
        "..2222.."],
    # points top/bottom (30 deg)
    1: ["..64...",
        ".66443.",
        "5644433",
        "5444443",
        "5444443",
        "5344422",
        ".33422.",
        "..32..."],
    # ~15 deg
    2: ["...555..",
        ".664443.",
        "6644443.",
        "64444443",
        ".3444432",
        ".344422.",
        "..322..."],
    # ~-15 deg
    3: ["..555...",
        ".544443.",
        ".6444433",
        "64444443",
        "6344442.",
        ".334422.",
        "...222.."],
}


def hex_bolt(c, cx: int, cy: int, variant: int = 0, washer: bool = True, mark: int = 0):
    """Hand-set hex-head bolt on a dark washer.  ``variant`` 0..3 picks the head
    rotation (0, 30, +15, -15 degrees); ``mark`` varies the crown stamping."""
    rows = HEX_HEADS[variant % 4]
    hh, hw = len(rows), len(rows[0])
    x0, y0 = cx - hw // 2, cy - hh // 2
    ccx, ccy = x0 + (hw - 1) / 2.0, y0 + (hh - 1) / 2.0
    if washer:
        R = max(hw, hh) / 2.0 + 1.0
        for yy in range(int(ccy - R) - 1, int(ccy + R) + 4):
            for xx in range(int(ccx - R) - 1, int(ccx + R) + 4):
                rr = math.hypot(xx - ccx - 1.0, yy - ccy - 1.2)
                if rr <= R + 0.3:
                    pset(c, xx, yy, P.SHADOW, 0.55 if rr < R - 0.7 else 0.3)
        for yy in range(int(ccy - R) - 1, int(ccy + R) + 2):
            for xx in range(int(ccx - R) - 1, int(ccx + R) + 2):
                dx, dy = xx - ccx, yy - ccy
                rr = math.hypot(dx, dy)
                if rr <= R:
                    lit = (-dx - dy) / (1.414 * max(rr, 1e-3))
                    col = P.GUN[1]
                    if rr > R - 1.05:
                        col = P.GUN[5] if lit > 0.55 else (P.GUN[3] if lit > -0.2 else P.GUN[0])
                    pset(c, xx, yy, col)
    leg = {str(i): P.STEEL[i] for i in range(7)}
    stamp(c, x0, y0, rows, leg)
    # crown stamping (grade marks), varied per bolt
    mx, my = int(ccx), int(ccy)
    if mark % 3 == 0:
        pset(c, mx, my, P.STEEL[2])
        pset(c, mx + 1, my, P.STEEL[3])
    elif mark % 3 == 1:
        pset(c, mx, my, P.STEEL[2])
        pset(c, mx, my + 1, P.STEEL[3])
    else:
        pset(c, mx + 1, my, P.STEEL[2])
        pset(c, mx - 1, my + 1, P.STEEL[3])


def rivet(c, x: int, y: int, big: bool = False):
    """Domed rivet: 3x3 (or 4x4) with glint and a contact shadow."""
    if big:
        stamp(c, x, y, [".hH.",
                        "hWmd",
                        "Hmdk",
                        ".dk.",
                        ], {"h": P.STEEL[4], "H": P.STEEL[3], "W": P.STEEL[6], "m": P.STEEL[3],
                            "d": P.STEEL[1], "k": P.STEEL[0]})
        pset(c, x + 4, y + 2, P.SHADOW, 0.45)
        pset(c, x + 4, y + 3, P.SHADOW, 0.45)
        pset(c, x + 2, y + 4, P.SHADOW, 0.45)
        pset(c, x + 3, y + 4, P.SHADOW, 0.45)
        pset(c, x + 1, y + 4, P.SHADOW, 0.2)
        pset(c, x + 4, y + 1, P.SHADOW, 0.2)
    else:
        stamp(c, x, y, ["hm.",
                        "mWd",
                        ".dk"], {"h": P.STEEL[5], "m": P.STEEL[3], "W": P.STEEL[4],
                                 "d": P.STEEL[1], "k": P.STEEL[0]})
        pset(c, x, y, P.STEEL[6])
        pset(c, x + 3, y + 2, P.SHADOW, 0.4)
        pset(c, x + 2, y + 3, P.SHADOW, 0.4)
        pset(c, x + 3, y + 3, P.SHADOW, 0.25)


def slot_screw(c, cx: int, cy: int, slot: int = 0):
    """5x5 pan-head screw; ``slot`` 0..3 = slot at 0 / 45 / 90 / 135 degrees."""
    x, y = cx - 2, cy - 2
    stamp(c, x, y, [".hh_.",
                    "hHmmd",
                    "hmmmd",
                    "_mmdk",
                    ".ddk."], {"h": P.STEEL[5], "H": P.STEEL[6], "m": P.STEEL[3],
                               "d": P.STEEL[2], "k": P.STEEL[1], "_": P.STEEL[3]})
    sl = P.GUN[0]
    pts = {0: [(0, 2), (1, 2), (2, 2), (3, 2), (4, 2)],
           1: [(0, 4), (1, 3), (2, 2), (3, 1), (4, 0)],
           2: [(2, 0), (2, 1), (2, 2), (2, 3), (2, 4)],
           3: [(0, 0), (1, 1), (2, 2), (3, 3), (4, 4)]}[slot % 4]
    for (i, j) in pts[1:4] if slot % 2 else pts:
        pset(c, x + i, y + j, sl)
    # contact shadow
    for i, j, a in ((5, 2, .35), (5, 3, .4), (4, 4, .4), (2, 5, .35), (3, 5, .4), (4, 5, .3), (5, 4, .3)):
        pset(c, x + i, y + j, P.SHADOW, a)


def oil_streak(c, x: int, y: int, length: int, seed: int = 0, a0: float = 0.5, wobble: bool = True):
    """Oil/rust weep running *down* from a fastener: 1px, fading, slight jog."""
    rng = np.random.RandomState(seed * 7 + x * 13 + y)
    xx = x
    for k in range(length):
        a = a0 * (1.0 - k / length) ** 1.2 * (0.75 + 0.25 * rng.rand())
        pset(c, xx, y + k, P.OIL, a)
        if k < length * 0.5:
            pset(c, xx + 1, y + k, P.OIL, a * 0.35)
        if wobble and rng.rand() < 0.12 and k > 2:
            xx += rng.choice((-1, 1))


def scratch(c, x0, y0, x1, y1, a: float = 0.35):
    """A bright scratch with a dark trailing edge below it."""
    n = max(abs(x1 - x0), abs(y1 - y0))
    for i in range(n + 1):
        t = i / max(1, n)
        x = int(round(x0 + (x1 - x0) * t))
        y = int(round(y0 + (y1 - y0) * t))
        fade = math.sin(math.pi * min(1.0, max(0.0, t))) ** 0.6
        pset(c, x, y, P.STEEL[5], a * fade)
        pset(c, x, y + 1, P.SHADOW, a * 0.55 * fade)


def edge_wear(c, x, y, w, h, seed: int = 0, amount: float = 0.55, sides: str = "tlbr"):
    """Paint worn back to bright steel along the edges of a raised part:
    broken runs of light pixels, densest at corners."""
    rng = np.random.RandomState(seed + 977)

    def run(n, fn, corner_boost=True):
        i = 0
        while i < n:
            d = min(i, n - 1 - i)
            p = amount * (1.0 if d < 4 else 0.35)
            if rng.rand() < p:
                ln = rng.randint(1, 4)
                for k in range(ln):
                    if i + k < n:
                        fn(i + k, 0.35 + 0.45 * rng.rand())
                i += ln
            i += 1

    if "t" in sides:
        run(w, lambda i, a: pset(c, x + i, y, P.STEEL[5], a))
    if "l" in sides:
        run(h, lambda i, a: pset(c, x, y + i, P.STEEL[5], a * 0.85))
    if "b" in sides:
        run(w, lambda i, a: pset(c, x + i, y + h - 1, P.STEEL[3], a * 0.6))
    if "r" in sides:
        run(h, lambda i, a: pset(c, x + w - 1, y + i, P.STEEL[3], a * 0.6))


# ---------------------------------------------------------------------------
# lamps
# ---------------------------------------------------------------------------

def bloom(c, x, y, w, h, col, radius: int = 2, strength: float = 0.45, keepout=None):
    """Light spilling from a lit rect (x, y, w, h) onto its surroundings."""
    r = radius
    H, W = h + 2 * r, w + 2 * r
    m = np.zeros((H, W), dtype=np.float32)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    dx = np.maximum(np.maximum(r - xx, xx - (r + w - 1)), 0)
    dy = np.maximum(np.maximum(r - yy, yy - (r + h - 1)), 0)
    d = np.sqrt(dx * dx + dy * dy)
    m = np.clip(1.0 - d / (r + 0.6), 0, 1) ** 1.6 * strength
    m[r:r + h, r:r + w] = 0
    if keepout is not None:
        m = m * keepout
    blend_mask(c, m, col, x - r, y - r)


# ---------------------------------------------------------------------------
# mask-based relief (arbitrary shapes: L-shaped castings, rounded keys ...)
# ---------------------------------------------------------------------------

def _shift(m, dx, dy):
    out = np.zeros_like(m)
    H, W = m.shape
    ys = slice(max(0, dy), H + min(0, dy))
    yd = slice(max(0, -dy), H + min(0, -dy))
    xs = slice(max(0, dx), W + min(0, dx))
    xd = slice(max(0, -dx), W + min(0, -dx))
    out[ys, xs] = m[yd, xd]
    return out


def full_mask(c, x, y, w, h, r: int = 0):
    """Canvas-sized bool mask of a (rounded) rect."""
    m = np.zeros((c.h, c.w), dtype=bool)
    x0, y0 = max(0, x), max(0, y)
    x1, y1 = min(c.w, x + w), min(c.h, y + h)
    if x1 <= x0 or y1 <= y0:
        return m
    rm = round_mask(w, h, r) if r else np.ones((h, w), dtype=bool)
    m[y0:y1, x0:x1] = rm[y0 - y:y1 - y, x0 - x:x1 - x]
    return m


def raise_mask(c, mask, a_hi: float = 0.5, a_lo: float = 0.6, contact: int = 2,
               a_contact: float = 0.45, hi=None, lo=None):
    """Bevel an arbitrary raised shape: lit top/left rim, core shadow on the
    bottom/right rim, contact shadow cast down-right onto whatever is outside."""
    hi = P.HILITE if hi is None else hi
    lo = P.SHADOW if lo is None else lo
    inside = mask
    if contact:
        sh = np.zeros(mask.shape, dtype=np.float32)
        for k in range(contact, 0, -1):
            cast = _shift(inside, k, k) & ~inside
            sh = np.maximum(sh, cast.astype(np.float32) * a_contact * (1.0 if k == 1 else 0.5))
        blend_mask(c, sh, P.SHADOW)
    top = inside & ~_shift(inside, 0, 1)
    left = inside & ~_shift(inside, 1, 0)
    bot = inside & ~_shift(inside, 0, -1)
    right = inside & ~_shift(inside, -1, 0)
    him = np.maximum(top.astype(np.float32) * a_hi, left.astype(np.float32) * a_hi * 0.8)
    lom = np.maximum(bot.astype(np.float32) * a_lo, right.astype(np.float32) * a_lo * 0.85)
    both = (him > 0) & (lom > 0)
    him[both] *= 0.4
    lom[both] *= 0.4
    blend_mask(c, him, hi)
    blend_mask(c, lom, lo)


def sink_mask(c, mask, depth: int = 2, a_sh: float = 0.7, a_lip: float = 0.35):
    """Relief for a hole of arbitrary shape: inner shadow falling in from the
    top/left, lit lip just outside the bottom/right edge."""
    inside = mask
    lip_b = ~inside & _shift(inside, 0, 1)
    lip_r = ~inside & _shift(inside, 1, 0)
    edge_t = ~inside & _shift(inside, 0, -1)
    edge_l = ~inside & _shift(inside, -1, 0)
    blend_mask(c, np.maximum(lip_b.astype(np.float32) * a_lip,
                             lip_r.astype(np.float32) * a_lip * 0.8), P.HILITE)
    blend_mask(c, np.maximum(edge_t.astype(np.float32) * 0.6,
                             edge_l.astype(np.float32) * 0.5), P.SHADOW)
    sh = np.zeros(mask.shape, dtype=np.float32)
    for k in range(depth, 0, -1):
        a = a_sh * (1.0 - (k - 1) / depth) ** 1.2
        band = inside & (~_shift(inside, 0, k) | ~_shift(inside, k, 0))
        sh = np.where(band, np.maximum(sh, a) if k == 1 else np.where(sh > a, sh, a), sh)
    # nearest band wins (k=1 strongest)
    sh2 = np.zeros(mask.shape, dtype=np.float32)
    for k in range(1, depth + 1):
        a = a_sh * (1.0 - (k - 1) / depth) ** 1.2
        band = inside & (~_shift(inside, 0, k) | ~_shift(inside, k, 0))
        sh2 = np.where((sh2 == 0) & band, a, sh2)
    blend_mask(c, sh2, P.SHADOW)


def fill_mask(c, mask, col, a: float = 1.0):
    blend_mask(c, mask.astype(np.float32) * a, col)


def tone_fill(c, mask, tone, lut, levels: int = 40):
    """Write a tone field through ``mask`` (both canvas-sized)."""
    put_rgb(c, tone_rgb(tone, lut, levels), mask=mask.astype(np.float32))


def cast_tone(c, seed: int = 0, base: float = 0.36):
    """Cast / parkerised gunmetal for bezels: orange-peel speckle, little streak."""
    X, Y = grid(c)
    g = grain(X, Y, seed + 51)
    b = vnoise(X, Y, 3.0, 3.0, seed + 52)
    w = fbm(X, Y, 0, seed + 53, octaves=2, sx=17.0, sy=11.0)
    return (base + (g - 0.5) * 0.06 + (b - 0.5) * 0.07 + (w - 0.5) * 0.10).astype(np.float32)
