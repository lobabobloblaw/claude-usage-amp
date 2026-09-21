"""Walnut 76 -- main window: cabinet, fascia, dial glass, title rail."""

from __future__ import annotations

import numpy as np

from skinkit import fonts
from skinkit.canvas import Canvas, mix
from skinkit.spec import Rect, lrect, lval, clutter_button_local, clutter_letters

import w76_common as K
import w76_digits as D
import w76_materials as M
import w76_palette as P
from w76_microfonts import PANEL, SERIF, TINY

SEAM = "#16130d"               # hairline gaps between machined parts

# dial-glass geometry (window coords, interiors)
GLASS_MAIN = (21, 18, 244, 37)     # x 21..264, y 18..54  : the long dial window
GLASS_LEG = (21, 55, 83, 6)        # x 21..103, y 55..60  : drops down round the visualiser


class MainWindow:
    """Mixin: every main-window painter."""

    # ------------------------------------------------------------------
    # background
    # ------------------------------------------------------------------
    MAIN_SCREWS = ((13, 18, 45), (12, 67, 0), (12, 110, 135), (262, 110, 90))

    def paint_main_background(self, c: Canvas) -> None:
        K.fascia(c)
        K.cheeks(c, K.RAIL_H, knots_left=[(3, 86, 1.5)], knots_right=[(271, 40, 1.2)])
        K.cheek_shadow(c, K.RAIL_H, c.h - 1)
        K.rail(c)
        K.rail_ends(c)
        # foot line under the whole cabinet
        c.hline(0, c.w - 1, c.h - 1, "#0c0806")
        M.shade_box(c, 0, c.h - 2, c.w, 1, 0.72)

        self._dial_glass(c)
        self._posbar_surround(c)
        self._control_deck(c)
        self._bottom_engraving(c)

        # clutter-bar channel
        cb = lrect("main", "clutterBar")
        c.rect(cb.x - 1, cb.y - 1, cb.w + 2, cb.h + 2, P.ALU[0])
        c.hline(cb.x - 1, cb.x1, cb.y1, P.ALU[6])
        c.vline(cb.x1, cb.y - 1, cb.y1, P.ALU[6])
        c.sub(cb).fill(SEAM)

        for sx, sy, ang in self.MAIN_SCREWS:
            M.screw(c, sx, sy, ang)

        self.paint_about_logo(c.sub(lrect("main", "aboutLogo")))

    # -- the dial window -------------------------------------------------
    def _dial_glass(self, c: Canvas) -> None:
        interior = K.rect_mask((c.h, c.w), GLASS_MAIN, GLASS_LEG)
        K.glass_shape(c, interior, glints=[
            (19, 16, P.CHROME[3]), (20, 16, P.CHROME[3]), (19, 17, P.CHROME[3]),
            (88, 16, P.CHROME[3]), (89, 16, P.CHROME[1]), (90, 16, P.CHROME[1]),
            (91, 16, P.CHROME[1]), (92, 16, P.CHROME[1]),
            (176, 16, P.CHROME[1]), (177, 16, P.CHROME[1]), (178, 16, P.CHROME[1]),
            (179, 16, P.CHROME[3]),
            (266, 56, P.CHROME[2]), (105, 62, P.CHROME[2]), (19, 40, P.CHROME[3]),
            (150, 56, P.CHROME[0]), (151, 56, P.CHROME[0]), (152, 56, P.CHROME[0]),
            (153, 56, P.CHROME[2]), (60, 62, P.CHROME[0]), (61, 62, P.CHROME[0]),
            (62, 62, P.CHROME[2]),
        ])
        gx, gy, gw, gh = GLASS_MAIN
        # recessed: ring shadow along the top and left of the pane
        c.hline(gx, gx + gw - 1, gy, "#010202")
        c.hline(gx, gx + gw - 1, gy + 1, "#030405")
        c.vline(gx, gy, GLASS_LEG[1] + GLASS_LEG[3] - 1, "#010202")
        c.vline(gx + 1, gy + 1, GLASS_LEG[1] + GLASS_LEG[3] - 1, "#030405")

        # static glare streak (masked off every dynamic well below)
        M.glare(c, 214, slope=-0.55, width=8.0, strength=0.22, mask=interior)
        M.glare(c, 66, slope=-0.55, width=3.0, strength=0.10, mask=interior)

        dim, ghost, mid = P.TEAL[1], "#07262a", P.TEAL[2]

        # ---- faint dial scale above the marquee: USAGE 0..100 % ----------
        mq = lrect("main", "marquee")
        x0, x1 = mq.x + 3, mq.x + mq.w - 14
        for k in range(11):
            tx = int(round(x0 + (x1 - x0) * k / 10.0))
            label = str(k * 10)
            lw = K.tw(label, TINY)
            K.legend(c, tx - lw // 2, 20, label, TINY, dim)
            c.vline(tx, 25, 25, mid)
            if k < 10:
                for j in range(1, 5):
                    mx = int(round(tx + (x1 - x0) / 10.0 * j / 5.0))
                    c.px(mx, 25, ghost if j != 0 else dim)
        K.legend(c, x1 + 8, 20, "%", TINY, dim)

        # ---- second band under the marquee: fine log ticks ----------------
        for k, tx in enumerate(range(mq.x + 1, mq.x + mq.w - 1, 3)):
            major = (k % 5 == 0)
            c.vline(tx, 35, 37 if major else 35, dim if major else ghost)
        c.hline(mq.x + 1, mq.x + mq.w - 2, 34, ghost)

        # ---- numeric field legends ---------------------------------------
        kb, kz = lrect("main", "kbps"), lrect("main", "khz")
        K.legend(c, kb.x1 + 3, kb.y + 1, "K/MIN", PANEL, dim)
        K.legend(c, kz.x1 + 3, kz.y + 1, "ACTIVE", PANEL, dim)
        # field brackets
        for r in (kb, kz):
            c.hline(r.x - 1, r.x + 1, r.y1 + 1, ghost)
            c.hline(r.x1 - 2, r.x1, r.y1 + 1, ghost)
            c.px(r.x - 1, r.y1, ghost)
            c.px(r.x1, r.y1, ghost)

        # ---- gauge legends on the lower edge of the glass ----------------
        vol, bal = lrect("main", "volume"), lrect("main", "balance")
        ex = K.legend(c, vol.x + 1, 50, "SESSION", PANEL, dim)
        c.hline(ex + 2, vol.x1 - 5, 52, ghost)
        c.vline(vol.x1 - 5, 52, 54, ghost)
        ex = K.legend(c, bal.x + 1, 50, "WEEK", PANEL, dim)
        c.hline(ex + 2, bal.x1 - 5, 52, ghost)
        c.vline(bal.x1 - 5, 52, 54, ghost)

        # ---- time block ----------------------------------------------------
        digs = [Rect(*d) for d in lval("main", "digits")]
        minus = lrect("main", "minusSignEx")
        K.legend(c, 37, 20, "RESET TIMER", TINY, dim)
        c.hline(37 + K.tw("RESET TIMER", TINY) + 3, 98, 22, ghost)
        c.vline(98, 22, 24, ghost)
        for r in digs:
            D.paint(c.sub(r), "blank", self.digit_background())
        mcell = c.sub(minus)
        D.paint(mcell, "blank", self.digit_background())
        mcell.fill(self.digit_background())
        for (x, y) in D.SEGMENTS["g"]:
            mcell.px(x, y, D.GHOST)
        # colon, slanted with the figures
        cx = (digs[1].x1 + digs[2].x) // 2
        cm = np.zeros((c.h, c.w), dtype=bool)
        cm[digs[0].y + 3:digs[0].y + 5, cx:cx + 2] = True
        cm[digs[0].y + 8:digs[0].y + 10, cx - 1:cx + 1] = True
        M.glow_mask(c, cm, D.HALO, strength=0.34, diag=0.45)
        c.a[:, :, :3][cm] = (0x8a, 0xf3, 0xe6)

        # ---- visualiser surround -----------------------------------------
        viz = lrect("main", "visualizer")
        c.hline(viz.x, viz.x1 - 1, viz.y1, ghost)
        for bx in range(viz.x, viz.x1, 4):
            c.px(bx + 1, viz.y1 + 1, dim)
        for k, yy in enumerate(range(viz.y, viz.y1, 4)):
            c.px(viz.x - 2, yy, dim if k == 0 else ghost)
        c.px(viz.x - 2, viz.y1 - 1, dim)
        c.vline(viz.x1 + 1, viz.y, viz.y1 - 1, "#061a1c")
        K.legend(c, viz.x1 + 3 - 3, viz.y - 0, "", TINY, dim)

        # ---- flat wells last: nothing static may live under dynamic art ----
        c.sub(viz).fill(P.VIZ_BG)
        for key in ("marquee", "kbps", "khz"):
            c.sub(lrect("main", key)).fill(self.text_background())

    # -- the tuning-dial surround ----------------------------------------
    def _posbar_surround(self, c: Canvas) -> None:
        r = lrect("main", "posbar")
        M.chrome_ring(c, r.x - 1, r.y - 1, r.w + 2, r.h + 2)
        M.shade_box(c, r.x, r.y1 + 1, r.w + 2, 1, 0.80)
        M.shade_box(c, r.x1 + 1, r.y, 1, r.h + 2, 0.84)

    # -- the control deck under the dial ----------------------------------
    def _control_deck(self, c: Canvas) -> None:
        # piano-key recess
        prev, nxt, ej = lrect("main", "previous"), lrect("main", "next"), lrect("main", "eject")
        x0, x1 = prev.x - 1, nxt.x1
        c.box(x0, prev.y - 1, x1 - x0 + 1, prev.h + 2, SEAM)
        c.hline(x0, x1, prev.y1 + 1, P.ALU[6])
        c.vline(x1 + 1, prev.y - 1, prev.y1 + 1, P.ALU[6])
        c.hline(x0, x1, prev.y - 2, P.ALU[1])
        c.box(ej.x - 1, ej.y - 1, ej.w + 1, ej.h + 2, SEAM)
        c.hline(ej.x - 1, ej.x1 - 1, ej.y1 + 1, P.ALU[6])
        c.vline(ej.x1, ej.y - 1, ej.y1 + 1, P.ALU[6])
        c.hline(ej.x - 1, ej.x1 - 1, ej.y - 2, P.ALU[1])
        # machined divider groove between transport and mode switches
        M.engrave_line_v(c, 160, 90, 103)
        # token-flow caption + power pilot in the strip under the glass
        K.engrave(c, 24, 65, "TOKEN FLOW", TINY)
        M.engrave_line_h(c, 24 + K.tw("TOKEN FLOW", TINY) + 3, 78, 67)
        K.engrave(c, 82, 65, "PWR", TINY)
        M.jewel(c, 99, 67, True, r=1)
        M.bloom(c, 99, 67, P.PILOT[2], radius=4.0, strength=0.35)
        M.jewel(c, 99, 67, True, r=1)
        # phones jack
        jx, jy = 245, 97
        for dy in range(-4, 5):
            for dx in range(-4, 5):
                r2 = dx * dx + dy * dy
                if r2 <= 18:
                    if r2 >= 11:
                        lit = (dx + dy) < 0
                        c.px(jx + dx, jy + dy, P.CHROME[3] if (lit and r2 >= 13 and dx + dy < -3)
                             else (P.CHROME[2] if lit else P.CHROME[1]))
                    elif r2 >= 5:
                        c.px(jx + dx, jy + dy, P.PLASTIC[2] if (dx + dy) > 0 else P.PLASTIC[0])
                    else:
                        c.px(jx + dx, jy + dy, "#000000")
        c.px(jx + 1, jy + 1, P.CHROME[0])
        M.shade_box(c, jx - 2, jy + 5, 6, 1, 0.82)

    def _bottom_engraving(self, c: Canvas) -> None:
        y = 108
        x = K.engrave(c, 20, y, "MODEL TA-76", TINY)
        K.engrave(c, x + 4, y, "·", TINY)
        K.engrave(c, x + 8, y, "SOLID STATE USAGE RECEIVER", TINY)
        K.engrave_c(c, 245, y, "PHONES", TINY)

    # ------------------------------------------------------------------
    # flat colours the app composites over
    # ------------------------------------------------------------------
    def digit_background(self):
        return P.GLASS_FLAT

    def text_background(self):
        return P.GLASS_FLAT

    # ------------------------------------------------------------------
    # maker's badge
    # ------------------------------------------------------------------
    def paint_about_logo(self, c: Canvas) -> None:
        M.chrome_ring(c, 0, 0, c.w, c.h, glints=False)
        c.px(0, 0, P.CHROME[3])
        c.px(1, 0, P.CHROME[3])
        inner = c.sub(1, 1, c.w - 2, c.h - 2)
        M.plastic(inner, level=0.30, seed=3)
        inner.hline(0, inner.w - 1, 0, "#000000")
        fonts.draw_text(inner, 1, 2, "TA", PANEL, P.CREAM)
        inner.hline(1, inner.w - 2, 8, P.PILOT[1])
        fonts.draw_text(inner, 2, 9, "76", TINY, P.PILOT[2], spacing=1)
        inner.px(inner.w - 2, 10, P.TEAL[3])
        inner.px(inner.w - 2, 12, P.RED[2])

    # ------------------------------------------------------------------
    # title rail
    # ------------------------------------------------------------------
    def paint_title_bar(self, c: Canvas, active: bool, variant: str) -> None:
        K.rail(c, knots=[(208, 8, 1.7)])
        K.rail_ends(c)
        if variant == "shade":
            self._shade_strip(c, active)
        else:
            text = "TOKENAMP" if variant == "main" else "MODEL TA-76"
            sw = K.tw(text, SERIF, 2) + 18
            K.name_strip(c, (c.w - sw) // 2, 2, sw, 10, text, active, spacing=2)
            if variant == "easter":
                s = c.sub((c.w - sw) // 2 + 1, 3, sw - 2, 8)
                s.tint(P.PILOT[2], 0.22 if active else 0.10)
        # pilot lamp in the rail (x > 20 so the shared title buttons stay valid)
        M.jewel(c, 27, 7, active, r=2, halo=0.9)
        if not active:
            M.shade_box(c, 8, 1, c.w - 16, c.h - 2, 0.90)
            M.jewel(c, 27, 7, False, r=2)
        # button escutcheons: hairline recesses the caps sit in
        for key in ("optionsButton", "minimizeButton", "shadeButton", "closeButton"):
            r = lrect("main", key)
            c.rect(r.x, r.y, r.w, r.h, P.WALNUT[0])

    def _shade_strip(self, c: Canvas, active: bool) -> None:
        interior = K.rect_mask((c.h, c.w), (77, 3, 165, 8))
        K.glass_shape(c, interior, glints=[(75, 1, P.CHROME[3]), (76, 1, P.CHROME[3]),
                                           (75, 2, P.CHROME[3]), (150, 1, P.CHROME[1]),
                                           (151, 1, P.CHROME[1]), (152, 1, P.CHROME[3])])
        c.hline(77, 241, 3, "#010202")
        dim, ghost = P.TEAL[1], "#07262a"
        mv = lrect("shade", "miniVisualizer")
        c.sub(mv).fill(P.VIZ_BG)
        c.hline(mv.x, mv.x1 - 1, mv.y1, ghost)
        glyphs = lval("shade", "timeGlyphs")
        gy = int(glyphs[0][1])
        cxp = int(glyphs[1][0]) + 5
        col = (0x8a, 0xf3, 0xe6) if active else P.TEAL[1]
        c.px(cxp, gy + 1, col)
        c.px(cxp, gy + 4, col)
        K.legend(c, 119, 5, "T", TINY, ghost)
        icol = P.TEAL[2] if active else P.TEAL[1]
        for key in ("previous", "play", "pause", "stop", "next", "eject"):
            self._mini_icon(c, lrect("shade", key), key, icol)
        c.vline(166, 4, 9, ghost)
        # a short engraved tab at the left of the rail
        s = c.sub(36, 3, 33, 8)
        M.aluminium(s, seed=9, level=0.64 if active else 0.42, sheen=0.5)
        c.rect(35, 2, 35, 10, P.WALNUT[0])
        s.hline(0, s.w - 1, 0, P.ALU[6] if active else P.ALU[4])
        s.hline(0, s.w - 1, s.h - 1, P.ALU[1])
        K.engrave(s, 3, 1, "TOKENAMP", TINY, ink=P.INK if active else "#4a4438",
                  lip=100 if active else 30)

    def _mini_icon(self, c: Canvas, r: Rect, kind: str, colour) -> None:
        x, y = r.x, r.y + 1
        if kind == "previous":
            c.vline(x + 1, y, y + 4, colour)
            self._tri(c, x + 3, y, 3, 5, "left", colour)
        elif kind == "next":
            self._tri(c, x + 2, y, 3, 5, "right", colour)
            c.vline(x + 6, y, y + 4, colour)
        elif kind == "play":
            self._tri(c, x + 3, y, 3, 5, "right", colour)
        elif kind == "pause":
            c.vline(x + 3, y, y + 4, colour)
            c.vline(x + 5, y, y + 4, colour)
        elif kind == "stop":
            c.box(x + 2, y + 1, 4, 4, colour)
        elif kind == "eject":
            self._tri(c, x + 2, y, 5, 3, "up", colour)
            c.hline(x + 2, x + 6, y + 4, colour)

    # -- title buttons ----------------------------------------------------
    def paint_title_button(self, c: Canvas, which: str, pressed: bool) -> None:
        # recess in the walnut: dark top/left wall, lit lower/right lip
        c.fill(P.WALNUT[0])
        c.hline(1, c.w - 1, c.h - 1, P.WALNUT[5])
        c.vline(c.w - 1, 1, c.h - 1, P.WALNUT[5])
        o = 1 if pressed else 0
        cap = c.sub(1 + o, 1 + o, 7 - o, 7 - o)
        M.plastic(cap, level=0.55 if not pressed else 0.30, seed=8, pressed=pressed)
        if not pressed:
            cap.hline(0, cap.w - 1, 0, P.PLASTIC[3])
            cap.vline(0, 0, cap.h - 1, P.PLASTIC[3])
            cap.px(0, 0, "#5a5e63")
            cap.hline(1, cap.w - 1, cap.h - 1, "#050506")
            cap.vline(cap.w - 1, 1, cap.h - 1, "#050506")
        else:
            cap.hline(0, cap.w - 1, 0, "#000000")
            cap.vline(0, 0, cap.h - 1, "#000000")
        ink = P.CREAM if not pressed else P.PILOT[2]
        ox, oy = 1 + o, 1 + o
        if which == "options":
            for i in range(3):
                c.px(ox + 1, oy + 1 + i * 2, ink)
                c.hline(ox + 3, ox + 5, oy + 1 + i * 2, ink)
        elif which == "minimize":
            c.hline(ox + 1, ox + 5, oy + 5, ink)
        elif which == "shade":
            c.hline(ox + 1, ox + 5, oy + 1, ink)
            c.hline(ox + 1, ox + 5, oy + 2, ink)
            c.px(ox + 3, oy + 4, ink)
        elif which == "unshade":
            c.rect(ox + 1, oy + 1, 5, 5, ink)
            c.hline(ox + 1, ox + 5, oy + 2, ink)
        elif which == "close":
            for i in range(5):
                c.px(ox + 1 + i, oy + 1 + i, ink)
                c.px(ox + 5 - i, oy + 1 + i, ink)
        else:
            raise ValueError(which)
        c.a[:, :, 3] = 255

    # -- clutter bar ----------------------------------------------------
    def paint_clutter_bar(self, c: Canvas, pressed=None, disabled: bool = False) -> None:
        c.fill(SEAM)
        # end blocks with a pin each
        for y0 in (0, c.h - 3):
            blk = c.sub(0, y0, c.w, 3 if y0 == 0 else 3)
            M.aluminium(blk, level=0.52, sheen=0.3)
            blk.hline(0, c.w - 1, 0, P.ALU[5])
            blk.hline(0, c.w - 1, 2, P.ALU[1])
            blk.px(3, 1, P.ALU[0])
            blk.px(4, 1, P.ALU[6])
        for letter in clutter_letters():
            r = clutter_button_local(letter)
            hit = pressed is not None and letter == str(pressed).upper()
            cap = c.sub(r.x, r.y, r.w, r.h - 1)       # last row of each cell = seam
            M.aluminium(cap, level=0.74 if not hit else 0.44, sheen=0.4, seed=40)
            if not hit:
                cap.hline(0, cap.w - 1, 0, P.ALU[6])
                cap.vline(0, 0, cap.h - 1, P.ALU[5])
                cap.hline(0, cap.w - 1, cap.h - 1, P.ALU[1])
                cap.vline(cap.w - 1, 0, cap.h - 1, P.ALU[2])
                cap.px(0, 0, "#ffffff")
            else:
                cap.hline(0, cap.w - 1, 0, P.ALU[0])
                cap.vline(0, 0, cap.h - 1, P.ALU[0])
                cap.hline(1, cap.w - 1, cap.h - 1, P.ALU[3])
            ink = P.INK if not disabled else P.ALU[1]
            o = 1 if hit else 0
            gw = TINY.width(letter)
            gx = (cap.w - gw) // 2 + o
            gy = (cap.h - 5) // 2 + o
            K.engrave(cap, gx, gy, letter, TINY, ink=ink, lip=0 if (hit or disabled) else 110)
        c.a[:, :, 3] = 255
