"""win_field -- the Token Flow window: a plate window cut through the cover.

The frame is the same binding as the Sessions ledger -- clay book cloth over
boards, sewn with linen thread -- with a rectangular window cut clean through
the board so the page shows.  The page *is* the display: the field draws its
ink on ivory.  A letterpress label is let into the head of the board to carry
the window's name, and a paper slip is let into the foot to carry the two
readings.

Tile discipline (skins/README.md).  The app tiles ``GEN_TOP_TILE`` and
``GEN_BOTTOM_TILE`` from x=0 and the side tiles from y=20, so:

* the cloth for this window is the *playlist* field, which is woven to repeat
  exactly every 25 px in x and every 29 px in y from y=20 -- the field window's
  resize step -- so any piece painted at its own window coordinates tiles;
* the two horizontal tiles are painted through a Plate whose origin is forced
  to x=0, because that is the phase the app tiles them at.  Every other piece
  keeps its true window origin, and ``w`` and ``h`` only ever change by a whole
  period, so every phase in the window agrees;
* everything a repeated tile draws besides the cloth is either constant along
  the repeat axis or has a pitch that divides the period (5 divides the 25 px
  top and bottom tiles; the sewing on the sides is drawn from the tile's own
  top edge).

The app also sets three runs of 5x6 text straight onto this chrome -- the
title at y=7 and the two readings at y=H-10 -- and a classic text.bmp glyph
carries its own cell background.  Both bands are therefore pressed flat in the
well colour (``M.plate_mark``), the way every other display in this skin is,
so the cells vanish into the paper.
"""

from __future__ import annotations

import numpy as np

from . import materials as M
from . import palette as P
from . import pictos
from . import typeset as T
from .plate import Plate

# the default-size window the builder paints in
W, H = 275, 232
TOP_H, BOT_H = 20, 14
LEFT_W, RIGHT_W = 12, 12
PERIOD_X, PERIOD_Y = 25, 29

#: the field frame is bound in the same cloth as the Sessions window, and that
#: is the one cloth field woven to repeat on (25, 29)
CLOTH_WIN = "playlist"

TOP_DYE = -0.12                  # the head and foot are a shade deeper than the boards
BOT_Y = H - BOT_H                # 218 -- the top row of the foot
WELL_X0, WELL_Y0 = LEFT_W, TOP_H
WELL_X1 = W - RIGHT_W - 1        # last column of the well

# the paper slip let into the foot.  The app sets its two readings at y=H-10,
# six rows tall, so rows 222..227 are pressed flat in the well colour.
SLIP_TOP = H - 12                # 220 -- the inlay's upper wall
SLIP_TEXT_Y = H - 10             # 222
SLIP_BOT = H - 3                 # 229 -- the inlay's lower wall, catching light

STITCH_PITCH_X = 5               # divides the 25 px horizontal tile
STITCH_Y = 6                     # the sewing line in the head

GRIP_RUN = 10                    # the binder's corner cap, in px along each leg


def _mask(art: str) -> np.ndarray:
    rows = art.strip("\n").split("\n")
    w = max(len(r) for r in rows)
    lut = {"#": 1.0, "+": 0.55, ":": 0.28}
    return np.array([[lut.get(k, 0.0) for k in r.ljust(w, ".")] for r in rows],
                    dtype=np.float32)


#: a printer's lozenge, and the lit lip its impression leaves below it
_LOZENGE = _mask("""
.#.
###
.#.
""")
_LOZENGE_LIP = _mask("""
...
...
.+.
""")

#: the AUTO seal: struck in clay when the field is choosing for itself
_SEAL = _mask("""
:###:
#####
#####
#####
:###:
""")
#: the ink spreading a hair into the fibres round a fresh strike
_SEAL_BLEED = _mask("""
.:::.
:###:
:###:
:###:
.:::.
""")


class FieldMixin:
    # ==================================================================
    # the head of the binding
    # ==================================================================
    def _fld_top_cloth(self, p: Plate) -> None:
        """Just the cloth, so a widget sprite can lay the identical ground."""
        M.lay_cloth(p, 0, 0, W, TOP_H, window=CLOTH_WIN, dye=TOP_DYE)

    def _fld_top(self, p: Plate) -> None:
        """The head: cloth, the lit turn-over, and the upper wall of the cut.

        A pure function of window x -- every line runs the full width -- so the
        25 px tile repeats and the corners only add their own ends.
        """
        self._fld_top_cloth(p)
        p.hline(0, W - 1, 0, P.CLAY_LIGHT, 0.55)
        p.hline(0, W - 1, 1, P.CLAY_LIGHT, 0.18)
        # the board is cut through here: the upper wall faces away from the
        # light, and the cloth creases as it turns over the cut edge
        p.hline(0, W - 1, TOP_H - 3, P.CLAY_LIGHT, 0.22)
        p.hline(0, W - 1, TOP_H - 2, P.SHADOW_ON_CLOTH, 0.40)
        p.hline(0, W - 1, TOP_H - 1, P.CLAY_SHADOW)

    def _fld_top_sewing(self, p: Plate, x0: int, length: int) -> None:
        """Linen sewing along the head.  Pitch 5 divides the 25 px tile, and
        ``x0`` is always a multiple of 5, so the run carries across the seam."""
        M.stitch_run(p, x0, STITCH_Y, length, vertical=False,
                     pitch=STITCH_PITCH_X, stitch=3, seed=31)

    def paint_gen_top_tile(self, c) -> None:
        """25x20, repeated along the head.  The app tiles it from x=0, so the
        piece is painted in that phase, not at its slot's own origin."""
        p = Plate(c, origin=(0, 0))
        self._fld_top(p)
        self._fld_top_sewing(p, 0, PERIOD_X)
        p.opaque()

    def paint_gen_top_left(self, c) -> None:
        """12x20 -- the head of the spine, with its silk head-band."""
        p = Plate(c)
        self._fld_top(p)
        self._headband(p, 4)
        p.vline(0, 0, TOP_H - 1, P.CLAY_LIGHT, 0.45)
        p.px(0, 0, P.CLAY_PALE, 0.75)
        p.px(1, 1, P.CLAY_PALE, 0.45)
        p.opaque()

    def paint_gen_top_right(self, c) -> None:
        """12x20 -- the fore-edge head; the close button sits over it."""
        p = Plate(c)
        self._fld_top(p)
        self._fld_top_sewing(p, 250, PERIOD_X)
        self._headband(p, W - 9)
        p.vline(W - 1, 0, TOP_H - 1, P.CLAY_SHADOW, 0.70)
        p.vline(W - 2, 1, TOP_H - 2, P.CLAY_DARK, 0.35)
        p.px(W - 1, 0, P.CLAY_PALE, 0.55)
        p.opaque()

    # ==================================================================
    # the title label -- let into the board, nothing baked into it
    # ==================================================================
    def paint_gen_title_plate(self, c) -> None:
        """100x20.  The app centres the window title on it at y=7 in the
        skin's own 5x6 face, so the middle is a pressed, flat ivory band and
        the label carries only its rules and its ends."""
        p = Plate(c)
        x0 = p.ox                       # 87 at the default width
        self._fld_top(p)
        # the label: ivory stock let into the cloth-covered board
        M.cut_opening(p, x0 + 1, 4, 98, 12, window=CLOTH_WIN, depth=1)
        # the printing plate's impression: flat well colour under the title,
        # wide enough for the longest title the app sets (17 glyphs)
        M.plate_mark(p, x0 + 7, 7, 86, 6, margin=1)
        # a clay rule printed under the title, with the ends turned up
        p.hline(x0 + 8, x0 + 91, 15, P.CLAY_DEEP, 0.85)
        for ex in (x0 + 7, x0 + 92):
            p.px(ex, 15, P.CLAY_DEEP, 0.55)
            p.px(ex, 14, P.CLAY_DEEP, 0.70)
        # a printer's lozenge at each end of the label
        for ex in (x0 + 2, x0 + 95):
            p.mask(ex, 8, _LOZENGE, P.CLAY_DEEP)
            p.mask(ex, 8, _LOZENGE_LIP, P.PAPER_HI, 0.75)
        p.opaque()

    # ==================================================================
    # the sides -- sewn boards, the cut walls facing the well
    # ==================================================================
    def paint_gen_left_tile(self, c) -> None:
        """12x29, repeated down the spine side.  Everything is drawn from the
        tile's own top edge, so the sewing repeats exactly."""
        p = Plate(c)
        y0, h = p.oy, c.h
        M.lay_cloth(p, 0, y0, LEFT_W, h, window=CLOTH_WIN, dye=-0.10)
        p.vline(0, y0, y0 + h - 1, P.CLAY_LIGHT, 0.45)
        p.vline(1, y0, y0 + h - 1, P.CLAY_LIGHT, 0.16)
        M.stitch_run(p, 4, y0, h, vertical=True, pitch=14, stitch=6, seed=33,
                     phase=1)
        # the cut: the left wall faces away from the light
        p.vline(WELL_X0 - 2, y0, y0 + h - 1, P.CLAY_LIGHT, 0.22)
        p.vline(WELL_X0 - 1, y0, y0 + h - 1, P.CLAY_SHADOW)
        p.opaque()

    def paint_gen_right_tile(self, c) -> None:
        """12x29, repeated down the fore-edge side."""
        p = Plate(c)
        y0, h = p.oy, c.h
        M.lay_cloth(p, W - RIGHT_W, y0, RIGHT_W, h, window=CLOTH_WIN, dye=-0.10)
        # the cut: the right wall faces the light and shows the board's core
        p.vline(WELL_X1 + 1, y0, y0 + h - 1, P.BOARD_CORE)
        p.vline(WELL_X1 + 2, y0, y0 + h - 1, P.SHADOW_ON_CLOTH, 0.18)
        M.stitch_run(p, W - 8, y0, h, vertical=True, pitch=14, stitch=6, seed=34,
                     phase=1)
        p.vline(W - 2, y0, y0 + h - 1, P.CLAY_DARK, 0.35)
        p.vline(W - 1, y0, y0 + h - 1, P.CLAY_SHADOW, 0.70)
        p.opaque()

    # ==================================================================
    # the foot -- a paper slip let in, carrying the two readings
    # ==================================================================
    def _fld_bottom(self, p: Plate) -> None:
        """The tail.  A pure function of window x, so the 25 px tile repeats;
        rows 222..227 are pressed flat for the app's 5x6 readings."""
        M.lay_cloth(p, 0, BOT_Y, W, BOT_H, window=CLOTH_WIN, dye=TOP_DYE)
        # the lower wall of the cut, catching the light, then the crease
        p.hline(0, W - 1, BOT_Y, P.BOARD_CORE_HI)
        p.hline(0, W - 1, BOT_Y + 1, P.SHADOW_ON_CLOTH, 0.20)
        # the slip let into the board
        M.lay_paper(p, 0, SLIP_TOP + 1, W, SLIP_BOT - SLIP_TOP - 1,
                    window=CLOTH_WIN, gain=0.8)
        p.hline(0, W - 1, SLIP_TOP, P.CLAY_SHADOW)
        p.hline(0, W - 1, SLIP_TOP + 1, P.SHADOW_ON_PAPER, 0.26)
        p.hline(0, W - 1, SLIP_BOT, P.BOARD_CORE_HI)
        # the impression the readings are set in: flat, in the well colour
        M.plate_mark(p, 0, SLIP_TEXT_Y, W, 6, margin=0)
        # the foot of the cover
        p.hline(0, W - 1, H - 2, P.CLAY_DARK, 0.45)
        p.hline(0, W - 1, H - 1, P.CLAY_SHADOW, 0.85)

    def paint_gen_bottom_tile(self, c) -> None:
        """25x14, repeated along the foot.  Tiled from x=0, like the head."""
        p = Plate(c, origin=(0, BOT_Y))
        self._fld_bottom(p)
        p.opaque()

    def _slip_end(self, p: Plate, x0: int, right: bool) -> None:
        """Close the slip off inside a corner piece: cloth again, then the
        inlay's wall -- dark on the left, lit board core on the right."""
        M.lay_cloth(p, x0, SLIP_TOP, 3, SLIP_BOT - SLIP_TOP + 1,
                    window=CLOTH_WIN, dye=TOP_DYE)
        wall = x0 if right else x0 + 2
        p.vline(wall, SLIP_TOP, SLIP_BOT, P.BOARD_CORE if right else P.CLAY_SHADOW)
        p.px(wall, SLIP_TOP, P.CLAY_SHADOW)
        p.px(wall, SLIP_BOT, P.BOARD_CORE_HI)
        # the wall it stands against: lit on the fore-edge side, in the board's
        # own shadow on the spine side
        edge = wall - 1 if right else wall + 1
        p.vline(edge, SLIP_TOP + 1, SLIP_BOT - 1,
                P.PAPER_HI if right else P.SHADOW_ON_PAPER, 0.45 if right else 0.30)

    def paint_gen_bottom_left(self, c) -> None:
        """12x14 -- the foot of the spine."""
        p = Plate(c)
        self._fld_bottom(p)
        self._slip_end(p, 0, right=False)
        p.vline(0, BOT_Y, H - 1, P.CLAY_LIGHT, 0.45)
        p.vline(1, BOT_Y + 1, H - 3, P.CLAY_LIGHT, 0.16)
        p.px(0, H - 1, P.CLAY_PALE, 0.75)
        p.px(1, H - 2, P.CLAY_PALE, 0.35)
        p.opaque()

    def paint_gen_bottom_right(self, c) -> None:
        """12x14 -- the fore-edge foot, carrying the resize grip."""
        p = Plate(c)
        self._fld_bottom(p)
        self._slip_end(p, W - 3, right=True)
        p.vline(W - 2, BOT_Y, H - 1, P.CLAY_DARK, 0.35)
        p.vline(W - 1, BOT_Y, H - 1, P.CLAY_SHADOW, 0.70)
        p.px(W - 1, H - 1, P.CLAY_PALE, 0.55)
        self._grip(p)
        p.opaque()

    def _grip(self, p: Plate) -> None:
        """The resize grip: the binder's corner cap -- a triangle of cloth
        folded over the corner of the boards and whipped down in linen thread,
        which is both a real half-binding's corner and something to pull on.
        Its fold is cut so the cap never reaches the right-hand reading, which
        can run out to x=W-7."""
        x0, y1 = W - GRIP_RUN, H - 1
        for y in range(y1 - GRIP_RUN + 1, y1 + 1):
            xs = x0 + (y1 - y)
            M.lay_cloth(p, xs, y, W - xs, 1, window=CLOTH_WIN, dye=-0.20)
            # the cloth folds over the corner: a lit crease, then the shadow
            # it casts -- on the slip's paper above, on the cover's cloth below
            p.px(xs, y, P.CLAY_LIGHT, 0.55)
            sh = P.SHADOW_ON_PAPER if y <= SLIP_BOT - 1 else P.SHADOW_ON_CLOTH
            for k, a in ((1, 0.34), (2, 0.14)):
                if xs - k >= W - 6:
                    p.px(xs - k, y, sh, a)
        # the outer edges of the cover carry on across the cap
        p.hline(x0, W - 1, y1, P.CLAY_SHADOW, 0.85)
        p.vline(W - 1, y1 - GRIP_RUN + 1, y1, P.CLAY_SHADOW, 0.70)
        p.px(W - 1, y1, P.CLAY_PALE, 0.55)
        # whipped over the fold in linen thread: three runs, pale on clay, the
        # grip you actually pull the corner by
        for off in (2, 5, 8):
            for y in range(y1 - GRIP_RUN + 1, y1 + 1):
                x = x0 + (y1 - y) + off
                if x > W - 2 or y > y1 - 1:
                    continue
                p.px(x, y, P.THREAD[2] if (x + y) % 2 else P.THREAD[1])
                p.px(x + 1, y, P.THREAD[0], 0.75)
                p.px(x + 1, y + 1, P.SHADOW_ON_CLOTH, 0.45)

    # ==================================================================
    # close button and the AUTO seal
    # ==================================================================
    def paint_gen_close(self, c, pressed: bool) -> None:
        """9x9 -- the same blind-stamped square as the other windows wear,
        struck into this window's cloth."""
        p = Plate(c)
        x, y = p.ox, p.oy
        t = M.cloth_t(CLOTH_WIN)[y:y + 9, x:x + 9]
        p.paste(x, y, M.cloth_rgb(t, dye=-0.265 if pressed else -0.215))
        p.hline(x, x + 8, y, P.SHADOW_ON_CLOTH, 0.55)
        p.vline(x, y + 1, y + 8, P.SHADOW_ON_CLOTH, 0.45)
        p.hline(x + 1, x + 8, y + 8, P.CLAY_LIGHT, 0.45)
        p.vline(x + 8, y + 1, y + 7, P.CLAY_LIGHT, 0.35)
        if pressed:
            p.hline(x + 1, x + 7, y + 1, P.SHADOW_ON_CLOTH, 0.35)
            p.vline(x + 1, y + 2, y + 7, P.SHADOW_ON_CLOTH, 0.28)
        m = pictos.TITLE["close"]
        if pressed:
            p.mask(x + 3, y + 3, m, P.CLAY_PALE)
        else:
            T.foil(p, x + 2, y + 2, "", cov=m, seed=ord("c"))
        p.opaque()

    def paint_gen_lamp(self, c, lit: bool) -> None:
        """9x9 -- whether the field is choosing its own configuration.  This
        skin has no lamps: it has a chit of stock stamped in clay ink when the
        thing is happening, and blind-debossed when it is not."""
        p = Plate(c)
        x, y = p.ox, p.oy
        self._fld_top_cloth(p)
        self._fld_top_sewing(p, 250, 11)
        M.card(p, x + 1, y + 1, 7, 7, window=CLOTH_WIN, on="cloth",
               tone="ivory" if lit else "manilla", notch=True, shadow=False)
        p.hline(x + 2, x + 8, y + 8, P.SHADOW_ON_CLOTH, 0.45)
        p.vline(x + 8, y + 2, y + 7, P.SHADOW_ON_CLOTH, 0.40)
        if lit:
            # struck: a solid seal of clay ink, with a hair of ink spread
            # into the fibres round the edge
            p.mask(x + 1, y + 1, _SEAL_BLEED, P.CLAY_PALE, 0.35)
            p.mask(x + 2, y + 2, _SEAL, P.CLAY_DEEP)
            p.px(x + 3, y + 3, P.CLAY, 0.75)          # the sheen on the wax
            p.px(x + 4, y + 3, P.CLAY, 0.35)
            p.px(x + 5, y + 5, P.CLAY_DARK, 0.65)     # where it pressed hardest
            p.px(x + 4, y + 6, P.CLAY_SHADOW, 0.55)
        else:
            # not struck -- only the ghost of the seal, blind in the stock
            T.blind(p, x + 2, y + 2, "", cov=_SEAL, on="paper", strength=1.0)
        p.opaque()
