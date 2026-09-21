"""Main-window sprites.  Every painter receives a canvas cut from the baked
board, so it only adds its own hardware on top, in window coordinates."""

from __future__ import annotations

from . import palette as P
from . import parts as K
from . import controls as C
from .pen import Pen
from .parts import M, G, T, E, S, silk
from .type_small import CAPS57, LCD56

WHITE = (255, 255, 255, 255)


# ---------------------------------------------------------------------------
# transport: six tact switches
# ---------------------------------------------------------------------------
def _icon(p, x, y, which, col):
    """7x7 silk pictogram."""
    art = {
        "previous": ("#..#..#", "#.##.##", "#######", "#######", "#######", "#.##.##", "#..#..#"),
        "play": ("#......", "###....", "#####..", "#######", "#####..", "###....", "#......"),
        "pause": (".##.##.", ".##.##.", ".##.##.", ".##.##.", ".##.##.", ".##.##.", ".##.##."),
        "stop": (".......", ".#####.", ".#####.", ".#####.", ".#####.", ".#####.", "......."),
        "next": ("#..#..#", "##.##.#", "#######", "#######", "#######", "##.##.#", "#..#..#"),
        "eject": ("...#...", "..###..", ".#####.", "#######", ".......", "#######", "#######"),
    }[which]
    if which == "previous":
        art = tuple(r[0] + "." + r[2:] if i in (0, 1, 5, 6) else r for i, r in enumerate(art))
    p.rows(x, y, art, {"#": col})


def transport(c, which, pressed):
    p = Pen(c)
    x, y = c.origin
    eject = which == "eject"
    cy = y + 1 if eject else y + 2
    C.tact_legs(p, x + 1, cy)
    C.tact_switch(p, x + 1, cy, pressed=pressed, red=eject)
    ix = x + 15
    _icon(p, ix, cy + 1 if not eject else cy, which, S[3] if not pressed else WHITE)
    # the key-down tell-tale: a tiny LED under the pictogram
    kind = "r" if eject else "g" if which == "play" else "a"
    K.led_smd(p, ix + 1, cy + 10 if not eject else cy + 9, kind, 1.0 if pressed else 0.0)


# ---------------------------------------------------------------------------
# toggles: slide switches with indicator LEDs
# ---------------------------------------------------------------------------
def shuffle(c, pressed, selected):
    p = Pen(c); x, y = c.origin
    C.slide_switch(p, x + 2, y + 3, 17, 9, on=selected, pressed=pressed)
    silk(p, x + 22, y + 2, "CYCLE", col=WHITE if selected else S[3])
    K.led_smd(p, x + 22, y + 9, "g", 1.0 if selected else 0.0)
    silk(p, x + 30, y + 8, "SW7", col=S[1])


def repeat(c, pressed, selected):
    p = Pen(c); x, y = c.origin
    silk(p, x + 3, y + 1, "ALERT", col=WHITE if selected else S[3])
    C.slide_switch(p, x + 3, y + 7, 15, 7, on=selected, pressed=pressed)
    K.led_smd(p, x + 21, y + 9, "r", 1.0 if selected else 0.0)


def small_toggle(c, pressed, selected, label, kind="a", sw_w=13):
    p = Pen(c); x, y = c.origin
    silk(p, x + 1, y + 1, label, col=WHITE if selected else S[3])
    K.led_smd(p, x + 1, y + 8, kind, 1.0 if selected else 0.0)
    C.slide_switch(p, x + c.w - sw_w - 1, y + 2, sw_w, 8, on=selected, pressed=pressed)


# ---------------------------------------------------------------------------
# lamps
# ---------------------------------------------------------------------------
def lamp(c, label, kind, on):
    p = Pen(c); x, y = c.origin
    K.led_smd(p, x + 1, y + 4, kind, 1.0 if on else 0.0)
    silk(p, x + 8, y + 3, label, col=S[3] if on else S[2])
    if on:                                       # light rakes across the legend
        p.light(x + 3, y + 5, P.led_ramp(kind)[3], radius=9, strength=0.35)


def play_state(c, state):
    p = Pen(c); x, y = c.origin
    art = {"playing": ("#....", "###..", "#####", "#####", "#####", "###..", "#...."),
           "paused": ("##.##", "##.##", "##.##", "##.##", "##.##", "##.##", "##.##"),
           "stopped": (".....", "#####", "#####", "#####", "#####", "#####", ".....")}[state]
    r = {"playing": P.LED_G, "paused": P.LED_A, "stopped": P.LED_R}[state]
    p.rows(x + 3, y + 1, art, {"#": r[3]})
    hot = {"playing": ((4, 4), (5, 4)), "paused": ((3, 4), (6, 4)), "stopped": ((5, 4), (4, 3))}[state]
    for hx, hy in hot:
        p.px(x + hx, y + hy, r[4])
    p.light(x + 5, y + 4, r[3], radius=5, strength=0.35)


def work_led(c, working):
    p = Pen(c); x, y = c.origin
    r = P.LED_B
    if working:
        p.box(x, y + 1, 2, 7, r[3]); p.vline(x, y + 2, y + 6, r[4]); p.px(x, y + 4, r[5])
        p.light(x + 0.5, y + 4, r[3], radius=3, strength=0.5)
    else:
        p.box(x, y + 1, 2, 7, r[1]); p.px(x, y + 1, r[2])


# ---------------------------------------------------------------------------
# seek: a long slide pot
# ---------------------------------------------------------------------------
def posbar(c):
    p = Pen(c); x, y = c.origin
    w, h = c.w, c.h
    p.cast(x, y, w, h - 1, depth=1, strength=0.5)
    for j in range(h - 1):
        for i in range(w):
            t = (0.86, 0.70, 0.62, 0.30, 0.10, 0.10, 0.50, 0.58, 0.34)[j]
            t += (((i * 7 + j * 3) % 9) - 4) * 0.008
            p.px(x + i, y + j, P.sample(T, t))
    # slot: shadowed top, lit lower lip
    p.hline(x + 5, x + w - 6, y + 3, E[0]); p.hline(x + 5, x + w - 6, y + 4, E[1])
    p.hline(x + 5, x + w - 6, y + 5, E[2]); p.hline(x + 5, x + w - 6, y + 6, T[6])
    p.px(x + 4, y + 4, E[0]); p.px(x + 4, y + 5, E[0]); p.px(x + w - 5, y + 4, T[5]); p.px(x + w - 5, y + 5, T[5])
    # mounting lugs with a solder blob each end, stamped part number
    for lx in (x + 1, x + w - 3):
        p.box(lx, y + 3, 2, 3, G[3]); p.px(lx, y + 3, G[5]); p.px(lx + 1, y + 5, G[1])
    p.px(x, y, M[2]); p.px(x + w - 1, y, M[2])
    p.px(x + 1, y + 1, WHITE); p.px(x + 120, y, WHITE)


def posbar_thumb(c, pressed):
    C.cap(Pen(c, origin=(0, 0)), 0, 0, c.w, c.h, pressed=pressed, index="v", lit=P.LED_A)


# ---------------------------------------------------------------------------
# utilisation gauges: LED rows on the mask, 28 levels
# ---------------------------------------------------------------------------
def gauge(c, i, label, n_leds):
    """Frame ``i`` of 28: a row of vertical 0603 LEDs on the mask.  ``n_leds``
    LEDs share the 27 steps, each ramping through (27 / n_leds) sub-levels, so
    the row reads as a level at a glance and still resolves every frame.  The
    legend is stamped on the LCD flange above (main_bg), never under the cap."""
    p = Pen(c); x, y = c.origin
    p.shade(x, y, c.w, 1, 0.60)                              # the flange's shadow
    per = 27.0 / n_leds
    span = c.w - 3
    pitch = span // n_leds
    gx = x + 2 + (span - pitch * n_leds) // 2
    # silk scale: a tick per LED, tall ones at 0 / 50 / 100 %
    for k in range(n_leds + 1):
        tx = gx - 1 + k * pitch
        p.px(tx, y + 2, S[2])
        if k in (0, n_leds // 2, n_leds):
            p.px(tx, y + 1, S[3]); p.px(tx, y + 2, S[3])
    # common return under the row, then the milled slot the cap's stem rides in
    p.hline(x + 2, x + c.w - 3, y + 9, P.POUR[3])
    p.hline(x + 1, x + c.w - 2, y + 10, M[0]); p.hline(x + 1, x + c.w - 2, y + 11, M[1])
    p.hline(x + 2, x + c.w - 2, y + 12, M[5])
    p.px(x + 1, y + 10, G[2]); p.px(x + c.w - 2, y + 11, G[4])
    for k in range(n_leds):
        lvl = min(1.0, max(0.0, (i - k * per) / per))
        f = (k + 0.5) / n_leds
        kind = "g" if f < 0.60 else "a" if f < 0.82 else "r"
        lx = gx + k * pitch
        lw = pitch - 1
        for ey, tt in ((y + 4, (T[6], T[4])), (y + 8, (T[4], T[2]))):   # tin lands
            p.hline(lx, lx + lw - 1, ey, tt[1]); p.px(lx, ey, tt[0])
        K.lens(p, lx, y + 5, lw, 3, P.led_ramp(kind), lvl, bloom=lvl > 0, radius=1.0 + 1.8 * lvl)


def gauge_thumb(c, pressed):
    C.cap(Pen(c, origin=(0, 0)), 0, 0, c.w, c.h, pressed=pressed, index="v", lit=P.LED_G)


# ---------------------------------------------------------------------------
# clutter bar: five labelled gold pads
# ---------------------------------------------------------------------------
def clutter(c, pressed, disabled):
    p = Pen(c); x, y = c.origin
    cells = (("O", 25, 8), ("A", 33, 7), ("I", 40, 7), ("D", 47, 8), ("V", 55, 7))
    p.vline(x + 7, y + 1, y + c.h - 2, S[0] if disabled else S[1])       # silk bracket
    p.px(x + 6, y + 1, S[1]); p.px(x + 6, y + c.h - 2, S[1])
    for letter, cy, ch in cells:
        hit = pressed == letter
        py = cy + (ch - 3) // 2
        o = 1 if hit else 0
        if hit:
            p.rows(x, py, ("bab", "aBa", "baW"), {"a": G[2], "b": G[1], "B": G[1], "W": WHITE})
        else:
            K.test_point(p, x + 1, py + 1)
        ink = WHITE if hit else S[0] if disabled else S[3]
        silk(p, x + 4 + (1 if letter == "I" else 0) , cy + (ch - 5) // 2 + o, letter, col=ink)


# ---------------------------------------------------------------------------
# title bar (main / shade / easter) and its gold pads
# ---------------------------------------------------------------------------
def castellations(p, x0, x1, y=0, pitch=4):
    for x in range(x0, x1, pitch):
        p.box(x, y, 3, 3, G[3]); p.hline(x, x + 2, y + 1, G[4]); p.hline(x, x + 2, y + 2, G[2])
        p.px(x + 1, y, M[0]); p.px(x, y, G[4]); p.px(x + 2, y, G[2])


def title_bar(c, active, variant):
    p = Pen(c)
    ink = S[3] if active else S[0]
    castellations(p, 40, 236)
    # power LED + legend, left of the title
    K.led_smd(p, 18, 6, "b", 1.0 if active else 0.0)
    silk(p, 25, 5, "PWR", col=ink)
    if variant == "shade":
        _shade_furniture(p, active)
        return
    text = "TOKENAMP"
    col = ink if variant == "main" else (G[4] if active else G[2])
    tw = sum(CAPS57.width(ch) for ch in text) + len(text) - 1
    tx = (275 - tw) // 2
    p.text(tx, 5, text, CAPS57, col)
    # silk rules either side of the name, broken by a via each
    for x0, x1 in ((44, tx - 5), (tx + tw + 4, 232)):
        p.hline(x0, x1, 8, S[2] if active else S[0])
    K.via(p, 42, 8); K.via(p, 234, 8)


def _shade_furniture(p, active):
    ink = S[3] if active else S[0]
    silk(p, 42, 5, "TA-5100", col=ink)
    # mini bargraph window and the little LCD for the countdown
    p.box(77, 3, 42, 9, E[1]); p.hline(77, 118, 3, E[0]); p.hline(77, 118, 11, E[3])
    p.box(79, 5, 38, 5, P.BAR_FACE)
    p.box(126, 2, 30, 10, P.BEZEL[1])
    p.box(128, 3, 26, 8, P.LCD_FIELD)
    p.hline(128, 153, 3, P.LCD_SHADE) if False else None
    p.px(140, 6, P.LCD_PIXEL); p.px(140, 8, P.LCD_PIXEL)
    for key, rx, rw in (("previous", 169, 8), ("play", 177, 10), ("pause", 187, 10),
                        ("stop", 197, 9), ("next", 206, 10), ("eject", 216, 9)):
        mini = {"previous": ("#.#", "###", "#.#"), "play": ("#..", "##.", "#.."),
                "pause": ("#.#", "#.#", "#.#"), "stop": ("###", "###", "###"),
                "next": ("#.#", "###", "#.#"), "eject": (".#.", "###", "###")}[key]
        mini = {"previous": ("#..#.", "#.##.", "####.", "#.##.", "#..#."),
                "play": ("#....", "##...", "###..", "##...", "#...."),
                "pause": ("##.##", "##.##", "##.##", "##.##", "##.##"),
                "stop": ("####.", "####.", "####.", "####.", "....."),
                "next": (".#..#", ".##.#", ".####", ".##.#", ".#..#"),
                "eject": ("..#..", ".###.", "#####", ".....", "#####")}[key]
        p.rows(rx + (rw - 5) // 2, 5, mini, {"#": ink})


def title_button(c, which, pressed):
    p = Pen(c); x, y = c.origin
    C.gold_button(p, x, y, which, pressed)


def shade_pos_bg(c):
    p = Pen(c); x, y = c.origin
    for j in range(c.h):
        for i in range(c.w):
            p.px(x + i, y + j, P.sample(T, (0.8, 0.62, 0.2, 0.08, 0.2, 0.55, 0.3)[j]))
    p.hline(x + 1, x + c.w - 2, y + 4, T[6])


def shade_pos_thumb(c, which):
    p = Pen(c, origin=(0, 0))
    C_ = P.CAP
    p.box(0, 0, 3, 7, C_[2])
    p.hline(0, 2, 0, C_[5]); p.hline(0, 2, 6, C_[0])
    col = {"left": (C_[5], S[3], C_[2]), "center": (C_[3], WHITE, C_[3]), "right": (C_[2], S[3], C_[0])}[which]
    for i in range(3):
        p.vline(i, 1, 5, col[i])
