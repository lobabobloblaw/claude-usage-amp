"""Things you touch: tact switches, slide switches, gold touch pads, pot caps."""

from __future__ import annotations

from . import palette as P
from .parts import M, G, T, E, S

WHITE = (255, 255, 255, 255)

_DISC3 = ("..###..", ".#####.", "#######", "#######", "#######", ".#####.", "..###..")
_RING4 = ("..#####..", ".#.....#.", "#.......#", "#.......#", "#.......#",
          "#.......#", "#.......#", ".#.....#.", "..#####..")


def tact_switch(p, x, y, pressed=False, red=False):
    """6 mm tact switch seen from above, 13x13: stamped tin cover with four
    crimp dimples, a round plunger in a well.  Pressed: the plunger sinks --
    darker, +1,+1, highlight shrinks to one pixel."""
    p.cast(x, y, 13, 13, depth=2, strength=0.5)
    for j in range(13):
        for i in range(13):
            if (i in (0, 12)) and (j in (0, 12)):
                continue                                     # clipped corners
            t = 0.74 - 0.030 * j - 0.012 * i + (((i * 7 + j * 3) % 5) - 2) * 0.012
            p.px(x + i, y + j, P.sample(T, t))
    p.hline(x + 1, x + 11, y, T[6]); p.vline(x, y + 1, y + 11, T[5])
    p.hline(x + 1, x + 11, y + 12, T[1]); p.vline(x + 12, y + 1, y + 11, T[1])
    p.px(x + 1, y + 1, WHITE)
    for dx, dy in ((2, 2), (9, 2), (2, 9), (9, 9)):          # crimp dimples
        p.px(x + dx, y + dy, T[1]); p.px(x + dx + 1, y + dy, T[2]); p.px(x + dx, y + dy + 1, T[2])
        p.px(x + dx + 1, y + dy + 1, T[6])
    # the well
    for j, row in enumerate(_RING4):
        for i, ch in enumerate(row):
            if ch == "#":
                lit = (i + j) >= 10
                p.px(x + 2 + i, y + 2 + j, T[5] if lit else E[0])
    p.box(x + 4, y + 3, 5, 7, E[0]); p.box(x + 3, y + 4, 7, 5, E[0])
    cap = P.RED_CAP if red else P.CAP
    o = 1 if pressed else 0
    k = 0.72 if pressed else 1.0
    for j, row in enumerate(_DISC3):
        for i, ch in enumerate(row):
            if ch != "#":
                continue
            if pressed and (i + o > 6 or j + o > 6):
                continue
            t = 0.46 - (i + j - 6) * 0.055
            col = P.sample(cap, max(0.05, t * k))
            p.px(x + 3 + i + o, y + 3 + j + o, col)
    if pressed:
        p.px(x + 5 + o, y + 5 + o, cap[4])
    else:
        p.px(x + 4, y + 5, cap[4]); p.px(x + 5, y + 4, cap[4]); p.px(x + 4, y + 4, cap[5])
        p.px(x + 5, y + 5, WHITE if not red else cap[4])
        p.px(x + 8, y + 8, cap[0])


def tact_legs(p, x, y, top=True, bottom=True):
    """Gull-wing legs of the switch soldered to gold lands above / below."""
    for lx in (x + 2, x + 9):
        if top:
            p.box(lx, y - 2, 2, 2, T[4]); p.px(lx, y - 2, T[6]); p.px(lx + 1, y - 1, T[2])
        if bottom:
            p.box(lx, y + 13, 2, 2, T[4]); p.px(lx, y + 13, T[5]); p.px(lx + 1, y + 14, T[1])


def slide_switch(p, x, y, w, h, on=False, pressed=False):
    """SMD slide switch: tin shell, dark aperture, cream nub with grip ridges.
    The nub sits left = off, right = on, and hangs mid-travel while pressed."""
    p.cast(x, y, w, h, depth=1, strength=0.5)
    for j in range(h):
        for i in range(w):
            t = 0.78 - 0.05 * j + (((i * 5 + j * 11) % 6) - 2.5) * 0.010
            p.px(x + i, y + j, P.sample(T, t))
    p.hline(x, x + w - 1, y, T[6]); p.vline(x, y, y + h - 1, T[5])
    p.hline(x, x + w - 1, y + h - 1, T[1]); p.vline(x + w - 1, y, y + h - 1, T[1])
    p.px(x + 1, y + 1, WHITE)
    ax, ay, aw, ah = x + 2, y + 2, w - 4, h - 4
    p.box(ax, ay, aw, ah, E[0])
    p.hline(ax, ax + aw - 1, ay + ah, T[6])                  # lit lower lip of the cut-out
    p.vline(ax + aw, ay, ay + ah - 1, T[5])
    nw = aw // 2
    travel = aw - nw
    nx = ax + (travel // 2 if pressed else travel if on else 0)
    C = P.STICKER
    p.box(nx, ay, nw, ah, C[1])
    p.hline(nx, nx + nw - 1, ay, C[2]); p.vline(nx, ay, ay + ah - 1, C[2])
    p.hline(nx, nx + nw - 1, ay + ah - 1, C[0]); p.vline(nx + nw - 1, ay, ay + ah - 1, C[0])
    for i in range(1, nw - 1, 2):
        p.vline(nx + i, ay + 1, ay + ah - 2, C[0])
    p.px(nx, ay, WHITE)
    if on and not pressed and ax + 1 < nx - 1:
        p.px(ax + 1, ay + ah // 2, P.LED_G[2])               # "ON" paint dot uncovered
    if pressed:
        p.shade(x, y, w, h, 0.78)
    for lx in (x + 2, x + w // 2, x + w - 3):                # three solder legs
        p.px(lx, y + h, T[4])


def gold_button(p, x, y, glyph, pressed=False, size=9):
    """A gold ENIG touch pad with its pictogram etched back to bare mask.
    Pressed: the pad darkens under the finger, bevel inverts, art moves +1,+1,
    and a solder-bright glint shows at the lower right."""
    p.rows(x, y, (".#######.", "#########", "#########", "#########", "#########",
                  "#########", "#########", "#########", ".#######."), {"#": M[1]})
    o = 1 if pressed else 0
    hi, mid, lo = (G[1], G[2], G[3]) if pressed else (G[4], G[3], G[2])
    p.box(x + 1, y + 1, 7, 7, mid)
    p.hline(x + 1, x + 7, y + 1, hi); p.vline(x + 1, y + 1, y + 7, hi)
    p.hline(x + 1, x + 7, y + 7, lo); p.vline(x + 7, y + 1, y + 7, lo)
    if pressed:
        p.px(x + 6, y + 6, G[5]); p.px(x + 7, y + 7, WHITE)
    else:
        p.px(x + 1, y + 1, G[5]); p.px(x + 2, y + 1, G[5])
    ink = M[0]
    gx, gy = x + 2 + o, y + 2 + o
    if glyph == "options":
        for r in (0, 2, 4):
            p.hline(gx, gx + 4 - o, gy + r, ink)
    elif glyph == "minimize":
        p.hline(gx, gx + 4 - o, gy + 4 - o, ink)
    elif glyph == "shade":
        p.hline(gx, gx + 4 - o, gy, ink); p.hline(gx, gx + 4 - o, gy + 1, ink)
        p.hline(gx + 1, gx + 3, gy + 3, ink)
    elif glyph == "unshade":
        p.hline(gx, gx + 4 - o, gy, ink)
        p.rect(gx, gy + 1, 5 - o, 4 - o, ink)
    elif glyph == "close":
        for i in range(5 - o):
            p.px(gx + i, gy + i, ink); p.px(gx + 4 - o - i, gy + i, ink)


def cap(p, x, y, w, h, pressed=False, index="v", lit=None):
    """A black moulded slider cap filling w*h (thumbs are opaque rectangles, so
    the clipped corners are painted as the shadow the cap would cast)."""
    C = P.CAP
    o = 1 if pressed else 0
    p.box(x, y, w, h, M[0])
    hi, lo = (C[0], C[4]) if pressed else (C[5], C[0])
    for j in range(h):
        for i in range(w):
            if (i in (0, w - 1)) and (j in (0, h - 1)):
                continue
            t = (0.30 if pressed else 0.42) - 0.16 * ((j / max(1, h - 1)) + (i / max(1, w - 1)) - 1)
            p.px(x + i, y + j, P.sample(C, t))
    p.hline(x + 1, x + w - 2, y, hi); p.vline(x, y + 1, y + h - 2, hi)
    p.hline(x + 1, x + w - 2, y + h - 1, lo); p.vline(x + w - 1, y + 1, y + h - 2, lo)
    if not pressed:
        p.px(x + 1, y + 1, C[5])
    glow = P.LED_A if lit is None else lit
    if index == "v":                                         # vertical index line
        cx = x + w // 2 - (1 if w % 2 == 0 else 0) + o
        for gx in range(x + 2 + o, x + w - 2, 2):            # grip ridges
            if abs(gx - cx) > 2:
                p.vline(gx, y + 2 + o, y + h - 3, C[0]); p.vline(gx + 1, y + 2 + o, y + h - 3, C[4])
        iw = 2 if w % 2 == 0 else 1
        p.box(cx - 1, y + 1 + o, iw + 2, h - 2 - o, C[0])
        p.box(cx, y + 1 + o, iw, h - 2 - o, glow[4] if pressed else S[3])
        if pressed:
            p.box(cx, y + 2 + o, iw, h - 4 - o, glow[5])
            p.light(cx + iw / 2 - 0.5, y + h / 2, glow[3], radius=4.5, strength=0.75)
        else:
            p.px(cx, y + h - 2, S[1]); p.px(cx + iw - 1, y + h - 2, S[1])
    else:                                                    # horizontal index line
        cy = y + h // 2 + o
        for gy in range(y + 2 + o, y + h - 2, 2):
            if abs(gy - cy) > 1:
                p.hline(x + 2 + o, x + w - 3, gy, C[0]); p.hline(x + 2 + o, x + w - 3, gy + 1, C[4]) if gy + 1 != cy - 1 else None
        p.box(x + 1 + o, cy - 1, w - 2 - o, 3, C[0])
        p.hline(x + 1 + o, x + w - 2, cy, glow[4] if pressed else S[3])
        if pressed:
            p.hline(x + 2 + o, x + w - 3, cy, glow[5])
            p.light(x + w / 2, cy, glow[3], radius=4.5, strength=0.75)
        else:
            p.px(x + w - 2, cy, S[1])
