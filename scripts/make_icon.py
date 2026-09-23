#!/usr/bin/env python3
"""Tokenamp macOS app icon generator.

Deterministic and re-runnable (needs only numpy and Pillow, not the app):

    python3 scripts/make_icon.py

Writes
    assets/icon/icon_1024.png
    assets/icon/preview_sizes.png
    assets/Tokenamp.iconset/*.png
    assets/Tokenamp.icns        (via /usr/bin/iconutil)

Design: the player itself.  A miniature Tokenamp main window in the Walnut 76
skin, hand-drawn as pixel art in the skin's own colours: wood title bar with
the cream TOKENAMP plate and window keys, wood side rails, a black display
with the countdown -02:47 in LCD digits (unlit segments ghosted), visualiser
bars with red peaks and the SESSION / 43% / LIVE readout, the volume and
balance sliders with EQ/PL keys, and the row of cream transport keys.  It sits
on a deep-teal squircle tile on Apple's macOS grid (body 824/1024, drop shadow
in the canvas margin, so Tahoe shows it as is) and casts a soft shadow.
No gloss, no badge, no logos.

The window is too wide (275x116) to be drawn honestly at icon sizes: it would
land on whole pixels only at 512 and 1024, where it fills two thirds of the
tile, and the Dock would swap compositions as it magnifies.  So every size
shows the same drawing at a whole-pixel scale, filling ~83% of the tile width:
    128 / 256 / 512 / 1024   the 86x46 sprite at 1x / 2x / 4x / 8x;
    64    a 44x24 re-draw: plate, play mark, 2:47, bars, sliders, keys;
    32    a 22x13 mark: title stripe with plate, 2:47, bars, key row;
    16    a 10x7 mark: wood stripe with plate, display with bars, key strip.
The tile is rendered smooth (supersampled, box-averaged); the sprite is
pasted on top at an integer position with nearest-neighbour, so its pixels
stay hard at every size.
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

    def to_image(self, size: int) -> Image.Image:
        """Premultiplied box downsample to `size` (exact k x k averages)."""
        pm = np.clip(self.rgb * self.a[..., None], 0.0, 1.0)
        arr = np.concatenate([pm, self.a[..., None]], axis=2)
        img = Image.fromarray((arr * 255.0 + 0.5).astype(np.uint8), "RGBA")
        if size != self.w:
            img = img.resize((size, size), Image.BOX)
        p = np.asarray(img).astype(np.float32) / 255.0
        al = p[..., 3:4]
        rgb = np.where(al > 1e-4, p[..., :3] / np.maximum(al, 1e-4), 0.0)
        out = np.concatenate([np.clip(rgb, 0, 1), np.clip(al, 0, 1)], axis=2)
        return Image.fromarray((out * 255.0 + 0.5).astype(np.uint8), "RGBA")


def grid(n: int):
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    return x + 0.5, y + 0.5


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


def cov(D: np.ndarray, aa: float) -> np.ndarray:
    """Antialiased coverage from a distance field (positive inside)."""
    return np.clip(D / aa + 0.5, 0.0, 1.0).astype(np.float32)


def rect_mask(X, Y, x0, y0, x1, y1, aa):
    return (cov(np.minimum(X - x0, x1 - X), aa) *
            cov(np.minimum(Y - y0, y1 - Y), aa)).astype(np.float32)


# --------------------------------------------------------------------------
# the tile
# --------------------------------------------------------------------------

TILE_TOP = C("#175a5c")
TILE_BOT = C("#0a3033")
BODY_A = 412.0 / 1024.0          # squircle half-size as a fraction of the canvas


def render_tile(S: int, player: tuple[int, int, int, int], ss: int) -> Image.Image:
    """Shadowed teal squircle with a soft shadow under the player rect
    (x0, y0, x1, y1 in final pixels).  Rendered at ss x and box-averaged."""
    n = S * ss
    X, Y = grid(n)
    X = X / ss
    Y = Y / ss                       # final-pixel space, sampled at ss
    aa = 1.1 / ss
    u = S / 1024.0                   # one 1024-space pixel in final pixels
    k = float(ss)                    # final pixel -> sample
    cv = Cv(n, n)
    a = BODY_A * S
    c = S / 2.0
    D, W = squircle(X, Y, c, c, a, 5.0)

    # drop shadow in the canvas margin, as on Apple's macOS icon grid
    sh = cov(D + a * 0.008, aa)
    sh = shift(sh, int(round(a * 0.0305 * k)), 0)
    sh = blur(sh, a * 0.049 * k)
    cv.over(np.zeros(3, np.float32), np.clip(sh * 0.34, 0, 1))
    sh2 = blur(shift(cov(D, aa), int(round(a * 0.012 * k)), 0), a * 0.013 * k)
    cv.over(np.zeros(3, np.float32), np.clip(sh2 * 0.26, 0, 1))

    body = cov(D, aa)
    t = np.clip((Y - (c - a)) / (2.0 * a), 0.0, 1.0)[..., None]
    plate = TILE_TOP.reshape(1, 1, 3) * (1.0 - t) + TILE_BOT.reshape(1, 1, 3) * t
    cv.over(plate.astype(np.float32), body)

    # a hairline of light on the upper rim, a touch of dark on the lower one
    edge = np.clip(1.0 - D / max(3.0 * u, 0.6), 0, 1) * body
    cv.over(np.ones(3, np.float32), np.clip(edge * np.clip(W, 0, 1) * 0.16, 0, 1))
    cv.over(np.zeros(3, np.float32), np.clip(edge * np.clip(-W, 0, 1) * 0.12, 0, 1))

    # the player's shadow on the tile: a wide soft one and a tight contact one
    x0, y0, x1, y1 = player
    pm = rect_mask(X, Y, x0, y0, x1, y1, aa)
    soft = blur(shift(pm, int(round(20 * u * k)), 0), max(22 * u * k, 1.0))
    cv.over(np.zeros(3, np.float32), np.clip(soft * body * 0.50, 0, 1))
    tight = blur(shift(pm, max(int(round(5 * u * k)), 1), 0), max(5 * u * k, 1.0))
    cv.over(np.zeros(3, np.float32), np.clip(tight * body * 0.40, 0, 1))
    return cv.to_image(S)


# --------------------------------------------------------------------------
# the player, drawn on its final pixel grid
# --------------------------------------------------------------------------

# Walnut 76 colours, sampled from the skin's render.
PAL = {
    "1": "#cc9867",   # wood, top highlight
    "2": "#aa6e39",   # wood, light grain
    "3": "#824c20",   # wood
    "4": "#633416",   # wood, dark
    "5": "#361d0c",   # wood, shadow
    "P": "#fbf7ea",   # plate / key highlight
    "p": "#ddd4bc",   # plate / faceplate cream
    "q": "#b9af95",   # cream shade
    "g": "#5d5546",   # cream, dark edge
    "K": "#1b1812",   # ink
    ".": "#050708",   # display black
    "o": "#0a2224",   # unlit LCD segment
    "t": "#0f5e60",   # dim teal
    "m": "#1c9893",   # mid teal
    "T": "#8af3e6",   # lit teal
    "R": "#ff4a30",   # peak red
    "A": "#ffb642",   # amber lamp
    "D": "#2a2c2f",   # dark key
    "e": "#8c8672",   # dark key legend
}
PAL_RGBA = {k: tuple(int(v[i:i + 2], 16) for i in (1, 3, 5)) + (255,)
            for k, v in PAL.items()}


class Px:
    """A sprite drawn with palette keys on its exact pixel grid."""

    def __init__(self, w: int, h: int, fill: str | None = None):
        self.w, self.h = w, h
        self.px = [[fill] * w for _ in range(h)]

    def rect(self, x0, y0, x1, y1, key):
        """Fill columns x0..x1-1, rows y0..y1-1."""
        for y in range(max(y0, 0), min(y1, self.h)):
            for x in range(max(x0, 0), min(x1, self.w)):
                self.px[y][x] = key

    def dot(self, x, y, key):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = key

    def stamp(self, x, y, rows, on, off=None):
        """rows: strings where '#' paints `on` and '.' paints `off`."""
        for j, row in enumerate(rows):
            for i, ch in enumerate(row):
                if ch == "#":
                    self.dot(x + i, y + j, on)
                elif ch == "." and off is not None:
                    self.dot(x + i, y + j, off)

    def text(self, x, y, s, font, on, gap=1) -> int:
        for ch in s:
            if ch == " ":
                x += 2
                continue
            g = font[ch]
            self.stamp(x, y, g, on)
            x += len(g[0]) + gap
        return x

    def image(self) -> Image.Image:
        im = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
        im.putdata([PAL_RGBA[k] if k else (0, 0, 0, 0)
                    for row in self.px for k in row])
        return im


# LCD digits.  6x9 with 2 px uprights (128), 4x7 (64), 3x5 (32).
LCD9 = {
    "8": ["######", "##..##", "##..##", "##..##", "######",
          "##..##", "##..##", "##..##", "######"],
    "0": ["######", "##..##", "##..##", "##..##", "##..##",
          "##..##", "##..##", "##..##", "######"],
    "2": ["######", "....##", "....##", "....##", "######",
          "##....", "##....", "##....", "######"],
    "4": ["##..##", "##..##", "##..##", "##..##", "######",
          "....##", "....##", "....##", "....##"],
    "7": ["######", "....##", "....##", "....##", "....##",
          "....##", "....##", "....##", "....##"],
}
LCD7 = {
    "2": ["####", "...#", "...#", "####", "#...", "#...", "####"],
    "4": ["#..#", "#..#", "#..#", "####", "...#", "...#", "...#"],
    "7": ["####", "...#", "...#", "...#", "...#", "...#", "...#"],
}
F35 = {  # 3x5 caps and figures
    "S": ["###", "#..", "###", "..#", "###"],
    "E": ["###", "#..", "##.", "#..", "###"],
    "I": ["#", "#", "#", "#", "#"],
    "O": ["###", "#.#", "#.#", "#.#", "###"],
    "N": ["#..#", "##.#", "#.##", "#..#", "#..#"],
    "2": ["###", "..#", "###", "#..", "###"],
    "3": ["###", "..#", ".##", "..#", "###"],
    "4": ["#.#", "#.#", "###", "..#", "..#"],
    "7": ["###", "..#", "..#", "..#", "..#"],
    "%": ["#.#", "..#", ".#.", "#..", "#.#"],
    "T": ["###", ".#.", ".#.", ".#.", ".#."],
    "K": ["#.#", "#.#", "##.", "#.#", "#.#"],
    "A": ["###", "#.#", "###", "#.#", "#.#"],
    "M": ["#...#", "##.##", "#.#.#", "#...#", "#...#"],
    "P": ["###", "#.#", "###", "#..", "#.."],
    "L": ["#..", "#..", "#..", "#..", "###"],
    "V": ["#.#", "#.#", "#.#", "#.#", ".#."],
}


def lcd(p: Px, x, y, s, font, lit="T", ghost=None, gap=1, colon_rows=()):
    """Draw a clock string; ':' is a 1 px wide pair of dots at colon_rows."""
    for ch in s:
        if ch == ":":
            for r in colon_rows:
                p.dot(x, y + r, lit)
            x += 1 + gap
            continue
        if ghost and "8" in font:
            p.stamp(x, y, font["8"], ghost)
        g = font[ch]
        p.stamp(x, y, g, lit)
        x += len(g[0]) + gap
    return x


def wood(p: Px, x0, x1, profile, seed):
    """A horizontal wood rail: one palette key per row, plus grain."""
    for j, key in enumerate(profile):
        p.rect(x0, j, x1, j + 1, key)
    inner = range(1, len(profile) - 1)
    if len(inner) < 2:
        return
    state = seed
    for x in range(x0, x1):
        state = (state * 1103515245 + 12345) & 0x7FFFFFFF
        if state % 11 == 0:                          # a short streak
            row = 1 + (state >> 8) % (len(profile) - 2)
            key = "4" if (state >> 4) % 2 else "2"
            for dx in range(1 + (state >> 12) % 4):
                if x + dx < x1 and p.px[row][x + dx] not in ("5", "1"):
                    p.dot(x + dx, row, key)


def key(p: Px, x0, y0, x1, y1, glyph=None):
    """A cream transport key (face x0..x1-1, y0..y1-1) with a centred glyph."""
    p.rect(x0, y0, x1, y1, "p")
    p.rect(x0, y0, x1, y0 + 1, "P")
    p.rect(x0, y1 - 1, x1, y1, "q")
    if glyph:
        gw, gh = len(glyph[0]), len(glyph)
        gx = x0 + (x1 - x0 - gw + 1) // 2
        gy = y0 + (y1 - y0 - gh) // 2
        p.stamp(gx, gy, glyph, "K")


def slider(p: Px, x0, x1, y, fill_to, thumb_w, thumb_h):
    """Track row y from x0..x1-1, teal up to fill_to, thumb centred there."""
    p.rect(x0 - 1, y - 1, x1 + 1, y + 2, "K")
    p.rect(x0, y, fill_to, y + 1, "m")
    p.rect(fill_to, y, x1, y + 1, "5")
    tx = fill_to - thumb_w // 2
    ty = y - thumb_h // 2
    p.rect(tx, ty, tx + thumb_w, ty + thumb_h, "p")
    p.rect(tx, ty, tx + thumb_w, ty + 1, "P")
    p.rect(tx + thumb_w - 1, ty, tx + thumb_w, ty + thumb_h, "q")


GLYPH5 = [
    ["#...#", "#..##", "#.###", "#..##", "#...#"],   # previous
    ["#..", "##.", "###", "##.", "#.."],              # play
    ["##.##", "##.##", "##.##", "##.##", "##.##"],    # pause
    ["###", "###", "###"],                            # stop
    ["#...#", "##..#", "###.#", "##..#", "#...#"],   # next
]


def sprite_128() -> Px:
    """86x46 miniature of the main window, drawn 1:1 for 128 px."""
    W, H = 86, 46
    p = Px(W, H, "p")
    # ---- title bar, rails ----------------------------------------------
    wood(p, 0, W, ["1", "4", "3", "2", "3", "4", "5"], seed=7)
    for x, k in enumerate(["2", "3", "4"]):
        p.rect(x, 7, x + 1, H, k)
    for x, k in enumerate(["3", "4", "5"]):
        p.rect(W - 3 + x, 7, W - 2 + x, H, k)
    p.rect(3, H - 1, W - 3, H, "g")
    # title plate: TOKENAMP
    px0, px1 = 24, 62
    p.rect(px0 - 1, 0, px1 + 1, 7, "5")
    p.rect(px0, 0, px1, 7, "p")
    p.rect(px0, 0, px1, 1, "P")
    p.rect(px0, 6, px1, 7, "q")
    p.text(px0 + 2, 1, "TOKENAMP", F35, "K")
    # menu key, window keys
    p.rect(4, 2, 7, 5, "D")
    p.dot(5, 3, "p")
    for bx in (71, 75, 79):
        p.rect(bx, 2, bx + 3, 5, "D")
        p.dot(bx + 1, 3, "p")

    # ---- display --------------------------------------------------------
    p.rect(4, 8, 82, 29, "K")
    p.rect(5, 9, 81, 28, ".")
    p.rect(4, 29, 82, 30, "P")                       # lit sill

    # amber status lamp, play triangle, -02:47
    p.rect(6, 13, 7, 16, "A")
    p.stamp(8, 12, ["#..", "##.", "###", "##.", "#.."], "T")
    p.rect(13, 14, 17, 15, "T")
    lcd(p, 18, 10, "02:47", LCD9, ghost="o", colon_rows=(2, 6))

    # visualiser under the clock: 2 px bars, red peaks
    heights = [3, 5, 4, 2, 4, 6, 5, 4, 6, 3, 0, 4, 2]
    base = 27
    for i, hgt in enumerate(heights):
        bx = 7 + i * 3
        if hgt:
            p.rect(bx, base - hgt + 1, bx + 2, base + 1, "t")
            p.rect(bx, base - hgt + 1, bx + 2, base - hgt // 2 + 1, "m")
            p.rect(bx, base - hgt + 1, bx + 2, base - hgt + 2, "T")
        p.rect(bx, base - hgt - 1, bx + 2, base - hgt, "R")

    # right panel: scale ticks, SESSION, underline, 43% and LIVE lamp
    for x in range(52, 80, 3):
        p.dot(x, 10, "t")
    p.text(52, 12, "SESSION", F35, "T")
    p.rect(52, 18, 79, 19, "t")
    for x in range(52, 80, 4):
        p.dot(x, 19, "t")
    p.text(52, 21, "43%", F35, "m")
    p.dot(64, 23, "R")
    p.text(66, 21, "LIVE", F35, "R")

    # ---- slider row -----------------------------------------------------
    p.stamp(6, 33, ["###.####.##.####"], "g")      # TOKEN FLOW -- PWR
    p.dot(23, 33, "A")
    slider(p, 27, 50, 33, 40, 4, 5)
    slider(p, 54, 66, 33, 60, 4, 5)
    p.rect(69, 31, 74, 36, "D")
    p.rect(75, 31, 80, 36, "D")
    p.stamp(70, 33, ["#.##"], "e")
    p.stamp(76, 33, ["#.##"], "e")

    # ---- transport ------------------------------------------------------
    ky0, ky1 = 37, 44                                # key faces ky0..ky1-1
    p.rect(4, ky0 - 1, 45, ky1 + 1, "K")
    for i, g in enumerate(GLYPH5):
        x0 = 5 + i * 8
        key(p, x0, ky0, x0 + 7, ky1, g)
    p.rect(47, ky0 - 1, 56, ky1 + 1, "K")            # eject
    key(p, 48, ky0, 55, ky1, ["..#..", ".###.", "#####", ".....", "#####"])
    p.rect(58, ky0, 79, ky1 - 1, "D")                # CYCLE | ALERT
    p.rect(68, ky0, 69, ky1 - 1, "K")
    p.dot(60, ky0 + 3, "A")
    p.rect(62, ky0 + 3, 66, ky0 + 4, "e")
    p.rect(71, ky0 + 3, 77, ky0 + 4, "e")
    p.rect(80, ky0 + 1, 82, ky1 - 2, "K")            # knob
    return p


def sprite_64() -> Px:
    """44x24 miniature for 64 px."""
    W, H = 44, 24
    p = Px(W, H, "p")
    wood(p, 0, W, ["1", "3", "4", "5"], seed=3)
    # title plate with a line of lettering, menu key, window keys
    p.rect(12, 0, 32, 4, "p")
    p.rect(12, 0, 32, 1, "P")
    p.rect(12, 3, 32, 4, "q")
    p.stamp(14, 2, ["#.##.#.##.##.#.##"], "K")
    p.rect(2, 1, 4, 3, "D")
    for bx in (35, 38, 41):
        p.rect(bx, 1, bx + 2, 3, "D")
    p.rect(0, 4, 1, H, "2")
    p.rect(1, 4, 2, H, "4")
    p.rect(W - 2, 4, W - 1, H, "3")
    p.rect(W - 1, 4, W, H, "5")
    p.rect(2, H - 1, W - 2, H, "g")
    # display: play mark, 2:47, visualiser
    p.rect(3, 5, 41, 14, ".")
    p.rect(3, 14, 41, 15, "P")
    p.stamp(5, 7, ["#..", "##.", "###", "##.", "#.."], "T")
    lcd(p, 10, 6, "2:47", LCD7, colon_rows=(2, 4))
    for i, hgt in enumerate([3, 5, 6, 4, 6, 5, 3]):
        bx = 28 + i * 2
        p.rect(bx, 13 - hgt + 1, bx + 1, 13, "m")
        p.dot(bx, 13 - hgt + 1, "T")
        p.dot(bx, 13 - hgt, "R")
    # volume and balance sliders, EQ / PL
    slider(p, 5, 19, 17, 12, 2, 3)
    slider(p, 22, 30, 17, 27, 2, 3)
    p.rect(33, 16, 36, 19, "D")
    p.rect(37, 16, 40, 19, "D")
    # transport keys, eject
    p.rect(3, 19, 30, 23, "K")
    for i in range(5):
        key(p, 4 + i * 5, 20, 8 + i * 5, 23)
    p.rect(10, 21, 11, 22, "K")                      # play mark
    p.rect(20, 21, 22, 22, "K")                      # stop mark
    p.rect(31, 19, 37, 23, "K")
    key(p, 32, 20, 36, 23)
    p.rect(33, 21, 35, 22, "K")
    return p


def sprite_32() -> Px:
    """22x13 mark for 32 px: title stripe, 2:47, key row."""
    W, H = 22, 13
    p = Px(W, H, "p")
    p.rect(0, 0, W, 1, "2")
    p.rect(0, 1, W, 2, "4")
    p.rect(6, 0, 16, 2, "p")
    p.rect(6, 0, 16, 1, "P")
    p.rect(0, 2, 1, H, "3")
    p.rect(W - 1, 2, W, H, "4")
    p.rect(1, 2, W - 1, 9, ".")
    lcd(p, 3, 3, "2:47", F35, colon_rows=(1, 3))
    p.rect(17, 5, 18, 8, "m")
    p.rect(19, 4, 20, 8, "m")
    p.dot(17, 4, "R")
    p.dot(19, 3, "R")
    p.rect(1, 10, W - 1, 12, "K")
    for x0 in (2, 6, 10, 14):
        p.rect(x0, 10, x0 + 3, 12, "p")
    p.rect(18, 10, 20, 12, "D")
    p.rect(1, 12, W - 1, 13, "g")
    return p


def sprite_16() -> Px:
    """10x7 mark for 16 px: wood stripe with plate, display with bars."""
    W, H = 10, 7
    p = Px(W, H, "p")
    p.rect(0, 0, W, 1, "3")
    p.rect(3, 0, 7, 1, "P")
    p.rect(0, 1, 1, H, "3")
    p.rect(W - 1, 1, W, H, "4")
    p.rect(1, 1, W - 1, 5, ".")
    for x, h in ((2, 2), (4, 3), (6, 2), (7, 1)):
        p.rect(x, 5 - h, x + 1, 5, "T")
    p.rect(1, 6, W - 1, 7, "g")
    p.rect(2, 5, 8, 6, "q")
    return p


# --------------------------------------------------------------------------
# composition
# --------------------------------------------------------------------------

def place(S: int, w: int, h: int) -> tuple[int, int]:
    """Top-left of a w x h player centred in an S canvas, a hair above centre
    so the shadow below balances it."""
    x0 = (S - w) // 2
    y0 = int(round(S * 0.49 - h / 2.0))
    return x0, y0


def compose(S: int, sprite: Image.Image, ss: int) -> Image.Image:
    w, h = sprite.size
    x0, y0 = place(S, w, h)
    img = render_tile(S, (x0, y0, x0 + w, y0 + h), ss)
    img.alpha_composite(sprite, (x0, y0))
    return img


def nn(im: Image.Image, k: int) -> Image.Image:
    return im.resize((im.width * k, im.height * k), Image.NEAREST)


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

    player = sprite_128().image()
    sizes: dict[int, Image.Image] = {
        1024: compose(1024, nn(player, 8), 2),
        512: compose(512, nn(player, 4), 2),
        256: compose(256, nn(player, 2), 4),
        128: compose(128, player, 6),
        64: compose(64, sprite_64().image(), 8),
        32: compose(32, sprite_32().image(), 8),
        16: compose(16, sprite_16().image(), 16),
    }

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
    row_b = [(16, 4), (32, 4), (64, 4), (128, 2)]
    pad, gap = 36, 22
    cw_a = [max(s, 56) for s in row_a]          # keep labels from colliding
    cw_b = [max(s * k, 96) for s, k in row_b]
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
        d.text((pad, t2), "enlarged, nearest-neighbour", fill=fg, font=fb)
        b_base = t2 + 30 + hb
        x = pad + (inner - wb) // 2
        for (s, k), cw in zip(row_b, cw_b):
            im = sizes[s].resize((s * k, s * k), Image.NEAREST)
            out.paste(im, (x + (cw - s * k) // 2, b_base - s * k), im)
            d.text((x, b_base + 8), "%d px @%dx" % (s, k), fill=fg, font=f)
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
