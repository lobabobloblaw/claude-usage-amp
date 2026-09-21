"""Bulkhead -- the Token Flow window frame (SPEC 3.3, the ``gen`` sheet).

An inspection viewport cut into the same engineering-deck plate as the other
three windows: fluted steel grab-rail across the head, a gasketted legend
window for the title, a chipped safety-orange stile down the left rail, a
graduation scale down the right, a hazard-guarded AUTO pilot lamp, and a
readout slot along the foot that the app's 5x6 face drops straight into.

Tiling discipline (the frame is resizable, unlike the other windows):

* ``GEN_TOP_TILE`` / ``GEN_BOTTOM_TILE`` are laid from window x = 0, so their
  art is sampled in *local* coordinates and every internal pitch is 1 or 5 px
  (both divide the 25 px tile).
* ``GEN_LEFT_TILE`` / ``GEN_RIGHT_TILE`` are laid from window y = 20, so their
  art is periodic with period 29 in ``(y - 20) mod 29`` -- and so is every
  corner piece that has to meet them.
* The six bezel rows 14..19 of the head are x-invariant *constants*, because
  ``GEN_TITLE_PLATE`` is centred and so lands on either of two tile phases
  depending on the window width.  Nothing there may vary along x.
"""

from __future__ import annotations

import numpy as np

import bh_materials as M
import bh_palette as P
import bh_parts as X

TOP = 20                          # title-bar height; the side tiles are laid from here
PX, PY = 25, 29                   # resize steps == tile pitches
CHAN = 14                         # rows 0..13 of the head are the rail channel

# -- the aperture's inner shadow, shared with the terminal windows ------------
SH1 = (3, 2, 1)
SH2 = (6, 4, 1)

# -- x-invariant bezel tones --------------------------------------------------
FACE = P.at(P.GUN_LUT, 0.40)
FACE_HI = P.mixc(FACE, P.HILITE, 0.13)
LIT_EDGE = P.mixc(FACE, P.GUN[7], 0.85)
WALL = P.GUN[0]
GASKET = P.RUBBER[1]
GASKET_LIT = P.RUBBER[4]
WALL_LIT = P.GUN[6]

#: colour by distance (1..4) from the aperture, for each limb of the bezel
TLIMB = (SH2, SH1, GASKET, WALL)          # head: in shadow
LLIMB = (SH2, SH1, GASKET, WALL)          # left rail: in shadow
RLIMB = (GASKET_LIT, WALL_LIT, FACE_HI, FACE)   # right rail: faces the light
BLIMB = (GASKET_LIT, WALL_LIT, FACE_HI)   # foot: faces the light

SLOT_TOP, SLOT_BOT = 4, 9         # rows of the foot the app's 5x6 readouts land on


# ---------------------------------------------------------------------------
# periodic material fields
# ---------------------------------------------------------------------------

def _yphase(c, pad: int = 0):
    """``(X, Yw)`` for a canvas, with Yw periodic on the 29 px side-rail pitch.
    With ``pad`` the grid is extended that many pixels up and left, so
    neighbour-difference relief keeps working across a tile seam."""
    xs = np.arange(-pad, c.w, dtype=np.float32) + c.ox
    ys = np.arange(-pad, c.h, dtype=np.float32) + c.oy
    Xg, Yg = np.meshgrid(xs, ys)
    return Xg, np.mod(Yg - TOP, PY).astype(np.float32)


def side_cast(c, seed: int, base: float = 0.40):
    """Cast gunmetal for the side rails: periodic every 29 px in y."""
    Xg, Yw = _yphase(c)
    g = M.grain(Xg, Yw, seed + 51)
    b = M.vnoise(Xg, Yw, 3.0, PY / 10.0, seed + 52, wrapy=10)
    w = M.fbm(Xg, Yw, 0, seed + 53, octaves=2, sx=9.0, sy=PY / 2.0, wrapy=2)
    return (base + (g - 0.5) * 0.06 + (b - 0.5) * 0.07 + (w - 0.5) * 0.10).astype(np.float32)


def head_cast(c, seed: int, base: float = 0.30):
    """Parkerised channel for the head / foot: periodic every 25 px in x."""
    Xw = np.mod(np.arange(c.w, dtype=np.float32) + c.ox, PX)
    Yg = np.arange(c.h, dtype=np.float32) + c.oy
    Xw, Yg = np.meshgrid(Xw, Yg)
    g = M.grain(Xw, Yg, seed + 61)
    m = M.vnoise(Xw, Yg, PX / 5.0, 1.0, seed + 62, wrapx=5)
    w = M.fbm(Xw, Yg, 0, seed + 63, octaves=2, sx=PX / 2.0, sy=9.0, wrapx=2)
    return (base + (g - 0.5) * 0.045 + (m - 0.5) * 0.07 + (w - 0.5) * 0.12).astype(np.float32)


def paint_band(c, x, y, w, h, seed: int, base: float = 0.42, chip: float = 0.44,
               lut=None, edge_bias: float = 0.30):
    """A coat of paint chipped back to bare steel, periodic every 29 px in y so
    it can run down a repeating rail without seaming."""
    lut = P.ORANGE_LUT if lut is None else lut
    v = c.sub(int(x), int(y), int(w), int(h))
    Xg, Yw = _yphase(v, pad=1)
    n = M.fbm(Xg, Yw, 0, seed + 31, octaves=3, sx=6.5, sy=PY / 6.0, wrapy=6)
    n2 = M.grain(Xg, Yw, seed + 32)
    lx = Xg - (v.ox - 1)                       # 1..w in the padded grid
    d = np.minimum(lx - 1, v.w - lx)
    edge = np.clip(1.0 - d / 2.5, 0, 1)
    painted = (n + edge * edge_bias + (n2 - 0.5) * 0.10) < (1.0 - chip * 0.42)
    mott = M.fbm(Xg, Yw, 0, seed + 33, octaves=2, sx=9.0, sy=PY / 4.0, wrapy=4)
    streak = M.vnoise(Xg, Yw, 1.7, PY / 2.0, seed + 34, wrapy=2)
    t = base + (mott - 0.5) * 0.22 + (streak - 0.5) * 0.13 + (n2 - 0.5) * 0.05
    rgb = M.tone_rgb(t, lut, 36)[1:, 1:]
    hi = M.tone_rgb(np.clip(t + 0.24, 0, 1), lut, 36)[1:, 1:]
    chips = ~painted
    core = painted[1:, 1:]
    cur = v.a[:, :, :3].astype(np.float32)
    bare = chips[1:, 1:]
    lift = np.array(P.STEEL[3], dtype=np.float32)
    cur[bare] = cur[bare] + (lift - cur[bare]) * 0.38
    out = np.where(core[:, :, None], rgb, cur)
    # chip pixel with paint above or left of it: core shadow at the film's edge
    sh = bare & (painted[:-1, 1:] | painted[1:, :-1])
    out[sh] = out[sh] * 0.45 + np.array(P.SHADOW, dtype=np.float32) * 0.55
    lip = core & (chips[:-1, 1:] | chips[1:, :-1])
    out[lip] = hi[lip]
    v.a[:, :, :3] = np.clip(np.rint(out), 0, 255).astype(np.uint8)


def _mitre(c, xs, ys, prof_v, prof_h):
    """Mitre a corner of the aperture.  ``xs`` / ``ys`` list the columns and
    rows of the corner block ordered *outward from the aperture*; the profiles
    give each limb's colour at that distance."""
    for i, yy in enumerate(ys):
        for j, xx in enumerate(xs):
            M.pset(c, xx, yy, prof_v[j] if j <= i else prof_h[i])


def _socket(c, x, y):
    M.stamp(c, x, y, ["dKd", "KkK", "lKl"],
            {"d": (P.SHADOW, 0.6), "K": P.GUN[0], "k": P.GUN[3], "l": (P.HILITE, 0.4)})


# ---------------------------------------------------------------------------
# the frame
# ---------------------------------------------------------------------------

class FieldMixin:

    # -- head ----------------------------------------------------------
    def _head_channel(self, c):
        """Rows 0..13: the parkerised channel the grab-rail is mounted in."""
        s = self.seed + 300
        v = c.sub(0, 0, c.w, CHAN)
        M.put_rgb(v, M.tone_rgb(head_cast(v, s), P.GUN_LUT))
        M.hl(c, 0, c.w - 1, 0, P.GUN[0])
        M.hl(c, 0, c.w - 1, 1, P.GUN[6], 0.7)
        M.hl(c, 0, c.w - 1, 2, P.GUN[4], 0.35)
        M.hl(c, 0, c.w - 1, CHAN - 2, P.GUN[1], 0.8)
        M.hl(c, 0, c.w - 1, CHAN - 1, P.GUN[0])

    def _head_bezel(self, c):
        """Rows 14..19: the lip of the aperture.  Constant along x."""
        M.hl(c, 0, c.w - 1, 14, LIT_EDGE)
        M.hl(c, 0, c.w - 1, 15, FACE_HI)
        for k in range(4):
            M.hl(c, 0, c.w - 1, 16 + k, TLIMB[3 - k])

    def _flutes(self, c, x0, x1):
        """Grip scores milled across the rail: pitch 5, which divides the 25 px
        tile.  Shallow -- the rail must still read as one turned tube."""
        for gx in range(int(np.ceil(x0 / 5.0)) * 5, x1 + 1, 5):
            M.vl(c, gx, 6, 9, P.STEEL[0], 0.30)
            M.pset(c, gx, 10, P.SHADOW, 0.30)
            M.vl(c, gx + 1, 6, 8, P.STEEL[6], 0.12)

    def _rail_post(self, c, x):
        """The machined end post a run of rail dies into (4 px wide)."""
        M.box(c, x, 2, 4, 10, P.GUN[0])
        M.box(c, x + 1, 3, 2, 8, P.STEEL[3])
        M.vl(c, x + 1, 3, 10, P.STEEL[5])
        M.pset(c, x + 1, 3, P.STEEL[6])
        M.pset(c, x + 2, 10, P.STEEL[0])

    def paint_gen_top_tile(self, c):
        c = c.resized_view(origin=(0, 0))          # the app lays this from x = 0
        self._head_channel(c)
        X.rail_tube(c, 0, c.w - 1, 3, 10, True, seed=self.seed + 300,
                    knurl=(), wrap_px=PX)
        self._flutes(c, 0, c.w - 1)
        M.hl(c, 0, c.w - 1, 11, P.SHADOW, 0.55)
        self._head_bezel(c)
        c.a[:, :, 3] = 255

    def paint_gen_top_left(self, c):
        s = self.seed + 300
        self._head_channel(c)
        X.tiny_lamp(c, 3, 5, P.LAMP_AMBER, True)
        self._rail_post(c, 8)
        M.hl(c, 8, c.w - 1, 12, P.SHADOW, 0.5)
        self._head_bezel(c)
        # the left stile comes up through the corner
        v = c.sub(0, 14, 8, 6)
        M.put_rgb(v, M.tone_rgb(side_cast(v, s + 1), P.GUN_LUT))
        paint_band(c, 3, 14, 4, 6, s + 70)
        M.vl(c, 2, 14, 19, P.HILITE, 0.12)
        M.vl(c, 7, 14, 19, P.SHADOW, 0.35)
        M.hl(c, 2, 7, 14, LIT_EDGE, 0.85)
        _mitre(c, (11, 10, 9, 8), (19, 18, 17, 16), LLIMB, TLIMB)
        # window edge
        M.vl(c, 0, 0, c.h - 1, P.GUN[0])
        M.vl(c, 1, 1, c.h - 1, P.GUN[6], 0.6)
        M.pset(c, 1, 1, P.STEEL[5])
        c.a[:, :, 3] = 255

    def paint_gen_top_right(self, c):
        s = self.seed + 300
        self._head_channel(c)
        self._rail_post(c, 0)
        self._head_bezel(c)
        # the right stile comes up through the corner (lit side)
        v = c.sub(0, 14, c.w, 6)
        M.put_rgb(v, M.tone_rgb(side_cast(v, s + 2), P.GUN_LUT))
        M.vl(c, 0, 14, 19, GASKET_LIT)
        M.vl(c, 1, 14, 19, WALL_LIT)
        M.vl(c, 2, 14, 19, FACE_HI)
        M.hl(c, 3, c.w - 3, 14, LIT_EDGE, 0.85)
        _mitre(c, (0, 1, 2, 3), (19, 18, 17, 16), RLIMB, TLIMB)
        # window edge
        M.vl(c, c.w - 2, 1, c.h - 1, P.GUN[1], 0.85)
        M.vl(c, c.w - 1, 0, c.h - 1, P.GUN[0])
        c.a[:, :, 3] = 255

    def paint_gen_title_plate(self, c):
        """100x20.  Nothing is baked in: rows 7..12 are a gasketted legend
        window the app sets the title into, in the skin's own 5x6 face."""
        s = self.seed + 300
        self._head_channel(c)
        X.rail_tube(c, 0, c.w - 1, 3, 10, True, seed=s, knurl=(), wrap_px=PX)
        M.hl(c, 0, c.w - 1, 11, P.SHADOW, 0.55)
        # the fascia panel bolted over the rail, between two end posts
        self._rail_post(c, 0)
        self._rail_post(c, c.w - 4)
        x0, x1 = 4, c.w - 5
        M.box(c, x0, 1, x1 - x0 + 1, 13, P.GUN[0])
        v = c.sub(x0 + 1, 2, x1 - x0 - 1, 11)
        M.put_rgb(v, M.tone_rgb(M.plate_tone(v, seed=s + 44, base=0.38, vgrad=0), P.GUN_LUT))
        M.hl(c, x0 + 1, x1 - 1, 2, P.GUN[6], 0.75)
        M.hl(c, x0 + 2, x1, 13, P.GUN[0], 0.8)
        M.vl(c, x0 + 1, 2, 12, P.GUN[5], 0.45)
        M.vl(c, x1 - 1, 3, 12, P.GUN[1], 0.8)
        M.edge_wear(c, x0 + 1, 2, x1 - x0 - 1, 11, seed=s + 9, amount=0.30, sides="tl")
        # fastener row on the fascia face
        for bx in (x0 + 3, x1 - 4):
            M.pset(c, bx, 3, P.STEEL[5])
            M.pset(c, bx + 1, 3, P.STEEL[2])
            M.pset(c, bx, 4, P.STEEL[2])
            M.pset(c, bx + 1, 4, P.STEEL[0])
        M.hl(c, x0 + 6, x1 - 6, 3, P.GUN[0], 0.35)
        M.hl(c, x0 + 6, x1 - 6, 4, P.GUN[6], 0.25)
        # the legend window: rubber gasket, then the flat well the glyphs sit on
        wx0, wx1 = 6, c.w - 7
        M.box(c, wx0 - 1, 5, wx1 - wx0 + 3, 9, P.RUBBER[2])
        M.hl(c, wx0 - 1, wx1 + 1, 5, P.RUBBER[0])
        M.vl(c, wx0 - 1, 5, 13, P.RUBBER[0])
        M.vl(c, wx1 + 1, 6, 13, P.RUBBER[4])
        # rows 7..12 are the app's title band: flat well colour, nothing baked
        M.box(c, wx0, 6, wx1 - wx0 + 1, 8, self.text_background())
        M.hl(c, wx0, wx1, 6, SH1)
        M.vl(c, wx0, 6, 13, SH1)
        M.vl(c, wx1, 7, 13, SH2)
        self._head_bezel(c)
        c.a[:, :, 3] = 255

    # -- side rails ----------------------------------------------------
    def paint_gen_left_tile(self, c):
        s = self.seed + 300
        M.put_rgb(c, M.tone_rgb(side_cast(c, s + 1), P.GUN_LUT))
        paint_band(c, 3, 0, 4, c.h, s + 70)
        M.vl(c, 0, 0, c.h - 1, P.GUN[0])
        M.vl(c, 1, 0, c.h - 1, P.GUN[6], 0.6)
        M.vl(c, 2, 0, c.h - 1, P.HILITE, 0.12)
        M.vl(c, 7, 0, c.h - 1, P.SHADOW, 0.35)
        for k in range(4):
            M.vl(c, 11 - k, 0, c.h - 1, LLIMB[k])
        _socket(c, 3, 11)
        M.oil_streak(c, 4, 14, 8, seed=31, a0=0.45, wobble=False)
        c.a[:, :, 3] = 255

    def paint_gen_right_tile(self, c):
        s = self.seed + 300
        M.put_rgb(c, M.tone_rgb(side_cast(c, s + 2), P.GUN_LUT))
        for k in range(4):
            M.vl(c, k, 0, c.h - 1, RLIMB[k])
        M.vl(c, 5, 0, c.h - 1, P.SHADOW, 0.30)
        M.vl(c, c.w - 2, 0, c.h - 1, P.GUN[1], 0.85)
        M.vl(c, c.w - 1, 0, c.h - 1, P.GUN[0])
        # graduation scale: one long mark per module, four short
        for k, y in enumerate((1, 7, 13, 19, 25)):
            M.hl(c, 6, 7 if k else 9, y, P.LEGEND[2], 0.62)
            M.pset(c, 6, y + 1, P.SHADOW, 0.30)
        _socket(c, 7, 21)
        c.a[:, :, 3] = 255

    # -- foot ----------------------------------------------------------
    def _foot_base(self, c):
        """The status fascia: a lit lip under the aperture, then the readout
        slot the app's two 5x6 lines land in, then the bottom edge."""
        s = self.seed + 300
        v = c.sub(0, 0, c.w, c.h)
        M.put_rgb(v, M.tone_rgb(head_cast(v, s + 3, base=0.36), P.GUN_LUT))
        for k in range(3):
            M.hl(c, 0, c.w - 1, k, BLIMB[k])
        # rows 4..9 are the flat well the app's 5x6 cells drop into -- nothing
        # may vary inside it, or the glyph cells would read as pasted patches
        M.hl(c, 0, c.w - 1, 3, P.SHADOW, 0.85)
        M.box(c, 0, SLOT_TOP, c.w, SLOT_BOT - SLOT_TOP + 1, self.text_background())
        M.hl(c, 0, c.w - 1, 10, P.GUN[5], 0.55)
        M.hl(c, 0, c.w - 1, 11, P.GUN[3], 0.35)
        M.hl(c, 0, c.w - 1, c.h - 2, P.GUN[1], 0.85)
        M.hl(c, 0, c.w - 1, c.h - 1, P.GUN[0])

    def paint_gen_bottom_tile(self, c):
        c = c.resized_view(origin=(0, c.oy))       # the app lays this from x = 0
        self._foot_base(c)
        c.a[:, :, 3] = 255

    def paint_gen_bottom_left(self, c):
        s = self.seed + 300
        self._foot_base(c)
        # the left stile dies into the foot
        v = c.sub(0, 0, 8, 3)
        M.put_rgb(v, M.tone_rgb(side_cast(v, s + 1), P.GUN_LUT))
        paint_band(c, 3, 0, 4, 3, s + 70)
        M.vl(c, 2, 0, 2, P.HILITE, 0.12)
        M.vl(c, 7, 0, 2, P.SHADOW, 0.35)
        # the stile's wall and gasket turn the corner into the sill's lit lip
        M.pset(c, 8, 0, WALL)
        M.pset(c, 9, 0, GASKET)
        M.pset(c, 10, 0, GASKET_LIT)
        M.pset(c, 11, 0, GASKET_LIT)
        M.pset(c, 9, 1, WALL_LIT)
        M.pset(c, 8, 1, P.GUN[2])
        # the slot stops short of the window edge
        M.vl(c, 2, 3, 10, P.SHADOW, 0.8)
        M.vl(c, 3, SLOT_TOP, SLOT_BOT, SH2)
        # the painted stile picks up again below the slot and runs to the sill
        paint_band(c, 3, 11, 5, 2, s + 71, base=0.42, chip=0.55)
        # window edge
        M.vl(c, 0, 0, c.h - 1, P.GUN[0])
        M.vl(c, 1, 0, c.h - 2, P.GUN[6], 0.6)
        M.vl(c, 2, 11, c.h - 2, P.HILITE, 0.12)
        M.hl(c, 0, c.w - 1, c.h - 1, P.GUN[0])
        M.oil_streak(c, 5, 11, 3, seed=33, a0=0.4, wobble=False)
        c.a[:, :, 3] = 255

    def paint_gen_bottom_right(self, c):
        s = self.seed + 300
        self._foot_base(c)
        # the right stile dies into the foot (both limbs are lit here)
        v = c.sub(0, 0, c.w, 3)
        M.put_rgb(v, M.tone_rgb(side_cast(v, s + 2), P.GUN_LUT))
        for k in range(3):
            M.hl(c, 0, c.w - 1, k, BLIMB[k])
        for k in range(3):
            M.vl(c, k, 0, 2, RLIMB[k])
        # the slot stops short of the window edge
        M.vl(c, c.w - 3, 3, 10, P.SHADOW, 0.8)
        M.vl(c, c.w - 4, SLOT_TOP, SLOT_BOT, SH2)
        M.vl(c, c.w - 2, 0, c.h - 2, P.GUN[1], 0.85)
        M.vl(c, c.w - 1, 0, c.h - 1, P.GUN[0])
        M.hl(c, 0, c.w - 1, c.h - 1, P.GUN[0])
        # resize grip: a machined pad with three diagonal ribs
        gx, gy, gw, gh = 1, 10, 9, 3
        M.steel(c, gx, gy, gw, gh, seed=s + 12, base=0.48, strength=0.7)
        M.hl(c, gx, gx + gw - 1, gy, P.STEEL[5], 0.55)
        M.vl(c, gx, gy, gy + gh - 1, P.STEEL[5], 0.40)
        M.hl(c, gx, gx + gw - 1, gy + gh - 1, P.STEEL[0], 0.85)
        for k in range(3):
            bx = gx + 7 - k * 3
            for j in range(3):
                M.pset(c, bx - j, gy + j, P.GUN[0])
                M.pset(c, bx - j + 1, gy + j, P.STEEL[6], 0.55)
        c.a[:, :, 3] = 255

    # -- furniture -----------------------------------------------------
    def paint_gen_close(self, c, pressed):
        X.mini_key(c, "close", pressed)

    def paint_gen_lamp(self, c, lit):
        """9x9 -- the AUTO lamp: the field choosing its own configuration is
        the guarded state, so the lamp wears the hazard surround the eject key
        does.  Its bottom row continues the aperture's lit lip."""
        s = self.seed + 300
        M.box(c, 0, 0, c.w, c.h, P.GUN[0])
        M.steel(c, 0, 0, 9, 8, seed=s + 5, base=0.40)
        M.hazard(c, 0, 0, 9, 8, width=2, seed=s + 3, chip=0.32)
        M.hl(c, 0, 7, 0, P.HILITE, 0.30)
        M.vl(c, 0, 1, 6, P.HILITE, 0.22)
        M.hl(c, 1, 8, 7, P.SHADOW, 0.50)
        M.vl(c, 8, 1, 7, P.SHADOW, 0.40)
        X.pilot_lamp(c, 3, 3, 3, 3, P.LAMP_AMBER, lit, cage="v", spill=2,
                     spill_strength=0.55)
        M.hl(c, 0, c.w - 1, 8, LIT_EDGE)
        c.a[:, :, 3] = 255
