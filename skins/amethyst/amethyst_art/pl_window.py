"""Playlist window -- a big STN module on its carrier board, in tiles.

Tile discipline: side tiles repeat every 29 px vertically, top/bottom tiles
every 25 px horizontally.  Everything in a tile is either invariant along the
repeat axis (mask tone, frame, traces, pot body) or periodic with a period
that divides the tile (castellations pitch 5; one frame tab per 29 px).
"""

from __future__ import annotations

import numpy as np

from . import palette as P
from . import board as B
from . import pen as pn
from . import parts as K
from . import parts2 as K2
from . import controls as C
from .main_widgets import castellations
from .pen import Pen
from .parts import M, G, T, E, S, silk
from .type_small import CAPS57, LCD56

W, H = 275, 232
WHITE = (255, 255, 255, 255)
SEED = B.SEEDS["playlist"]


def _mask(c, mode):
    """mode 'h' = strip tiled horizontally (tone varies with y only),
    'v' = strip tiled vertically (varies with x only), 'free' = 2-D mottle."""
    if mode == "h":
        t = pn.mask_value(c, seed=SEED, invariant="x")
    elif mode == "v":
        t = pn.mask_value(c, seed=SEED, invariant="y")
    else:
        t = pn.mask_value(c, seed=SEED)
    return t


def _tin_h(p, x0, x1, y):
    """Top/bottom limb of the 2 px tin frame."""
    for xx in range(x0, x1 + 1):
        p.px(xx, y, T[6] if (xx * 7) % 13 else T[5]); p.px(xx, y + 1, T[3])


def _tin_v(p, x, y0, y1, lit=True):
    for yy in range(y0, y1 + 1):
        p.px(x, yy, T[5] if lit else T[3]); p.px(x + 1, yy, T[3] if lit else T[1])


def _bezel_h(p, x0, x1, y, glow_row, f=0.5):
    for xx in range(x0, x1 + 1):
        for k in range(2):
            p.px(xx, y + k, P.BEZEL[1] if (xx + k) % 5 else P.BEZEL[2])
        p.px(xx, glow_row, P.lerp(P.BEZEL[1], P.LCD_FIELD, f))


# ---------------------------------------------------------------------------
# top strip
# ---------------------------------------------------------------------------
def _top_common(c, active):
    pn.paint_mask(c, _mask(c, "h"))
    p = Pen(c)
    x0, x1 = c.ox, c.ox + c.w - 1
    p.hline(x0, x1, 0, P.FR4[3]); p.hline(x0, x1, 1, M[6])
    castellations_p5(p, x0, x1)
    p.hline(x0, x1, 8, S[2] if active else S[0])
    p.shade(x0, 18, c.w, 1, 0.6) if False else None
    _tin_h(p, x0, x1, 16)
    _bezel_h(p, x0, x1, 18, 19, f=0.40)
    return p


def castellations_p5(p, x0, x1):
    for x in range((x0 // 5) * 5, x1 + 1, 5):
        if x < 25 or x > 249:
            continue
        p.box(x + 1, 0, 3, 3, G[3]); p.hline(x + 1, x + 3, 1, G[4]); p.hline(x + 1, x + 3, 2, G[2])
        p.px(x + 2, 0, M[0]); p.px(x + 1, 0, G[4]); p.px(x + 3, 0, G[2])


def top_tile(c, active):
    _top_common(c, active)


def top_left(c, active):
    p = _top_common(c, active)
    p.box(0, 0, 8, 20, M[3])
    t = _mask(c, "v")
    sub = c.sub(0, 0, 8, 20)
    pn.paint_mask(sub, t[:, :8])
    p.hline(0, 24, 0, P.FR4[3]); p.hline(1, 24, 1, M[6])
    p.vline(0, 0, 19, P.FR4[3]); p.vline(1, 1, 19, M[5]); p.px(0, 0, P.FR4[4])
    p.hline(2, 12, 8, M[3]) if False else None
    # the frame's top-left fold
    _tin_v(p, 8, 16, 19); _tin_h(p, 8, 24, 16)
    p.box(10, 18, 2, 2, P.BEZEL[1])
    K.led_smd(p, 12, 6, "b", 1.0 if active else 0.0)
    K.fiducial(p, 5, 7)
    K.traces(p, [[(3, 12), (3, 19)], [(5, 12), (5, 19)]])
    K.via(p, 3, 11) if False else None


def top_right(c, active):
    p = _top_common(c, active)
    sub = c.sub(9, 0, 16, 16)
    pn.paint_mask(sub, _mask(sub, "free"))
    p.hline(250, 274, 0, P.FR4[3]); p.hline(250, 273, 1, M[6])
    p.vline(274, 0, 19, P.FR4[1]); p.vline(273, 1, 19, M[1])
    p.box(259, 12, 16, 8, M[3])
    pn.paint_mask(c.sub(9, 12, 14, 8), _mask(c.sub(9, 12, 14, 8), "v"))
    p.vline(274, 0, 19, P.FR4[1]); p.vline(273, 1, 19, M[1])
    _tin_v(p, 257, 16, 19, lit=False); p.px(257, 16, T[6]); p.px(258, 16, T[4])
    _pot_column(p, 12, 19, top_end=True)
    C.gold_button(p, 254, 3, "shade", False)
    K.traces(p, [[(271, 14), (271, 19)]])


def title(c, active):
    p = _top_common(c, active)
    text = "SESSIONS"
    tw = sum(CAPS57.width(ch) for ch in text) + len(text) - 1
    tx = c.ox + (c.w - tw) // 2
    pn.paint_mask(c.sub(tx - 6 - c.ox, 3, tw + 12, 11), _mask(c.sub(tx - 6 - c.ox, 3, tw + 12, 11), "h"))
    p.text(tx, 5, text, CAPS57, S[3] if active else S[0])
    K.via(p, tx - 7, 8); K.via(p, tx + tw + 6, 8)


# ---------------------------------------------------------------------------
# sides
# ---------------------------------------------------------------------------
def left_tile(c):
    pn.paint_mask(c, _mask(c, "v"))
    p = Pen(c)
    y0, y1 = c.oy, c.oy + c.h - 1
    p.vline(0, y0, y1, P.FR4[3]); p.vline(1, y0, y1, M[5])
    K.traces(p, [[(3, y0), (3, y1)], [(5, y0), (5, y1)]])
    _tin_v(p, 8, y0, y1)
    for yy in range(y0, y1 + 1):
        p.px(10, yy, P.BEZEL[1]); p.px(11, yy, P.lerp(P.BEZEL[1], P.LCD_FIELD, 0.62))
    # one locking tab per tile
    ty = y0 + 13
    p.box(5, ty - 1, 3, 5, M[0]); p.box(6, ty, 2, 3, T[4]); p.vline(6, ty, ty + 2, T[6]); p.px(7, ty + 2, T[2])
    K.traces(p, [[(5, ty - 4), (4, ty - 3), (4, ty + 5), (5, ty + 6)]]) if False else None


def _pot_column(p, y0, y1, top_end=False, bottom_end=False):
    """The scrollbar's slide pot, x259..268, between rows y0..y1."""
    tones = (0.90, 0.68, 0.60, 0.16, 0.04, 0.04, 0.88, 0.60, 0.52, 0.28)
    for yy in range(y0, y1 + 1):
        for k, t in enumerate(tones):
            p.px(259 + k, yy, P.sample(T, t))
        p.shade(269, yy, 1, 1, 0.6); p.shade(270, yy, 1, 1, 0.82)
    if top_end:
        p.hline(259, 268, y0, T[6]); p.box(262, y0 + 1, 4, 3, T[4]); p.px(263, y0 + 2, G[4]); p.px(264, y0 + 2, G[2])
    if bottom_end:
        p.hline(259, 268, y1, T[1]); p.box(262, y1 - 3, 4, 3, T[3]); p.px(263, y1 - 2, G[4]); p.px(264, y1 - 2, G[2])
        p.shade(260, y1 + 1, 10, 1, 0.6)


def right_tile(c):
    pn.paint_mask(c, _mask(c, "v"))
    p = Pen(c)
    y0, y1 = c.oy, c.oy + c.h - 1
    for yy in range(y0, y1 + 1):
        p.px(255, yy, P.lerp(P.BEZEL[1], P.LCD_FIELD, 0.22)); p.px(256, yy, P.BEZEL[1])
    _tin_v(p, 257, y0, y1, lit=False)
    _pot_column(p, y0, y1)
    K.traces(p, [[(271, y0), (271, y1)]])
    p.vline(274, y0, y1, P.FR4[1]); p.vline(273, y0, y1, M[1])
    # graduation stamped on the pot body once per tile
    p.px(260, y0 + 14, T[1]); p.px(261, y0 + 14, T[1]); p.px(267, y0 + 14, T[1])


def scroll_handle(c, pressed):
    C.cap(Pen(c, origin=(0, 0)), 0, 0, c.w, c.h, pressed=pressed, index="h", lit=P.LED_A)


# ---------------------------------------------------------------------------
# bottom
# ---------------------------------------------------------------------------
def _bottom_common(c, mode="free"):
    t = _mask(c, mode)
    if mode == "free":
        tv = _mask(c, "v")
        k = np.clip((np.arange(c.h, dtype=np.float32)[:, None] - 3) / 5.0, 0, 1)
        t = tv * (1 - k) + t * k
    pn.paint_mask(c, t)
    p = Pen(c)
    x0, x1 = c.ox, c.ox + c.w - 1
    _bezel_h(p, x0, x1, 194, 194, f=0.50)
    for xx in range(x0, x1 + 1):
        p.px(xx, 196, T[3]); p.px(xx, 197, T[1])
    p.shade(x0, 198, c.w, 1, 0.6); p.shade(x0, 199, c.w, 1, 0.82)
    p.hline(x0, x1, 231, P.FR4[1]); p.hline(x0, x1, 230, M[1])
    return p


def bottom_tile(c):
    _bottom_common(c, "h")


def bottom_left(c):
    p = _bottom_common(c)
    p.vline(0, 194, 231, P.FR4[3]); p.vline(1, 194, 230, M[5])
    p.box(2, 194, 10, 4, M[3])
    pn.paint_mask(c.sub(2, 0, 6, 4), _mask(c.sub(2, 0, 6, 4), "v"))
    _tin_v(p, 8, 194, 197); p.hline(8, 124, 196, T[3]); p.hline(9, 124, 197, T[1]); p.px(8, 197, T[3])
    for yy in (194, 195):
        p.px(10, yy, P.BEZEL[1]); p.px(11, yy, P.lerp(P.BEZEL[1], P.LCD_FIELD, 0.5))
    K.traces(p, [[(3, 194), (3, 204), (9, 210), (18, 210)], [(5, 194), (5, 202), (11, 208), (18, 208)]])
    # 16-pin module header, with the silk everyone knows by heart
    K2.header(p, 20, 203, 16)
    silk(p, 20, 209, "1", col=S[2]); silk(p, 62, 209, "16", col=S[2]); silk(p, 34, 209, "J5")
    for k in range(16):
        p.px(21 + 3 * k, 201, P.POUR[3]); p.px(21 + 3 * k, 202, P.POUR[3])
    K2.trimpot(p, 78, 203); silk(p, 88, 203, "RV1", col=S[2]); silk(p, 74, 212, "CONTRAST")
    K.chip_r(p, 104, 204); K.chip_r(p, 104, 209); silk(p, 111, 204, "BL", col=S[2])
    K.mount_hole(p, 8, 222)
    silk(p, 16, 219, "TA-LCD4019 SESSIONS", col=S[3], worn=0.2)
    K2.sticker(p, 16, 226 - 6 + 1 - 7 + 7, w=21, h=6) if False else None
    K.fiducial(p, 118, 224)


def bottom_right(c):
    p = _bottom_common(c)
    p.vline(274, 194, 231, P.FR4[1]); p.vline(273, 194, 230, M[1])
    p.px(255, 194, P.lerp(P.BEZEL[1], P.LCD_FIELD, 0.3)); p.box(255, 195, 2, 1, P.BEZEL[1])
    _tin_v(p, 257, 194, 197, lit=False)
    _pot_column(p, 194, 201, bottom_end=True)
    # the little status glass
    B.bezel(p, 127, 200, 113, 27)
    p.hline(127, 239, 200, P.BEZEL[3]); p.vline(127, 200, 226, P.BEZEL[3]); p.hline(127, 239, 226, P.BEZEL[0])
    p.cast(127, 200, 113, 27, depth=2, strength=0.5)
    B.lcd_window(p, 130, 202, 108, 23)
    for xx in range(132, 236, 2):
        p.px(xx, 213, P.LCD_GHOST)
    p.text(132, 217, "NEXT RESET", LCD56, P.LCD_PIXEL_SOFT)
    K.mount_hole(p, 264, 220)
    K.traces(p, [[(271, 194), (271, 208), (268, 211)]])
    K.via(p, 267, 212)
    silk(p, 244, 204, "RV2", col=S[2])


def vis_bg(c):
    c.fill(P.EPOXY[1])
    p = Pen(c, origin=(0, 0))
    p.box(2, 2, c.w - 4, c.h - 4, P.BAR_FACE)
    p.rect(1, 1, c.w - 2, c.h - 2, E[0]); p.hline(2, c.w - 2, c.h - 2, E[3])
    c.a[:, :, 3] = 255
