"""Shared board construction: laminate, routed edge, LCD and LED-module shells."""

from __future__ import annotations

import numpy as np

from . import palette as P
from . import pen as pn
from .parts import M, G, T, E, S, silk

SEEDS = {"main": 41, "eq": 57, "playlist": 73, "shade": 41}


def laminate(c, window, mottle=1.0, invariant=None, pours=()):
    """Fill ``c`` with purple solder mask; ``pours`` = list of (bool-region fn, hatch)."""
    t = pn.mask_value(c, seed=SEEDS.get(window, 41), mottle=mottle, invariant=invariant)
    pn.paint_mask(c, t)
    for region, hatch in pours:
        pn.pour(c, t, region, hatch=hatch)
    return t


def region(c, polys):
    """Bool array of ``c`` covered by window-space polygons (H/V/45 outlines)."""
    from PIL import Image, ImageDraw
    img = Image.new("1", (c.w, c.h), 0)
    d = ImageDraw.Draw(img)
    for poly in polys:
        d.polygon([(x - c.ox, y - c.oy) for x, y in poly], fill=1, outline=1)
    return np.array(img, dtype=bool)


def routed_edge(p, w, h, top=True, bottom=True, left=True, right=True, x0=0, y0=0):
    """The board outline: a hairline of bare FR4 where the mask pulls back from
    the routed edge, then the mask's own lip -- lit on top/left."""
    if top:
        p.hline(x0, x0 + w - 1, y0, P.FR4[3]); p.hline(x0 + 1, x0 + w - 2, y0 + 1, M[6])
    if left:
        p.vline(x0, y0, y0 + h - 1, P.FR4[3]); p.vline(x0 + 1, y0 + 1, y0 + h - 2, M[5])
    if bottom:
        p.hline(x0, x0 + w - 1, y0 + h - 1, P.FR4[1]); p.hline(x0 + 1, x0 + w - 2, y0 + h - 2, M[1])
    if right:
        p.vline(x0 + w - 1, y0, y0 + h - 1, P.FR4[1]); p.vline(x0 + w - 2, y0 + 1, y0 + h - 2, M[1])
    if top and left:
        p.px(x0, y0, P.FR4[4])
    if bottom and right:
        p.px(x0 + w - 1, y0 + h - 1, P.FR4[0])


def tin_frame(p, x, y, w, h, t=3, seed=5):
    """A folded tin LCD frame (outer rect, ``t`` px thick) -- hollow."""
    for k in range(t):
        tone_tl = (0.92, 0.70, 0.52)[min(k, 2)]
        tone_br = (0.30, 0.44, 0.58)[min(k, 2)]
        x0, y0, x1, y1 = x + k, y + k, x + w - 1 - k, y + h - 1 - k
        for xx in range(x0, x1 + 1):
            g = (((xx * 13) % 7) - 3) * 0.012
            p.px(xx, y0, P.sample(T, tone_tl + g)); p.px(xx, y1, P.sample(T, tone_br + g))
        for yy in range(y0, y1 + 1):
            g = (((yy * 11) % 5) - 2) * 0.012
            p.px(x0, yy, P.sample(T, tone_tl - 0.06 + g)); p.px(x1, yy, P.sample(T, tone_br + g))


def frame_tab(p, x, y, up=True):
    """A twisted locking tab of the LCD frame poking through its board slot."""
    if up:
        p.box(x - 1, y - 1, 5, 3, M[0])
        p.box(x, y, 3, 2, T[4]); p.hline(x, x + 2, y, T[6]); p.px(x + 2, y + 1, T[2])
    else:
        p.box(x - 1, y - 1, 5, 3, M[0])
        p.box(x, y - 1, 3, 2, T[3]); p.hline(x, x + 2, y - 1, T[5]); p.hline(x, x + 2, y, T[1])


def lcd_window(p, x, y, w, h, glow_left=True):
    """One glass aperture of the STN module: flat field, a 1 px recess shadow
    top/left (outside any glyph cell), and backlight spill on the black bezel
    around it -- strongest at the left, where the side-fire LEDs sit."""
    p.box(x, y, w, h, P.LCD_FIELD)
    p.hline(x, x + w - 1, y, P.LCD_SHADE); p.vline(x, y, y + h - 1, P.LCD_SHADE)
    p.px(x, y, P.LCD_DEEP)
    p.hline(x + 1, x + w - 1, y + h - 1, P.LCD_GLOW) if False else None
    # spill on the bezel (static art only)
    for xx in range(x - 1, x + w + 1):
        f = 1.0 - 0.75 * (xx - x) / max(1, w)
        top = P.lerp(P.BEZEL[1], P.LCD_DEEP, 0.55 * f)
        bot = P.lerp(P.BEZEL[1], P.LCD_FIELD, 0.50 * f)
        p.px(xx, y - 1, top); p.px(xx, y + h, bot)
    for yy in range(y, y + h):
        p.px(x - 1, yy, P.lerp(P.BEZEL[1], P.LCD_FIELD, 0.62))
        p.px(x + w, yy, P.lerp(P.BEZEL[1], P.LCD_FIELD, 0.22))
    if glow_left:
        for yy in range(y - 1, y + h + 1):
            p.px(x - 2, yy, P.lerp(P.BEZEL[1], P.LCD_DEEP, 0.30))


def bezel(p, x, y, w, h):
    """Black moulded bezel plate with a faint satin texture."""
    for j in range(h):
        for i in range(w):
            k = ((x + i) * 3 + (y + j) * 7) % 11
            p.px(x + i, y + j, P.BEZEL[2] if k == 0 else P.BEZEL[1] if k < 8 else P.BEZEL[0])


def led_module(p, x, y, w, h, face, light_body=False):
    """Shell of an LED display module: 1 px body edge, then the dark face."""
    body = P.SEG_BODY if light_body else (E[1], E[3], E[5])
    p.box(x, y, w, h, face)
    p.hline(x, x + w - 1, y, body[2]); p.vline(x, y, y + h - 1, body[2])
    p.hline(x, x + w - 1, y + h - 1, body[0]); p.vline(x + w - 1, y, y + h - 1, body[0])
    p.px(x, y, (255, 255, 255, 255) if light_body else body[2])
    p.px(x + w - 1, y, body[1]); p.px(x, y + h - 1, body[1])


def _erode(m):
    e = m.copy()
    e[1:, :] &= m[:-1, :]; e[:-1, :] &= m[1:, :]; e[:, 1:] &= m[:, :-1]; e[:, :-1] &= m[:, 1:]
    e[0, :] = False; e[-1, :] = False; e[:, 0] = False; e[:, -1] = False
    return e


def framed_module(p, rects, t=3):
    """A tin frame of thickness ``t`` folded round the union of ``rects``
    (window coords), a black bezel plate inside it, and the contact shadow the
    whole module throws down-right.  Handles L shapes: every ring pixel is
    toned by the side it faces, so inner corners come out right."""
    x0 = min(r[0] for r in rects) - 4; y0 = min(r[1] for r in rects) - 4
    x1 = max(r[0] + r[2] for r in rects) + 4; y1 = max(r[1] + r[3] for r in rects) + 4
    w, h = x1 - x0, y1 - y0
    inside = np.zeros((h, w), bool)
    for rx, ry, rw, rh in rects:
        inside[ry - y0:ry - y0 + rh, rx - x0:rx - x0 + rw] = True
    # contact shadow first (depth 2, down-right)
    for d, f in ((1, 0.55), (2, 0.78)):
        sh = np.zeros_like(inside); sh[d:, d:] = inside[:-d, :-d]
        ys, xs = np.nonzero(sh & ~inside)
        for yy, xx in zip(ys, xs):
            p.shade(int(xx) + x0, int(yy) + y0, 1, 1, f)
    cur = inside
    tl = (0.92, 0.72, 0.54); br = (0.26, 0.40, 0.56)
    for k in range(t):
        nxt = _erode(cur)
        ring = cur & ~nxt
        ys, xs = np.nonzero(ring)
        for yy, xx in zip(ys, xs):
            up = not cur[yy - 1, xx]; lf = not cur[yy, xx - 1]
            dn = not cur[yy + 1, xx]; rt = not cur[yy, xx + 1]
            g = ((((xx + x0) * 13 + (yy + y0) * 7) % 7) - 3) * 0.012
            if up or lf:
                tone = tl[k] - (0.06 if lf and not up else 0.0)
            elif dn or rt:
                tone = br[k]
            else:                      # convex inner-corner filler
                tone = 0.5
            if (up or lf) and (dn or rt):
                tone = 0.6
            p.px(int(xx) + x0, int(yy) + y0, P.sample(T, tone + g))
        cur = nxt
    ys, xs = np.nonzero(cur)
    for yy, xx in zip(ys, xs):
        X, Y = int(xx) + x0, int(yy) + y0
        k = (X * 3 + Y * 7) % 11
        p.px(X, Y, P.BEZEL[2] if k == 0 else P.BEZEL[1] if k < 8 else P.BEZEL[0])
