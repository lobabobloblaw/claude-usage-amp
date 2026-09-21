"""Main window -- the static board (everything baked into main.bmp)."""

from __future__ import annotations

from . import palette as P
from . import board as B
from . import parts as K
from . import parts2 as K2
from .pen import Pen
from .parts import M, G, T, E, S, silk

W, H = 275, 116

# ---- fixed geometry (window coords) ----------------------------------------
SEG_MOD = (21, 22, 81, 19)        # seven-segment clock module  x21..101 y22..40
BAR_MOD = (22, 41, 80, 20)        # LED bargraph module         x22..101 y41..60
LCD_TOP = (104, 19, 168, 22)      # tin frame, upper limb       x104..271 y19..40
LCD_LOW = (104, 19, 106, 38)      # tin frame, lower-left limb  x104..209 y19..56
MARQ_WIN = (109, 25, 158, 10)     # glass aperture around the marquee
STAT_WIN = (109, 42, 95, 8)       # glass aperture around kbps / khz
MCU = (247, 90)
SWITCH_X = (16, 39, 62, 85, 108)


def paint(c, theme):
    B.laminate(c, "main", pours=_pours(c))
    p = Pen(c)
    B.routed_edge(p, W, H)
    _top_strip(p)
    _left_margin(p)
    _seg_module(p)
    _bar_module(p)
    _lcd_module(p)
    _lamp_nook(p)
    _mid_band(p)
    _transport_zone(p)
    _mcu_zone(p)
    _bottom_strip(p)


def _pours(c):
    # a ground pour wrapping the lower-left of the board, clipped at 45 degrees
    poly = [(2, 84), (12, 84), (12, 108), (16, 112), (132, 112), (132, 114), (2, 114)]
    return [(B.region(c, [poly]), True)]


# ---------------------------------------------------------------------------
def _top_strip(p):
    """y14..21 over the clock module: the segment-driver passives."""
    silk(p, 23, 16, "DS1")
    K2_res = K.res_array
    K2_res(p, 38, 16); K2_res(p, 50, 16)
    for x in (39, 41, 43, 45, 51, 53, 55, 57):
        p.px(x, 21, P.POUR[3])                               # stubs diving under the module
    silk(p, 62, 16, "RN2", col=S[2])
    K.chip_c(p, 77, 17)
    K.sot23(p, 85, 15)
    silk(p, 92, 16, "Q1", col=S[2])


def _left_margin(p):
    K.mount_hole(p, 6, 18)
    # the five clutter pads hang off one resistor-ladder sense line
    K.traces(p, [[(5, 27), (5, 66), (8, 69), (8, 71)]])
    for cy in (28, 36, 43, 50, 58):
        K.traces(p, [[(5, cy), (9, cy)]])
    K.via(p, 8, 72)
    silk(p, 3, 76, "J1", col=S[2])
    K.fiducial(p, 8, 85)
    K.mount_hole(p, 7, 107)


def _seg_module(p):
    x, y, w, h = SEG_MOD
    B.led_module(p, x, y, w, h, P.SEG_FACE, light_body=True)
    # the face sheet catches a little sky along its top edge, outside the cells
    p.hline(x + 1, x + w - 2, y + 1, P.SEG_FACE_HI)
    # ghost decimal points and the lit colon (two round LEDs, slanted like the digits)
    for dx in (58, 88):
        p.box(dx, 37, 2, 2, P.SEG_GHOST); p.px(dx, 37, P.SEG_GHOST_HI)
    for cx, cy in ((73, 29), (72, 34)):
        p.box(cx, cy, 2, 2, P.SEG[2]); p.px(cx, cy, P.SEG[4])
        p.light(cx + 0.5, cy + 0.5, P.SEG[2], radius=2.6, strength=0.55)
    # annunciator legends etched in the face sheet (ghost ink)
    silk(p, 24, 24, "RUN", col=P.SEG_GHOST)
    p.cast(x, y, w, h + 20, depth=2, strength=0.4)


def _bar_module(p):
    x, y, w, h = BAR_MOD
    B.led_module(p, x, y, w, h, E[1])
    p.box(24, 43, 76, 16, P.BAR_FACE)
    p.hline(23, 100, 42, E[0]); p.vline(23, 42, 59, E[0])    # well: shadowed top/left
    p.hline(24, 100, 59, E[3]); p.vline(100, 43, 59, E[3])   # lit bottom/right lip
    p.px(x, y, M[2]); p.px(x + 1, y, E[4]); p.px(x, y + 1, E[4])   # pin-1 chamfer
    # driver IC, its decoupler and the ballast network under the module
    silk(p, 23, 64, "DS2")
    K2.soic(p, 40, 64, pins=8, label=True)
    for k in range(8):
        p.px(41 + 2 * k, 61, P.POUR[3])
    silk(p, 60, 64, "U3", col=S[2])
    K.chip_c(p, 70, 65)
    K.res_array(p, 80, 63)
    silk(p, 91, 64, "RN3", col=S[2])


def _lcd_module(p):
    # one STN module; its folded tin frame is an L so the lamps sit in its nook
    B.framed_module(p, [LCD_TOP, LCD_LOW], t=3)
    B.lcd_window(p, *MARQ_WIN)
    B.lcd_window(p, *STAT_WIN)
    # fixed LCD annunciators in the status line
    silk(p, 128, 44, "K/MIN", col=P.LCD_PIXEL_SOFT)
    silk(p, 168, 44, "ACTIVE", col=P.LCD_PIXEL_SOFT)
    # part number pad-printed on the bezel strip between the two apertures
    silk(p, 111, 36, "TA-LCD2401", col=E[4])
    silk(p, 160, 36, "STN Y/G", col=E[4])
    _legend_flange(p)
    # locking tabs twisted through the board along the top edge
    for tx in (110, 134, 226, 264):
        B.frame_tab(p, tx, 17, up=True)
    # 16-way interface: tinned pads of the module's pin strip, numbered in silk
    for k in range(16):
        K.pad(p, 152 + 4 * k, 15, 2, 3, tin=True)
    silk(p, 147, 14, "1", col=S[2]); silk(p, 216, 14, "16", col=S[2])


def _legend_flange(p):
    """The frame's lower limb is a wide flange, and the gauge legends are
    stamped on it in black -- directly over their gauges, where no slider cap
    can ever cover them."""
    for yy in range(50, 57):
        tone = {50: 0.90, 56: 0.30}.get(yy, 0.66 - (yy - 51) * 0.02)
        for xx in range(107, 209):
            g = (((xx * 7 + yy * 3) % 9) - 4) * 0.010
            p.px(xx, yy, P.sample(T, tone + g))
    p.px(107, 50, (255, 255, 255, 255))
    silk(p, 108, 51, "SESSION", col=T[0])
    silk(p, 178, 51, "WEEK", col=T[0])
    # index arrows pointing down at each gauge, and two spot-weld dimples
    for ax in (138, 198):
        p.hline(ax, ax + 4, 52, T[1]); p.hline(ax + 1, ax + 3, 53, T[1]); p.px(ax + 2, 54, T[1])
    for wx in (150, 168):
        p.px(wx, 53, T[1]); p.px(wx + 1, 54, T[6])


def _lamp_nook(p):
    """Board in the crook of the LCD frame: LOCAL / LIVE lamps live here.
    (The lamps and legends themselves are sprites; this is what is under them.)"""
    K.chip_r(p, 262, 43, horizontal=False)
    K.traces(p, [[(215, 50), (215, 54), (243, 54), (243, 50)]])
    K.via_tented(p, 229, 54)


def _mid_band(p):
    # silk tick ruler over the long slide pot: centre of the cap runs 30..249
    for k in range(21):
        x = 30 + int(round(k * 219 / 20))
        p.px(x, 71, S[2])
        if k % 5 == 0:
            p.px(x, 70, S[3]); p.px(x, 71, S[3])
    K.via(p, 269, 61); K.via(p, 269, 66)
    K.traces(p, [[(266, 61), (267, 61)], [(266, 66), (267, 66)]])


def _transport_zone(p):
    for i, sx in enumerate(SWITCH_X):
        silk(p, sx + 2, 82, f"SW{i + 1}", col=S[2])
    silk(p, 138, 83, "SW6", col=S[2]) if False else None
    # ground rail under the row, a stub up to every switch's lower-right leg
    K.traces(p, [[(18, 110), (128, 110)]], width=2)
    for sx in SWITCH_X:
        K.traces(p, [[(sx + 11, 106), (sx + 11, 109)]])
        # the signal leg drops, jogs 45 degrees and dives through a via
        K.traces(p, [[(sx + 4, 106), (sx + 4, 107), (sx + 6, 109)]]) if False else None
        K.via(p, sx + 4, 107)


def _mcu_zone(p):
    mx, my = MCU
    # bus sweeping in from the toggle bank to the MCU's west pins
    lines = K.bus(p, [(142, 87), (231, 87), (239, 95), (244, 95)], 3, pitch=2, side=-1)
    for ln in lines:
        K.via(p, ln[0][0] - 1, ln[0][1])
    # west pin fan-out to staggered vias
    for k, py in enumerate((99, 101, 103, 105)):
        vx = 241 - (k % 2) * 3
        K.traces(p, [[(244, py), (vx + 1, py)]])
        K.via(p, vx, py)
    # crystal and its load caps over the north pins
    K2.crystal(p, 250, 82, w=11, h=5)
    K.traces(p, [[(252, 87), (252, 87)], [(258, 87), (258, 87)]])
    silk(p, 263, 82, "Y1", col=S[2])
    K2.qfp(p, mx, my, 17)
    # decouplers hugging the east side
    K.chip_c(p, 268, 90, horizontal=False)
    K.chip_c(p, 268, 98, horizontal=False)
    K.mount_hole(p, 268, 109) if False else None


def _bottom_strip(p):
    silk(p, 137, 108, "TOKENAMP REV C")
    K.fiducial(p, 198, 110)
    K.test_point(p, 205, 110, "TP1", lx=208, ly=108)
    silk(p, 223, 108, "U1", col=S[2])
    K.via(p, 250, 111); K.via(p, 256, 111); K.via(p, 262, 111)
    for vx in (250, 256, 262):
        p.px(vx, 109, P.POUR[3])
