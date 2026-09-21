"""Walnut 76 -- the Token Flow hood (SPEC 3.3).

The receiver's matching scope unit.  The same walnut lid and side panels and
the same champagne fascia as the other three components; in the middle of the
lid a machined aluminium escutcheon rises out of the fascia to carry a
chrome-framed black glass title window, and the base is a machined plinth with
a full-width glass legend channel that the app sets its two readout lines in.

Tile discipline
---------------
The app tiles GEN_TOP_TILE / GEN_BOTTOM_TILE from window x = 0 in steps of 25
and GEN_LEFT_TILE / GEN_RIGHT_TILE from window y = 20 in steps of 29, while the
builder paints those tiles at window x = 12 / y = 20.  So:

* every top and bottom row is either a flat colour or walnut made periodic in
  x with period 25, and the two horizontal tiles are painted through a view
  whose origin x is 0 -- the phase the app will actually show them at;
* the side rails are walnut periodic in y with period 29, painted at their
  true window position, which is already the phase the app tiles them at
  (20 + 29k == 20 mod 29);
* every corner piece evaluates the very same functions at its own window
  position, so it meets the tiles by construction;
* small repeated hardware (the knurl on the plinth lip) is stepped in window
  coordinates with a pitch that divides 25.
"""

from __future__ import annotations

import numpy as np

from skinkit.canvas import Canvas, mix

import w76_common as K
import w76_materials as M
import w76_palette as P

W, H = 275, 232
TOP_H, BOT_H, SIDE_W = 20, 14, 12
RAIL_H = 14                 # walnut rows of the title bar
CHEEK = 5                   # walnut side panel, this window
# 5 px, not the 7 of the other windows: the app sets the bottom-left readout
# at x=6 and right-aligns the other at x=W-6, so the glass legend channel has
# to start at x=5 for either line to have a margin of glass beside it.
XP, YP = 25, 29             # tile pitches

ARRIS = mix(P.WALNUT[6], "#ffffff", 0.16)     # the lid's oiled front edge
ARRIS2 = P.WALNUT[5]
WALL = "#000000"            # the well's inner wall
WALL_LIT = "#171c1e"        # the same wall where it faces the light
EDGE = "#010202"            # the field glass's own dark edge
FOOT = "#0c0806"            # the cabinet's bottom edge

# chamfer under the lid: a step down from the wood into the fascia.  Kept in
# the middle of the ALU ramp -- broad runs of #ece5d0 read as white paint, not
# as champagne, and this frame is nearly all edge.
CHAMFER = (0.18, 0.32, 0.46, 0.42)
# the fascia sliver between a cheek and the well, left side (the cheek's
# shadow falls to its right) and right side (its inner face is lit)
SLIVER_L = (0.05, 0.16, 0.26, 0.34)
SLIVER_R = (0.26, 0.30, 0.34, 0.40)


def _alu(t: float):
    return P.ramp_at(P.ALU, t)


def _stepped(c: Canvas, y: int, pitch: int, colour, phase: int = 0) -> None:
    """A pixel every ``pitch`` px along row ``y``, stepped in WINDOW x so the
    pattern is continuous across the cut between a tile and a corner."""
    x = -((c.ox - phase) % pitch)
    while x < c.w:
        if x >= 0:
            c.px(x, y, colour)
        x += pitch


class FieldWindow:
    """Mixin: every piece of the ``gen`` sheet."""

    # ------------------------------------------------------------------
    # the two full-width strips, as pure functions of window x and y
    # ------------------------------------------------------------------
    def _f_top_strip(self, s: Canvas) -> None:
        """The whole 20-row title bar at this canvas's window x."""
        wood = s.sub(0, 0, s.w, RAIL_H)
        M.walnut(wood, "h", seed=153, period=XP, tone=0.03)
        M.shade_rows(wood, {2: 1.14, 3: 1.05, 10: 0.97, 11: 0.90,
                            12: 0.72, 13: 0.44})
        # the lid's front arris: flat, so the escutcheon can butt it at any width
        s.hline(0, s.w - 1, 0, ARRIS)
        s.hline(0, s.w - 1, 1, ARRIS2)
        for k, t in enumerate(CHAMFER):
            s.hline(0, s.w - 1, RAIL_H + k, _alu(t))
        _stepped(s, RAIL_H + 3, 25, _alu(0.62))      # machined index every 25
        s.hline(0, s.w - 1, 18, P.CHROME[2])         # the well's trim, top run
        s.hline(0, s.w - 1, 19, WALL)

    def _f_bottom_strip(self, s: Canvas) -> None:
        """The whole 14-row plinth: the glass legend channel and its lips.

        Rows 4..9 are flat ``GLASS_FLAT``: the app sets the two readout lines
        there in its own 5x6 face, whose cells carry that exact background.
        """
        s.hline(0, s.w - 1, 0, P.CHROME[1])          # the well's trim, bottom run
        s.hline(0, s.w - 1, 1, _alu(0.50))           # the plinth, catching the light
        s.hline(0, s.w - 1, 2, _alu(0.34))           # rolling away from it
        s.hline(0, s.w - 1, 3, _alu(0.08))           # channel's top wall, in shadow
        s.box(0, 4, s.w, 6, P.GLASS_FLAT)            # the legend glass
        s.hline(0, s.w - 1, 10, WALL_LIT)            # channel's lit lower wall
        s.hline(0, s.w - 1, 11, _alu(0.72))          # machined lip
        _stepped(s, 11, 5, _alu(0.52))               # knurled, pitch 5 | 25
        s.hline(0, s.w - 1, 12, _alu(0.42))
        s.hline(0, s.w - 1, 13, FOOT)

    def _f_top_bg(self, c: Canvas) -> None:
        """Fill any title-bar piece with the strip at its own window place."""
        s = Canvas(c.w, TOP_H, origin=(c.ox, 0), window=c.window)
        self._f_top_strip(s)
        c.blit(s.crop(0, c.oy, c.w, c.h), 0, 0, alpha=False)

    def _f_bottom_bg(self, c: Canvas) -> None:
        s = Canvas(c.w, BOT_H, origin=(c.ox, H - BOT_H), window=c.window)
        self._f_bottom_strip(s)
        c.blit(s.crop(0, c.oy - (H - BOT_H), c.w, c.h), 0, 0, alpha=False)

    # ------------------------------------------------------------------
    # cabinet parts
    # ------------------------------------------------------------------
    def _f_cheek(self, c: Canvas, x0: int, left: bool) -> None:
        """A walnut side panel, vertical grain, periodic in y every 29 px."""
        v = c.sub(x0, 0, CHEEK, c.h)
        M.walnut(v, "v", seed=176 if left else 191, period=YP,
                 tone=0.0 if left else -0.02)
        if left:
            M.shade_cols(v, {0: 1.30, 1: 1.10, 2: 1.16, 3: 0.86, 4: 0.56})
        else:
            M.shade_cols(v, {0: 1.32, 1: 1.08, 2: 1.12, 3: 0.78, 4: 0.46})

    def _f_end_block(self, c: Canvas, x0: int, left: bool) -> None:
        """End grain of a side panel showing at the end of the lid rail."""
        blk = c.sub(x0, 0, CHEEK, RAIL_H)
        X, Y = M.grid(blk)
        n = M._hash01(X.astype(np.int64), Y.astype(np.int64), 4242)
        n2 = M.vnoise(X, Y, 2.0, 2.0, 99)
        t = (0.10 + 0.20 * n2 + np.where(n > 0.82, -0.08, 0.0)
             + np.where(n < 0.10, 0.07, 0.0))
        M._put(blk, M._ramp_map(P.WALNUT, t))
        M.shade_rows(blk, {0: 1.50, 1: 1.15, RAIL_H - 2: 0.70, RAIL_H - 1: 0.46})
        if left:
            c.vline(x0 + CHEEK, 1, RAIL_H - 1, P.WALNUT[0])       # lid joint
            M.shade_box(c, x0 + CHEEK + 1, 1, 1, RAIL_H - 2, 1.16)
            c.vline(0, 0, RAIL_H - 1, P.WALNUT[5])                # lit outer edge
            c.px(0, 0, P.WALNUT[6])
        else:
            c.vline(x0 - 1, 1, RAIL_H - 1, P.WALNUT[0])
            M.shade_box(c, x0, 1, 1, RAIL_H - 2, 1.12)
            c.vline(c.w - 1, 0, RAIL_H - 1, P.WALNUT[0])          # dark outer edge

    def _f_corner_cap(self, c: Canvas, x0: int, grip: bool) -> None:
        """A machined corner cap over the foot of a side panel.  The right-hand
        one is knurled: it is the resize grip."""
        y0 = 6
        for k, t in enumerate((0.56, 0.48, 0.42, 0.36, 0.28, 0.20)):
            c.hline(x0, x0 + CHEEK - 1, y0 + k, _alu(t))
        c.hline(x0, x0 + CHEEK - 1, y0, P.ALU[5])          # lit top chamfer
        c.vline(x0, y0 + 1, y0 + 5, P.ALU[3])
        c.hline(x0, x0 + CHEEK - 1, BOT_H - 1, FOOT)       # cabinet's foot
        if grip:
            base = x0 + CHEEK - 1 + BOT_H - 2          # the cap's outer corner
            for k in (1, 4, 7):
                for y in range(y0 + 1, BOT_H - 1):
                    for x, col in ((base - k - y, P.ALU[0]),
                                   (base - k + 1 - y, P.ALU[5])):
                        if x0 + 1 <= x <= x0 + CHEEK - 1:
                            c.px(x, y, col)
        else:
            for ry in (y0 + 2, y0 + 4):
                c.px(x0 + 2, ry, P.ALU[0])
                c.px(x0 + 3, ry, P.ALU[5])

    # ------------------------------------------------------------------
    # top edge
    # ------------------------------------------------------------------
    def paint_gen_top_tile(self, c: Canvas) -> None:
        """25x20 -- x-invariant: walnut periodic in x every 25 px."""
        v = c.resized_view(origin=(0, c.oy))
        self._f_top_bg(v)
        c.a[:, :, 3] = 255

    def paint_gen_top_left(self, c: Canvas) -> None:
        self._f_top_bg(c)
        self._f_end_block(c, 0, True)
        self._f_cheek(c.sub(0, RAIL_H, CHEEK, c.h - RAIL_H), 0, True)
        for k, t in enumerate(SLIVER_L):                    # fascia sliver
            c.vline(CHEEK + k, RAIL_H, c.h - 1, _alu(t))
        c.vline(9, 18, 19, P.CHROME[2])                     # the well's trim
        c.px(9, 18, P.CHROME[3])                            # corner glint
        c.px(10, 19, WALL)
        c.px(11, 19, WALL)
        c.a[:, :, 3] = 255

    def paint_gen_top_right(self, c: Canvas) -> None:
        self._f_top_bg(c)
        self._f_end_block(c, c.w - CHEEK, False)
        self._f_cheek(c.sub(0, RAIL_H, c.w, c.h - RAIL_H), c.w - CHEEK, False)
        for k, t in enumerate(SLIVER_R):
            c.vline(3 + k, RAIL_H, c.h - 1, _alu(t))
        c.vline(2, 18, 19, P.CHROME[1])
        c.px(1, 18, WALL)
        c.px(1, 19, WALL)
        c.px(0, 18, EDGE)
        c.px(0, 19, EDGE)
        c.a[:, :, 3] = 255

    def paint_gen_title_plate(self, c: Canvas) -> None:
        """100x20 -- the escutcheon.  Nothing is baked into the glass: the app
        sets the window title in it, centred, at y=7."""
        self._f_top_bg(c)
        esc = c.sub(1, 3, c.w - 2, 13)
        M.aluminium(esc, seed=31, level=0.36, sheen=0.40, win_w=W, win_h=H)
        c.hline(0, c.w - 1, 2, P.WALNUT[0])                 # rebate in the lid
        c.vline(0, 2, 15, P.WALNUT[0])
        c.vline(c.w - 1, 2, 15, P.WALNUT[0])
        c.hline(1, c.w - 2, 3, P.ALU[4])                    # lit chamfers
        c.vline(1, 3, 15, P.ALU[3])
        c.vline(c.w - 2, 4, 15, P.ALU[1])
        # the title window: chrome trim, black wall, flat glass
        interior = K.rect_mask((c.h, c.w), (7, 6, 87, 8))
        K.glass_shape(c, interior, glints=[(5, 4, P.CHROME[3]), (6, 4, P.CHROME[3]),
                                           (5, 5, P.CHROME[3])])
        for px_ in (2, c.w - 3):                            # machined pins
            c.px(px_, 9, P.ALU[0])
            c.px(px_, 10, P.ALU[6])
        c.a[:, :, 3] = 255

    # ------------------------------------------------------------------
    # sides
    # ------------------------------------------------------------------
    def paint_gen_left_tile(self, c: Canvas) -> None:
        """12x29 -- y-invariant: walnut periodic in y every 29 px."""
        self._f_cheek(c, 0, True)
        for k, t in enumerate(SLIVER_L):
            c.vline(CHEEK + k, 0, c.h - 1, _alu(t))
        c.vline(9, 0, c.h - 1, P.CHROME[2])
        c.vline(10, 0, c.h - 1, WALL)
        c.vline(11, 0, c.h - 1, EDGE)
        c.a[:, :, 3] = 255

    def paint_gen_right_tile(self, c: Canvas) -> None:
        self._f_cheek(c, c.w - CHEEK, False)
        for k, t in enumerate(SLIVER_R):
            c.vline(3 + k, 0, c.h - 1, _alu(t))
        c.vline(2, 0, c.h - 1, P.CHROME[1])
        c.vline(1, 0, c.h - 1, WALL)
        c.vline(0, 0, c.h - 1, EDGE)
        c.a[:, :, 3] = 255

    # ------------------------------------------------------------------
    # bottom edge
    # ------------------------------------------------------------------
    def paint_gen_bottom_tile(self, c: Canvas) -> None:
        """25x14 -- x-invariant: flat rows only."""
        v = c.resized_view(origin=(0, c.oy))
        self._f_bottom_bg(v)
        c.a[:, :, 3] = 255

    def paint_gen_bottom_left(self, c: Canvas) -> None:
        self._f_bottom_bg(c)
        self._f_cheek(c, 0, True)
        M.shade_rows(c.sub(0, 0, CHEEK, c.h), {c.h - 2: 0.74, c.h - 1: 0.40})
        self._f_corner_cap(c, 0, grip=False)
        # the cheek's shadow on the fascia, above and below the glass channel
        for x, f in ((CHEEK, 0.62), (CHEEK + 1, 0.86)):
            M.shade_box(c, x, 0, 1, 3, f)
            M.shade_box(c, x, 11, 1, 2, f)
        c.px(9, 0, P.CHROME[2])                    # the well's trim turns the corner
        c.px(10, 0, WALL)
        c.px(11, 0, EDGE)
        c.a[:, :, 3] = 255

    def paint_gen_bottom_right(self, c: Canvas) -> None:
        self._f_bottom_bg(c)
        self._f_cheek(c, c.w - CHEEK, False)
        M.shade_rows(c.sub(c.w - CHEEK, 0, CHEEK, c.h), {c.h - 2: 0.74, c.h - 1: 0.40})
        self._f_corner_cap(c, c.w - CHEEK, grip=True)
        for x, f in ((c.w - CHEEK - 1, 0.80),):
            M.shade_box(c, x, 0, 1, 3, f)
            M.shade_box(c, x, 11, 1, 2, f)
        c.px(2, 0, P.CHROME[1])
        c.px(1, 0, WALL)
        c.px(0, 0, EDGE)
        c.a[:, :, 3] = 255

    # ------------------------------------------------------------------
    # hardware
    # ------------------------------------------------------------------
    def paint_gen_close(self, c: Canvas, pressed: bool) -> None:
        """9x9 -- a black plastic push cap in a recess in the lid, the same
        hardware as the other windows' title buttons."""
        self.paint_title_button(c, "close", pressed)

    def paint_gen_lamp(self, c: Canvas, lit: bool) -> None:
        """9x9 -- the AUTO pilot: a warm incandescent jewel in a chrome collar,
        sunk into the walnut lid."""
        self._f_top_bg(c)
        c.rect(1, 1, 7, 7, P.WALNUT[0])                   # sunk bezel
        c.hline(2, 6, 7, mix(P.WALNUT[5], P.WALNUT[6], 0.4))
        c.vline(7, 2, 6, mix(P.WALNUT[4], P.WALNUT[5], 0.5))
        M.jewel(c, 4, 4, lit, r=2, colour="amber", halo=1.0)
        c.a[:, :, 3] = 255
