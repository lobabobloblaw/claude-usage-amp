"""Equalizer window -- the ten-band fader board."""

from __future__ import annotations

from . import palette as P
from . import board as B
from . import parts as K
from . import parts2 as K2
from . import controls as C
from .main_widgets import castellations
from .pen import Pen
from .parts import M, G, T, E, S, silk
from .type_small import CAPS57

W, H = 275, 116
WHITE = (255, 255, 255, 255)
BAND_X = [78 + 18 * i for i in range(10)]
PRE_X = 21
CAPTIONS = ("-9", "-8", "-7", "-6", "-5", "-4", "-3", "-2", "-1", "NOW")
OLED = (82, 15, 121, 23)                  # module outline x82..202 y15..37
OLED_BG = (4, 8, 14, 255)
OLED_GRID = (12, 30, 44, 255)
OLED_BLUE = (90, 208, 255)
OLED_YEL = (255, 225, 74)


def paint(c, theme):
    poly = [(38, 40), (74, 40), (74, 100), (38, 100)]
    B.laminate(c, "eq", pours=[(B.region(c, [poly]), True)])
    p = Pen(c)
    B.routed_edge(p, W, H)
    _oled(p)
    _scale_and_analog(p)
    _left_margin(p)
    _header_fan(p)
    _captions(p)
    _bottom(p)


def _oled(p):
    x, y, w, h = OLED
    p.cast(x, y, w, h, depth=2, strength=0.5)
    # the module's own little PCB (black mask), glass on top
    B.bezel(p, x, y, w, h)
    p.hline(x, x + w - 1, y, P.BEZEL[3]); p.vline(x, y, y + h - 1, P.BEZEL[3])
    p.hline(x, x + w - 1, y + h - 1, P.BEZEL[0]); p.vline(x + w - 1, y, y + h - 1, P.BEZEL[0])
    # glass: 1 px lit lower/right lip, dark upper/left recess
    p.rect(85, 16, 115, 21, E[0])
    p.hline(86, 199, 36, E[4]); p.vline(199, 17, 36, E[4])
    # four gold pads (GND VCC SCL SDA) on the module's left ear, mounting holes
    for k in range(4):
        K.pad(p, 83, 18 + 4 * k, 2, 2)
    p.px(201, 17, G[3]); p.px(201, 35, G[3])
    silk(p, 205, 31, "DS3", col=S[2])


def graph_bg(c):
    p = Pen(c); x, y = c.origin
    p.box(x, y, c.w, c.h, OLED_BG)
    for gx in range(0, c.w, 12):                             # bucket grid, dotted
        for gy in range(1, c.h, 2):
            p.px(x + gx + 2, y + gy, OLED_GRID)
    for gx in range(0, c.w, 2):
        p.px(x + gx, y + 9, OLED_GRID)
    p.hline(x, x + c.w - 1, y + 4, (20, 18, 6, 255))         # the yellow/blue glass split
    c.a[:, :, 3] = 255


def line_colours():
    out = []
    for r in range(19):
        base = OLED_YEL if r < 5 else OLED_BLUE
        out.append(tuple(base))
    return out


def preamp_line(c):
    for x in range(c.w):
        c.px(x, 0, (44, 104, 128, 255) if x % 3 != 2 else OLED_BG)
    c.a[:, :, 3] = 255


def _scale_and_analog(p):
    # scale legends, right-aligned against the first fader, with leader ticks
    for text, y in (("MAX", 39), ("MID", 65), ("0", 92)):
        tw = K.silk_w(text)
        silk(p, 72 - tw, y, text)
        p.hline(74, 76, y + 2, S[2])
    # summing amplifier and its passives between WEEK and the band faders
    K2.soic(p, 47, 48, pins=4, vertical=True)
    silk(p, 45, 60, "U2", col=S[2])
    K.chip_c(p, 42, 72); K.chip_r(p, 52, 72)
    K.chip_r(p, 42, 78); K.chip_c(p, 52, 78)
    K.tantalum(p, 44, 86)
    silk(p, 55, 86, "+", col=S[2])


def _left_margin(p):
    K2.electrolytic(p, 10, 48)
    silk(p, 4, 58, "C9", col=S[2])
    K.inductor(p, 6, 68)
    silk(p, 4, 78, "L1", col=S[2])
    K.diode(p, 5, 88)
    K.traces(p, [[(9, 55), (9, 67)], [(9, 75), (9, 87)], [(9, 91), (9, 98), (12, 101)]], width=1)
    K.via(p, 13, 102)


def _header_fan(p):
    K2.header(p, 264, 42, 10, vertical=True)
    silk(p, 262, 36, "J4", col=S[2])
    silk(p, 269, 43, "1", col=S[2])
    # ten wiper lines fan in from the header and tuck under the last fader
    for k in range(10):
        hy = 43 + 3 * k
        ty = 52 + 2 * k - 5
        dy = ty - hy
        mid = 262 - abs(dy)
        K.traces(p, [[(263, hy), (mid, hy), (mid - abs(dy), ty) if False else (262 - abs(dy), hy)]]) if False else None
        if dy == 0:
            K.traces(p, [[(263, hy), (255, hy)]])
        else:
            s = 1 if dy > 0 else -1
            K.traces(p, [[(263, hy), (261, hy), (261 - abs(dy), hy + dy), (255, hy + dy)]])


def _captions(p):
    silk(p, PRE_X - 1, 103, "WEEK")
    for bx, cap in zip(BAND_X, CAPTIONS):
        tw = K.silk_w(cap)
        silk(p, bx + 3 + (7 - tw) // 2, 103, cap)


def _bottom(p):
    K.mount_hole(p, 7, 108); K.mount_hole(p, 267, 108)
    silk(p, 40, 110, "TA-EQ10 USAGE EQ REV C", col=S[2])
    K2.sticker(p, 200, 108, w=19, h=6)
    K.fiducial(p, 250, 110)


# ---------------------------------------------------------------------------
def title_bar(c, active):
    p = Pen(c)
    ink = S[3] if active else S[0]
    castellations(p, 40, 236)
    K.led_smd(p, 8, 6, "b", 1.0 if active else 0.0)
    text = "USAGE EQUALIZER"
    tw = sum(CAPS57.width(ch) for ch in text) + len(text) - 1
    tx = (W - tw) // 2
    p.text(tx, 5, text, CAPS57, ink)
    for x0, x1 in ((24, tx - 5), (tx + tw + 4, 254)):
        p.hline(x0, x1, 8, S[2] if active else S[0])


def toggle(c, pressed, selected, label, kind):
    from .main_widgets import small_toggle
    small_toggle(c, pressed, selected, label, kind)


def presets(c, pressed):
    p = Pen(c); x, y = c.origin
    # a low-profile SMD push button, 12x9
    bx, by = x + 1, y + 2
    p.cast(bx, by, 12, 9, depth=1, strength=0.5)
    for j in range(9):
        for i in range(12):
            p.px(bx + i, by + j, P.sample(T, 0.8 - 0.05 * j + (((i * 5 + j * 3) % 5) - 2) * 0.01))
    p.hline(bx, bx + 11, by, T[6]); p.vline(bx, by, by + 8, T[5])
    p.hline(bx, bx + 11, by + 8, T[1]); p.vline(bx + 11, by, by + 8, T[1])
    o = 1 if pressed else 0
    p.box(bx + 2, by + 2, 8, 5, E[0])
    cap = P.CAP
    p.box(bx + 2 + o, by + 2 + o, 8 - o, 5 - o, cap[1] if pressed else cap[3])
    if not pressed:
        p.hline(bx + 2, bx + 9, by + 2, cap[5]); p.vline(bx + 2, by + 2, by + 6, cap[4])
        p.hline(bx + 3, bx + 9, by + 6, cap[0]); p.px(bx + 3, by + 3, WHITE)
    silk(p, x + 16, y + 2, "RANGE", col=WHITE if pressed else S[3])
    # a down-chevron in silk: this key opens a list
    p.rows(x + 38, y + 3, ("#...#", ".#.#.", "..#.."), {"#": S[3]})
    K.led_smd(p, x + 16, y + 8, "a", 1.0 if pressed else 0.0, bloom=True)


def slider_frame(c, i):
    """14x63, baked at eleven x positions: painted edge to edge so nothing of
    the underlay survives, and nothing in it depends on window x."""
    p = Pen(c, origin=(0, 0))
    for j in range(c.h):
        t = 0.50 + (((j * 37) % 11) - 5) * 0.004
        col = P.sample(M, t)
        p.hline(0, 13, j, col)
    # silk scale, left of the pot
    for k in range(0, 28):
        yy = 60 - 2 * k
        if k % 9 == 0:
            p.hline(0, 1, yy, S[3])
        elif k % 3 == 0:
            p.px(1, yy, S[1])
    # pot body x3..9
    p.shade(10, 1, 1, 62, 0.62); p.shade(11, 2, 1, 61, 0.82)
    for j in range(c.h):
        g = (((j * 5) % 7) - 3) * 0.012
        for xx, t in ((3, 0.92), (4, 0.70), (5, 0.18), (6, 0.04), (7, 0.86), (8, 0.60), (9, 0.30)):
            p.px(xx, j, P.sample(T, t + (g if xx in (4, 8) else 0)))
    for yy in (0, 62):
        p.hline(3, 9, yy, T[2] if yy else T[6])
    p.box(5, 0, 3, 3, T[4]); p.box(5, 60, 3, 3, T[3])        # slot stops
    p.px(6, 1, G[4]); p.px(6, 61, G[3])                      # rivets
    # LED ladder x12..13
    for k in range(1, 28):
        yy = 60 - 2 * k
        r = P.led_ramp("g" if k <= 16 else "a" if k <= 22 else "r")
        if k <= i:
            p.px(12, yy, r[4] if k == i else r[3]); p.px(13, yy, r[3])
            p.light(12.5, yy, r[3], radius=2.2, strength=0.30)
            if k == i:
                p.px(12, yy, r[5])
        else:
            p.px(12, yy, r[1]); p.px(13, yy, r[0])
    c.a[:, :, 3] = 255


def thumb(c, pressed):
    C.cap(Pen(c, origin=(0, 0)), 0, 0, c.w, c.h, pressed=pressed, index="h", lit=P.LED_G)
