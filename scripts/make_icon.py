#!/usr/bin/env python3
"""Tokenamp macOS app icon generator.

Deterministic and re-runnable:

    python3 scripts/make_icon.py

Writes
    assets/icon/icon_1024.png
    assets/icon/preview_sizes.png
    assets/Tokenamp.iconset/*.png
    assets/Tokenamp.icns        (via /usr/bin/iconutil)

Design: a chunky front-on piece of retro hi-fi hardware in the macOS icon
idiom.  Graphite squircle faceplate with a 2-step bevel and countersunk
screws, a recessed near-black display holding a pixel-art spectrum
analyzer, and an amber "T" token medallion at the lower right.

The smooth parts (body, bevels, glare, shadows) are rendered at 3x and
downsampled with LANCZOS.  The display contents are authored on a coarse
pixel grid whose cells land exactly on final-image pixel boundaries, so
they stay crisp.  16px and 32px use a separate simplified composition.
"""

from __future__ import annotations

import math
import os
import shutil
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")
ICON_DIR = os.path.join(ASSETS, "icon")
ICONSET = os.path.join(ASSETS, "Tokenamp.iconset")
ICNS = os.path.join(ASSETS, "Tokenamp.icns")

SS = 3  # supersample for the detailed 1024 render


# --------------------------------------------------------------------------
# small numeric helpers
# --------------------------------------------------------------------------

def C(h: str) -> np.ndarray:
    """'#rrggbb' -> float32 rgb in 0..1."""
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)


def _box1d(a: np.ndarray, r: int, axis: int) -> np.ndarray:
    if r <= 0:
        return a
    k = 2 * r + 1
    pad = [(0, 0)] * a.ndim
    pad[axis] = (r, r)
    ap = np.pad(a, pad, mode="edge")
    cs = np.cumsum(ap, axis=axis, dtype=np.float64)
    zs = list(cs.shape)
    zs[axis] = 1
    cs = np.concatenate([np.zeros(zs, dtype=np.float64), cs], axis=axis)
    n = a.shape[axis]
    hi = np.take(cs, np.arange(k, k + n), axis=axis)
    lo = np.take(cs, np.arange(0, n), axis=axis)
    return ((hi - lo) / k).astype(np.float32)


def blur(a: np.ndarray, sigma: float) -> np.ndarray:
    """Three box passes ~= a gaussian of the given sigma."""
    r = int(round(sigma))
    if r < 1:
        return a.astype(np.float32, copy=True)
    out = a.astype(np.float32)
    for _ in range(3):
        out = _box1d(out, r, 0)
        out = _box1d(out, r, 1)
    return out


def shift(a: np.ndarray, dy: int, dx: int, fill: float = 0.0) -> np.ndarray:
    out = np.full_like(a, fill)
    h, w = a.shape[:2]
    ys0, ys1 = max(0, -dy), min(h, h - dy)
    yd0, yd1 = max(0, dy), min(h, h + dy)
    xs0, xs1 = max(0, -dx), min(w, w - dx)
    xd0, xd1 = max(0, dx), min(w, w + dx)
    if ys1 > ys0 and xs1 > xs0:
        out[yd0:yd1, xd0:xd1] = a[ys0:ys1, xs0:xs1]
    return out


def sstep(x: np.ndarray) -> np.ndarray:
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)


class Cv:
    """Straight-alpha RGBA canvas."""

    def __init__(self, h: int, w: int):
        self.h, self.w = h, w
        self.rgb = np.zeros((h, w, 3), np.float32)
        self.a = np.zeros((h, w), np.float32)

    def over(self, rgb, a: np.ndarray) -> None:
        if not isinstance(rgb, np.ndarray) or rgb.ndim == 1:
            rgb = np.asarray(rgb, np.float32).reshape(1, 1, 3) * np.ones(
                (self.h, self.w, 1), np.float32)
        sa = a[..., None]
        da = self.a[..., None]
        out_a = a + self.a * (1.0 - a)
        num = rgb * sa + self.rgb * da * (1.0 - sa)
        self.rgb = (num / np.maximum(out_a[..., None], 1e-6)).astype(np.float32)
        self.a = out_a.astype(np.float32)

    def add(self, rgb: np.ndarray, w: np.ndarray) -> None:
        """Additive light, only where the canvas is already opaque-ish."""
        self.rgb = np.clip(self.rgb + rgb * w[..., None], 0.0, 1.0).astype(np.float32)

    def mul(self, rgb: np.ndarray, w: np.ndarray) -> None:
        f = 1.0 - w[..., None] * (1.0 - rgb)
        self.rgb = np.clip(self.rgb * f, 0.0, 1.0).astype(np.float32)

    def to_image(self, size: int, resample=Image.LANCZOS) -> Image.Image:
        """Premultiplied downsample to `size`."""
        pm = np.clip(self.rgb * self.a[..., None], 0.0, 1.0)
        arr = np.concatenate([pm, self.a[..., None]], axis=2)
        img = Image.fromarray((arr * 255.0 + 0.5).astype(np.uint8), "RGBA")
        if size != self.w:
            img = img.resize((size, size), resample)
        p = np.asarray(img).astype(np.float32) / 255.0
        al = p[..., 3:4]
        rgb = np.where(al > 1e-4, p[..., :3] / np.maximum(al, 1e-4), 0.0)
        out = np.concatenate([np.clip(rgb, 0, 1), np.clip(al, 0, 1)], axis=2)
        return Image.fromarray((out * 255.0 + 0.5).astype(np.uint8), "RGBA")


def grid(n: int):
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    return x + 0.5, y + 0.5


# --------------------------------------------------------------------------
# shape fields
# --------------------------------------------------------------------------

def squircle(X, Y, cx, cy, a, n=5.0):
    """Returns (D, W): px distance inside the superellipse, and the
    top-left lighting weight of the outward normal (+1 .. -1)."""
    ux = (X - cx) / a
    uy = (Y - cy) / a
    au, av = np.abs(ux), np.abs(uy)
    f = au ** n + av ** n
    r = f ** (1.0 / n)
    D = (1.0 - r) * a
    gx = np.sign(ux) * au ** (n - 1.0)
    gy = np.sign(uy) * av ** (n - 1.0)
    gl = np.sqrt(gx * gx + gy * gy) + 1e-9
    W = -(gx + gy) / (gl * math.sqrt(2.0))
    return D.astype(np.float32), W.astype(np.float32)


def rbox(X, Y, x0, y0, x1, y1, rad):
    """Signed distance to a rounded box; positive inside."""
    cx, cy = (x0 + x1) * 0.5, (y0 + y1) * 0.5
    hw, hh = (x1 - x0) * 0.5, (y1 - y0) * 0.5
    qx = np.abs(X - cx) - (hw - rad)
    qy = np.abs(Y - cy) - (hh - rad)
    ax = np.maximum(qx, 0.0)
    ay = np.maximum(qy, 0.0)
    sd = np.sqrt(ax * ax + ay * ay) + np.minimum(np.maximum(qx, qy), 0.0) - rad
    return (-sd).astype(np.float32)


def cov(D: np.ndarray, aa: float) -> np.ndarray:
    """Antialiased coverage from a distance field (positive inside)."""
    return np.clip(D / aa + 0.5, 0.0, 1.0).astype(np.float32)


def disc(X, Y, cx, cy, r):
    return (r - np.sqrt((X - cx) ** 2 + (Y - cy) ** 2)).astype(np.float32)


def rect_mask(X, Y, x0, y0, x1, y1, aa):
    return (cov(np.minimum(X - x0, x1 - X), aa) *
            cov(np.minimum(Y - y0, y1 - Y), aa)).astype(np.float32)


# --------------------------------------------------------------------------
# palette
# --------------------------------------------------------------------------

BODY_TOP = C("#3d434b")
BODY_BOT = C("#16181c")
SCREEN_TOP = C("#050b08")
SCREEN_BOT = C("#0a1610")

BAR_STOPS = [
    (0.00, C("#10c93f")),
    (0.30, C("#2ff055")),
    (0.50, C("#7cf73e")),
    (0.64, C("#f2e335")),
    (0.80, C("#ff9614")),
    (1.00, C("#ff2f14")),
]
CAP_COL = C("#eafff1")

COIN_LIT = C("#ffd65e")
COIN_MID = C("#ffa21f")
COIN_DEEP = C("#e0640c")
COIN_RIM_HI = C("#ffcf7c")
COIN_RIM_LO = C("#772d02")
T_DARK = C("#3a1505")


def bar_color(t: float) -> np.ndarray:
    t = min(max(t, 0.0), 1.0)
    for i in range(len(BAR_STOPS) - 1):
        a, ca = BAR_STOPS[i]
        b, cb = BAR_STOPS[i + 1]
        if t <= b or i == len(BAR_STOPS) - 2:
            u = 0.0 if b == a else (t - a) / (b - a)
            u = min(max(u, 0.0), 1.0)
            return ca * (1.0 - u) + cb * u
    return BAR_STOPS[-1][1]


# --------------------------------------------------------------------------
# shared pieces
# --------------------------------------------------------------------------

def paint_body(cv, X, Y, cx, cy, a, aa, *, detail: bool, brush_seed: int = 7):
    """Shadow + graphite squircle + 2-step bevel.  Returns (D, W, body_a)."""
    n = 5.0
    D, W = squircle(X, Y, cx, cy, a, n)

    # ---- drop shadow ----------------------------------------------------
    sh_off = a * 0.0305          # ~12.6px at 1024
    sh_sig = a * 0.049           # ~20px
    sh = cov(D + a * 0.008, aa)
    sh = shift(sh, int(round(sh_off)), 0)
    sh = blur(sh, sh_sig)
    cv.over(np.zeros(3, np.float32), np.clip(sh * 0.34, 0, 1))
    # a tighter contact shadow
    sh2 = blur(shift(cov(D, aa), int(round(a * 0.012)), 0), a * 0.013)
    cv.over(np.zeros(3, np.float32), np.clip(sh2 * 0.26, 0, 1))

    body_a = cov(D, aa)

    # ---- plate -----------------------------------------------------------
    t = np.clip((Y - (cy - a)) / (2.0 * a), 0.0, 1.0)[..., None]
    plate = (BODY_TOP.reshape(1, 1, 3) * (1.0 - t) + BODY_BOT.reshape(1, 1, 3) * t)
    # broad soft sheen sweeping from the top-left
    sheen = sstep(1.0 - (((X - cx) / a) * 0.45 + ((Y - cy) / a) * 0.9 + 0.55))
    plate = plate + (sheen * 0.032)[..., None]

    if detail:
        rng = np.random.default_rng(brush_seed)
        h, w = X.shape
        noise = rng.standard_normal((h, w)).astype(np.float32)
        noise = _box1d(noise, max(1, int(a * 0.075)), 1)   # smear along x
        noise = _box1d(noise, max(1, int(a * 0.0015)), 0)
        noise /= (np.abs(noise).max() + 1e-6)
        rows = rng.standard_normal((h, 1)).astype(np.float32)
        rows = _box1d(rows, 2, 0)
        rows /= (np.abs(rows).max() + 1e-6)
        plate = plate + (noise * 0.030 + rows * 0.012)[..., None]

    cv.over(np.clip(plate, 0, 1).astype(np.float32), body_a)

    # ---- 2-step bevel ----------------------------------------------------
    pos = np.clip(W, 0, 1)
    neg = np.clip(-W, 0, 1)
    if detail:
        edge_w, lip_w, riser_c, riser_s = a * 0.0145, a * 0.041, a * 0.046, a * 0.0115
        hi_s, lo_s = 0.45, 0.46
    else:
        edge_w, lip_w, riser_c, riser_s = a * 0.058, a * 0.11, 0.0, 0.0
        hi_s, lo_s = 0.32, 0.34
    # 1. crisp outer highlight right on the rim
    edge = (np.clip(1.0 - D / edge_w, 0.0, 1.0) ** 1.15) * body_a
    cv.over(np.ones(3, np.float32), np.clip(edge * pos * hi_s, 0, 1))
    cv.over(np.zeros(3, np.float32), np.clip(edge * neg * lo_s, 0, 1))
    # 2. the lip surface itself, a touch lighter than the face
    lipm = np.clip(1.0 - D / lip_w, 0, 1) * body_a
    cv.over(np.ones(3, np.float32), np.clip(lipm * 0.055, 0, 1))
    # 3. the riser down to the face: inverted lighting reads as a step
    if riser_s > 0:
        riser = np.exp(-(((D - riser_c) / riser_s) ** 2)) * body_a
        cv.over(np.zeros(3, np.float32), np.clip(riser * pos * 0.44, 0, 1))
        cv.over(np.ones(3, np.float32), np.clip(riser * neg * 0.22, 0, 1))

    return D, W, body_a


def paint_recess(cv, X, Y, x0, y0, x1, y1, rad, aa, scale, top, bot):
    """A window cut into the plate: dark interior, inner shadow, lit lower
    rim.  Returns the interior mask."""
    D = rbox(X, Y, x0, y0, x1, y1, rad)
    m = cov(D, aa)

    # outer groove: dark above-left, light below-right of the opening
    ring = np.clip(1.0 - np.abs(D) / (scale * 0.009), 0, 1)
    out = 1.0 - m
    cv.over(np.zeros(3, np.float32), np.clip(ring * out * 0.55, 0, 1))
    lit = shift(cov(D, aa), int(scale * 0.006), int(scale * 0.005))
    cv.over(np.ones(3, np.float32),
            np.clip(np.clip(1.0 - np.abs(rbox(X, Y, x0, y0, x1, y1, rad)) /
                            (scale * 0.006), 0, 1) * (1.0 - lit) * 0.30, 0, 1))

    # interior
    t = np.clip((Y - y0) / max(y1 - y0, 1.0), 0, 1)[..., None]
    inner = top.reshape(1, 1, 3) * (1.0 - t) + bot.reshape(1, 1, 3) * t
    cv.over(np.clip(inner, 0, 1).astype(np.float32), m)

    # inner shadow from the top-left
    sh = blur(shift(1.0 - m, int(scale * 0.009), int(scale * 0.007)), scale * 0.011)
    cv.over(np.zeros(3, np.float32), np.clip(sh * m * 0.85, 0, 1))
    sh2 = blur(1.0 - m, scale * 0.020)
    cv.over(np.zeros(3, np.float32), np.clip(sh2 * m * 0.45, 0, 1))
    return m


def paint_coin(cv, X, Y, cx, cy, r, aa, *, detail: bool, t_rects=None, rim=0.875):
    """Amber token medallion with a bevelled rim and a slab T."""
    d = disc(X, Y, cx, cy, r)
    m = cov(d, aa)

    # cast shadow
    sh = blur(shift(cov(disc(X, Y, cx, cy, r * 1.02), aa),
                    int(r * 0.10), int(r * 0.03)), r * 0.10)
    cv.over(np.zeros(3, np.float32), np.clip(sh * 0.55, 0, 1))

    dx = (X - cx) / r
    dy = (Y - cy) / r
    rr = np.sqrt(dx * dx + dy * dy) + 1e-9
    w = -(dx + dy) / (rr * math.sqrt(2.0))          # +1 top-left

    # rim
    cv.over(np.clip(COIN_RIM_LO.reshape(1, 1, 3) +
                    (COIN_RIM_HI - COIN_RIM_LO).reshape(1, 1, 3) *
                    np.clip((w * 0.5 + 0.5), 0, 1)[..., None], 0, 1).astype(np.float32), m)

    # face
    fr = r * rim
    fm = cov(disc(X, Y, cx, cy, fr), aa)
    q = np.clip(np.sqrt(((X - cx) ** 2 + (Y - cy) ** 2)) / fr, 0, 1)
    ramp = np.clip(0.5 - 0.5 * (dx * 0.80 + dy * 0.80), 0, 1) ** 0.85
    face = (COIN_DEEP.reshape(1, 1, 3) * (1.0 - ramp[..., None]) +
            COIN_LIT.reshape(1, 1, 3) * ramp[..., None])
    face = face * (1.0 - 0.16 * (q ** 3)[..., None])
    face = face + (COIN_MID.reshape(1, 1, 3) - face) * 0.18
    cv.over(np.clip(face, 0, 1).astype(np.float32), fm)
    # face inner shadow under the rim (top-left)
    ish = blur(shift(1.0 - fm, int(r * 0.055), int(r * 0.045)), r * 0.05)
    cv.over(np.zeros(3, np.float32), np.clip(ish * fm * 0.55, 0, 1))
    ihl = blur(shift(1.0 - fm, -int(r * 0.05), -int(r * 0.04)), r * 0.05)
    cv.over(np.ones(3, np.float32), np.clip(ihl * fm * 0.28, 0, 1))
    # secondary catch-light on the lower-right of the rim (polished metal)
    ring = np.clip(m - fm, 0, 1)
    cv.over(np.ones(3, np.float32), np.clip(ring * (np.clip(-w, 0, 1) ** 2.8) * 0.22, 0, 1))
    if detail:
        gl = np.clip(1.0 - np.sqrt((X - (cx - r * 0.34)) ** 2 +
                                   (Y - (cy - r * 0.40)) ** 2) / (r * 0.62), 0, 1) ** 2
        cv.over(np.ones(3, np.float32), np.clip(gl * fm * 0.30, 0, 1))

    # the T
    if t_rects is None:
        dd = 2.0 * r
        t_rects = [
            (cx - 0.310 * dd, cy - 0.255 * dd, cx + 0.310 * dd, cy - 0.085 * dd),
            (cx - 0.105 * dd, cy - 0.085 * dd, cx + 0.105 * dd, cy + 0.258 * dd),
        ]
    tm = np.zeros_like(m)
    for (a0, b0, a1, b1) in t_rects:
        tm = np.maximum(tm, rect_mask(X, Y, a0, b0, a1, b1, aa))
    off = max(1, int(round(r * 0.045)))
    tlo = shift(tm, off, off)
    cv.over(np.ones(3, np.float32), np.clip(np.clip(tlo - tm, 0, 1) * fm * 0.55, 0, 1))
    cv.over(T_DARK, np.clip(tm * fm, 0, 1))
    thi = shift(tm, -max(1, off // 2), -max(1, off // 2))
    cv.over(np.zeros(3, np.float32),
            np.clip(np.clip(thi - tm, 0, 1) * fm * 0.28, 0, 1))


def fill(rgb_l, a_l, x0, y0, x1, y1, color, alpha=1.0):
    """Hard-edged integer rectangle into a layer (pixel-art parts)."""
    x0, y0, x1, y1 = int(x0), int(y0), int(x1), int(y1)
    if x1 <= x0 or y1 <= y0:
        return
    rgb_l[y0:y1, x0:x1] = color
    a_l[y0:y1, x0:x1] = alpha


def draw_analyzer(rgb_l, a_l, k, x0, baseline, bw, gap, cell, rows,
                  heights, caps, seg_gap, cap_h=None, cap_tint=0.45):
    """Pixel-grid spectrum bars + floating peak caps."""
    if cap_h is None:
        cap_h = cell - seg_gap
    for i, h in enumerate(heights):
        bx = x0 + i * (bw + gap)
        for row in range(h):
            top = baseline - (row + 1) * cell
            col = bar_color(row / max(rows - 1, 1))
            fill(rgb_l, a_l, bx * k, (top + seg_gap) * k,
                 (bx + bw) * k, (baseline - row * cell) * k, col)
        cr = caps[i]
        if cr is not None and cr >= h:
            top = baseline - (cr + 1) * cell
            col = (bar_color(cr / max(rows - 1, 1)) * cap_tint +
                   CAP_COL * (1.0 - cap_tint))
            fill(rgb_l, a_l, bx * k, (top + seg_gap) * k,
                 (bx + bw) * k, (top + seg_gap + cap_h) * k, col)


# --------------------------------------------------------------------------
# the detailed icon (64 px and up)
# --------------------------------------------------------------------------

# 1024-space geometry
BODY_C, BODY_A = 512.0, 412.0
DX0, DY0, DX1, DY1 = 164, 210, 860, 776      # display opening
BZ = 20                                       # bezel -> interior
IX0, IY0, IX1, IY1 = DX0 + BZ, DY0 + BZ, DX1 - BZ, DY1 - BZ
CELL = 24
BAR_W, BAR_GAP = 48, 24
BAR_X0, BAR_BASE, BAR_ROWS = 200, 672, 16
SEG_GAP = 6
HEIGHTS = [6, 12, 9, 14, 4, 11, 13, 7, 10]
CAPS = [8, 14, 11, 15, 6, 13, 15, 9, 12]
GRV_X0, GRV_X1, GRV_Y0, GRV_Y1 = 200, 824, 704, 728
THUMB = (588, 690, 644, 742)
COIN = (772.0, 724.0, 116.0)
SCREW = 62.0
VENT = [(196, y, 340, y + 13) for y in (818, 846, 874)]


def render_detailed(ss: int = SS) -> Cv:
    n = 1024 * ss
    X, Y = grid(n)
    k = float(ss)
    X = X / k
    Y = Y / k                      # work in 1024-space, sample at ss
    aa = 1.0 / k * 1.1
    cv = Cv(n, n)

    D, W, body_a = paint_body(cv, X, Y, BODY_C, BODY_C, BODY_A, aa,
                              detail=True)

    # ---- screws ---------------------------------------------------------
    lo, hi = 100.0 + SCREW, 924.0 - SCREW
    for cx, cy, ang in ((lo, lo, 0.55), (hi, lo, -0.35),
                        (lo, hi, -0.90), (hi, hi, 0.25)):
        rh = 21.0
        hole = cov(disc(X, Y, cx, cy, rh), aa)
        dxs = (X - cx) / rh
        dys = (Y - cy) / rh
        rs = np.sqrt(dxs * dxs + dys * dys) + 1e-9
        ws = -(dxs + dys) / (rs * math.sqrt(2.0))
        cv.over(np.zeros(3, np.float32), np.clip(hole * 0.55, 0, 1))
        ring = np.clip(rs, 0, 1) ** 2.0
        cv.over(np.zeros(3, np.float32), np.clip(hole * ring * np.clip(ws, 0, 1) * 0.75, 0, 1))
        cv.over(np.ones(3, np.float32), np.clip(hole * ring * np.clip(-ws, 0, 1) * 0.40, 0, 1))
        hd = cov(disc(X, Y, cx, cy, rh * 0.70), aa)
        tt = np.clip((Y - (cy - rh)) / (2 * rh), 0, 1)[..., None]
        head = (C("#767d86").reshape(1, 1, 3) * (1 - tt) +
                C("#3c4249").reshape(1, 1, 3) * tt)
        cv.over(np.clip(head, 0, 1).astype(np.float32), hd)
        ca, sa_ = math.cos(ang), math.sin(ang)
        xr = (X - cx) * ca + (Y - cy) * sa_
        yr = -(X - cx) * sa_ + (Y - cy) * ca
        slot = cov(np.minimum(rh * 0.075 - np.abs(yr), rh * 0.52 - np.abs(xr)), aa)
        cv.over(np.zeros(3, np.float32), np.clip(slot * hd * 0.72, 0, 1))
        cv.over(np.ones(3, np.float32), np.clip(shift(slot, 3, 3) * hd * 0.22, 0, 1))

    # ---- engraved vent slots, bottom left --------------------------------
    for (vx0, vy0, vx1, vy1) in VENT:
        vm = cov(rbox(X, Y, vx0, vy0, vx1, vy1, 6.0), aa)
        cv.over(np.zeros(3, np.float32), np.clip(vm * 0.62, 0, 1))
        lit = np.clip(shift(vm, -5, -4) - vm, 0, 1)
        cv.over(np.ones(3, np.float32), np.clip(lit * 0.16, 0, 1))

    # ---- display --------------------------------------------------------
    dm = paint_recess(cv, X, Y, DX0, DY0, DX1, DY1, 30.0, aa, 1024.0,
                      SCREEN_TOP, SCREEN_BOT)

    # vignette inside the glass
    vx = np.clip(np.abs(X - (DX0 + DX1) / 2) / ((DX1 - DX0) / 2), 0, 1)
    vy = np.clip(np.abs(Y - (DY0 + DY1) / 2) / ((DY1 - DY0) / 2), 0, 1)
    vig = np.clip((vx ** 3 + vy ** 3) * 0.55, 0, 1)
    cv.over(np.zeros(3, np.float32), np.clip(vig * dm * 0.55, 0, 1))

    # ---- pixel-art layer -------------------------------------------------
    rgb_l = np.zeros((n, n, 3), np.float32)
    a_l = np.zeros((n, n), np.float32)
    draw_analyzer(rgb_l, a_l, ss, BAR_X0, BAR_BASE, BAR_W, BAR_GAP, CELL,
                  BAR_ROWS, HEIGHTS, CAPS, SEG_GAP, cap_h=12,
                  cap_tint=0.15)
    # seek groove: recessed slot, dim green fill up to the thumb
    tx0, ty0, tx1, ty1 = THUMB
    fill(rgb_l, a_l, GRV_X0 * ss, GRV_Y0 * ss, GRV_X1 * ss, GRV_Y1 * ss, C("#0b1712"))
    fill(rgb_l, a_l, GRV_X0 * ss, GRV_Y0 * ss, GRV_X1 * ss, (GRV_Y0 + 6) * ss, C("#02070a"))
    fill(rgb_l, a_l, GRV_X0 * ss, (GRV_Y1 - 6) * ss, GRV_X1 * ss, GRV_Y1 * ss, C("#2a4a38"))
    fill(rgb_l, a_l, GRV_X0 * ss, (GRV_Y0 + 6) * ss, (tx0 + 28) * ss, (GRV_Y1 - 6) * ss,
         C("#1d9c4a"))
    # thumb
    fill(rgb_l, a_l, tx0 * ss, ty0 * ss, tx1 * ss, ty1 * ss, C("#93a5b2"))
    fill(rgb_l, a_l, tx0 * ss, ty0 * ss, tx1 * ss, (ty0 + 10) * ss, C("#eef4f9"))
    fill(rgb_l, a_l, tx0 * ss, (ty1 - 10) * ss, tx1 * ss, ty1 * ss, C("#3e4a54"))
    fill(rgb_l, a_l, (tx0 + 22) * ss, (ty0 + 14) * ss, (tx0 + 34) * ss, (ty1 - 14) * ss,
         C("#2e3840"))

    # bloom, under the bars
    pm = rgb_l * a_l[..., None]
    cx0, cy0 = int((DX0 - 40) * ss), int((DY0 - 40) * ss)
    cx1, cy1 = int((DX1 + 40) * ss), int((DY1 + 40) * ss)
    sub = pm[cy0:cy1, cx0:cx1]
    g = np.zeros_like(sub)
    for c in range(3):
        g[..., c] = (blur(sub[..., c], 9.0 * ss) * 0.85 +
                     blur(sub[..., c], 26.0 * ss) * 0.55)
    dsub = dm[cy0:cy1, cx0:cx1][..., None]
    cv.rgb[cy0:cy1, cx0:cx1] = np.clip(
        cv.rgb[cy0:cy1, cx0:cx1] + g * dsub, 0, 1).astype(np.float32)
    del pm, sub, g

    cv.over(rgb_l, np.clip(a_l * dm, 0, 1))
    del rgb_l, a_l

    # ---- glass ----------------------------------------------------------
    s = ((X - DX0) * 0.80 + (Y - DY0) * 1.0) / (DX1 - DX0)
    wedge = sstep((0.46 - s) / 0.22)
    streak = np.exp(-(((s - 0.60) / 0.055) ** 2))
    cv.over(np.ones(3, np.float32), np.clip((wedge * 0.030 + streak * 0.042) * dm, 0, 1))

    # ---- medallion -------------------------------------------------------
    paint_coin(cv, X, Y, COIN[0], COIN[1], COIN[2], aa, detail=True)
    return cv


# --------------------------------------------------------------------------
# the simplified icon (16 and 32 px)
# --------------------------------------------------------------------------

SMALL = {
    16: dict(
        k=16, margin=1.5, disp=(3.0, 3.0, 13.0, 10.0), rad=1.5, bez=1.0,
        bar_x0=4, base=9, bw=2, gap=1, rows=5,
        heights=[2, 4, 3], caps=[3, 4, 4],
        coin=(10.5, 10.5, 3.0), rim=0.90,
        trects=[(9.0, 9.0, 12.0, 10.0), (10.0, 10.0, 11.0, 12.0)],
        groove=None,
    ),
    32: dict(
        k=8, margin=3.0, disp=(6.0, 5.0, 26.0, 21.0), rad=3.0, bez=1.0,
        bar_x0=7, base=18, bw=3, gap=2, rows=12,
        heights=[7, 11, 5, 9], caps=[9, 12, 8, 11],
        coin=(22.0, 22.0, 6.4), rim=0.88,
        trects=[(18.0, 19.0, 26.0, 21.0), (21.0, 21.0, 23.0, 25.0)],
        groove=(8, 24, 19, 20, 16),
    ),
}


def render_small(S: int) -> Cv:
    cfg = SMALL[S]
    k = cfg["k"]
    n = S * k
    X, Y = grid(n)
    X = X / k
    Y = Y / k
    aa = 1.0 / k * 1.1
    cv = Cv(n, n)

    m = cfg["margin"]
    c = S / 2.0
    paint_body(cv, X, Y, c, c, c - m, aa, detail=False)

    dx0, dy0, dx1, dy1 = cfg["disp"]
    dm = paint_recess(cv, X, Y, dx0, dy0, dx1, dy1, cfg["rad"], aa, float(S),
                      SCREEN_TOP, SCREEN_BOT)

    rgb_l = np.zeros((n, n, 3), np.float32)
    a_l = np.zeros((n, n), np.float32)
    draw_analyzer(rgb_l, a_l, k, cfg["bar_x0"], cfg["base"], cfg["bw"],
                  cfg["gap"], 1, cfg["rows"], cfg["heights"], cfg["caps"], 0,
                  cap_tint=0.0)
    if cfg["groove"]:
        gx0, gx1, gy0, gy1, gfill = cfg["groove"]
        fill(rgb_l, a_l, gx0 * k, gy0 * k, gx1 * k, gy1 * k, C("#0c1a12"))
        fill(rgb_l, a_l, gx0 * k, gy0 * k, gfill * k, gy1 * k, C("#1d9c4a"))

    pm = rgb_l * a_l[..., None]
    g = np.zeros_like(pm)
    for ch in range(3):
        g[..., ch] = blur(pm[..., ch], 0.9 * k) * 0.75
    cv.rgb = np.clip(cv.rgb + g * dm[..., None], 0, 1).astype(np.float32)
    del pm, g

    cv.over(rgb_l, np.clip(a_l * dm, 0, 1))
    del rgb_l, a_l

    ccx, ccy, cr = cfg["coin"]
    paint_coin(cv, X, Y, ccx, ccy, cr, aa, detail=False,
               t_rects=cfg["trects"], rim=cfg["rim"])
    return cv


# --------------------------------------------------------------------------
# outputs
# --------------------------------------------------------------------------

ICONSET_FILES = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]


def build() -> dict:
    os.makedirs(ICON_DIR, exist_ok=True)
    if os.path.isdir(ICONSET):
        shutil.rmtree(ICONSET)
    os.makedirs(ICONSET)

    big = render_detailed()
    sizes: dict[int, Image.Image] = {}
    for s in (1024, 512, 256, 128, 64):
        sizes[s] = big.to_image(s)
    del big
    for s in (32, 16):
        # exact k x k area average: keeps the 1-px pixel art pixel-perfect
        sizes[s] = render_small(s).to_image(s, Image.BOX)

    sizes[1024].save(os.path.join(ICON_DIR, "icon_1024.png"))
    for name, s in ICONSET_FILES:
        sizes[s].save(os.path.join(ICONSET, name))
    return sizes


def _font(sz: int):
    for p in ("/System/Library/Fonts/Supplemental/Arial Bold.ttf",
              "/System/Library/Fonts/Supplemental/Arial.ttf",
              "/System/Library/Fonts/Menlo.ttc"):
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, sz)
            except Exception:
                pass
    try:
        return ImageFont.load_default(size=sz)
    except Exception:
        return ImageFont.load_default()


def build_preview(sizes: dict) -> None:
    row_a = [16, 32, 64, 128, 256, 512, 1024]
    row_b = [16, 32, 64]
    pad, gap = 36, 22
    cw_a = [max(s, 56) for s in row_a]          # keep labels from colliding
    cw_b = [max(s * 4, 96) for s in row_b]
    wa = sum(cw_a) + gap * (len(row_a) - 1)
    wb = sum(cw_b) + gap * (len(row_b) - 1)
    inner = max(wa, wb)
    W = inner + pad * 2
    ha, hb = 1024, 256
    panel_h = pad + 32 + ha + 8 + 24 + 30 + hb + 8 + 24 + pad
    H = panel_h * 2

    out = Image.new("RGB", (W, H), (232, 232, 232))
    d = ImageDraw.Draw(out)
    f = _font(17)
    fb = _font(22)

    for pi, (bg, fg) in enumerate(((0xE8E8E8, (40, 40, 40)),
                                   (0x1E1E1E, (225, 225, 225)))):
        y0 = pi * panel_h
        d.rectangle([0, y0, W, y0 + panel_h],
                    fill=((bg >> 16) & 255, (bg >> 8) & 255, bg & 255))
        d.text((pad, y0 + pad),
               "actual size  ·  %s background (#%06x)" %
               ("light" if pi == 0 else "dark", bg), fill=fg, font=fb)
        a_base = y0 + pad + 32 + ha
        x = pad + (inner - wa) // 2
        for s, cw in zip(row_a, cw_a):
            out.paste(sizes[s], (x + (cw - s) // 2, a_base - s), sizes[s])
            d.text((x, a_base + 8), "%d px" % s, fill=fg, font=f)
            x += cw + gap
        t2 = a_base + 8 + 24
        d.text((pad, t2), "4x nearest-neighbour", fill=fg, font=fb)
        b_base = t2 + 30 + hb
        x = pad + (inner - wb) // 2
        for s, cw in zip(row_b, cw_b):
            im = sizes[s].resize((s * 4, s * 4), Image.NEAREST)
            out.paste(im, (x + (cw - s * 4) // 2, b_base - s * 4), im)
            d.text((x, b_base + 8), "%d px @4x" % s, fill=fg, font=f)
            x += cw + gap

    out.save(os.path.join(ICON_DIR, "preview_sizes.png"))


def main() -> int:
    sizes = build()
    build_preview(sizes)
    if os.path.exists(ICNS):
        os.remove(ICNS)
    r = subprocess.run(["/usr/bin/iconutil", "-c", "icns", ICONSET, "-o", ICNS],
                       capture_output=True, text=True)
    if r.stdout.strip():
        print(r.stdout.strip())
    if r.stderr.strip():
        print(r.stderr.strip(), file=sys.stderr)
    if r.returncode != 0 or not os.path.exists(ICNS):
        print("iconutil failed", file=sys.stderr)
        return 1
    print("wrote %s (%d bytes)" % (ICNS, os.path.getsize(ICNS)))
    print("wrote %s" % os.path.join(ICON_DIR, "icon_1024.png"))
    print("wrote %s" % os.path.join(ICON_DIR, "preview_sizes.png"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
