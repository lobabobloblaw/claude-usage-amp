"""win_eq -- the equaliser window: a page from a lab notebook.

Ivory graph paper ruled faint accent blue, ten hand-ruled scales that fill
bottom-to-top with ink wash, terracotta tile thumbs, and the curve drawn on a
slip of graph paper taped onto the page.
"""

from __future__ import annotations

import numpy as np

from skinkit.spec import lrect, lval

from . import doodles as D
from . import marks
from . import materials as M
from . import palette as P
from . import typeset as T
from .plate import Plate

W, H = 275, 116
TITLE_H = 14

# the ruled grid of the notebook page
GRID = 7
MARGIN_X = 10       # the red-ruled left margin of a notebook page, in clay here

BANDS = lval("eq", "bandSliders")
CAPTIONS = ("-9", "-8", "-7", "-6", "-5", "-4", "-3", "-2", "-1", "NOW")


def _band_x(i: int) -> int:
    return int(BANDS["x0"]) + int(BANDS["strideX"]) * i


class EqMixin:
    # ------------------------------------------------------------------
    # the page
    # ------------------------------------------------------------------
    def _notebook_page(self, p: Plate) -> None:
        """Ivory stock, faint blue graticule, a clay margin rule, deckle foot."""
        M.lay_paper(p, 0, TITLE_H, W, H - TITLE_H, window="eq")
        # blue graph rules, fading where the page has been handled
        for y in range(TITLE_H + GRID, H - 2, GRID):
            p.hline(2, W - 3, y, P.BLUE[2], 0.34)
        for x in range(MARGIN_X + GRID, W - 2, GRID):
            p.vline(x, TITLE_H + 2, H - 4, P.BLUE[2], 0.26)
        # the margin rule, ruled twice the way a notebook is
        p.vline(MARGIN_X, TITLE_H + 1, H - 3, P.CLAY_LIGHT, 0.55)
        p.vline(MARGIN_X + 1, TITLE_H + 1, H - 3, P.CLAY_PALE, 0.30)
        # the page sitting in the cover: cut edge at the top, shadow under it
        p.hline(0, W - 1, TITLE_H, P.PAPER_DEEP, 0.55)
        p.hline(0, W - 1, TITLE_H + 1, P.PAPER_HI, 0.75)
        # deckled foot and the board edge showing round the page
        M.lay_cloth(p, 0, H - 3, W, 3, window="eq")
        p.hline(0, W - 1, H - 3, P.SHADOW_ON_PAPER, 0.30)
        p.hline(0, W - 1, H - 1, P.CLAY_SHADOW, 0.75)
        p.vline(0, TITLE_H, H - 1, P.CLAY_SHADOW, 0.40)
        p.vline(W - 1, TITLE_H, H - 1, P.CLAY_SHADOW, 0.55)

    def paint_eq_background(self, c) -> None:
        p = Plate(c)
        self._notebook_page(p)
        # the ten band scales and their captions
        for i in range(int(BANDS["count"])):
            self._scale_rule(p, i)
        self._preamp_rule(p)
        # a coffee ring someone left on the corner of the page
        D.coffee_ring(p, 238, 104, r=12.0, a=0.13, seed=3)
        # the pasted-in slip that carries the curve
        g = lrect("eq", "graph")
        M.soft_shadow(p, g.x - 3, g.y - 3, g.w + 6, g.h + 6, P.SHADOW_ON_PAPER,
                      strength=0.34, spread=2, dx=2, dy=2)
        M.lay_paper(p, g.x - 3, g.y - 3, g.w + 6, g.h + 6, window="eq",
                    base=P.PAPER_HI)
        p.hline(g.x - 3, g.x + g.w + 2, g.y - 3, P.PAPER_HI)
        p.vline(g.x - 3, g.y - 3, g.y + g.h + 2, P.PAPER_HI)
        p.hline(g.x - 3, g.x + g.w + 2, g.y + g.h + 2, P.PAPER_SH, 0.9)
        p.vline(g.x + g.w + 2, g.y - 2, g.y + g.h + 2, P.PAPER_SH, 0.9)
        # washi tape holding it down at two corners
        D.washi(p, g.x - 8, g.y - 6, 14, 7, P.BLUE[2], seed=1)
        D.washi(p, g.x + g.w - 6, g.y + g.h - 1, 14, 7, P.CLAY_PALE, seed=2)
        # a paper clip on the outer margin
        D.paper_clip(p, 4, 46, vertical=True)
        # blind-stamped note in the clear band under the buttons -- the foot
        # belongs to the band captions
        T.blind(p, 14, 32, "LAB NOTE No 5.1", "micro", on="paper", strength=0.85)
        marks.mark(p, 264, H - 11, "tiny")
        p.opaque()

    # The slider sprite owns every row of its 14x63 rect, so a caption drawn
    # inside it would be painted over by the wash.  Captions live below it.
    CAPTION_Y = 103

    def _scale_rule(self, p: Plate, i: int) -> None:
        """One hand-ruled vertical scale with its letterpress caption."""
        x, y = _band_x(i), int(BANDS["y"])
        h = int(BANDS["h"])
        self._trough(p, x, y, h)
        cov = T.coverage(CAPTIONS[i], "micro")
        T.letterpress(p, x + (14 - cov.shape[1]) // 2, self.CAPTION_Y, "", cov=cov,
                      ink=P.INK_BODY, lip=0.8)

    #: the wash column's x offset and width inside a 14 px slider
    TROUGH_X, TROUGH_W = 4, 6

    def _trough(self, p: Plate, x: int, y: int, h: int) -> None:
        """The ruled channel a wash column rises in, ticked each side."""
        tx, tw = self.TROUGH_X, self.TROUGH_W
        p.box(x + tx, y, tw, h, P.PAPER_LO)
        p.vline(x + tx, y, y + h - 1, P.PAPER_DEEP, 0.70)
        p.vline(x + tx + tw - 1, y, y + h - 1, P.PAPER_HI, 0.75)
        p.hline(x + tx, x + tx + tw - 1, y, P.PAPER_DEEP, 0.55)
        for k in range(0, 5):
            ty = y + int(round((h - 1) * k / 4.0))
            p.hline(x + 1, x + tx - 1, ty, P.INK_GREY, 0.55)
            p.hline(x + tx + tw, x + 12, ty, P.INK_GREY, 0.45)

    def _preamp_rule(self, p: Plate) -> None:
        r = lrect("eq", "preampSlider")
        self._trough(p, r.x, r.y, r.h)
        cov = T.coverage("WEEK", "micro")
        T.letterpress(p, r.x + (14 - cov.shape[1]) // 2, self.CAPTION_Y, "", cov=cov,
                      ink=P.INK_BODY, lip=0.8)

    # ------------------------------------------------------------------
    # title bar
    # ------------------------------------------------------------------
    def paint_eq_title_bar(self, c, active: bool) -> None:
        p = Plate(c, origin=(0, 0))
        self._spine_cloth(p, active, window="eq")
        self._headband(p, 17)
        self._headband(p, 238)
        self._title_text(p, "USAGE EQUALIZER", active)
        p.opaque()

    def paint_eq_close(self, c, pressed: bool) -> None:
        self.paint_title_button(c, "close", pressed)

    # ------------------------------------------------------------------
    # the three buttons: index tabs clipped to the page
    # ------------------------------------------------------------------
    def _page_tab(self, c, label: str, pressed: bool, selected: bool,
                  seed: int) -> None:
        p = Plate(c)
        x, y, w, h = p.ox, p.oy, c.w, c.h
        dx, dy = self.press_offset(pressed)
        M.card(p, x + dx, y + dy, w - 2, h - 2, window="eq", on="paper",
               pressed=pressed, notch=False,
               tone="manilla" if selected else "ivory")
        cov = T.coverage(label, "micro")
        tx = x + dx + (w - 2 - cov.shape[1]) // 2
        ty = y + dy + (h - 2 - cov.shape[0]) // 2
        T.letterpress(p, tx, ty, "", cov=cov,
                      ink=P.CLAY_DEEP if selected else P.INK_SOFT,
                      lip=0.0 if pressed else 0.8)
        if selected:
            D.wobble_line(p, tx - 1, tx + cov.shape[1], ty + cov.shape[0] + 1,
                          P.CLAY_DEEP, a=0.75, seed=seed)
        p.opaque()

    def paint_eq_on(self, c, pressed: bool, selected: bool) -> None:
        self._page_tab(c, "ON", pressed, selected, 1)

    def paint_eq_auto(self, c, pressed: bool, selected: bool) -> None:
        self._page_tab(c, "AUTO", pressed, selected, 2)

    def paint_eq_presets(self, c, pressed: bool) -> None:
        self._page_tab(c, "RANGE", pressed, False, 3)

    # ------------------------------------------------------------------
    # band sliders
    # ------------------------------------------------------------------
    def paint_eq_slider_frame(self, c, i: int) -> None:
        """14x63, x-invariant: the wash rises to meet the thumb.

        The thumb is 11 px tall and travels rows 0..51, so at frame ``i`` it
        sits with its top at ``51 - round(51 * i/27)`` and the column of wash
        runs from just under it to the foot of the sprite.
        """
        p = Plate(c, origin=(0, 0))
        h = c.h
        bot = int(lval("eq", "sliderThumbTravelY")[1])
        self._trough(p, 0, 0, h)
        thumb_top = bot - int(round(bot * i / 27.0))
        y0 = thumb_top + 11
        col_h = h - y0
        if col_h > 0:
            cols = np.stack([P.heat(1.0 - k / max(1.0, col_h - 1))
                             for k in range(col_h)])
            lead = np.ones((col_h, self.TROUGH_W), dtype=np.float32)
            rng = np.random.RandomState(4300 + i)
            # the top of the column is where the brush lifted: uneven
            for k in range(self.TROUGH_W):
                lead[0, k] = 0.30 + 0.60 * rng.rand()
                if col_h > 1:
                    lead[1, k] = 0.80 + 0.20 * rng.rand()
            M.wash_band(p, self.TROUGH_X, y0, self.TROUGH_W, col_h, cols, seed=i,
                        horizontal=False, lead=lead)
        p.opaque()

    def paint_eq_thumb(self, c, pressed: bool) -> None:
        p = Plate(c, origin=(0, 0))
        self._tile_thumb(p, 0, 1, c.w, c.h - 2, pressed)

    # ------------------------------------------------------------------
    # the curve slip
    # ------------------------------------------------------------------
    def paint_eq_graph_background(self, c) -> None:
        p = Plate(c)
        g = lrect("eq", "graph")
        M.lay_paper(p, g.x, g.y, g.w, g.h, window="eq", base=P.PAPER_HI)
        # a finer graticule on the slip, and a ruled centre line
        for y in range(g.y + 3, g.y + g.h, 4):
            p.hline(g.x, g.x + g.w - 1, y, P.BLUE[2], 0.30)
        for x in range(g.x + 3, g.x + g.w, 4):
            p.vline(x, g.y, g.y + g.h - 1, P.BLUE[2], 0.22)
        p.hline(g.x, g.x + g.w - 1, g.y + g.h // 2, P.BLUE[1], 0.55)
        p.hline(g.x, g.x + g.w - 1, g.y, P.PAPER_SH, 0.55)
        p.opaque()

    def eq_graph_line_colours(self):
        """19 rows, top to bottom: clay ink, darker at the top of the curve."""
        out = []
        for k in range(19):
            t = k / 18.0
            out.append(P.mix(P.CLAY_DARK, P.CLAY_LIGHT, t))
        return [tuple(int(v) for v in c[:3]) for c in out]

    def paint_eq_preamp_line(self, c) -> None:
        p = Plate(c, origin=(0, 0))
        for x in range(c.w):
            p.px(x, 0, P.INK_SOFT if x % 3 else P.INK_BODY, 0.85)
        p.opaque()
