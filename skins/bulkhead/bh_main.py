"""Bulkhead -- main window painters."""

from __future__ import annotations

import numpy as np

import bh_digits as D
import bh_materials as M
import bh_palette as P
import bh_parts as X
import bh_type as T

# ---- geometry (window coords) ---------------------------------------------
BAND = (2, 14, 17, 57)            # chipped orange paint band behind the clutterbar
CAST_L = (19, 14, 88, 51)         # casting, left limb: main tube     x19..106 y14..64
CAST_R = (107, 14, 165, 45)       # casting, right limb: strip+data   x107..271 y14..58
GLASS_A = (23, 22, 78, 40)        # main tube                         x23..100 y22..61
GLASS_B = (108, 22, 160, 14)      # message strip                     x108..267 y22..35
GLASS_C = (108, 40, 102, 10)      # data tube                         x108..209 y40..49
LEGEND_Y = 52                     # SESSION / WEEK stencils on the casting lip, y52..56
TRAY_T = (14, 86, 146, 21)        # transport tray                    x14..159 y86..106
TRAY_S = (162, 87, 78, 19)        # cycle/alert tray                  x162..239 y87..105
STRAP_Y = 107

MARQUEE = (111, 27, 154, 6)
KBPS = (111, 43, 15, 6)
KHZ = (156, 43, 10, 6)
VIZ = (24, 43, 76, 16)
TIME_BAND = (36, 26, 64, 13)      # minus sign + four digits + colon: x36..99
ICONS = (24, 28, 11, 9)           # work LED + play-state


def _keepout(c):
    k = np.zeros((c.h, c.w), dtype=bool)
    for (x, y, w, h) in (MARQUEE, KBPS, KHZ, VIZ, TIME_BAND, ICONS):
        k[y:y + h, x:x + w] = True
    return k


def silk(c, x, y, text, col=None, a=0.92, face=None, wear=0.0, seed=0):
    """Silk-screened micro label: flat ink, no relief (relief turns 3x5 to mush)."""
    return T.draw(c, x, y, text, T.MICRO if face is None else face,
                  P.LEGEND[2] if col is None else col, a=a, wear=wear, seed=seed)


class MainMixin:
    """Every main-window painter and the display data hooks."""

    # ------------------------------------------------------------------
    # background
    # ------------------------------------------------------------------
    def paint_main_background(self, c):
        s = self.seed
        M.plate(c, seed=s, base=0.47)
        # a slightly different batch of plate for the lower deck
        lower = c.sub(0, 84, c.w, c.h - 84)
        M.put_rgb(lower, M.tone_rgb(M.plate_tone(lower, seed=s + 17, base=0.44), P.GUN_LUT))
        X.window_frame(c)

        self._paint_band(c)
        self._paint_casting(c)
        self._paint_gauge_bay(c)
        self._paint_lower_deck(c)
        self._paint_fasteners(c)

    # -- orange band -----------------------------------------------------
    def _paint_band(self, c):
        x, y, w, h = BAND
        M.paint_layer(c, x, y, w, h, seed=self.seed + 2, base=0.50, chip=0.42, edge_bias=0.30)
        # the band's edges: a masking-tape line where it was sprayed
        M.vl(c, x + w, y + 1, y + h - 1, P.SHADOW, 0.35)
        # inventory code sprayed up the band in black (reads bottom-to-top)
        m = np.rot90(T.MICRO.mask("ENG-04"), 1)
        mh, mw = m.shape
        sx, sy = x + 1, y + 16
        sub = c.sub(sx, sy, mw, mh)
        Xg, Yg = M.grid(sub)
        n = M.fbm(Xg, Yg, 0, self.seed + 5, octaves=2, sx=3.0, sy=4.0)
        cur = sub.a[:, :, :3].astype(np.int32)
        is_orange = (cur[:, :, 0] - cur[:, :, 2]) > 70
        a = m.astype(np.float32) * np.clip(1.25 - n * 0.8, 0.45, 0.95) * is_orange
        M.blend_mask(sub, a, P.HAZ_K[0])
        # clutterbar pocket: the keys sit in a slot cut through the paint
        M.box(c, 9, 21, 10, 45, P.GUN[0])
        M.hl(c, 9, 18, 66, P.ORANGE[6], 0.5)
        M.vl(c, 19, 21, 65, P.GUN[6], 0.3)

    # -- the CRT casting ---------------------------------------------------
    def _paint_casting(self, c):
        s = self.seed
        mask = M.full_mask(c, *CAST_L, r=2) | M.full_mask(c, *CAST_R, r=2)
        tone = M.cast_tone(c, seed=s + 8, base=0.40)
        M.tone_fill(c, mask, tone, P.GUN_LUT)
        M.raise_mask(c, mask, a_hi=0.70, a_lo=0.75, contact=2, a_contact=0.55)
        # inner chamfer line: the casting is thick, its top face starts 1px in
        inner = M.full_mask(c, CAST_L[0] + 1, CAST_L[1] + 1, CAST_L[2] - 2, CAST_L[3] - 2, r=1) | \
            M.full_mask(c, CAST_R[0] + 1, CAST_R[1] + 1, CAST_R[2] - 2, CAST_R[3] - 2, r=1)
        bot = inner & ~M._shift(inner, 0, -1)
        M.blend_mask(c, bot.astype(np.float32) * 0.30, P.SHADOW)
        M.edge_wear(c, CAST_L[0], CAST_L[1], CAST_L[2] + CAST_R[2], 1, seed=s + 70, amount=0.5,
                    sides="t")
        M.edge_wear(c, CAST_L[0], CAST_L[1], 1, CAST_L[3], seed=s + 71, amount=0.5, sides="l")

        ga = X.crt_glass(c, *GLASS_A, r=3, depth=3)
        gb = X.crt_glass(c, *GLASS_B, r=2, depth=2)
        gc = X.crt_glass(c, *GLASS_C, r=2, depth=2, lip_bottom=False)   # legends below
        glass = ga | gb | gc
        keep = _keepout(c)

        # ---- static phosphor furniture (burned-in graticule & captions) ----
        # baseline + bar ticks under the spectrum
        M.hl(c, VIZ[0], VIZ[0] + VIZ[2] - 1, 60, P.AMBER_DIM, 0.75)
        for k in range(20):
            M.pset(c, min(VIZ[0] + k * 4, VIZ[0] + VIZ[2] - 1), 59,
                   P.AMBER_LOW if k % 5 == 0 else P.AMBER_DIM, 0.9)
        # dotted rule between the clock and the spectrum
        for xx in range(VIZ[0], VIZ[0] + VIZ[2], 2):
            M.pset(c, xx, 41, P.AMBER_GHOST2)
        # character-cell registration dots under the marquee
        for xx in range(MARQUEE[0], MARQUEE[0] + MARQUEE[2], 5):
            M.pset(c, xx, 34, P.AMBER_DIM, 0.8)
        # captions drawn by the tube itself, dimmer than live text
        T.draw(c, KBPS[0] + KBPS[2] + 3, KBPS[1], "K/MIN", T.CRT, P.AMBER_LOW)
        T.draw(c, KHZ[0] + KHZ[2] + 3, KHZ[1], "ACTIVE", T.CRT, P.AMBER_LOW)
        # field brackets
        for (fx0, fx1) in ((KBPS[0] - 2, KBPS[0] + KBPS[2] + 0), (KHZ[0] - 2, KHZ[0] + KHZ[2] + 0)):
            M.pset(c, fx0, KBPS[1] - 1, P.AMBER_DIM)
            M.pset(c, fx0, KBPS[1] + 6, P.AMBER_DIM)
            M.pset(c, fx0 + 1, KBPS[1] - 1, P.AMBER_DIM, 0.6)
            M.pset(c, fx0 + 1, KBPS[1] + 6, P.AMBER_DIM, 0.6)

        # ---- glare on the curved glass (never over a dynamic well) ----------
        X.glare(c, glass, keep, strength=0.20, offset=58.0, slope=0.62, width=8.0)
        X.glare(c, glass, keep, strength=0.12, offset=306.0, slope=0.62, width=12.0, second=False)
        # soft top-edge reflection following the curve of each tube
        for (gx, gy, gw, gh) in (GLASS_A, GLASS_B, GLASS_C):
            n = int(gw * 0.7)
            for i in range(n):
                a = 0.20 * (1.0 - i / n) ** 1.4
                M.pset(c, gx + 4 + i, gy + 1, (255, 236, 200), a)
            M.pset(c, gx + 3, gy + 2, (255, 236, 200), 0.14)
            M.pset(c, gx + 2, gy + 3, (255, 236, 200), 0.12)
            M.pset(c, gx + 2, gy + 4, (255, 236, 200), 0.08)

        # ---- wells stay clean: restore every dynamic rect to its flat colour --
        for r in (MARQUEE, KBPS, KHZ):
            M.box(c, *r, self.text_background())
        M.box(c, *VIZ, self.viz_bg)
        X.glass_rows(c, *TIME_BAND)
        X.glass_rows(c, *ICONS)
        # ghost of the minus bar + the baked colon
        M.put_rgb(c, D.cell("blank", wy0=26, ghost_all=False), x=38, y=26)
        M.put_rgb(c, D.colon(26), x=71, y=26)

        # ---- casting furniture ------------------------------------------------
        # the glare streak continues across the metal of the bezel
        Xg, Yg = M.grid(c)
        t = Xg + Yg / 0.62 - 58.0
        a = np.clip(1.0 - np.abs(t) / 8.0, 0, 1) ** 1.5 * 0.13
        a2 = np.clip(1.0 - np.abs(t - 248.0) / 12.0, 0, 1) ** 1.5 * 0.08
        M.blend_mask(c, (np.maximum(a, a2) * (mask & ~glass)).astype(np.float32), P.HILITE)
        # silk-screened designators on the top rail
        silk(c, 27, 15, "A1", P.ORANGE[4], a=0.9)
        silk(c, 38, 15, "CHRONO/FLOW", P.LEGEND[3], a=0.85)
        silk(c, 112, 15, "A2", P.ORANGE[4], a=0.9)
        silk(c, 123, 15, "TOKEN FLOW MON", P.LEGEND[3], a=0.85)
        silk(c, 247, 15, "MK IV", P.LEGEND[3], a=0.85)
        # socket screws holding the casting down
        for (sx, sy) in ((21, 15), (100, 15), (196, 15), (104, 60), (267, 15)):
            self._socket(c, sx, sy)

    def _socket(self, c, x, y):
        """3x3 socket-head cap screw, countersunk."""
        M.stamp(c, x, y, ["dKd", "KkK", "lKl"],
                {"d": (P.SHADOW, 0.6), "K": P.GUN[0], "k": P.GUN[3], "l": (P.HILITE, 0.4)})

    # -- gauge bay (volume / balance / EQ / PL row) -------------------------
    def _paint_gauge_bay(self, c):
        # SESSION / WEEK stencilled on the casting lip straight above each
        # ladder -- out of the knob's travel, which spans the whole frame
        self._gauge_legend(c, 107, 68, "SESSION")
        self._gauge_legend(c, 177, 38, "WEEK")
        # engraved rule tying the two ladders together, with end ticks
        M.hl(c, 107, 214, 70, P.SHADOW, 0.45)
        M.hl(c, 107, 214, 71, P.HILITE, 0.14)
        M.vl(c, 175, 58, 69, P.SHADOW, 0.35)
        M.vl(c, 176, 58, 69, P.HILITE, 0.12)

    def _gauge_legend(self, c, gx, gw, text):
        """Silk-screened legend over a ladder, in the same flat ink as the top
        rail's designators: the word starts over the first segment, then a
        bracket line runs to the ladder's far end and drops a tick toward its
        window, so the word owns the whole run.  Row LEGEND_Y + 5 stays bare
        casting: air between the legend and the window rim."""
        y = LEGEND_Y
        x1 = silk(c, gx + 2, y, text, P.LEGEND[3], a=0.92)
        bx0, bx1 = x1 + 2, gx + gw - 3
        if bx1 - bx0 >= 3:
            M.hl(c, bx0, bx1, y + 2, P.LEGEND[2], 0.75)
            M.vl(c, bx1, y + 3, y + 4, P.LEGEND[2], 0.75)

    # -- lower deck -----------------------------------------------------------
    def _paint_lower_deck(self, c):
        s = self.seed
        # butt seam between the display deck and the control deck
        M.hl(c, 2, c.w - 3, 83, P.GUN[0], 0.9)
        M.hl(c, 2, c.w - 3, 84, P.GUN[6], 0.35)
        M.edge_wear(c, 2, 84, c.w - 4, 1, seed=s + 60, amount=0.5, sides="t")
        # trays: pockets milled into the plate for the key banks
        for tray in (TRAY_T, TRAY_S):
            tx, ty, tw, th = tray
            v = c.sub(tx, ty, tw, th)
            M.put_rgb(v, M.tone_rgb(M.plate_tone(v, seed=s + 23, base=0.24), P.GUN_LUT))
            M.recessed(c, tx, ty, tw, th, depth=2, a_sh=0.7, a_lip=0.45)

        # ---- riveted strap lapped over the bottom edge of the plate ------------
        v = c.sub(2, STRAP_Y, c.w - 4, c.h - STRAP_Y - 2)
        M.put_rgb(v, M.tone_rgb(M.plate_tone(v, seed=s + 31, base=0.52), P.GUN_LUT))
        M.hl(c, 2, c.w - 3, STRAP_Y, P.GUN[7], 0.75)
        M.hl(c, 2, c.w - 3, STRAP_Y - 1, P.SHADOW, 0.30)
        M.edge_wear(c, 2, STRAP_Y, c.w - 4, 1, seed=s + 61, amount=0.7, sides="t")
        for rx in (5, 46, 128):
            M.rivet(c, rx, STRAP_Y + 2)
        silk(c, 12, STRAP_Y + 2, "ENG-04/B", P.LEGEND[3], a=0.9, wear=0.35, seed=s + 1)
        # CAUTION label with hazard chevrons
        lx, ly, lw, lh = 53, STRAP_Y + 1, 72, 6
        M.box(c, lx, ly, lw, lh, P.HAZ_Y[2])
        M.hl(c, lx, lx + lw - 1, ly, P.HAZ_Y[3])
        M.hl(c, lx, lx + lw - 1, ly + lh - 1, P.HAZ_Y[1])
        M.hazard(c, lx + 1, ly, 15, lh, width=2, seed=s + 9, chip=0.12)
        M.hazard(c, lx + lw - 16, ly, 15, lh, width=2, seed=s + 10, chip=0.12, slope=-1)
        T.draw(c, lx + 19, ly + 1, "CAUTION", T.MICRO, P.HAZ_K[0], a=0.95)
        T.draw(c, lx + 19 + 30, ly + 1, "!", T.MICRO, P.RED[3], a=0.95)
        Xn = M.fbm(*M.grid(c.sub(lx, ly, lw, lh)), 0, s + 12, octaves=2, sx=5.0, sy=3.0)
        M.blend_mask(c, np.clip((Xn - 0.62) * 5.0, 0, 0.8), P.GUN[3], lx, ly)   # scuffs through the label

        # ---- armoured conduit clipped along the strap, into a gland -----------
        cy0 = STRAP_Y + 1
        X.conduit_h(c, 142, cy0, 131, 5, seed=s)
        # gland nut where the conduit starts
        M.box(c, 136, cy0 - 1, 7, 7, P.GUN[0])
        M.box(c, 137, cy0, 5, 5, P.STEEL[3])
        M.hl(c, 137, 141, cy0, P.STEEL[5])
        M.hl(c, 137, 141, cy0 + 4, P.STEEL[1])
        M.vl(c, 139, cy0, cy0 + 4, P.STEEL[1], 0.7)
        M.pset(c, 137, cy0, P.STEEL[6])
        for clipx in (176, 214, 252):
            M.box(c, clipx, cy0 - 1, 4, 7, P.GUN[0])
            M.box(c, clipx + 1, cy0 - 1, 2, 7, P.STEEL[2])
            M.pset(c, clipx + 1, cy0 - 1, P.STEEL[5])
            M.pset(c, clipx + 1, cy0, P.STEEL[4])
            M.pset(c, clipx + 2, cy0 + 5, P.STEEL[0])

        # ---- maker's plate (covers the about-logo area) -----------------------
        self.paint_about_logo(c)

        # ---- louvred vent down the left margin ---------------------------------
        X.louvres(c, 3, 88, 10, 6, pitch=3)
        M.pset(c, 2, 86, P.SHADOW, 0.4)

    def _paint_fasteners(self, c):
        M.hex_bolt(c, 6, 18, 0, mark=0)
        M.oil_streak(c, 5, 24, 11, seed=1, a0=0.55)
        M.hex_bolt(c, 6, 76, 2, mark=1)
        M.hex_bolt(c, 268, 64, 1, mark=2)
        M.oil_streak(c, 268, 70, 6, seed=3, a0=0.5)
        M.hex_bolt(c, 268, 77, 3, mark=0)
        M.oil_streak(c, 269, 83, 3, seed=4, a0=0.4)
        M.scratch(c, 222, 85, 238, 84, a=0.35)
        M.scratch(c, 40, 69, 58, 67, a=0.3)
        M.scratch(c, 131, 96, 134, 101, a=0.3)

    def paint_about_logo(self, c):
        """The maker's plate: light zinc plate, four rivets, stamped serial.
        Drawn into the full background (it is bigger than the 13x15 logo rect)."""
        if c.w < 100:            # called with the bare logo rect: nothing to add
            return
        x, y, w, h = 242, 86, 30, 19
        m = M.full_mask(c, x, y, w, h, r=1)
        sub = c.sub(x, y, w, h)
        tone = M.steel_tone(sub, seed=self.seed + 4, base=0.62, strength=0.7)
        M.put_rgb(sub, M.tone_rgb(tone, P.STEEL_LUT, 40), mask=M.round_mask(w, h, 1).astype(np.float32))
        M.raise_mask(c, m, a_hi=0.6, a_lo=0.55, contact=1, a_contact=0.55)
        ink = P.GUN[0]
        T.draw(c, x + 5, y + 2, "T-AMP", T.MICRO, ink, a=0.9)
        M.hl(c, x + 4, x + w - 5, y + 8, ink, 0.5)
        T.draw(c, x + 5, y + 10, "N.4773", T.MICRO, ink, a=0.85)
        # tiny stamped emblem: a chevron
        for k, (ex, ey) in enumerate(((23, 3), (24, 4), (25, 5), (24, 6), (23, 7))):
            pass
        M.pset(c, x + 24, y + 3, P.ORANGE[3])
        M.pset(c, x + 25, y + 4, P.ORANGE[3])
        M.pset(c, x + 24, y + 5, P.ORANGE[3])
        for (rx, ry) in ((x + 1, y + 1), (x + w - 3, y + 1), (x + 1, y + h - 3), (x + w - 3, y + h - 3)):
            M.pset(c, rx, ry, P.STEEL[6])
            M.pset(c, rx + 1, ry, P.STEEL[3])
            M.pset(c, rx, ry + 1, P.STEEL[3])
            M.pset(c, rx + 1, ry + 1, P.STEEL[0])
        M.oil_streak(c, x + w - 3, y + h, 2, seed=9, a0=0.4)

    def paint_time_frame(self, c):
        pass

    def digit_background(self):
        return P.hexs(D.glass_row(32))

    def text_background(self):
        return P.hexs(P.AMBER_WELL)

    # ------------------------------------------------------------------
    # title bar
    # ------------------------------------------------------------------
    def paint_title_bar(self, c, active, variant):
        X.title_strip_base(c, active, seed=self.seed)
        amber = P.LAMP_AMBER
        if variant == "shade":
            X.rail_tube(c, 24, 74, 3, 10, active, seed=self.seed, knurl=((0.0, 1.0),))
            self._shade_furniture(c, active)
            X.tiny_lamp(c, 18, 5, amber, active)
            return
        # rail with two knurled grips and a flat name boss in the middle
        X.rail_tube(c, 26, 232, 3, 10, active, seed=self.seed,
                    knurl=((0.03, 0.34), (0.66, 0.97)))
        title = "TOKENAMP" if variant != "easter" else "TOKENAMP"
        tw = T.STENCIL.width(title)
        bx0 = (c.w - tw) // 2 - 5
        M.box(c, bx0, 2, tw + 10, 10, P.GUN[0])
        v = c.sub(bx0 + 1, 3, tw + 8, 8)
        M.put_rgb(v, M.tone_rgb(M.plate_tone(v, seed=self.seed + 44, base=0.36, vgrad=0), P.GUN_LUT))
        M.hl(c, bx0 + 1, bx0 + tw + 8, 3, P.GUN[6], 0.6)
        M.hl(c, bx0 + 1, bx0 + tw + 8, 10, P.GUN[0], 0.7)
        col = P.LEGEND[3] if active else P.LEGEND[1]
        if variant == "easter":
            col = P.ORANGE[5] if active else P.ORANGE[3]
        T.draw(c, bx0 + 5, 3, title, T.STENCIL, col, a=1.0, wear=0.10, seed=self.seed + 6)
        X.tiny_lamp(c, 18, 5, amber, active)
        X.tiny_lamp(c, 237, 5, amber, active)

    def _shade_furniture(self, c, active):
        # mini visualiser tube
        M.box(c, 78, 4, 40, 7, P.RUBBER[1])
        M.box(c, 79, 5, 38, 5, self.viz_bg)
        M.hl(c, 78, 117, 11, P.GUN[5], 0.5)
        # countdown tube
        M.box(c, 127, 3, 28, 8, P.RUBBER[1])
        M.box(c, 128, 3, 26, 8, self.text_background())
        M.hl(c, 127, 154, 11, P.GUN[5], 0.5)
        M.pset(c, 140, 5, P.AMBER_BRIGHT)
        M.pset(c, 140, 8, P.AMBER_BRIGHT)
        # mini transport pictograms, paint-filled
        col = P.LEGEND[3] if active else P.LEGEND[1]
        pics = {
            "previous": (169, ["#..#.", "#.##.", "####.", "#.##.", "#..#."]),
            "play": (178, ["#....", "###..", "#####", "###..", "#...."]),
            "pause": (188, ["##.##", "##.##", "##.##", "##.##", "##.##"]),
            "stop": (198, ["#####", "#####", "#####", "#####", "#####"]),
            "next": (207, ["#..#.", "##.#.", "####.", "##.#.", "#..#."]),
            "eject": (217, ["..#..", ".###.", "#####", ".....", "#####"]),
        }
        for k, (px, rows) in pics.items():
            for j, row in enumerate(rows):
                for i, ch in enumerate(row):
                    if ch == "#":
                        M.pset(c, px + i + 1, 6 + j, P.SHADOW, 0.6)
                        M.pset(c, px + i, 5 + j, col)

    def paint_title_button(self, c, which, pressed):
        X.mini_key(c, which, pressed)

    # ------------------------------------------------------------------
    # clutterbar
    # ------------------------------------------------------------------
    def paint_clutter_bar(self, c, pressed=None, disabled=False):
        M.box(c, 0, 0, c.w, c.h, P.GUN[0])
        # strip above and below the keys: orange paint continues
        M.paint_layer(c, 0, 0, c.w, 3, seed=self.seed + 12, base=0.5, chip=0.5, edge_bias=0.0)
        M.paint_layer(c, 0, c.h - 3, c.w, 3, seed=self.seed + 13, base=0.46, chip=0.6, edge_bias=0.0)
        M.pset(c, 3, 1, P.GUN[0])
        M.pset(c, 4, 1, P.STEEL[4])
        M.pset(c, 3, c.h - 2, P.GUN[0])
        M.pset(c, 4, c.h - 2, P.STEEL[4])
        keys = (("O", 3, 8), ("A", 11, 7), ("I", 18, 7), ("D", 25, 8), ("V", 33, 7))
        for letter, ky, kh in keys:
            hit = pressed is not None and pressed.upper() == letter
            M.box(c, 0, ky, 8, kh, P.GUN[0])
            face_h = kh - 1
            d = 1 if hit else 0
            M.box(c, 1, ky, 6, face_h, P.GUN[2] if not hit else P.GUN[1])
            if not hit:
                M.hl(c, 1, 5, ky, P.GUN[6], 0.8)
                M.vl(c, 1, ky + 1, ky + face_h - 1, P.GUN[5], 0.55)
                M.hl(c, 2, 6, ky + face_h - 1, P.GUN[0], 0.8)
                M.vl(c, 6, ky + 1, ky + face_h - 1, P.GUN[0], 0.6)
            else:
                M.hl(c, 1, 6, ky, P.SHADOW, 0.95)
                M.vl(c, 1, ky + 1, ky + face_h - 1, P.SHADOW, 0.8)
            ink = P.LEGEND[3]
            if disabled:
                ink = P.GUN[5]
            if hit:
                ink = P.AMBER_BRIGHT
            gw = T.MICRO.width(letter)
            gx = 2 + (4 - gw) // 2 + (1 if gw == 1 else 0) + d
            gy = ky + (face_h - 5) // 2 + d
            if letter in ("O", "D"):
                gy = ky + 1 + d
            T.draw(c, gx, gy, letter, T.MICRO, ink)
            if hit:
                M.blend_mask(c, np.full((face_h - 1, 5), 0.16, dtype=np.float32), P.AMBER_BRIGHT, 2, ky + 1)

    # ------------------------------------------------------------------
    # transport
    # ------------------------------------------------------------------
    def paint_transport(self, c, which, pressed):
        k = ("previous", "play", "pause", "stop", "next", "eject").index(which)
        X.keycap(c, which, pressed, seed=self.seed + k * 3, guard=(which == "eject"))

    # ------------------------------------------------------------------
    # toggles
    # ------------------------------------------------------------------
    def paint_shuffle(self, c, pressed, selected):
        X.toggle(c, pressed, selected, "CYCLE", P.LAMP_AMBER, lamp_w=6, seed=self.seed + 1)

    def paint_repeat(self, c, pressed, selected):
        X.toggle(c, pressed, selected, "ALERT", P.RED, face=T.MICRO, lamp_w=3, seed=self.seed + 2)

    def paint_eq_toggle(self, c, pressed, selected):
        X.toggle(c, pressed, selected, "EQ", P.LAMP_AMBER, lamp_w=4, seed=self.seed + 3)

    def paint_pl_toggle(self, c, pressed, selected):
        X.toggle(c, pressed, selected, "PL", P.LAMP_AMBER, lamp_w=4, seed=self.seed + 4)

    # ------------------------------------------------------------------
    # seek bar
    # ------------------------------------------------------------------
    def paint_posbar_background(self, c):
        w, h = c.w, c.h
        # engraved tick scale above the slot, paint-filled; the last tenth is redlined
        for x in range(4, w - 3, 4):
            major = ((x - 4) % 24 == 0)
            f = (x - 4) / float(w - 8)
            col = P.LEGEND[2] if f < 0.9 else P.RED[4]
            M.pset(c, x, 1, col, 0.9)
            if major:
                M.pset(c, x, 0, col, 0.9)
                M.pset(c, x + 1, 1, P.SHADOW, 0.5)
        # milled slot
        M.box(c, 1, 3, w - 2, 5, P.GUN[0])
        M.box(c, 2, 4, w - 4, 3, (10, 12, 14))
        M.hl(c, 1, w - 2, 2, P.SHADOW, 0.55)
        M.hl(c, 1, w - 2, 8, P.GUN[6], 0.55)                 # lit lower lip
        M.vl(c, w - 1, 3, 7, P.GUN[6], 0.4)
        M.vl(c, 0, 3, 7, P.SHADOW, 0.5)
        # guide rod down the middle of the slot
        M.hl(c, 3, w - 4, 5, P.STEEL[2])
        M.hl(c, 3, w - 4, 4, P.STEEL[4], 0.55)
        M.hl(c, 3, w - 4, 6, P.GUN[0], 0.8)
        # end stops
        for ex in (2, w - 5):
            M.box(c, ex, 4, 3, 3, P.STEEL[2])
            M.pset(c, ex, 4, P.STEEL[5])
            M.pset(c, ex + 2, 6, P.STEEL[0])

    def paint_posbar_thumb(self, c, pressed):
        w, h = c.w, c.h
        M.box(c, 0, 0, w, h, P.GUN[0])
        M.steel(c, 1, 1, w - 3, h - 3, seed=self.seed + 7, base=0.52 if not pressed else 0.44,
                direction="v", strength=0.5, local=True)
        M.box(c, 1, h - 1, w - 1, 1, P.SHADOW)
        M.box(c, w - 1, 1, 1, h - 1, P.SHADOW)
        kw, kh = w - 2, h - 2
        for x in range(3, kw - 1, 2):
            if 10 <= x <= 17:
                continue
            M.vl(c, x, 2, kh - 1, P.STEEL[1], 0.85)
            M.vl(c, x + 1, 2, kh - 1, P.STEEL[5], 0.5)
        M.hl(c, 1, kw - 1, 1, P.STEEL[6], 0.9)
        M.vl(c, 1, 2, kh - 1, P.STEEL[5], 0.8)
        M.hl(c, 1, kw, kh, P.STEEL[0], 0.95)
        M.vl(c, kw, 1, kh, P.STEEL[0], 0.8)
        # index window
        M.box(c, 11, 2, 6, kh - 2, P.GUN[0])
        M.box(c, 12, 2, 4, kh - 2, P.GUN[1])
        red = P.RED[3] if not pressed else P.RED[5]
        M.vl(c, 13, 2, kh - 1, red)
        M.vl(c, 14, 2, kh - 1, P.RED[2] if not pressed else P.RED[4])
        if pressed:
            M.pset(c, 13, 3, P.RED[6])
            M.vl(c, 12, 2, kh - 1, P.RED[4], 0.5)
            M.vl(c, 15, 2, kh - 1, P.RED[4], 0.5)
            M.vl(c, 11, 2, kh - 1, P.RED[3], 0.3)
            M.vl(c, 16, 2, kh - 1, P.RED[3], 0.3)
        c.a[:, :, 3] = 255

    # ------------------------------------------------------------------
    # volume / balance
    # ------------------------------------------------------------------
    def paint_volume_frame(self, c, i):
        X.led_ladder(c, i, seed=self.seed + 1)

    def paint_balance_frame(self, c, i):
        X.led_ladder(c, i, seed=self.seed + 2)

    def paint_volume_thumb(self, c, pressed):
        X.knob(c, pressed, seed=self.seed + 8)

    def paint_balance_thumb(self, c, pressed):
        X.knob(c, pressed, seed=self.seed + 9)

    # ------------------------------------------------------------------
    # annunciators
    # ------------------------------------------------------------------
    def _annunciator(self, c, text, on, ramp, face):
        w, h = c.w, c.h
        if on:
            # light spilling onto the surround (inside the sprite's own margin)
            M.blend_mask(c, np.full((h, w), 0.30, dtype=np.float32), ramp[4])
        M.box(c, 1, 1, w - 2, h - 2, P.GUN[0])
        fx, fy, fw, fh = 2, 2, w - 4, h - 4
        if on:
            M.box(c, fx, fy, fw, fh, ramp[4])
            M.box(c, fx, fy, fw, 1, ramp[5])
            M.box(c, fx, fy + fh - 1, fw, 1, ramp[3])
            M.vl(c, fx, fy, fy + fh - 1, ramp[3], 0.6)
            M.vl(c, fx + fw - 1, fy, fy + fh - 1, ramp[3], 0.6)
            yy, xx = np.mgrid[0:fh, 0:fw].astype(np.float32)
            hot = np.clip(1.0 - (((xx - fw / 2) / (fw * 0.55)) ** 2 + ((yy - fh / 2) / (fh * 0.8)) ** 2), 0, 1)
            M.blend_mask(c, hot * 0.45, ramp[5], fx, fy)
            ink = ramp[0]
        else:
            M.box(c, fx, fy, fw, fh, (16, 15, 13))
            M.box(c, fx, fy, fw, 1, (30, 29, 26))
            M.pset(c, fx, fy, (70, 72, 70))
            ink = P.mixc(ramp[3], (96, 92, 80), 0.55)
        tw = face.width(text)
        T.draw(c, fx + (fw - tw) // 2 + (1 if (fw - tw) % 2 else 0), fy + (fh - 5) // 2 + 0, text, face, ink)
        # tile seams: split lens look
        M.hl(c, 1, w - 2, h - 1, P.HILITE, 0.18)
        c.a[:, :, 3] = 255

    def paint_mono(self, c, on):
        self._annunciator(c, "LOCAL", on, P.LAMP_AMBER, T.LEGEND)

    def paint_stereo(self, c, on):
        self._annunciator(c, "LIVE", on, P.GREEN, T.LEGEND)

    # ------------------------------------------------------------------
    # play state / work LED (drawn by the tube)
    # ------------------------------------------------------------------
    def paint_play_state(self, c, state):
        X.glass_rows(c, 0, 0, c.w, c.h)
        lit = state == "playing"
        col = P.AMBER_BRIGHT if lit else P.AMBER_LOW
        rows = {
            "playing": ["#.....", "###...", "#####.", "######", "#####.", "###...", "#....."],
            "paused": ["##.##.", "##.##.", "##.##.", "##.##.", "##.##.", "##.##.", "##.##."],
            "stopped": ["......", "#####.", "#####.", "#####.", "#####.", "#####.", "......"],
        }[state]
        for j, row in enumerate(rows):
            for i, ch in enumerate(row):
                if ch == "#":
                    k = col
                    if D.raster_dark(c.oy + 1 + j):
                        k = tuple(int(v * s) for v, s in zip(col, (0.86, 0.8, 0.7)))
                    M.pset(c, 2 + i, 1 + j, k)
        if lit:
            M.pset(c, 2, 4, P.AMBER_CORE)
            M.pset(c, 3, 4, P.AMBER_CORE)
            M.pset(c, 4, 4, P.AMBER_CORE)
        c.a[:, :, 3] = 255

    def paint_work_indicator(self, c, working):
        X.glass_rows(c, 0, 0, c.w, c.h)
        if working:
            M.box(c, 0, 2, 2, 5, P.AMBER_BRIGHT)
            M.box(c, 0, 3, 2, 3, P.AMBER_CORE)
            M.box(c, 0, 1, 2, 1, P.AMBER_LOW, 0.7)
            M.box(c, 0, 7, 2, 1, P.AMBER_LOW, 0.7)
        else:
            M.box(c, 0, 2, 2, 5, P.AMBER_GHOST2)
        c.a[:, :, 3] = 255

    # ------------------------------------------------------------------
    # digits and glyphs
    # ------------------------------------------------------------------
    def paint_digit(self, c, d):
        M.put_rgb(c, D.cell(d, wy0=c.oy, ghost_all=(d != "minus")))
        c.a[:, :, 3] = 255

    def paint_glyph(self, c, ch):
        M.box(c, 0, 0, c.w, c.h, self.text_background())
        g = T.CRT.glyph(ch)
        for j, row in enumerate(g):
            for i, px in enumerate(row[:5]):
                if px == "#":
                    M.pset(c, i, j, P.AMBER_BRIGHT)
        c.a[:, :, 3] = 255

    # ------------------------------------------------------------------
    # shade-mode position bar
    # ------------------------------------------------------------------
    def paint_shade_position_background(self, c):
        M.box(c, 0, 0, c.w, c.h, P.GUN[0])
        M.box(c, 1, 2, c.w - 2, 3, (10, 12, 14))
        M.hl(c, 1, c.w - 2, 3, P.STEEL[2])
        M.hl(c, 0, c.w - 1, 6, P.GUN[5], 0.6)
        M.hl(c, 0, c.w - 1, 0, P.SHADOW)
        M.hl(c, 1, c.w - 2, 1, P.GUN[1])
        M.hl(c, 1, c.w - 2, 5, P.GUN[1])
        for x in range(2, c.w - 1, 4):
            M.pset(c, x, 1, P.LEGEND[1], 0.8)
        c.a[:, :, 3] = 255

    def paint_shade_position_thumb(self, c, which):
        M.box(c, 0, 0, 3, 7, P.STEEL[3])
        M.hl(c, 0, 2, 0, P.STEEL[6])
        M.hl(c, 0, 2, 6, P.STEEL[0])
        if which == "left":
            M.vl(c, 0, 0, 6, P.STEEL[5])
            M.vl(c, 2, 1, 5, P.STEEL[1])
        elif which == "right":
            M.vl(c, 0, 1, 5, P.STEEL[5])
            M.vl(c, 2, 0, 6, P.STEEL[0])
        else:
            M.vl(c, 1, 1, 5, P.RED[4])
            M.vl(c, 0, 1, 5, P.STEEL[4])
            M.vl(c, 2, 1, 5, P.STEEL[1])
        c.a[:, :, 3] = 255

    # ------------------------------------------------------------------
    # visualiser palette
    # ------------------------------------------------------------------
    def viscolors(self):
        out = [P.AMBER_WELL, P.AMBER_GHOST]
        stops = [(0.00, P.hx("#ff2a18")), (0.12, P.hx("#ff5a14")), (0.30, P.hx("#ff8c1a")),
                 (0.50, P.AMBER_BRIGHT), (0.75, P.hx("#d9820e")), (1.00, P.hx("#8f4c06"))]
        for k in range(16):
            t = k / 15.0
            for a in range(len(stops) - 1):
                if stops[a][0] <= t <= stops[a + 1][0]:
                    f = (t - stops[a][0]) / (stops[a + 1][0] - stops[a][0])
                    out.append(P.mixc(stops[a][1], stops[a + 1][1], f))
                    break
        out += [P.AMBER_CORE, P.AMBER_BRIGHT, P.AMBER_MID, P.AMBER_LOW, P.AMBER_DIM]
        out.append(P.AMBER_WHITE)
        return [tuple(int(v) for v in col) for col in out]
