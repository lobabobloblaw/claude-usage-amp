"""Walnut 76 -- the Sessions deck: a walnut-framed black glass panel.

Tile discipline: the top rail is walnut whose figure is *periodic in x every
25 px*; the cheeks are walnut periodic in y every 29 px.  The corner and title
pieces evaluate the very same periodic functions in window coordinates, so
they meet the tiles without a seam by construction.  Everything else in a tile
(shading rows/columns, chrome, the scroll slot) is invariant along its axis.
"""

from __future__ import annotations

import numpy as np

from skinkit import fonts
from skinkit.canvas import Canvas, mix
from skinkit.spec import lval

import w76_common as K
import w76_materials as M
import w76_palette as P
import w76_plfont_data as PF
from w76_microfonts import PANEL, SERIF, TINY

SEAM = "#16130d"
W, H = 275, 232
TOP_H, BOT_H = 20, 38

# frame cross-sections (window x)
L_ALU = (7, 8)          # left: cheek 0..6 | alu 7..8 | chrome 9 | wall 10 | glass 11
R_CHROME = 257          # right: glass 255 | wall 256 | chrome 257 | alu 258..267 | cheek 268..


def _alu_cols(c: Canvas, x0: int, x1: int, tones) -> None:
    """y-invariant aluminium: one tone per column (reads as vertical brushing)."""
    for k, x in enumerate(range(x0, x1 + 1)):
        c.vline(x, 0, c.h - 1, P.ramp_at(P.ALU, tones[k % len(tones)]))


def _alu_rows(c: Canvas, y0: int, y1: int, tones) -> None:
    for k, y in enumerate(range(y0, y1 + 1)):
        c.hline(0, c.w - 1, y, P.ramp_at(P.ALU, tones[k % len(tones)]))


class PlaylistWindow:
    """Mixin: every playlist piece, the pledit colours and the plfont."""

    # ------------------------------------------------------------------
    # top edge
    # ------------------------------------------------------------------
    def _pl_top(self, c: Canvas, active: bool) -> None:
        """Rail + the strip of fascia + the top run of the glass trim.  Pure
        function of window x (period 25) and y, so any piece can call it."""
        K.rail(c, period=25)
        _alu_rows(c.sub(0, K.RAIL_H, c.w, 4), 0, 3, (0.34, 0.50, 0.60, 0.64))
        c.hline(0, c.w - 1, 18, P.CHROME[2])
        c.hline(0, c.w - 1, 19, "#000000")
        if not active:
            M.shade_box(c, 0, 1, c.w, K.RAIL_H - 2, 0.90)

    def paint_pl_top_left(self, c: Canvas, active: bool) -> None:
        self._pl_top(c, active)
        # left end: end-grain block, then the cheek starts under the rail
        self._end_block(c, 0, True)
        cheek = c.sub(0, K.RAIL_H, K.CHEEK, c.h - K.RAIL_H)
        M.walnut(cheek, "v", seed=76, period=29)
        M.shade_cols(cheek, {0: 1.28, 1: 1.10, 2: 1.16, K.CHEEK - 1: 0.62, K.CHEEK - 2: 0.88})
        M.shade_rows(cheek, {0: 0.55})
        # fascia sliver, trim corner
        for y in range(K.RAIL_H, c.h):
            c.px(7, y, P.ramp_at(P.ALU, 0.22 if y > K.RAIL_H else 0.16))
            c.px(8, y, P.ramp_at(P.ALU, 0.52 if y > K.RAIL_H else 0.30))
        c.vline(9, 18, c.h - 1, P.CHROME[2])
        c.px(9, 18, P.CHROME[3])
        c.px(10, 18, P.CHROME[3])
        c.vline(10, 19, c.h - 1, "#000000")
        c.hline(7, 8, 18, P.ramp_at(P.ALU, 0.5))
        c.hline(7, 8, 19, P.ramp_at(P.ALU, 0.5))
        c.px(7, 18, P.ramp_at(P.ALU, 0.22))
        c.px(7, 19, P.ramp_at(P.ALU, 0.22))
        M.jewel(c, 17, 7, active, r=2, halo=0.9)

    def _end_block(self, c: Canvas, x0: int, left: bool) -> None:
        h = K.RAIL_H
        blk = c.sub(x0, 0, K.CHEEK, h)
        X, Y = M.grid(blk)
        n = M._hash01(X.astype(np.int64), Y.astype(np.int64), 4242)
        n2 = M.vnoise(X, Y, 2.0, 2.0, 99)
        t = 0.10 + 0.20 * n2 + np.where(n > 0.82, -0.08, 0.0) + np.where(n < 0.1, 0.07, 0.0)
        M._put(blk, M._ramp_map(P.WALNUT, t))
        M.shade_rows(blk, {0: 1.5, 1: 1.15, h - 1: 0.55})
        if left:
            c.vline(K.CHEEK, 1, h - 1, P.WALNUT[0])
            c.vline(0, 0, h - 1, P.WALNUT[5])
            c.px(0, 0, P.WALNUT[6])
        else:
            c.vline(x0 - 1, 1, h - 1, P.WALNUT[0])
            c.vline(c.w - 1, 0, h - 1, P.WALNUT[0])

    def paint_pl_title(self, c: Canvas, active: bool) -> None:
        self._pl_top(c, active)
        text = "SESSIONS"
        sw = K.tw(text, SERIF, 2) + 18
        K.name_strip(c, (c.w - sw) // 2, 2, sw, 10, text, active, spacing=2, seed=21)

    def paint_pl_top_tile(self, c: Canvas, active: bool) -> None:
        self._pl_top(c, active)

    def paint_pl_top_right(self, c: Canvas, active: bool) -> None:
        self._pl_top(c, active)
        self._end_block(c, c.w - K.CHEEK, False)
        cheek = c.sub(c.w - K.CHEEK, K.RAIL_H, K.CHEEK, c.h - K.RAIL_H)
        M.walnut(cheek, "v", seed=91, period=29, tone=-0.02)
        M.shade_cols(cheek, {0: 1.30, 1: 1.08, 3: 1.12, K.CHEEK - 1: 0.50, K.CHEEK - 2: 0.80})
        M.shade_rows(cheek, {0: 0.55})
        # right run of the trim + the scrollbar channel's top
        lx = R_CHROME - (W - c.w)
        c.vline(lx, 18, c.h - 1, P.CHROME[1])
        c.vline(lx - 1, 19, c.h - 1, "#000000")
        c.hline(lx + 1, c.w - K.CHEEK - 1, 18, P.ramp_at(P.ALU, 0.62))
        c.hline(lx + 1, c.w - K.CHEEK - 1, 19, P.ramp_at(P.ALU, 0.62))
        # recesses for the two caps
        for bx in (c.w - 11, c.w - 21):
            c.rect(bx, 3, 9, 9, P.WALNUT[0])
        # the collapse cap is never drawn "normal" by the builder: bake it here
        cap = c.crop(c.w - 21, 3, 9, 9)
        self.paint_title_button(cap, "shade", False)
        c.blit(cap, c.w - 21, 3, alpha=False)

    # ------------------------------------------------------------------
    # sides
    # ------------------------------------------------------------------
    def paint_pl_left_tile(self, c: Canvas) -> None:
        cheek = c.sub(0, 0, K.CHEEK, c.h)
        M.walnut(cheek, "v", seed=76, period=29)
        M.shade_cols(cheek, {0: 1.28, 1: 1.10, 2: 1.16, K.CHEEK - 1: 0.62, K.CHEEK - 2: 0.88})
        c.vline(7, 0, c.h - 1, P.ramp_at(P.ALU, 0.22))
        c.vline(8, 0, c.h - 1, P.ramp_at(P.ALU, 0.52))
        c.vline(9, 0, c.h - 1, P.CHROME[2])
        c.vline(10, 0, c.h - 1, "#000000")
        c.vline(11, 0, c.h - 1, "#010202")
        c.a[:, :, 3] = 255

    def _channel(self, c: Canvas, x0: int) -> None:
        """The scrollbar channel: y-invariant brushed strip with the slot."""
        tones = (0.74, 0.62, 0.58, 0.63, 0.55, 0.60, 0.66, 0.58, 0.61, 0.50)
        _alu_cols(c, x0, x0 + 9, tones)
        c.vline(x0 + 4, 0, c.h - 1, "#000000")
        c.vline(x0 + 5, 0, c.h - 1, P.PLASTIC[0])
        c.vline(x0 + 6, 0, c.h - 1, P.ALU[6])
        c.vline(x0 + 3, 0, c.h - 1, P.ALU[1])

    def paint_pl_right_tile(self, c: Canvas) -> None:
        c.vline(0, 0, c.h - 1, P.LIST_BG)
        c.vline(1, 0, c.h - 1, "#171c1e")
        c.vline(2, 0, c.h - 1, P.CHROME[1])
        self._channel(c, 3)
        cheek = c.sub(c.w - K.CHEEK, 0, K.CHEEK, c.h)
        M.walnut(cheek, "v", seed=91, period=29, tone=-0.02)
        M.shade_cols(cheek, {0: 1.30, 1: 1.08, 3: 1.12, K.CHEEK - 1: 0.50, K.CHEEK - 2: 0.80})
        c.a[:, :, 3] = 255

    # ------------------------------------------------------------------
    # footer
    # ------------------------------------------------------------------
    def _footer(self, c: Canvas, invariant: bool = False) -> None:
        """Brushed footer plate with the bottom run of the glass trim."""
        M.aluminium(c, seed=31, streak=0.0 if invariant else 1.0,
                    sheen=0.0 if invariant else 1.0, win_h=H)
        c.hline(0, c.w - 1, 0, "#171c1e")
        c.hline(0, c.w - 1, 1, P.CHROME[1])
        M.shade_rows(c, {2: 0.80, c.h - 4: 1.06, c.h - 3: 0.80, c.h - 2: 0.55})
        c.hline(0, c.w - 1, c.h - 1, "#0c0806")

    def paint_pl_bottom_tile(self, c: Canvas) -> None:
        self._footer(c, invariant=True)
        c.a[:, :, 3] = 255

    def paint_pl_bottom_left(self, c: Canvas) -> None:
        self._footer(c)
        cheek = c.sub(0, 0, K.CHEEK, c.h)
        M.walnut(cheek, "v", seed=76, period=29, knots=[(3, 213, 1.4)])
        M.shade_cols(cheek, {0: 1.28, 1: 1.10, 2: 1.16, K.CHEEK - 1: 0.62, K.CHEEK - 2: 0.88})
        M.shade_rows(cheek, {c.h - 1: 0.4, c.h - 2: 0.75})
        # fascia sliver + trim corner, continuing the left tile
        c.vline(7, 0, 1, P.ramp_at(P.ALU, 0.22))
        c.vline(8, 0, 1, P.ramp_at(P.ALU, 0.52))
        c.px(9, 0, P.CHROME[2])
        c.px(10, 0, "#000000")
        c.px(9, 1, P.CHROME[2])
        M.shade_box(c, 7, 2, 1, c.h - 3, 0.62)
        M.shade_box(c, 8, 2, 1, c.h - 3, 0.86)

        # ventilation louvres
        vx, vy = 14, 8
        for k in range(6):
            yy = vy + k * 4
            c.hline(vx + 1, vx + 30, yy, P.ALU[0])
            c.hline(vx, vx + 31, yy + 1, "#0d0b08")
            c.hline(vx + 1, vx + 30, yy + 2, P.ALU[6])
            c.px(vx, yy + 1, P.ALU[0])
        # maker's plate.  66 wide so the serif wordmark (59 px) clears the
        # chrome ring with a margin either side; the right edge stays at 116
        # so the two fasteners beside it do not move.
        px_, py_, pw, ph = 50, 7, 66, 24
        M.chrome_ring(c, px_, py_, pw, ph, glints=False)
        c.px(px_, py_, P.CHROME[3])
        c.px(px_ + 1, py_, P.CHROME[3])
        plate = c.sub(px_ + 1, py_ + 1, pw - 2, ph - 2)
        M.plastic(plate, level=0.25, seed=44)
        plate.hline(0, plate.w - 1, 0, "#000000")
        wordmark = K.tw("TOKENAMP", SERIF)
        fonts.draw_text(plate, (plate.w - wordmark) // 2, 2, "TOKENAMP", SERIF, P.CREAM, spacing=1)
        plate.hline(4, plate.w - 5, 10, P.PILOT[1])
        # model right, caption left: they share the line, so keep them apart
        fonts.draw_text(plate, 4, 12, "SESSION", TINY, P.CREAM_DIM)
        fonts.draw_text(plate, plate.w - 4 - K.tw("TA-76P", TINY), 12, "TA-76P", TINY, P.PILOT[2])
        fonts.draw_text(plate, 4, 17, "SER 076-0412", TINY, P.CREAM_DIM)
        for rx, ry in ((2, plate.h - 3), (plate.w - 3, plate.h - 3)):
            plate.px(rx, ry, P.CHROME[2])
        M.shade_box(c, px_ + 1, py_ + ph, pw, 1, 0.80)
        M.shade_box(c, px_ + pw, py_ + 1, 1, ph, 0.84)
        M.screw(c, 119, 12, 45)
        M.screw(c, 119, 27, 0)
        c.a[:, :, 3] = 255

    def paint_pl_bottom_right(self, c: Canvas) -> None:
        self._footer(c)
        ox = c.ox
        cheek = c.sub(c.w - K.CHEEK, 0, K.CHEEK, c.h)
        M.walnut(cheek, "v", seed=91, period=29, tone=-0.02)
        M.shade_cols(cheek, {0: 1.30, 1: 1.08, 3: 1.12, K.CHEEK - 1: 0.50, K.CHEEK - 2: 0.80})
        M.shade_rows(cheek, {c.h - 1: 0.4, c.h - 2: 0.75})
        M.shade_box(c, c.w - K.CHEEK - 1, 2, 1, c.h - 3, 0.80)
        # end of the glass trim and of the scrollbar channel
        lx = R_CHROME - ox
        c.px(lx - 1, 0, "#171c1e")
        c.px(lx, 0, P.CHROME[1])
        c.hline(lx + 1, c.w - K.CHEEK - 1, 0, P.ramp_at(P.ALU, 0.62))
        c.hline(lx + 1, c.w - K.CHEEK - 1, 1, P.ramp_at(P.ALU, 0.62))
        c.px(lx, 1, P.CHROME[1])
        c.hline(lx + 5 - 1, lx + 6 + 1, 1, P.ALU[1])
        c.hline(lx + 5, lx + 6, 0, "#000000")

        # counter window
        info = [int(v) for v in lval("playlist", "runningInfoFromBottomRight")]
        mini = [int(v) for v in lval("playlist", "miniTimeFromBottomRight")]
        ix, iy = info[0] + c.w, info[1] + c.h
        mx, my = mini[0] + c.w, mini[1] + c.h
        gx, gy, gw, gh = ix - 3, iy - 3, 109, (my + 6 + 3) - (iy - 3)
        interior = K.rect_mask((c.h, c.w), (gx, gy, gw, gh))
        K.glass_shape(c, interior, glints=[(gx - 2, gy - 2, P.CHROME[3]),
                                           (gx - 1, gy - 2, P.CHROME[3]),
                                           (gx - 2, gy - 1, P.CHROME[3]),
                                           (gx + 50, gy - 2, P.CHROME[1]),
                                           (gx + 51, gy - 2, P.CHROME[1]),
                                           (gx + 52, gy - 2, P.CHROME[3])])
        c.hline(gx, gx + gw - 1, gy, "#010202")
        c.vline(gx, gy, gy + gh - 1, "#010202")
        M.glare(c, ox + gx + 92, slope=-0.55, width=5.0, strength=0.18, mask=interior)
        ghost, dim = "#07262a", P.TEAL[1]
        c.hline(gx + 2, gx + gw - 3, iy + 8, ghost)
        K.legend(c, ix, my + 1, "NEXT RESET", TINY, dim)
        c.hline(ix + K.tw("NEXT RESET", TINY) + 2, mx - 4, my + 3, ghost)
        K.legend(c, ix + 82, iy + 1 - 1, "", TINY, dim)
        # flat wells under the dynamic text
        c.box(ix, iy, 100, 6, P.GLASS_FLAT)
        c.box(mx, my, 30, 6, P.GLASS_FLAT)
        # engraved captions + hardware right of the window
        K.engrave(c, gx, gy + gh + 3, "SESSIONS TODAY", TINY) if (gy + gh + 9) < c.h - 3 else None
        M.screw(c, c.w - K.CHEEK - 8, 9, 135, big=True)
        M.screw(c, c.w - K.CHEEK - 8, 28, 45, big=True)
        c.a[:, :, 3] = 255

    def paint_pl_visualizer_background(self, c: Canvas) -> None:
        self._footer(c)
        interior = K.rect_mask((c.h, c.w), (4, 6, c.w - 8, c.h - 14))
        K.glass_shape(c, interior)
        c.a[:, :, 3] = 255

    def paint_pl_scroll_handle(self, c: Canvas, pressed: bool) -> None:
        self._slider_cap(c, pressed, vertical=True)

    def paint_pl_close(self, c: Canvas, pressed: bool) -> None:
        self.paint_title_button(c, "close", pressed)

    def paint_pl_collapse(self, c: Canvas, pressed: bool) -> None:
        self.paint_title_button(c, "shade", pressed)

    # ------------------------------------------------------------------
    # list colours and the list face
    # ------------------------------------------------------------------
    def pledit_colours(self):
        return {"Normal": "#2FBDB4", "Current": "#FFB642", "NormalBG": P.LIST_BG.upper(),
                "SelectedBG": "#0B3B3F", "Font": "Arial"}

    def pl_font_cell(self):
        return PF.CELL

    def paint_pl_font_glyph(self, c: Canvas, ch: str) -> None:
        rows = PF.cell_rows(ch)
        ink = np.array([[k == "#" for k in r] for r in rows], dtype=bool)
        p = np.pad(ink.astype(np.float32), 1)
        h, w = ink.shape
        orth = p[0:h, 1:w + 1] + p[2:h + 2, 1:w + 1] + p[1:h + 1, 0:w] + p[1:h + 1, 2:w + 2]
        dg = p[0:h, 0:w] + p[0:h, 2:w + 2] + p[2:h + 2, 0:w] + p[2:h + 2, 2:w + 2]
        cov = np.clip(orth * 0.15 + dg * 0.05, 0, 0.36)
        cov[ink] = 1.0
        v = np.clip(np.rint(cov * 255), 0, 255).astype(np.uint8)
        c.a[:, :, 0] = c.a[:, :, 1] = c.a[:, :, 2] = v
        c.a[:, :, 3] = 255

    def pl_font_metrics(self):
        return {"Monospace": 0, "Spacing": 1, "SpaceWidth": 3, "RowHeight": 12, "OffsetY": 0}
