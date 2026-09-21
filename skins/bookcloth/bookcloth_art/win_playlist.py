"""win_playlist -- the Sessions window: a ledger card in a cloth binding.

Tile discipline.  The cloth for this window is woven to repeat: period 25 in x
(the width of the top and bottom tiles) and period 29 in y from y=20 (the
height of the side tiles), with the first 20 rows a plain lead for the title
piece.  So the edge pieces may simply lay cloth at their own window
coordinates and still tile seamlessly.  Everything else a repeated tile draws
is either invariant along the axis it repeats on, or written as a function of
``x % 25`` / ``y % 29``.
"""

from __future__ import annotations

import numpy as np

from skinkit.spec import lval

from . import doodles as D
from . import materials as M
from . import palette as P
from . import type_list
from . import typeset as T
from .plate import Plate

W, H = 275, 232
TOP_H, BOT_H = 20, 38
LEFT_W, RIGHT_W = 12, 20
PERIOD_X, PERIOD_Y = 25, 29
LEAD_Y = 20

# the page block's fore-edge occupies the left of the right-hand tile
FORE_X0, FORE_X1 = 255, 258
GROOVE_X0 = 259


class PlaylistMixin:
    # ------------------------------------------------------------------
    # top edge
    # ------------------------------------------------------------------
    def _pl_top(self, p: Plate, active: bool) -> None:
        """The head of the binding: cloth, a lit turn-over, a groove where the
        board meets the page block.  A pure function of window x."""
        M.lay_cloth(p, 0, 0, W, TOP_H, window="playlist",
                    dye=-0.150 if active else -0.030,
                    fade=0.0 if active else 0.55)
        p.hline(0, W - 1, 0, P.CLAY_LIGHT, 0.55)
        p.hline(1, W - 2, 1, P.CLAY_LIGHT, 0.18)
        # the joint: the page block starts just under the boards
        p.hline(0, W - 1, TOP_H - 2, P.SHADOW_ON_CLOTH, 0.45)
        p.hline(0, W - 1, TOP_H - 1, P.PAPER_DEEP, 0.75)

    def paint_pl_top_tile(self, c, active: bool) -> None:
        p = Plate(c)
        self._pl_top(p, active)
        # pitch 5 divides the 25 px period, so the run carries across the seam
        M.stitch_run(p, p.ox, 6, PERIOD_X, vertical=False, pitch=5, stitch=3,
                     seed=21)
        p.opaque()

    def paint_pl_title(self, c, active: bool) -> None:
        p = Plate(c)
        self._pl_top(p, active)
        cov = T.coverage("SESSIONS", "list", spacing=2, space=5)
        tx = p.ox + (c.w - cov.shape[1]) // 2
        T.foil(p, tx, 3, "", cov=cov, dull=0.0 if active else 0.55, seed=8)
        p.opaque()

    def paint_pl_top_left(self, c, active: bool) -> None:
        p = Plate(c)
        self._pl_top(p, active)
        self._headband(p, 5)
        M.stitch_run(p, 15, 6, 10, vertical=False, pitch=5, stitch=3, seed=22)
        p.vline(0, 0, TOP_H - 1, P.CLAY_LIGHT, 0.45)
        p.px(0, 0, P.CLAY_PALE, 0.75)
        p.opaque()

    def paint_pl_top_right(self, c, active: bool) -> None:
        p = Plate(c)
        self._pl_top(p, active)
        self._headband(p, 266)
        p.vline(W - 1, 0, TOP_H - 1, P.CLAY_SHADOW, 0.70)
        p.px(W - 1, 0, P.CLAY_PALE, 0.55)
        p.opaque()

    # ------------------------------------------------------------------
    # sides
    # ------------------------------------------------------------------
    def paint_pl_left_tile(self, c) -> None:
        """The fore-board and the sewn spine edge; periodic in y (29)."""
        p = Plate(c)
        M.lay_cloth(p, 0, p.oy, LEFT_W, c.h, window="playlist", dye=-0.10)
        p.vline(0, p.oy, p.oy + c.h - 1, P.CLAY_LIGHT, 0.45)
        p.vline(1, p.oy, p.oy + c.h - 1, P.CLAY_LIGHT, 0.16)
        # the stitching runs the length of the binding, in step with the tile
        # two stitches per 29 px tile, drawn from the tile's own top edge so
        # the rhythm repeats exactly
        M.stitch_run(p, 4, p.oy, c.h, vertical=True, pitch=14, stitch=6,
                     seed=23, phase=1)
        # the page block's edge, and the shadow the board casts on it
        p.vline(LEFT_W - 1, p.oy, p.oy + c.h - 1, P.PAPER_DEEP, 0.80)
        p.vline(LEFT_W - 2, p.oy, p.oy + c.h - 1, P.SHADOW_ON_CLOTH, 0.30)
        p.opaque()

    def paint_pl_right_tile(self, c) -> None:
        """The fore-edge of the page block, then the scrollbar groove cut into
        the board.  Periodic in y (29)."""
        p = Plate(c)
        y0, h = p.oy, c.h
        M.lay_cloth(p, W - RIGHT_W, y0, RIGHT_W, h, window="playlist", dye=-0.10)
        # fore-edge: individual page ends, gilded slightly by handling
        for y in range(y0, y0 + h):
            k = (y - LEAD_Y) % PERIOD_Y
            base = P.PAPER_SH if k % 2 else P.PAPER_LO
            p.hline(FORE_X0, FORE_X1, y, base)
            if k % 7 == 3:
                p.hline(FORE_X0, FORE_X1, y, P.PAPER_DEEP, 0.75)
            if k % 11 == 5:
                p.px(FORE_X1, y, P.KRAFT[3], 0.45)
        p.vline(FORE_X0 - 1, y0, y0 + h - 1, P.SHADOW_ON_PAPER, 0.35)
        p.vline(FORE_X1 + 1, y0, y0 + h - 1, P.CLAY_SHADOW, 0.55)
        # the groove the ribbon runs in
        p.box(GROOVE_X0, y0, 10, h, P.CLAY_SHADOW, 0.55)
        p.vline(GROOVE_X0, y0, y0 + h - 1, P.SHADOW_ON_CLOTH, 0.60)
        p.vline(GROOVE_X0 + 9, y0, y0 + h - 1, P.CLAY_LIGHT, 0.30)
        p.vline(W - 1, y0, y0 + h - 1, P.CLAY_SHADOW, 0.70)
        p.opaque()

    def paint_pl_scroll_handle(self, c, pressed: bool) -> None:
        """A ribbon bookmark hanging in the groove."""
        p = Plate(c)
        x, y, w, h = p.ox, p.oy, c.w, c.h
        body = P.CLAY_DEEP if pressed else P.CLAY
        p.box(x, y, w, h, body)
        p.vline(x, y, y + h - 1, P.CLAY_LIGHT, 0.75)
        p.vline(x + w - 1, y, y + h - 1, P.CLAY_SHADOW, 0.85)
        p.hline(x, x + w - 1, y, P.CLAY_LIGHT, 0.55)
        p.hline(x, x + w - 1, y + h - 1, P.CLAY_SHADOW, 0.80)
        # woven grain along the ribbon
        for k in range(y + 1, y + h - 1, 2):
            p.hline(x + 1, x + w - 2, k, P.CLAY_LIGHT, 0.18)
        # the V-notch cut in the free end
        p.px(x + w // 2, y + h - 2, P.CLAY_SHADOW, 0.7)
        p.opaque()

    # ------------------------------------------------------------------
    # footer -- the colophon
    # ------------------------------------------------------------------
    def _pl_bottom(self, p: Plate) -> None:
        """Cloth footer; a pure function of window x, so the tile repeats."""
        M.lay_cloth(p, 0, H - BOT_H, W, BOT_H, window="playlist", dye=-0.10)
        p.hline(0, W - 1, H - BOT_H, P.PAPER_DEEP, 0.70)
        p.hline(0, W - 1, H - BOT_H + 1, P.SHADOW_ON_CLOTH, 0.35)
        p.hline(0, W - 1, H - 1, P.CLAY_SHADOW, 0.80)
        p.hline(1, W - 2, H - 2, P.CLAY_DARK, 0.45)

    def paint_pl_bottom_tile(self, c) -> None:
        p = Plate(c)
        self._pl_bottom(p)
        M.stitch_run(p, p.ox, H - BOT_H + 5, PERIOD_X, vertical=False, pitch=5,
                     stitch=3, seed=24)
        p.opaque()

    def paint_pl_bottom_left(self, c) -> None:
        p = Plate(c)
        self._pl_bottom(p)
        p.vline(0, H - BOT_H, H - 1, P.CLAY_LIGHT, 0.45)
        p.px(0, H - 1, P.CLAY_PALE, 0.70)
        # the colophon: a pasted label, ruled and signed
        lx, ly, lw, lh = 12, H - BOT_H + 6, 100, 25
        M.soft_shadow(p, lx, ly, lw, lh, P.SHADOW_ON_CLOTH, strength=0.45,
                      spread=1, dx=2, dy=2)
        M.card(p, lx, ly, lw, lh, window="playlist", on="cloth", tone="manilla",
               notch=True)
        T.letterpress(p, lx + 5, ly + 4, "SESSIONS", "micro", ink=P.INK_BODY)
        D.wobble_line(p, lx + 5, lx + 44, ly + 11, P.CLAY_DEEP, a=0.8, seed=5)
        T.letterpress(p, lx + 5, ly + 13, "A LEDGER OF", "micro", ink=P.INK_SOFT)
        T.letterpress(p, lx + 5, ly + 19, "TOKENS SPENT", "micro", ink=P.INK_SOFT)
        D.spark(p, lx + 86, ly + 15, 9, P.CLAY_DEEP, 0.9)
        p.opaque()

    def paint_pl_bottom_right(self, c) -> None:
        p = Plate(c)
        self._pl_bottom(p)
        p.vline(W - 1, H - BOT_H, H - 1, P.CLAY_SHADOW, 0.70)
        p.px(W - 1, H - 1, P.CLAY_PALE, 0.55)
        info = [int(v) for v in lval("playlist", "runningInfoFromBottomRight")]
        mini = [int(v) for v in lval("playlist", "miniTimeFromBottomRight")]
        ix, iy = info[0] + W, info[1] + H
        mx, my = mini[0] + W, mini[1] + H
        # one slip of paper carrying both readings
        sx, sy = ix - 4, iy - 4
        sw, sh = 112, (my + 6 + 4) - sy
        M.soft_shadow(p, sx, sy, sw, sh, P.SHADOW_ON_CLOTH, strength=0.45,
                      spread=1, dx=2, dy=2)
        M.card(p, sx, sy, sw, sh, window="playlist", on="cloth", notch=True)
        M.plate_mark(p, ix, iy, 100, 6, margin=1)
        M.plate_mark(p, mx, my, 30, 6, margin=1)
        T.letterpress(p, ix, my + 1, "NEXT RESET", "micro", ink=P.INK_SOFT)
        D.pencil_rule(p, ix + 40, mx - 3, my + 4, a=0.55, seed=6)
        p.opaque()

    def paint_pl_visualizer_background(self, c) -> None:
        """Tokenamp does not place this piece; keep the sheet valid anyway."""
        p = Plate(c)
        self._pl_bottom(p)
        p.box(p.ox, p.oy, c.w, c.h, self.viz_bg)
        p.opaque()

    def paint_pl_close(self, c, pressed: bool) -> None:
        self.paint_title_button(c, "close", pressed)

    def paint_pl_collapse(self, c, pressed: bool) -> None:
        self.paint_title_button(c, "shade", pressed)

    # ------------------------------------------------------------------
    # list colours and the Sessions typeface
    # ------------------------------------------------------------------
    def pledit_colours(self):
        return {"Normal": "#3D3D3A", "Current": "#C15F3C", "NormalBG": "#F0EEE6",
                "SelectedBG": "#EBDBBC", "Font": "Times New Roman"}

    def pl_font_cell(self):
        return (type_list.CELL_W, type_list.CELL_H)

    def paint_pl_font_glyph(self, c, ch: str) -> None:
        cov = type_list.cell(ch)
        v = np.clip(np.rint(cov * 255.0), 0, 255).astype(np.uint8)
        c.a[:, :, 0] = c.a[:, :, 1] = c.a[:, :, 2] = v
        c.a[:, :, 3] = 255

    def pl_font_metrics(self):
        return {"Monospace": 0, "Spacing": 1, "SpaceWidth": 3,
                "RowHeight": type_list.CELL_H + 2, "OffsetY": 0}
