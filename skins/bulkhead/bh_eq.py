"""Bulkhead -- equaliser window ("USAGE EQUALIZER"): a rack unit of ten
fuel-rod gauges, a preamp rod, and a small amber graph tube."""

from __future__ import annotations

import numpy as np

import bh_digits as D
import bh_materials as M
import bh_palette as P
import bh_parts as X
import bh_type as T

GRAPH = (86, 17, 113, 19)
BAY_BANDS = (74, 37, 184, 65)     # x74..257 y37..101
BAY_PRE = (17, 37, 22, 65)        # x17..38
BAND_X0, BAND_STRIDE, BAND_W, BAND_Y, BAND_H = 78, 18, 14, 38, 63
CAPTIONS = ("-9", "-8", "-7", "-6", "-5", "-4", "-3", "-2", "-1", "NOW")


def rod_level_row(i: int) -> float:
    """Row (in frame coords) of the thumb centre for frame i."""
    return 5.0 + (1.0 - i / 27.0) * 51.0


class EqMixin:

    def paint_eq_background(self, c):
        s = self.seed + 100
        M.plate(c, seed=s, base=0.46)
        X.window_frame(c)

        # ---- graph tube in its own small casting ------------------------------
        gx, gy, gw, gh = GRAPH
        cast = M.full_mask(c, gx - 4, 14, gw + 8, gh + 6, r=2)
        M.tone_fill(c, cast, M.cast_tone(c, seed=s + 8, base=0.34), P.GUN_LUT)
        M.raise_mask(c, cast, a_hi=0.6, a_lo=0.7, contact=2, a_contact=0.5)
        X.crt_glass(c, gx, gy, gw, gh, r=2, depth=2)

        # ---- rod bays: deep pockets holding the gauge tubes --------------------
        for bay in (BAY_BANDS, BAY_PRE):
            bx, by, bw, bh = bay
            v = c.sub(bx, by, bw, bh)
            M.put_rgb(v, M.tone_rgb(M.plate_tone(v, seed=s + 23, base=0.20), P.GUN_LUT))
            M.recessed(c, bx, by, bw, bh, depth=3, a_sh=0.75, a_lip=0.45)
            # graduation lines across the bay floor: MAX / MID / 0
            for lv, a in ((27, 0.55), (13.5, 0.4), (0, 0.55)):
                yy = int(round(BAND_Y + 5 + (1 - lv / 27.0) * 51))
                M.hl(c, bx + 1, bx + bw - 2, yy, P.LEGEND[1], a * 0.6)
        # hazard band across the top of the band bay: the hot zone
        M.hazard(c, BAY_BANDS[0] + 1, BAY_BANDS[1] + 1, BAY_BANDS[2] - 2, 3, width=3, seed=s + 3,
                 chip=0.35)

        # ---- captions -------------------------------------------------------------
        for i, cap in enumerate(CAPTIONS):
            bx = BAND_X0 + BAND_STRIDE * i
            tw = T.MICRO.width(cap)
            T.draw(c, bx + (BAND_W - tw) // 2 + 0, 104, cap, T.MICRO,
                   P.LEGEND[3] if cap == "NOW" else P.LEGEND[2], a=0.92, wear=0.2, seed=s + i)
        T.draw(c, 20, 104, "WEEK", T.MICRO, P.LEGEND[2], a=0.92, wear=0.2, seed=s + 11)
        for text, lv in (("MAX", 27), ("MID", 13.5), ("0", 0)):
            yy = int(round(BAND_Y + 5 + (1 - lv / 27.0) * 51))
            tw = T.MICRO.width(text)
            T.draw(c, 71 - tw, yy - 2, text, T.MICRO, P.LEGEND[2], a=0.92, wear=0.15, seed=s + 12)
            M.hl(c, 72, 73, yy, P.LEGEND[2], 0.8)
            M.hl(c, 40, 42, yy, P.LEGEND[2], 0.8)

        # ---- stencils, plates, fasteners -----------------------------------------
        # vertical louvre stack at the right
        X.louvres(c, 261, 40, 9, 8, pitch=4)
        # strap along the bottom, same as the main unit
        v = c.sub(2, 110, c.w - 4, 4)
        M.put_rgb(v, M.tone_rgb(M.plate_tone(v, seed=s + 31, base=0.40), P.GUN_LUT))
        M.hl(c, 2, c.w - 3, 110, P.GUN[6], 0.8)
        M.hl(c, 2, c.w - 3, 109, P.SHADOW, 0.25)
        M.hex_bolt(c, 7, 22, 3, mark=1)
        M.oil_streak(c, 7, 28, 7, seed=5, a0=0.5)
        M.hex_bolt(c, 267, 24, 0, mark=2)
        M.oil_streak(c, 268, 30, 8, seed=6, a0=0.5)
        M.hex_bolt(c, 7, 104, 1, mark=0)
        M.hex_bolt(c, 267, 104, 2, mark=1)

    # ------------------------------------------------------------------
    def paint_eq_title_bar(self, c, active):
        X.title_strip_base(c, active, seed=self.seed + 100)
        X.rail_tube(c, 12, 252, 3, 10, active, seed=self.seed + 100,
                    knurl=((0.03, 0.27), (0.73, 0.97)))
        title = "USAGE EQUALIZER"
        tw = T.STENCIL.width(title)
        bx0 = (c.w - tw) // 2 - 5
        M.box(c, bx0, 2, tw + 10, 10, P.GUN[0])
        v = c.sub(bx0 + 1, 3, tw + 8, 8)
        M.put_rgb(v, M.tone_rgb(M.plate_tone(v, seed=self.seed + 144, base=0.36, vgrad=0), P.GUN_LUT))
        M.hl(c, bx0 + 1, bx0 + tw + 8, 3, P.GUN[6], 0.6)
        M.hl(c, bx0 + 1, bx0 + tw + 8, 10, P.GUN[0], 0.7)
        col = P.LEGEND[3] if active else P.LEGEND[1]
        T.draw(c, bx0 + 5, 3, title, T.STENCIL, col, a=1.0, wear=0.10, seed=self.seed + 106)
        X.tiny_lamp(c, 5, 5, P.LAMP_AMBER, active)
        X.tiny_lamp(c, 257, 5, P.LAMP_AMBER, active)

    def paint_eq_close(self, c, pressed):
        X.mini_key(c, "close", pressed)

    def paint_eq_on(self, c, pressed, selected):
        X.toggle(c, pressed, selected, "ON", P.GREEN, lamp_w=4, seed=self.seed + 111)

    def paint_eq_auto(self, c, pressed, selected):
        X.toggle(c, pressed, selected, "AUTO", P.LAMP_AMBER, lamp_w=4, seed=self.seed + 112)

    def paint_eq_presets(self, c, pressed):
        X.toggle(c, pressed, False, "RANGE", P.LAMP_AMBER, lamp_w=0, seed=self.seed + 113, arrow=True)

    # ------------------------------------------------------------------
    def paint_eq_slider_frame(self, c, i):
        """14x63 fuel rod.  x-invariant: painted entirely in local coordinates."""
        w, h = c.w, c.h
        # bay floor behind the rod
        for y in range(h):
            M.hl(c, 0, w - 1, y, P.GUN[1])
        g = M._hash01(np.arange(w)[None, :].repeat(h, 0), np.arange(h)[:, None].repeat(w, 1), 777)
        M.blend_mask(c, (g > 0.6).astype(np.float32) * 0.18, P.GUN[0])
        # graduation lines continue across the floor
        for lv, a in ((27, 0.33), (13.5, 0.24), (0, 0.33)):
            yy = int(round(5 + (1 - lv / 27.0) * 51))
            M.hl(c, 0, w - 1, yy, P.LEGEND[1], a)
        for k in range(1, 27):
            yy = int(round(5 + (1 - k / 27.0) * 51))
            if k % 3 == 0:
                M.hl(c, 11, 12, yy, P.LEGEND[1], 0.5)
        # hazard band at the top (continues the bay's)
        # glass tube x3..9
        M.box(c, 2, 0, 9, h, P.GUN[0])
        M.box(c, 3, 1, 7, h - 2, (8, 9, 10))
        level = rod_level_row(i)
        for k in range(20):
            y1 = 60 - k * 3
            y0 = y1 - 1
            f = k / 19.0
            ramp = X.ladder_colour(f)
            mid = (y0 + y1) / 2.0
            if i > 0 and mid >= level - 0.01:
                part = 1.0
            elif i > 0 and y1 >= level - 1.2:
                part = 0.5
            else:
                part = 0.0
            if part >= 1.0:
                M.box(c, 4, y0, 5, 2, ramp[4])
                M.hl(c, 4, 8, y0, ramp[5])
                M.pset(c, 5, y0, ramp[6])
                M.pset(c, 6, y0, ramp[6])
                M.box(c, 3, y0, 1, 2, ramp[3], 0.6)       # glow on the tube wall
                M.box(c, 9, y0, 1, 2, ramp[2], 0.6)
                M.hl(c, 4, 8, y1 + 1, ramp[2], 0.55)
            elif part > 0:
                M.box(c, 4, y0, 5, 2, ramp[3])
                M.hl(c, 4, 8, y0, ramp[4], 0.6)
            else:
                M.box(c, 4, y0, 5, 2, ramp[1])
                M.hl(c, 4, 8, y0, ramp[2], 0.45)
        # glass highlight down the left of the tube, shadow down the right
        M.vl(c, 3, 2, h - 3, (190, 205, 215), 0.20)
        M.vl(c, 4, 2, h - 3, (190, 205, 215), 0.08)
        M.vl(c, 9, 2, h - 3, P.SHADOW, 0.35)
        # steel end caps
        for y in (0, h - 3):
            M.box(c, 1, y, 11, 3, P.STEEL[2])
            M.hl(c, 1, 11, y, P.STEEL[5])
            M.hl(c, 1, 11, y + 2, P.STEEL[0])
            M.pset(c, 1, y, P.STEEL[6])
        c.a[:, :, 3] = 255

    def paint_eq_thumb(self, c, pressed):
        X.knob(c, pressed, seed=self.seed + 120, vertical=True)

    def paint_eq_graph_background(self, c):
        X.glass_rows(c, 0, 0, c.w, c.h)
        # graticule: dotted verticals every 12 px (one per band), solid centre line
        for k in range(10):
            gx = int(round(k * (c.w - 1) / 9.0))
            for y in range(0, c.h, 2):
                M.pset(c, gx, y, P.AMBER_GHOST2)
        for x in range(0, c.w, 2):
            M.pset(c, x, c.h // 2, P.AMBER_DIM, 0.7)
        for y in (0, c.h - 1):
            for x in range(0, c.w, 4):
                M.pset(c, x, y, P.AMBER_DIM, 0.6)
        c.a[:, :, 3] = 255

    def eq_graph_line_colours(self):
        stops = [(0.00, P.hx("#ff3a1c")), (0.18, P.hx("#ff7a18")), (0.40, P.AMBER_BRIGHT),
                 (0.75, P.hx("#e08a10")), (1.00, P.AMBER_MID)]
        out = []
        for y in range(19):
            t = y / 18.0
            for a in range(len(stops) - 1):
                if stops[a][0] <= t <= stops[a + 1][0]:
                    f = (t - stops[a][0]) / (stops[a + 1][0] - stops[a][0])
                    out.append(tuple(int(v) for v in P.mixc(stops[a][1], stops[a + 1][1], f)))
                    break
        return out

    def paint_eq_preamp_line(self, c):
        for x in range(c.w):
            M.pset(c, x, 0, P.AMBER_LOW if (x % 4) < 2 else P.AMBER_DIM)
        c.a[:, :, 3] = 255
