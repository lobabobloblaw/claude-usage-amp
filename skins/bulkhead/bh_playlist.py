"""Bulkhead -- playlist window ("SESSIONS"): a steel-framed amber terminal.

Tile discipline: the top strip is periodic every 25 px in x, the side rails
every 29 px in y (phase-locked to the list top at y = 20), and every corner /
title piece samples the same periodic fields, so nothing seams.  Horizontal
lines never stop short of a tile edge; vertical relief lives only in the
corner pieces.
"""

from __future__ import annotations

import numpy as np

import bh_materials as M
import bh_palette as P
import bh_parts as X
import bh_type as T

W, H = 275, 232
TOP, BOT, LEFT, RIGHT = 20, 38, 12, 20
PX, PY = 25, 29

GLASS_SH1 = (3, 2, 1)        # darkest inner-shadow row/column of the list glass
GLASS_SH2 = (6, 4, 1)


def _cast_wrap(c, seed: int, axis: str, base: float = 0.40):
    """Cast bezel tone, periodic along ``axis`` ('x' every 25, 'y' every 29 from y=20)."""
    Xg, Yg = M.grid(c)
    if axis == "x":
        Xw = np.mod(Xg, PX)
        g = M.grain(Xw, Yg, seed + 51)
        b = M.vnoise(Xw, Yg, PX / 8.0, 3.0, seed + 52, wrapx=8)
        w = M.fbm(Xw, Yg, 0, seed + 53, octaves=2, sx=PX / 2.0, sy=9.0, wrapx=2)
    else:
        Yw = np.mod(Yg - TOP, PY)
        g = M.grain(Xg, Yw, seed + 51)
        b = M.vnoise(Xg, Yw, 3.0, PY / 10.0, seed + 52, wrapy=10)
        w = M.fbm(Xg, Yw, 0, seed + 53, octaves=2, sx=9.0, sy=PY / 2.0, wrapy=2)
    return (base + (g - 0.5) * 0.06 + (b - 0.5) * 0.07 + (w - 0.5) * 0.10).astype(np.float32)


def _socket(c, x, y):
    M.stamp(c, x, y, ["dKd", "KkK", "lKl"],
            {"d": (P.SHADOW, 0.6), "K": P.GUN[0], "k": P.GUN[3], "l": (P.HILITE, 0.4)})


class PlaylistMixin:

    # ------------------------------------------------------------------
    # top strip
    # ------------------------------------------------------------------
    def _pl_top_base(self, c, active):
        """Rows 0..13 rail channel (as on the other units), rows 14..19 the top
        limb of the terminal bezel: lit edge, face, wall in shadow, gasket, and
        the first -- darkest -- row of glass."""
        s = self.seed + 200
        X.title_strip_base(c, active, seed=s, wrap_px=PX, rows=14)
        v = c.sub(0, 14, c.w, 6)
        M.put_rgb(v, M.tone_rgb(_cast_wrap(v, s, "x"), P.GUN_LUT))
        M.hl(c, 0, c.w - 1, 14, P.GUN[7], 0.8)
        M.hl(c, 0, c.w - 1, 15, P.HILITE, 0.18)
        M.hl(c, 0, c.w - 1, 17, P.GUN[0])
        M.hl(c, 0, c.w - 1, 18, P.RUBBER[1])
        M.hl(c, 0, c.w - 1, 19, GLASS_SH1)

    def _rail(self, c, x0, x1, active, knurl=()):
        X.rail_tube(c, x0, x1, 3, 10, active, seed=self.seed + 200, knurl=knurl, wrap_px=PX)

    def paint_pl_top_tile(self, c, active):
        self._pl_top_base(c, active)
        self._rail(c, 0, c.w - 1, active)
        M.hl(c, 0, c.w - 1, 11, P.SHADOW, 0.55)

    def paint_pl_top_left(self, c, active):
        self._pl_top_base(c, active)
        self._rail(c, 12, c.w - 1, active, knurl=((0.25, 1.0),))
        M.hl(c, 12, c.w - 1, 11, P.SHADOW, 0.55)
        # rail end post
        M.box(c, 9, 2, 4, 10, P.GUN[0])
        M.box(c, 10, 3, 2, 8, P.STEEL[3])
        M.vl(c, 10, 3, 10, P.STEEL[5])
        M.pset(c, 10, 3, P.STEEL[6])
        X.tiny_lamp(c, 4, 5, P.LAMP_AMBER, active)
        # window edge
        M.vl(c, 0, 0, c.h - 1, P.GUN[0])
        M.vl(c, 1, 1, c.h - 1, P.GUN[6], 0.6)
        M.pset(c, 1, 1, P.STEEL[5])
        # bezel corner: the top limb turns down into the left limb
        v = c.sub(2, 14, 6, 6)
        M.put_rgb(v, M.tone_rgb(_cast_wrap(v, self.seed + 201, "y"), P.GUN_LUT))
        M.hl(c, 2, 7, 14, P.GUN[7], 0.8)
        M.vl(c, 8, 17, 19, P.GUN[0])
        M.vl(c, 9, 18, 19, P.RUBBER[1])
        M.vl(c, 10, 19, 19, GLASS_SH1)
        M.pset(c, 11, 19, GLASS_SH1)
        M.pset(c, 8, 17, P.GUN[0])
        _socket(c, 3, 15)

    def paint_pl_top_right(self, c, active):
        self._pl_top_base(c, active)
        self._rail(c, 0, 0, active)
        M.box(c, 0, 2, 4, 10, P.GUN[0])
        M.box(c, 1, 3, 2, 8, P.STEEL[3])
        M.vl(c, 1, 3, 10, P.STEEL[5])
        M.pset(c, 1, 3, P.STEEL[6])
        # window edge
        M.vl(c, c.w - 1, 0, c.h - 1, P.GUN[0])
        M.vl(c, c.w - 2, 1, c.h - 1, P.GUN[1], 0.85)
        # bezel corner on the right: gasket and wall turn down (lit side)
        v = c.sub(7, 14, 16, 6)
        M.put_rgb(v, M.tone_rgb(_cast_wrap(v, self.seed + 202, "y"), P.GUN_LUT))
        M.hl(c, 7, c.w - 3, 14, P.GUN[7], 0.8)
        M.hl(c, 5, 6, 17, P.GUN[0])
        M.hl(c, 5, 5, 18, P.RUBBER[1])
        M.pset(c, 5, 19, P.RUBBER[4])
        M.pset(c, 6, 18, P.GUN[2])
        M.pset(c, 6, 19, P.GUN[6])
        M.vl(c, c.w - 2, 14, 19, P.GUN[1], 0.85)
        _socket(c, 19, 15)
        # collapse key is part of the corner art (its pressed sprite replaces it)
        X.mini_key(c.sub(4, 3, 9, 9), "shade", False)

    def paint_pl_title(self, c, active):
        self._pl_top_base(c, active)
        s = self.seed + 200
        self._rail(c, 0, c.w - 1, active, knurl=((0.0, 0.20), (0.80, 1.0)))
        M.hl(c, 0, c.w - 1, 11, P.SHADOW, 0.55)
        title = "SESSIONS"
        tw = T.STENCIL.width(title)
        bx0 = (c.w - tw) // 2 - 5
        M.box(c, bx0, 2, tw + 10, 10, P.GUN[0])
        v = c.sub(bx0 + 1, 3, tw + 8, 8)
        M.put_rgb(v, M.tone_rgb(M.plate_tone(v, seed=s + 44, base=0.36, vgrad=0), P.GUN_LUT))
        M.hl(c, bx0 + 1, bx0 + tw + 8, 3, P.GUN[6], 0.6)
        M.hl(c, bx0 + 1, bx0 + tw + 8, 10, P.GUN[0], 0.7)
        col = P.LEGEND[3] if active else P.LEGEND[1]
        T.draw(c, bx0 + 5, 3, title, T.STENCIL, col, a=1.0, wear=0.10, seed=s + 6)

    # ------------------------------------------------------------------
    # side rails (tiled vertically: nothing here may vary in y except the
    # periodic cast texture and the one socket screw per tile)
    # ------------------------------------------------------------------
    def paint_pl_left_tile(self, c):
        s = self.seed + 200
        M.put_rgb(c, M.tone_rgb(_cast_wrap(c, s + 1, "y"), P.GUN_LUT))
        M.vl(c, 0, 0, c.h - 1, P.GUN[0])
        M.vl(c, 1, 0, c.h - 1, P.GUN[6], 0.6)
        M.vl(c, 2, 0, c.h - 1, P.HILITE, 0.12)
        M.vl(c, 7, 0, c.h - 1, P.SHADOW, 0.35)
        M.vl(c, 8, 0, c.h - 1, P.GUN[0])            # wall, in shadow
        M.vl(c, 9, 0, c.h - 1, P.RUBBER[1])         # gasket
        M.vl(c, 10, 0, c.h - 1, GLASS_SH1)          # glass, inner shadow
        M.vl(c, 11, 0, c.h - 1, GLASS_SH2)
        _socket(c, 3, 13)

    def paint_pl_right_tile(self, c):
        s = self.seed + 200
        M.put_rgb(c, M.tone_rgb(_cast_wrap(c, s + 2, "y"), P.GUN_LUT))
        M.vl(c, 0, 0, c.h - 1, P.RUBBER[4])         # gasket, lit side
        M.vl(c, 1, 0, c.h - 1, P.GUN[6])            # wall facing the light
        M.vl(c, 2, 0, c.h - 1, P.HILITE, 0.10)
        # slotted rail for the scroll slider: slot x4..13, the handle rides x5..12
        M.vl(c, 3, 0, c.h - 1, P.SHADOW, 0.75)
        M.box(c, 4, 0, 10, c.h, P.GUN[0])
        M.box(c, 5, 0, 8, c.h, (10, 12, 14))
        M.vl(c, 5, 0, c.h - 1, P.SHADOW)
        M.vl(c, 8, 0, c.h - 1, P.STEEL[3])          # guide rod
        M.vl(c, 9, 0, c.h - 1, P.STEEL[1])
        M.vl(c, 14, 0, c.h - 1, P.GUN[6], 0.6)      # lit lip of the slot
        M.vl(c, 18, 0, c.h - 1, P.GUN[1], 0.85)
        M.vl(c, 19, 0, c.h - 1, P.GUN[0])
        # graduation ticks beside the slot, one long + four short per tile
        for k, y in enumerate((2, 8, 14, 20, 26)):
            M.hl(c, 15, 16 if k else 17, y, P.LEGEND[2], 0.75)

    # ------------------------------------------------------------------
    # bottom: status strip
    # ------------------------------------------------------------------
    def _pl_bottom_base(self, c):
        s = self.seed + 200
        M.put_rgb(c, M.tone_rgb(_cast_wrap(c, s + 3, "x"), P.GUN_LUT))
        M.hl(c, 0, c.w - 1, 0, P.RUBBER[4])          # gasket, lit side
        M.hl(c, 0, c.w - 1, 1, P.GUN[6])             # wall facing the light
        M.hl(c, 0, c.w - 1, 2, P.HILITE, 0.10)
        # the status tray: a long pocket, rows 6..31
        M.hl(c, 0, c.w - 1, 5, P.SHADOW, 0.75)
        tray = c.sub(0, 6, c.w, 26)
        M.put_rgb(tray, M.tone_rgb(_cast_wrap(tray, s + 4, "x", base=0.22), P.GUN_LUT))
        M.hl(c, 0, c.w - 1, 6, P.SHADOW, 0.6)
        M.hl(c, 0, c.w - 1, 7, P.SHADOW, 0.25)
        M.hl(c, 0, c.w - 1, 32, P.GUN[6], 0.55)
        M.hl(c, 0, c.w - 1, c.h - 2, P.GUN[1], 0.85)
        M.hl(c, 0, c.w - 1, c.h - 1, P.GUN[0])

    def paint_pl_bottom_tile(self, c):
        self._pl_bottom_base(c)

    def paint_pl_bottom_left(self, c):
        self._pl_bottom_base(c)
        s = self.seed + 200
        # left limb of the bezel comes down through the corner
        v = c.sub(0, 0, 12, c.h)
        M.put_rgb(v, M.tone_rgb(_cast_wrap(v, s + 1, "y"), P.GUN_LUT))
        M.vl(c, 0, 0, c.h - 1, P.GUN[0])
        M.vl(c, 1, 0, c.h - 2, P.GUN[6], 0.6)
        M.vl(c, 2, 0, c.h - 3, P.HILITE, 0.12)
        M.vl(c, 8, 0, 0, P.GUN[0])
        M.pset(c, 9, 0, P.RUBBER[1])
        M.pset(c, 10, 0, P.RUBBER[4])
        M.pset(c, 11, 0, P.RUBBER[4])
        M.pset(c, 9, 1, P.GUN[6])
        M.hl(c, 2, 11, c.h - 2, P.GUN[1], 0.85)
        M.hl(c, 0, 11, c.h - 1, P.GUN[0])
        # tray starts after the limb
        M.vl(c, 12, 6, 31, P.SHADOW, 0.8)
        M.vl(c, 13, 7, 31, P.SHADOW, 0.35)
        M.hex_bolt(c, 6, 27, 1, mark=1)
        M.oil_streak(c, 6, 33, 3, seed=11, a0=0.45)
        # hazard end-cap, maker's plate, louvres, power jewel
        M.hazard(c, 15, 8, 8, 23, width=3, seed=s + 8, chip=0.35)
        x, y, w, h = 27, 9, 47, 21
        m = M.full_mask(c, x, y, w, h, r=1)
        sub = c.sub(x, y, w, h)
        M.put_rgb(sub, M.tone_rgb(M.steel_tone(sub, seed=s + 9, base=0.60, strength=0.7),
                                  P.STEEL_LUT, 40), mask=M.round_mask(w, h, 1).astype(np.float32))
        M.raise_mask(c, m, a_hi=0.6, a_lo=0.55, contact=1, a_contact=0.6)
        T.draw(c, x + 5, y + 2, "SESSION", T.MICRO, P.GUN[0], a=0.9)
        T.draw(c, x + 5, y + 8, "LOG", T.MICRO, P.GUN[0], a=0.9)
        T.draw(c, x + 20, y + 8, "T-04", T.MICRO, P.RED[2], a=0.9)
        M.hl(c, x + 4, x + w - 5, y + 14, P.GUN[0], 0.5)
        T.draw(c, x + 5, y + 15, "N.4773-B", T.MICRO, P.GUN[1], a=0.8)
        for (rx, ry) in ((x + 1, y + 1), (x + w - 3, y + 1), (x + 1, y + h - 3), (x + w - 3, y + h - 3)):
            M.pset(c, rx, ry, P.STEEL[6])
            M.pset(c, rx + 1, ry, P.STEEL[3])
            M.pset(c, rx, ry + 1, P.STEEL[3])
            M.pset(c, rx + 1, ry + 1, P.STEEL[0])
        X.louvres(c, 79, 10, 22, 7, pitch=3)
        # power jewel
        X.tiny_lamp(c, 108, 12, P.GREEN, True, size=4)
        T.draw(c, 106, 21, "PWR", T.MICRO, P.LEGEND[2], a=0.9)
        M.scratch(c, 84, 33, 99, 34, a=0.3)

    def paint_pl_bottom_right(self, c):
        self._pl_bottom_base(c)
        s = self.seed + 200
        # right limb of the bezel: slot rail ends in a stop, window edge
        v = c.sub(c.w - 20, 0, 20, c.h)
        M.put_rgb(v, M.tone_rgb(_cast_wrap(v, s + 2, "y"), P.GUN_LUT))
        bx = c.w - 20
        M.pset(c, bx, 0, P.RUBBER[4])
        M.vl(c, bx + 1, 0, 1, P.GUN[6])
        M.hl(c, bx + 2, c.w - 3, 1, P.HILITE, 0.0)
        # slot end
        M.box(c, bx + 4, 0, 10, 4, P.GUN[0])
        M.box(c, bx + 5, 0, 8, 3, (10, 12, 14))
        M.vl(c, bx + 8, 0, 1, P.STEEL[3])
        M.vl(c, bx + 9, 0, 1, P.STEEL[1])
        M.box(c, bx + 7, 1, 4, 2, P.STEEL[2])
        M.hl(c, bx + 7, bx + 10, 1, P.STEEL[5])
        M.hl(c, bx + 4, bx + 13, 4, P.GUN[6], 0.6)
        M.vl(c, bx + 14, 0, 3, P.GUN[6], 0.6)
        M.vl(c, bx + 3, 0, 3, P.SHADOW, 0.75)
        M.vl(c, c.w - 2, 0, c.h - 2, P.GUN[1], 0.85)
        M.vl(c, c.w - 1, 0, c.h - 1, P.GUN[0])
        M.hl(c, bx, c.w - 1, c.h - 2, P.GUN[1], 0.85)
        M.hl(c, 0, c.w - 1, c.h - 1, P.GUN[0])
        M.vl(c, bx - 1, 6, 31, P.GUN[6], 0.45)       # tray's far wall, lit
        M.hex_bolt(c, c.w - 10, 27, 3, mark=2)
        M.oil_streak(c, c.w - 10, 33, 3, seed=12, a0=0.45)
        silk = lambda x, y, t, col=P.LEGEND[2]: T.draw(c, x, y, t, T.MICRO, col, a=0.9)  # noqa: E731
        silk(bx + 3, 9, "PL", P.LEGEND[1])
        silk(bx + 3, 15, "04", P.LEGEND[1])
        # readout tubes (their interiors are the flat glyph background)
        X.crt_glass(c, 4, 8, 110, 10, r=2, depth=2)
        M.box(c, 7, 10, 104, 6, self.text_background())
        X.crt_glass(c, 60, 21, 36, 10, r=2, depth=2)
        M.box(c, 63, 23, 30, 6, self.text_background())
        # silk-screened captions in the tray
        silk(8, 23, "RESET IN")
        M.hl(c, 42, 56, 25, P.LEGEND[1], 0.8)
        M.pset(c, 55, 24, P.LEGEND[1], 0.8)
        M.pset(c, 55, 26, P.LEGEND[1], 0.8)
        silk(101, 23, "H:M", P.LEGEND[1])
        silk(118, 10, "DAY", P.LEGEND[1])
        _socket(c, 117, 25)

    def paint_pl_visualizer_background(self, c):
        self._pl_bottom_base(c)
        X.crt_glass(c, 3, 9, c.w - 6, 20, r=2, depth=2)
        c.a[:, :, 3] = 255

    def paint_pl_scroll_handle(self, c, pressed):
        X.knob(c, pressed, seed=self.seed + 220, vertical=True)

    def paint_pl_close(self, c, pressed):
        X.mini_key(c, "close", pressed)

    def paint_pl_collapse(self, c, pressed):
        X.mini_key(c, "shade", pressed)

    # ------------------------------------------------------------------
    # list colours + typeface
    # ------------------------------------------------------------------
    def pledit_colours(self):
        return {"Normal": "#D98214", "Current": "#FFE2A0", "NormalBG": P.hexs(P.AMBER_WELL),
                "SelectedBG": "#3A1E03", "Font": "Arial"}

    def pl_font_cell(self):
        import bh_plfont
        return (bh_plfont.CELL_W, bh_plfont.CELL_H)

    def paint_pl_font_glyph(self, c, ch):
        import bh_plfont
        cov = bh_plfont.coverage(ch)
        v = np.clip(np.rint(cov * 255), 0, 255).astype(np.uint8)
        c.a[:, :, 0] = v
        c.a[:, :, 1] = v
        c.a[:, :, 2] = v
        c.a[:, :, 3] = 255

    def pl_font_metrics(self):
        return {"Monospace": 0, "Spacing": 1, "SpaceWidth": 3, "RowHeight": 11, "OffsetY": 1}
