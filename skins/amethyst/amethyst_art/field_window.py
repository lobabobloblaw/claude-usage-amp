"""Token Flow window (SPEC 3.3) -- the big LED dot-matrix panel.

The faceplate's token bargraph has a full-size sibling: a dot-matrix LED module
in a black epoxy body, bolted to the same purple board, with a character-LCD
status strip along its bottom edge and a small LCD title window in the top
flange.  The field the app blits into the well is painted in ``viscolors``, and
``viscolors()[0]`` is ``BAR_FACE`` -- the same black the module's face is
painted in here -- so the well and the module's face are one surface.

Tile discipline
---------------
``GEN_TOP_TILE`` / ``GEN_BOTTOM_TILE`` repeat every 25 px horizontally and
``GEN_LEFT_TILE`` / ``GEN_RIGHT_TILE`` every 29 px vertically, so:

* every row of the top and bottom strips is x-invariant, or repeats with a
  pitch that divides 25 (the gold castellations, pitch 5; one part per tile);
* every column of the side strips is y-invariant, or repeats with pitch 29.

The app tiles the top and bottom strips from x = 0 while the builder hands the
tile painter a canvas whose origin is x = 12, so the tiles are painted through
a Pen re-origined to x = 25: a mark made at window x then lands on the screen
at x mod 25, in step with the corners.
"""

from __future__ import annotations

from . import palette as P
from . import parts as K
from . import controls as C
from . import pen as pn
from .parts import M, G, T, E, S
from .pen import Pen

W, H = 275, 232
SEED = 89

TITLE_H, BOTTOM_H, SIDE_W = 20, 14, 12
WELL_BOTTOM = H - BOTTOM_H                              # 218
FACE = P.BAR_FACE                                       # == viscolors()[0]

# rows of the top strip (window y).  Gold castellations sit on rows 0..2.
BUS_A, BUS_B = 5, 12            # the panel's power and return rails
SILK_Y = 14                     # the panel's silk courtyard line
RIM_TOP = 16                    # 16..19  panel flange, then its face margin

# rows of the bottom strip: the status glass, with the app's two readouts on
# rows 222..227 (``readoutFromBottomLeft`` / ``valueFromBottomRight``)
GLASS_TOP, GLASS_BOT = 221, 228

# the glass runs nearly edge to edge: the left readout starts at x = 6 and the
# right one is right-aligned on x = W - 6, so its last ink column is W - 7
GLASS_X0, GLASS_X1 = 4, W - 6


def _mask_h(c):
    """Solder mask for a horizontally tiled strip: tone varies with y only."""
    pn.paint_mask(c, pn.mask_value(c, seed=SEED, invariant="x"))


def _mask_v(c):
    """Solder mask for a vertically tiled strip: tone varies with x only."""
    pn.paint_mask(c, pn.mask_value(c, seed=SEED, invariant="y"))


def _trace_h(p, x0, x1, y):
    """A horizontal trace: invariant along x apart from its sheen, which is on
    a 5 px pitch so it survives the 25 px repeat."""
    p.shade(x0, y + 1, x1 - x0 + 1, 1, 0.80)
    p.hline(x0, x1, y, P.POUR[3])
    for x in range(x0 + (-x0) % 5, x1 + 1, 5):
        p.px(x, y, P.POUR[4])


def _trace_v(p, x, y0, y1, sheen=()):
    p.shade(x + 1, y0 + 1, 1, y1 - y0 + 1, 0.80)
    p.vline(x, y0, y1, P.POUR[3])
    for y in sheen:
        p.px(x, y, P.POUR[4])


def _teeth(p, x0, x1):
    """Gold edge plating on the routed board edge, 3 px teeth on a 5 px pitch."""
    for x in range(x0 + (-x0) % 5, x1 + 1, 5):
        p.box(x, 0, 3, 3, G[3])
        p.hline(x, x + 2, 1, G[4])
        p.hline(x, x + 2, 2, G[2])
        p.px(x, 0, G[4]); p.px(x + 1, 0, M[0]); p.px(x + 2, 0, G[2])


# ---------------------------------------------------------------------------
# top strip
# ---------------------------------------------------------------------------
def _top_rows(p, x0, x1, teeth=True, rim=None):
    """Every x-invariant row of the 20 px title strip, x0..x1 inclusive.

    ``rim`` limits the panel's top flange to the x range the panel occupies;
    outside it (the outer 8 px of each corner) the board runs to the edge."""
    p.hline(x0, x1, 0, P.FR4[3])                       # routed edge, bare laminate
    p.hline(x0, x1, 1, M[6])                           # the mask's lit lip
    if teeth:
        _teeth(p, x0, x1)
    p.shade(x0, 3, x1 - x0 + 1, 1, 0.74)               # the teeth's contact shadow
    _trace_h(p, x0, x1, BUS_A)
    _trace_h(p, x0, x1, BUS_B)
    p.hline(x0, x1, SILK_Y, S[1])                      # silk courtyard of the panel
    # the panel's top flange: lit arris, body, dark inner lip, then its face
    rx0, rx1 = rim if rim else (x0, x1)
    p.hline(rx0, rx1, RIM_TOP, E[4])
    p.hline(rx0, rx1, RIM_TOP + 1, E[2])
    p.hline(rx0, rx1, RIM_TOP + 2, E[1])
    p.hline(rx0, rx1, RIM_TOP + 3, FACE)


def top_tile(c):
    _mask_h(c)
    p = Pen(c, origin=(25, 0))                         # see the module docstring
    _top_rows(p, 25, 49)
    # One part per 25 px, bridging the two rails, and a tented via on the
    # return.  Both live at tile-local x >= 14, so the AUTO lamp (which always
    # lands on tile-local 2..10) never sits on a part.
    K.sot23(p, 39, BUS_A + 2)
    for sx in (38, 44):                                 # its silk courtyard
        p.px(sx, BUS_A + 3, S[1]); p.px(sx, BUS_A + 5, S[1])
    p.vline(41, BUS_A, BUS_A + 2, P.POUR[3])
    p.vline(39, BUS_A + 6, BUS_B, P.POUR[3]); p.vline(43, BUS_A + 6, BUS_B, P.POUR[3])
    K.via_tented(p, 47, BUS_B)


def top_left(c):
    _mask_h(c)
    p = Pen(c)
    _top_rows(p, 0, SIDE_W - 1, teeth=False, rim=(8, SIDE_W - 1))
    _teeth(p, 5, SIDE_W - 1)
    # the two rails turn 45 degrees into the left edge's vertical pair
    K.traces(p, [[(11, BUS_A), (5, BUS_A), (3, BUS_A + 2), (3, 19)],
                 [(11, BUS_B), (7, BUS_B), (5, BUS_B + 2), (5, 19)]])
    p.hline(0, SIDE_W - 1, SILK_Y, S[1])           # silk prints over the copper
    K.test_point(p, 3, 9)                          # the rail's probe pad, on the bend
    # the routed left edge and the panel's lit left arris
    p.vline(0, 0, 19, P.FR4[3]); p.vline(1, 1, 19, M[5]); p.px(0, 0, P.FR4[4])
    _rim_left(p, RIM_TOP + 1, 19)


def top_right(c):
    _mask_h(c)
    p = Pen(c, origin=(W - SIDE_W, 0))
    _top_rows(p, W - SIDE_W, W - 1, teeth=False, rim=(W - SIDE_W, W - 9))
    _teeth(p, W - 10, W - 2)
    # the traces dive under the close pad and surface again as the right edge's
    # vertical pair, each out of its own via
    K.via(p, W - 6, 12)
    K.via(p, W - 4, 15)
    _trace_v(p, W - 6, 13, 19)
    _trace_v(p, W - 4, 16, 19)
    p.hline(W - SIDE_W, W - 1, SILK_Y, S[1])
    p.vline(W - 1, 0, 19, P.FR4[1]); p.vline(W - 2, 1, 19, M[1])
    _rim_right(p, RIM_TOP + 1, 19)


def _mask_patch(c, x, y, w, h):
    """Repaint a rect of the strip's mask (used where art has to be undone)."""
    v = c.sub(x, y, w, h)
    pn.paint_mask(v, pn.mask_value(v, seed=SEED, invariant="x"))


def title_plate(c):
    """100x20.  Nothing is baked into the text band: the app centres the window
    title on it in the skin's 5x6 LCD face, whose cells carry their own field
    colour, so the band is painted as one long character-LCD aperture."""
    _mask_h(c)
    p = Pen(c)
    x0 = c.ox
    x1 = x0 + c.w - 1
    _top_rows(p, x0, x1, teeth=False)
    # the module sits over the castellated edge: repaint rows 3..15 and build it
    _mask_patch(c, 0, 3, c.w, 13)
    # tin frame
    for x in (x0, x0 + 1):
        p.vline(x, 3, 15, T[5] if x == x0 else T[3])
    for x in (x1 - 1, x1):
        p.vline(x, 3, 15, T[2] if x == x1 - 1 else T[1])
    p.hline(x0, x1, 3, T[6]); p.hline(x0, x1, 4, T[3])
    p.hline(x0, x1, 15, T[2])
    p.px(x0, 3, (255, 255, 255, 255)); p.px(x1, 15, T[0])
    # two twisted frame tabs, the way the playlist module is held down
    for tx in (x0 + 6, x1 - 8):
        p.box(tx, 2, 3, 2, T[4]); p.hline(tx, tx + 2, 2, T[6]); p.px(tx + 2, 3, T[2])
    # black bezel, then the glass
    for x in (x0 + 2, x0 + 3, x1 - 2, x1 - 3):
        p.vline(x, 5, 14, P.BEZEL[1])
    p.hline(x0 + 2, x1 - 2, 5, P.BEZEL[1])
    p.hline(x0 + 2, x1 - 2, 14, P.BEZEL[1])
    p.box(x0 + 4, 6, c.w - 8, 8, P.LCD_FIELD)
    p.hline(x0 + 4, x1 - 4, 6, P.LCD_SHADE)            # recess under the bezel
    p.vline(x0 + 4, 6, 13, P.LCD_SHADE)
    p.px(x0 + 4, 6, P.LCD_DEEP)
    # backlight spill on the bezel, strongest at the left where the LEDs sit
    for k, x in enumerate(range(x0 + 2, x1 - 1)):
        f = 1.0 - 0.8 * k / max(1, c.w - 8)
        p.px(x, 5, P.lerp(P.BEZEL[1], P.LCD_DEEP, 0.5 * f))
        p.px(x, 14, P.lerp(P.BEZEL[1], P.LCD_FIELD, 0.45 * f))
    # the character cells of the module: faint where nothing is lit, and hidden
    # wherever the app's (opaque) glyph cells land
    for x in range(x0 + 9, x1 - 4, 5):
        p.vline(x, 7, 12, P.LCD_GHOST)
        p.px(x, 6, P.lerp(P.LCD_SHADE, P.LCD_DEEP, 0.4))
    p.hline(x0 + 5, x1 - 5, 13, P.lerp(P.LCD_FIELD, P.LCD_GHOST, 0.55))
    p.shade(x0 + 1, 16, c.w - 1, 1, 0.72)              # the module's contact shadow


# ---------------------------------------------------------------------------
# the panel's body, seen edge-on down the sides
# ---------------------------------------------------------------------------
def _rim_left(p, y0, y1):
    """Columns 8..11: lit arris, epoxy body, inner lip, face margin."""
    for x, col in ((8, E[4]), (9, E[2]), (10, E[1]), (11, FACE)):
        p.vline(x, y0, y1, col)


def _rim_right(p, y0, y1):
    """Columns 263..266 mirrored, and the shadow the body throws on the board."""
    for x, col in ((W - 12, FACE), (W - 11, E[1]), (W - 10, E[2]), (W - 9, E[0])):
        p.vline(x, y0, y1, col)
    p.shade(W - 8, y0, 1, y1 - y0 + 1, 0.62)
    p.shade(W - 7, y0, 1, y1 - y0 + 1, 0.82)


# ---------------------------------------------------------------------------
# sides -- 12x29, repeated down the window; every column is y-invariant
# ---------------------------------------------------------------------------
def left_tile(c):
    _mask_v(c)
    p = Pen(c)
    y0, y1 = c.oy, c.oy + c.h - 1
    p.vline(0, y0, y1, P.FR4[3]); p.vline(1, y0, y1, M[5])
    _trace_v(p, 3, y0, y1, sheen=(y0 + 5, y0 + 21))
    _trace_v(p, 5, y0, y1, sheen=(y0 + 12,))
    _rim_left(p, y0, y1)
    # one via and one test point per tile (pitch 29, both clear of the clip)
    K.via(p, 3, y0 + 9)
    K.test_point(p, 6, y0 + 17)
    p.px(2, y0 + 3, S[0]); p.px(2, y0 + 4, S[0])        # a silk tick in the margin


def right_tile(c):
    _mask_v(c)
    p = Pen(c)
    y0, y1 = c.oy, c.oy + c.h - 1
    _rim_right(p, y0, y1)
    _trace_v(p, W - 6, y0, y1, sheen=(y0 + 7,))
    _trace_v(p, W - 4, y0, y1, sheen=(y0 + 19,))
    p.vline(W - 1, y0, y1, P.FR4[1]); p.vline(W - 2, y0, y1, M[1])
    K.via_tented(p, W - 4, y0 + 11)
    K.chip_r(p, W - 6, y0 + 20, horizontal=False, n=3)  # a series resistor per tile
    p.px(W - 3, y0 + 2, S[0])


# ---------------------------------------------------------------------------
# bottom strip -- the status glass
# ---------------------------------------------------------------------------
def _bottom_rows(p, x0, x1, panel=True):
    """Every x-invariant row of the 14 px bottom strip, x0..x1 inclusive."""
    if panel:
        p.hline(x0, x1, WELL_BOTTOM, E[3])                  # inner bevel, facing the light
        p.hline(x0, x1, WELL_BOTTOM + 1, E[2])              # the flange's face
        p.hline(x0, x1, WELL_BOTTOM + 2, E[0])              # dark outer arris
    p.hline(x0, x1, GLASS_TOP, P.LCD_SHADE)                 # glass, recessed at the top
    for y in range(GLASS_TOP + 1, GLASS_BOT + 1):
        p.hline(x0, x1, y, P.LCD_FIELD)
    p.hline(x0, x1, GLASS_BOT + 1, P.BEZEL[1])              # bezel below the glass
    p.hline(x0, x1, H - 2, M[1])                            # the mask's dark lip
    p.hline(x0, x1, H - 1, P.FR4[1])                        # routed bottom edge
    # the module's character cells, faint under the app's (opaque) glyph cells
    for x in range(x0 + (-x0) % 5, x1 + 1, 5):
        p.px(x, GLASS_BOT, P.LCD_GHOST)


def bottom_tile(c):
    _mask_h(c)
    p = Pen(c, origin=(25, WELL_BOTTOM))
    _bottom_rows(p, 25, 49)


def bottom_left(c):
    _mask_h(c)
    p = Pen(c)
    _bottom_rows(p, 0, SIDE_W - 1, panel=False)
    # the panel's bottom-left corner, then the board outside it
    p.hline(8, SIDE_W - 1, WELL_BOTTOM, E[3]); p.px(8, WELL_BOTTOM, E[4])
    p.hline(8, SIDE_W - 1, WELL_BOTTOM + 1, E[2]); p.px(8, WELL_BOTTOM + 1, E[3])
    p.hline(8, SIDE_W - 1, WELL_BOTTOM + 2, E[0])
    # the side bus ends on two gold pads under the panel
    for x in (3, 5):
        p.px(x, WELL_BOTTOM, P.POUR[3])
    K.pad(p, 2, WELL_BOTTOM + 1, 2, 2)
    K.pad(p, 5, WELL_BOTTOM + 1, 2, 2)
    # the glass's left end: bezel, recess, then the field the readout sits on
    p.vline(GLASS_X0 - 2, GLASS_TOP, GLASS_BOT + 1, P.BEZEL[1])
    p.vline(GLASS_X0 - 1, GLASS_TOP, GLASS_BOT, P.LCD_SHADE)
    p.px(GLASS_X0 - 1, GLASS_TOP, P.LCD_DEEP)
    p.vline(0, WELL_BOTTOM, H - 1, P.FR4[3]); p.vline(1, WELL_BOTTOM, H - 2, M[5])
    p.px(0, H - 1, P.FR4[0])


def bottom_right(c):
    _mask_h(c)
    p = Pen(c)
    _bottom_rows(p, W - SIDE_W, W - 1, panel=False)
    p.hline(W - SIDE_W, W - 9, WELL_BOTTOM, E[3]); p.px(W - 9, WELL_BOTTOM, E[0])
    p.hline(W - SIDE_W, W - 9, WELL_BOTTOM + 1, E[2]); p.px(W - 9, WELL_BOTTOM + 1, E[0])
    p.hline(W - SIDE_W, W - 9, WELL_BOTTOM + 2, E[0])
    p.shade(W - 8, WELL_BOTTOM, 2, 3, 0.62)
    # the glass stops where the right-hand readout does; the rest is the grip
    for y in range(GLASS_TOP, GLASS_BOT + 2):
        p.hline(GLASS_X1 + 1, W - 1, y, M[3])
    _mask_patch(c, GLASS_X1 + 1 - c.ox, GLASS_TOP - c.oy, W - 1 - GLASS_X1, GLASS_BOT + 2 - GLASS_TOP)
    p.vline(GLASS_X1 + 1, GLASS_TOP, GLASS_BOT + 1, P.BEZEL[1])
    p.px(GLASS_X1 + 1, GLASS_BOT + 1, P.BEZEL[0])
    _grip(p)
    p.vline(W - 1, WELL_BOTTOM, H - 1, P.FR4[1]); p.vline(W - 2, WELL_BOTTOM, H - 2, M[1])
    p.px(W - 1, H - 1, P.FR4[0])


def _grip(p):
    """The resize grip: the module's end tab, knurled so it reads as a handle."""
    x0, y0, x1, y1 = W - 5, WELL_BOTTOM + 1, W - 3, H - 3
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            t = 0.66 - 0.014 * (y - y0) - 0.10 * (x - x0)
            p.px(x, y, P.sample(T, t))
    p.hline(x0, x1, y0, T[5]); p.vline(x0, y0, y1, T[4])
    p.hline(x0, x1, y1, T[1]); p.vline(x1, y0, y1, T[1])
    for k in range(3):                                  # 45-degree knurl
        yy = y0 + 4 + k * 3
        p.line(x0, yy + 1, x1, yy - 1, T[1])
        p.line(x0, yy, x1, yy - 2, T[5])
    p.px(x0, y0, T[6])
    p.shade(x1 + 1, y0 + 1, 1, y1 - y0, 0.7)            # its shadow on the mask


# ---------------------------------------------------------------------------
# title-bar hardware
# ---------------------------------------------------------------------------
def close(c, pressed):
    """9x9 gold touch pad, the same key the other windows close with."""
    p = Pen(c)
    x, y = c.origin
    C.gold_button(p, x, y, "close", pressed)


def lamp(c, lit):
    """9x9 -- AUTO: a 1206 LED straddling the return rail, lit while the field
    is choosing its own configuration."""
    _mask_h(c)
    p = Pen(c)
    x, y = c.origin
    _top_rows(p, x, x + c.w - 1, teeth=False)           # the board runs on behind it
    r = P.LED_A
    # tin lands either side, with the solder fillet catching the light
    for ex in (x, x + 7):
        p.box(ex, y + 2, 2, 5, T[3])
        p.hline(ex, ex + 1, y + 2, T[5]); p.hline(ex, ex + 1, y + 6, T[1])
    p.px(x, y + 2, T[6])
    p.cast(x, y + 2, 9, 5, depth=1, strength=0.45)
    K.lens(p, x + 2, y + 2, 5, 5, r, 1.0 if lit else 0.0, bloom=lit, radius=3.4)
    if lit:
        p.px(x + 4, y + 4, r[5])
        p.px(x + 3, y + 3, r[4]); p.px(x + 5, y + 5, P.lerp(r[3], r[2], 0.4))
    else:
        p.px(x + 3, y + 3, P.lerp(r[1], r[2], 0.45))    # a dull sky reflection
        p.px(x + 4, y + 6, r[0])
    c.a[:, :, 3] = 255
