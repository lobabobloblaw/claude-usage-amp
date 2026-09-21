"""Walnut 76 -- the matching graphic-equaliser component (USAGE EQUALIZER)."""

from __future__ import annotations

import numpy as np

from skinkit import fonts
from skinkit.canvas import Canvas, mix
from skinkit.spec import Rect, lrect, lval

import w76_common as K
import w76_materials as M
import w76_palette as P
from w76_microfonts import PANEL, SERIF, TINY

SEAM = "#16130d"
EQ_CAPTIONS = ("-9", "-8", "-7", "-6", "-5", "-4", "-3", "-2", "-1", "NOW")


class EqWindow:
    """Mixin: every equaliser-window painter."""

    EQ_SCREWS = ((12, 110, 0), (262, 110, 45), (261, 42, 135), (261, 97, 90),
                 (48, 110, 90))

    def paint_eq_background(self, c: Canvas) -> None:
        K.fascia(c)
        K.cheeks(c, K.RAIL_H, knots_left=[(2, 52, 1.3)], knots_right=[(272, 92, 1.5)])
        K.cheek_shadow(c, K.RAIL_H, c.h - 1)
        K.rail(c)
        K.rail_ends(c)
        c.hline(0, c.w - 1, c.h - 1, "#0c0806")
        M.shade_box(c, 0, c.h - 2, c.w, 1, 0.72)

        # curve window
        g = lrect("eq", "graph")
        interior = K.rect_mask((c.h, c.w), (g.x, g.y, g.w, g.h))
        K.glass_shape(c, interior, glints=[(g.x - 2, g.y - 2, P.CHROME[3]),
                                           (g.x - 1, g.y - 2, P.CHROME[3]),
                                           (g.x - 2, g.y - 1, P.CHROME[3]),
                                           (g.x + 40, g.y - 2, P.CHROME[1]),
                                           (g.x + 41, g.y - 2, P.CHROME[1]),
                                           (g.x + 42, g.y - 2, P.CHROME[1]),
                                           (g.x + 43, g.y - 2, P.CHROME[3])])
        # engraved captions either side of the curve window

        # slider bay: a shallow machined recess the eleven pots sit in
        pre = lrect("eq", "preampSlider")
        bands = lval("eq", "bandSliders")
        bx0 = int(bands["x0"])
        bx1 = bx0 + int(bands["strideX"]) * (int(bands["count"]) - 1) + int(bands["w"]) - 1
        by, bh = int(bands["y"]), int(bands["h"])
        for (x0, x1) in ((pre.x - 3, pre.x1 + 2), (bx0 - 3, bx1 + 3)):
            bay = c.sub(x0, by - 2, x1 - x0 + 1, bh + 4)
            M.shade_box(bay, 0, 0, bay.w, bay.h, 0.90)
            bay.hline(0, bay.w - 1, 0, P.ALU[0])
            bay.vline(0, 0, bay.h - 1, P.ALU[0])
            bay.hline(1, bay.w - 1, bay.h - 1, P.ALU[6])
            bay.vline(bay.w - 1, 1, bay.h - 1, P.ALU[6])
            M.shade_box(bay, 1, 1, bay.w - 2, 1, 0.80)
            M.shade_box(bay, 1, 2, 1, bay.h - 3, 0.84)

        # scale captions and their hairline leaders
        for text, row in (("MAX", 5), ("MID", 30), ("0", 56)):
            yy = by + row
            K.engrave(c, 41, yy - 2, text, TINY)
            M.engrave_line_h(c, 41 + K.tw(text, TINY) + 2, bx0 - 6, yy)
        # band captions
        K.engrave_c(c, pre.x + pre.w // 2, by + bh + 3, "WEEK", TINY)
        for i in range(int(bands["count"])):
            cx = bx0 + int(bands["strideX"]) * i + int(bands["w"]) // 2
            K.engrave_c(c, cx, by + bh + 3, EQ_CAPTIONS[i], TINY)
        # legend row
        K.engrave(c, 56, 109, "TEN BAND USAGE EQUALIZER", TINY)
        K.engrave(c, 172, 109, "·", TINY)
        K.engrave(c, 178, 109, "MODEL TA-76E", TINY)
        # captions by the curve window
        K.engrave(c, 76, 18, "+", TINY)
        K.engrave(c, 77, 30, "-", TINY)
        K.engrave(c, 203, 24, "H", TINY)

        for sx, sy, ang in self.EQ_SCREWS:
            M.screw(c, sx, sy, ang)

    def paint_eq_title_bar(self, c: Canvas, active: bool) -> None:
        K.rail(c, knots=[(52, 6, 1.6)])
        K.rail_ends(c)
        text = "USAGE EQUALIZER"
        sw = K.tw(text, SERIF, 2) + 18
        K.name_strip(c, (c.w - sw) // 2, 2, sw, 10, text, active, spacing=2, seed=12)
        M.jewel(c, 27, 7, active, r=2, halo=0.9)
        if not active:
            M.shade_box(c, 8, 1, c.w - 16, c.h - 2, 0.90)
            M.jewel(c, 27, 7, False, r=2)
        r = lrect("eq", "closeButton")
        c.rect(r.x, r.y, r.w, r.h, P.WALNUT[0])

    def paint_eq_close(self, c: Canvas, pressed: bool) -> None:
        self.paint_title_button(c, "close", pressed)

    def paint_eq_on(self, c: Canvas, pressed: bool, selected: bool) -> None:
        self._switch(c, pressed, selected, "ON", PANEL, jewel_r=1)

    def paint_eq_auto(self, c: Canvas, pressed: bool, selected: bool) -> None:
        self._switch(c, pressed, selected, "AUTO", PANEL, jewel_r=1)

    def paint_eq_presets(self, c: Canvas, pressed: bool) -> None:
        self._switch(c, pressed, False, "RANGE", PANEL, lamp=False, arrow=True, spacing=2)

    # -- slide pots ------------------------------------------------------
    def paint_eq_slider_frame(self, c: Canvas, i: int) -> None:
        w, h = c.w, c.h
        # a black escutcheon let into the bay; x-invariant by construction
        c.fill(P.PLASTIC[0])
        X, Y = np.meshgrid(np.arange(w), np.arange(h))
        n = M._hash01(X.astype(np.int64), Y.astype(np.int64), 321)
        t = 0.10 + (n - 0.5) * 0.10
        M._put(c, M._ramp_map(P.PLASTIC, t))
        c.hline(0, w - 1, 0, "#000000")
        c.vline(0, 0, h - 1, "#000000")
        c.hline(1, w - 1, h - 1, P.PLASTIC[3])
        c.vline(w - 1, 1, h - 1, P.PLASTIC[3])
        # level ladder, lit from the bottom up
        nseg = 19
        lit_n = int(round(i / 27.0 * nseg))
        for k in range(nseg):
            t = k / (nseg - 1)
            sy = h - 6 - k * 3                  # rows sy, sy+1
            if k < lit_n:
                col = P.level_colour(t)
                c.box(2, sy, 3, 2, col)
                c.px(2, sy, mix(col, "#ffffff", 0.5))
                c.px(4, sy + 1, mix(col, "#000000", 0.25))
                c.hline(2, 4, sy + 2, mix(col, P.PLASTIC[0], 0.74))
                c.px(1, sy, mix(col, P.PLASTIC[0], 0.80))
                c.px(5, sy, mix(col, P.PLASTIC[0], 0.80))
            else:
                c.box(2, sy, 3, 2, P.level_ghost(t))
        # the slot
        c.vline(7, 4, h - 5, "#000000")
        c.vline(8, 4, h - 5, "#000000")
        c.vline(9, 5, h - 5, P.PLASTIC[3])
        c.px(7, 3, P.PLASTIC[1])
        c.hline(7, 8, h - 4, P.PLASTIC[3])
        # silk-screened ticks
        for k in range(11):
            ty = int(round(5 + 51 * k / 10.0))
            major = (k % 5 == 0)
            c.hline(11, 12 if major else 11, ty, P.CREAM if major else P.CREAM_DIM)
        c.a[:, :, 3] = 255

    def paint_eq_thumb(self, c: Canvas, pressed: bool) -> None:
        self._slider_cap(c, pressed, vertical=True)

    # -- curve window ------------------------------------------------------
    def paint_eq_graph_background(self, c: Canvas) -> None:
        c.fill(P.GLASS_FLAT)
        ghost, dim = "#07262a", P.TEAL[1]
        c.hline(0, c.w - 1, 0, "#010202")
        c.vline(0, 0, c.h - 1, "#010202")
        for k in range(10):
            gx = int(round(k * (c.w - 1) / 9.0))
            for yy in range(1, c.h, 2):
                c.px(gx, yy, ghost)
        for xx in range(0, c.w, 2):
            c.px(xx, c.h // 2, dim if xx % 4 == 0 else ghost)
        for xx in range(1, c.w, 4):
            c.px(xx, 2, ghost)
            c.px(xx, c.h - 3, ghost)
        M.glare(c, 170, slope=-0.55, width=6.0, strength=0.14)
        c.a[:, :, 3] = 255

    def eq_graph_line_colours(self):
        stops = [(0, P.RED[2]), (2, P.PILOT[2]), (5, "#c8fff6"), (8, P.TEAL[3]),
                 (14, P.TEAL[2]), (18, "#178a86")]
        out = []
        for y in range(19):
            for (a, ca), (b, cb) in zip(stops, stops[1:]):
                if a <= y <= b:
                    f = (y - a) / float(b - a)
                    out.append(tuple(int(v) for v in mix(ca, cb, f)[:3]))
                    break
        return out

    def paint_eq_preamp_line(self, c: Canvas) -> None:
        for x in range(c.w):
            c.px(x, 0, P.PILOT[1] if (x % 5) < 3 else "#2a1804")
        c.a[:, :, 3] = 255
