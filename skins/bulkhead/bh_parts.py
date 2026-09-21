"""Bulkhead -- hardware parts shared by the three windows.

Frames, CRT glass, the grab-rail title strip, keycaps, steel toggles with
caged pilot lamps, LED ladders, knobs, label plates, louvres, conduit.
All light is top-left.
"""

from __future__ import annotations

import numpy as np

import bh_digits as D
import bh_materials as M
import bh_palette as P
import bh_type as T

# ---------------------------------------------------------------------------
# window frame
# ---------------------------------------------------------------------------


def window_frame(c, top: bool = True):
    """Outer edge of a rack module: black silhouette line, lit inner edge on
    top/left, shadowed inner edge bottom/right, worn bright at the corners."""
    w, h = c.w, c.h
    M.outline(c, 0, 0, w, h, P.GUN[0])
    M.hl(c, 1, w - 2, 1, P.GUN[6], 0.75)
    M.vl(c, 1, 2, h - 2, P.GUN[6], 0.6)
    M.hl(c, 1, w - 2, h - 2, P.GUN[1], 0.85)
    M.vl(c, w - 2, 2, h - 3, P.GUN[1], 0.8)
    M.pset(c, 1, 1, P.STEEL[5])
    M.pset(c, w - 2, 1, P.GUN[4])
    M.pset(c, 1, h - 2, P.GUN[4])
    M.edge_wear(c, 1, 1, w - 2, h - 2, seed=c.w + (7 if c.window == "eq" else 3), amount=0.4,
                sides="tl")


# ---------------------------------------------------------------------------
# CRT glass
# ---------------------------------------------------------------------------

def glass_rows(c, x, y, w, h):
    """Raster-lined amber-black glass, keyed to window rows."""
    for j in range(h):
        M.box(c, x, y + j, w, 1, D.glass_row(c.oy + y + j))


def crt_glass(c, x, y, w, h, r: int = 3, gasket: int = 1, vignette: float = 1.0,
              depth: int = 3, lip_bottom: bool = True):
    """A tube face behind a rubber gasket.  (x, y, w, h) is the glass itself.
    ``lip_bottom=False`` leaves the casting bare under the gasket (room for a
    legend there).  Returns the canvas-sized bool mask of the glass."""
    gx, gy, gw, gh = x - gasket, y - gasket, w + 2 * gasket, h + 2 * gasket
    # the gasket: rubber ring; its top/left limbs sit in shadow, bottom/right catch light
    gm = M.full_mask(c, gx, gy, gw, gh, r=min(4, r + 1))
    glass = M.full_mask(c, x, y, w, h, r=r)
    # the wall of the aperture, one pixel outside the gasket: the top/left wall
    # is in its own shadow, the bottom/right wall faces the light
    M.sink_mask(c, gm, depth=0, a_sh=0.0, a_lip=0.55, lip_bottom=lip_bottom)
    ring = gm & ~glass
    M.fill_mask(c, ring, P.RUBBER[2])
    yy, xx = np.mgrid[0:c.h, 0:c.w]
    tl = ring & ((yy < y + 2) | (xx < x + 2))
    br = ring & ((yy >= y + h - 1) | (xx >= x + w - 1)) & ~tl
    M.fill_mask(c, tl, P.RUBBER[0])
    M.fill_mask(c, br, P.RUBBER[4])
    # rubber stipple on the lit limb
    g = M.grain(*M.grid(c), 97)
    M.fill_mask(c, br & (g > 0.72), P.RUBBER[5])
    # glass
    v = np.zeros((c.h, c.w, 3), dtype=np.float32)
    for j in range(c.h):
        v[j, :, :] = D.glass_row(c.oy + j)
    M.put_rgb(c, v, mask=glass.astype(np.float32))
    # vignette toward green-black at the rim, deepest in the corners
    fx_ = (xx - (x + (w - 1) / 2.0)) / (w / 2.0)
    fy_ = (yy - (y + (h - 1) / 2.0)) / (h / 2.0)
    d = np.clip(np.maximum(np.abs(fx_) ** 6, np.abs(fy_) ** 3) + 0.5 * (np.abs(fx_) ** 4) * (np.abs(fy_) ** 2), 0, 1)
    M.blend_mask(c, (d * 0.55 * vignette) * glass, P.GLASS_GREEN)
    # a faint warm lift in the middle of the tube (phosphor never quite black)
    M.blend_mask(c, (np.clip(1.0 - d * 3.0, 0, 1) * 0.10) * glass, P.AMBER_GHOST)
    # the glass sits well below the bezel: deep inner shadow from top/left
    M.sink_mask(c, glass, depth=depth, a_sh=0.62, a_lip=0.0)
    return glass


def glare(c, glass_mask, keep_out, strength: float = 0.12, offset: float = 0.0, slope: float = 0.55,
          width: float = 9.0, second: bool = True, col=None):
    """Curved-glass glare: a diagonal streak sampled in window space, painted
    only where ``keep_out`` (dynamic wells) is False."""
    col = (255, 240, 214) if col is None else col
    X, Y = M.grid(c)
    t = X + Y / slope - offset
    a = np.clip(1.0 - np.abs(t) / width, 0, 1) ** 1.5 * strength
    if second:
        t2 = t - width * 2.3
        a = np.maximum(a, np.clip(1.0 - np.abs(t2) / (width * 0.35), 0, 1) * strength * 0.6)
    a = a * glass_mask * (~keep_out)
    # quantise so the streak is a few clean steps, not a smear
    a = np.rint(a * 24) / 24
    M.blend_mask(c, a.astype(np.float32), col)


# ---------------------------------------------------------------------------
# pilot lamps
# ---------------------------------------------------------------------------

def pilot_lamp(c, x, y, w, h, ramp, on: bool, cage: str = "v", spill: int = 2,
               spill_strength: float = 0.4):
    """Caged pilot lamp.  Lens (x, y, w, h) sits in a dark socket one pixel
    bigger; cage bars cross the lens; lit lenses bloom onto the surround."""
    if on and spill:
        M.bloom(c, x - 1, y - 1, w + 2, h + 2, ramp[4], radius=spill, strength=spill_strength)
    M.box(c, x - 1, y - 1, w + 2, h + 2, P.GUN[0])
    M.hl(c, x - 1, x + w, y + h, P.GUN[5], 0.55)          # socket lip, lit below/right
    M.vl(c, x + w, y - 1, y + h, P.GUN[5], 0.45)
    if on:
        M.box(c, x, y, w, h, ramp[4])
        M.box(c, x, y, w, 1, ramp[5])
        M.box(c, x, y + h - 1, w, 1, ramp[3])
        # hot core, off-centre toward the light
        M.box(c, x + max(0, (w - 2) // 2), y + max(0, (h - 2) // 2), min(2, w), min(2, h), ramp[6])
        M.pset(c, x + max(0, (w - 2) // 2), y + max(0, (h - 2) // 2), (255, 255, 255))
    else:
        M.box(c, x, y, w, h, ramp[1])
        M.box(c, x, y, w, 1, ramp[2])
        M.box(c, x, y + h - 1, w, 1, ramp[0])
        M.pset(c, x, y, ramp[3], 0.8)                       # dead glint on the lens
    bar = P.GUN[1] if not on else P.mixc(P.GUN[0], ramp[2], 0.35)
    if cage == "v":
        for i in range(1, w - 1, 2):
            M.vl(c, x + i, y, y + h - 1, bar, 0.85)
    elif cage == "h":
        for j in range(1, h - 1, 2):
            M.hl(c, x, x + w - 1, y + j, bar, 0.85)


def tiny_lamp(c, x, y, ramp, on: bool, size: int = 3):
    """3x3 (or 4x4) jewel lamp in a socket, for the title rail ends."""
    s = size
    if on:
        M.bloom(c, x, y, s, s, ramp[4], radius=2, strength=0.5)
    M.box(c, x - 1, y - 1, s + 2, s + 2, P.GUN[0])
    M.hl(c, x - 1, x + s, y + s, P.GUN[5], 0.6)
    M.vl(c, x + s, y - 1, y + s - 1, P.GUN[5], 0.45)
    if on:
        M.box(c, x, y, s, s, ramp[4])
        M.box(c, x, y, s - 1, s - 1, ramp[5])
        M.pset(c, x, y, ramp[6])
        M.pset(c, x + s - 1, y + s - 1, ramp[3])
    else:
        M.box(c, x, y, s, s, ramp[1])
        M.pset(c, x, y, ramp[2])
        M.pset(c, x + s - 1, y + s - 1, ramp[0])


# ---------------------------------------------------------------------------
# steel toggles
# ---------------------------------------------------------------------------

def steel_face(c, x, y, w, h, pressed: bool, seed: int = 0, base: float = 0.40):
    """A machined steel button body filling (x, y, w, h), with a black seam
    around it.  Pressed: sunk, bevel inverted, darker, no contact shadow."""
    M.box(c, x, y, w, h, P.GUN[0])
    ix, iy, iw, ih = x + 1, y + 1, w - 2, h - 2
    M.steel(c, ix, iy, iw, ih, seed=seed, base=base - (0.10 if pressed else 0.0), strength=0.8)
    if not pressed:
        M.hl(c, ix, ix + iw - 2, iy, P.STEEL[5], 0.85)
        M.vl(c, ix, iy + 1, iy + ih - 2, P.STEEL[5], 0.6)
        M.hl(c, ix + 1, ix + iw - 1, iy + ih - 1, P.STEEL[0], 0.9)
        M.vl(c, ix + iw - 1, iy + 1, iy + ih - 2, P.STEEL[0], 0.75)
        M.hl(c, ix + 1, ix + iw - 2, iy + ih - 2, P.STEEL[1], 0.45)
        M.pset(c, ix, iy, P.STEEL[6])
    else:
        M.hl(c, ix, ix + iw - 1, iy, P.SHADOW, 0.85)
        M.hl(c, ix, ix + iw - 1, iy + 1, P.SHADOW, 0.45)
        M.vl(c, ix, iy + 1, iy + ih - 1, P.SHADOW, 0.75)
        M.vl(c, ix + 1, iy + 2, iy + ih - 1, P.SHADOW, 0.3)
        M.hl(c, ix + 1, ix + iw - 1, iy + ih - 1, P.STEEL[3], 0.6)
        M.vl(c, ix + iw - 1, iy + 1, iy + ih - 2, P.STEEL[3], 0.5)


def toggle(c, pressed: bool, selected: bool, text: str, ramp, face=None, lamp_w: int = 4,
           seed: int = 0, arrow: bool = False):
    """Rectangular steel toggle with a caged pilot lamp at the left and an
    engraved, paint-filled legend."""
    face = T.LEGEND if face is None else face
    w, h = c.w, c.h
    steel_face(c, 0, 0, w, h, pressed, seed=seed)
    d = 1 if pressed else 0
    lh = h - 6
    lx, ly = 3 + d, 3 + d
    tw = face.width(text)
    free = w - (lx + lamp_w + 2) - 2
    tx = lx + lamp_w + 2 + max(0, (free - tw - (6 if arrow else 0)) // 2) + (1 if free - tw > 3 else 0)
    ty = (h - face.h) // 2 + d
    if lamp_w:
        pilot_lamp(c, lx, ly, lamp_w, lh, ramp, selected, cage="v", spill=2,
                   spill_strength=0.42)
    else:
        tx = (w - tw - (6 if arrow else 0)) // 2 + d
    ink = P.LEGEND[4] if selected else P.LEGEND[3]
    if pressed:
        ink = P.LEGEND[4]
    T.engraved(c, tx, ty, text, face, ink, depth=0.6, lip=0.25)
    if arrow:
        ax = tx + tw + 3
        ay = ty + 1
        for k in range(3):
            M.hl(c, ax + k, ax + 4 - k, ay + k, ink)
        M.hl(c, ax - 0, ax + 4, ay - 1, P.SHADOW, 0.5)
    # wear: a polished thumb-spot in the middle, scuffed corners
    if not pressed:
        M.pset(c, w - 3, 2, P.STEEL[5], 0.5)
        M.pset(c, 2, h - 3, P.STEEL[1], 0.5)


# ---------------------------------------------------------------------------
# transport keycaps
# ---------------------------------------------------------------------------

def _icon_mask(which: str) -> np.ndarray:
    """9 px tall transport pictograms (bool masks)."""
    rows = {
        "previous": ["##....#...#",
                     "##...##..##",
                     "##..###.###",
                     "##.########",
                     "###########",
                     "##.########",
                     "##..###.###",
                     "##...##..##",
                     "##....#...#"],
        "play": ["##.......",
                 "####.....",
                 "######...",
                 "########.",
                 "#########",
                 "########.",
                 "######...",
                 "####.....",
                 "##......."],
        "pause": ["###..###",
                  "###..###",
                  "###..###",
                  "###..###",
                  "###..###",
                  "###..###",
                  "###..###",
                  "###..###",
                  "###..###"],
        "stop": ["#########",
                 "#########",
                 "#########",
                 "#########",
                 "#########",
                 "#########",
                 "#########",
                 "#########",
                 "#########"][:8],
        "eject": ["....#....",
                  "...###...",
                  "..#####..",
                  ".#######.",
                  "#########",
                  ".........",
                  "#########",
                  "#########"],
    }
    if which == "next":
        r = [row[::-1] for row in rows["previous"]]
    else:
        r = rows[which]
    return np.array([[ch == "#" for ch in row] for row in r], dtype=bool)


def keycap(c, which: str, pressed: bool, seed: int = 0, guard: bool = False):
    """Heavy rubberised keycap in a steel surround.  The sprite's outer ring is
    the surround (shared seams with its neighbours); the cap floats inside it
    and sinks +1,+1 when pressed."""
    w, h = c.w, c.h
    # surround: steel frame, or hazard-painted guard for the eject key
    M.box(c, 0, 0, w, h, P.GUN[0])
    if guard:
        M.steel(c, 1, 1, w - 2, h - 2, seed=seed + 5, base=0.38)
        M.hazard(c, 1, 1, w - 2, h - 2, width=3, seed=seed + 3, chip=0.30)
        M.hl(c, 1, w - 2, 1, P.HILITE, 0.35)
        M.vl(c, 1, 2, h - 2, P.HILITE, 0.25)
        M.hl(c, 1, w - 2, h - 2, P.SHADOW, 0.5)
        M.vl(c, w - 2, 1, h - 2, P.SHADOW, 0.4)
        inset = 3
    else:
        M.steel(c, 1, 1, w - 2, h - 2, seed=seed + 5, base=0.47, strength=0.7)
        M.hl(c, 1, w - 2, 1, P.STEEL[5], 0.8)
        M.vl(c, 1, 2, h - 2, P.STEEL[5], 0.55)
        M.hl(c, 1, w - 2, h - 2, P.STEEL[0], 0.9)
        M.vl(c, w - 2, 2, h - 2, P.STEEL[0], 0.7)
        inset = 2
    # the pocket the cap sits in
    px, py, pw, ph = inset, inset, w - 2 * inset, h - 2 * inset
    M.box(c, px, py, pw, ph, P.RUBBER[0])
    d = 1 if pressed else 0
    # cap: when up it covers the pocket except a 1px shadow gap bottom/right;
    # when pressed it slides down-right and the gap opens on the top/left
    cx, cy, cw, ch = px + d, py + d, pw - 1, ph - 1
    cap = M.round_mask(cw, ch, 1)
    sub = c.sub(cx, cy, cw, ch)
    X, Y = M.grid(sub)
    g = M.grain(X, Y, seed + 21)
    b = M.vnoise(X, Y, 4.0, 4.0, seed + 22)
    yy, xx = np.mgrid[0:ch, 0:cw].astype(np.float32)
    # worn, polished patch in the middle of the cap where thumbs land
    r2 = ((xx - cw / 2.0) / (cw * 0.42)) ** 2 + ((yy - ch / 2.0) / (ch * 0.5)) ** 2
    polish = np.clip(1.0 - r2, 0, 1)
    t = 0.50 + (g - 0.5) * 0.10 * (1 - polish * 0.7) + (b - 0.5) * 0.07 + polish * 0.13
    if pressed:
        t = t - 0.10
    rgb = M.tone_rgb(t, P.RUBBER_LUT, 32)
    M.put_rgb(sub, rgb, mask=cap.astype(np.float32))
    # cap relief
    if not pressed:
        M.hl(c, cx + 1, cx + cw - 2, cy, P.RUBBER[5], 0.9)
        M.vl(c, cx, cy + 1, cy + ch - 2, P.RUBBER[5], 0.65)
        M.hl(c, cx + 1, cx + cw - 2, cy + ch - 1, P.RUBBER[1], 0.9)
        M.vl(c, cx + cw - 1, cy + 1, cy + ch - 2, P.RUBBER[1], 0.8)
        M.pset(c, cx + 1, cy + 1, P.GUN[6], 0.55)        # sheen glint
    else:
        M.hl(c, cx + 1, cx + cw - 2, cy, P.RUBBER[3], 0.8)
        M.vl(c, cx, cy + 1, cy + ch - 2, P.RUBBER[3], 0.6)
        M.hl(c, px, px + pw - 1, py, P.SHADOW, 1.0)       # deep gap top/left
        M.vl(c, px, py, py + ph - 1, P.SHADOW, 1.0)
    # pictogram: engraved and paint-filled
    m = _icon_mask(which)
    ih, iw = m.shape
    ix = cx + (cw - iw) // 2 + (1 if which == "play" else 0)
    iy = cy + (ch - ih) // 2
    paint = P.ORANGE[5] if which == "play" else P.LEGEND[3]
    if pressed:
        paint = P.ORANGE[6] if which == "play" else P.LEGEND[4]
    pad = np.zeros((ih + 2, iw + 2), dtype=bool)
    pad[1:-1, 1:-1] = m
    cut = np.zeros_like(pad)
    cut[:-1, :-1] |= pad[1:, 1:]
    cut &= ~pad
    lipm = np.zeros_like(pad)
    lipm[1:, 1:] |= pad[:-1, :-1]
    lipm &= ~pad & ~cut
    M.blend_mask(c, cut.astype(np.float32) * 0.75, P.RUBBER[0], ix - 1, iy - 1)
    M.blend_mask(c, lipm.astype(np.float32) * 0.35, P.RUBBER[5], ix - 1, iy - 1)
    if pressed:
        glowm = np.zeros((ih + 4, iw + 4), dtype=np.float32)
        glowm[2:-2, 2:-2] = m
        k = glowm.copy()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            k = np.maximum(k, np.roll(np.roll(glowm, dx, 1), dy, 0) * 0.5)
        k[2:-2, 2:-2][m] = 0
        M.blend_mask(c, k * 0.45, paint, ix - 2, iy - 2)
    # paint fill, worn thinner toward the polished centre
    sub2 = c.sub(max(0, ix), max(0, iy), iw, ih)
    X2, Y2 = M.grid(sub2)
    wear = M.grain(X2, Y2, seed + 31)
    edge = m & ~(np.roll(m, 1, 0) & np.roll(m, -1, 0) & np.roll(m, 1, 1) & np.roll(m, -1, 1))
    a = np.where((wear > 0.80) & edge, 0.55, 1.0) if not pressed else np.ones_like(wear)
    M.blend_mask(c, m.astype(np.float32) * a, paint, ix, iy)
    # top row of the paint catches a little more light
    topm = m & ~np.vstack([np.zeros((1, iw), dtype=bool), m[:-1]])
    M.blend_mask(c, topm.astype(np.float32) * 0.35, (255, 255, 255), ix, iy)


# ---------------------------------------------------------------------------
# LED ladders (volume / balance) and knobs
# ---------------------------------------------------------------------------

def ladder_colour(f: float):
    """Ramp family for a segment at fraction f along the ladder."""
    if f < 0.56:
        return P.GREEN
    if f < 0.80:
        return P.LAMP_AMBER
    return P.RED


def led_ladder(c, i: int, n_frames: int = 28, seed: int = 0):
    """Horizontal segmented LED ladder behind smoked glass with a silk-screened
    ruler under it.  Frame ``i`` lights segments left -> right; the leading
    segment comes up in three steps so all 28 frames are distinct.

    The knob rides rows 1..11 of the frame across the whole width, so nothing
    that must stay readable (the SESSION / WEEK legend) can live in here: the
    legends are stencilled on the casting lip above the ladders instead
    (``bh_main._paint_gauge_bay``)."""
    w, h = c.w, c.h
    # recess for the smoked window: rows 1..6.  Row 0 stays casting (the
    # knob never reaches it), a clear row between the window and the legend.
    M.box(c, 0, 1, w, 6, P.GUN[0])
    M.box(c, 1, 2, w - 2, 4, (9, 10, 11))
    M.hl(c, 0, w - 1, 1, P.SHADOW, 0.9)
    M.hl(c, 1, w - 2, 6, P.GUN[5], 0.75)               # lit lower lip
    M.vl(c, w - 1, 2, 6, P.GUN[5], 0.5)
    M.vl(c, 0, 1, 6, P.SHADOW, 0.85)
    nseg = (w - 4) // 3
    x0 = 2 + ((w - 4) - nseg * 3 + 1) // 2
    level = i / (n_frames - 1) * nseg
    last_lit = -1
    for k in range(nseg):
        f = k / max(1, nseg - 1)
        ramp = ladder_colour(f)
        sx = x0 + k * 3
        frac = level - k
        if frac >= 5.0 / 6.0:
            part = 3
        elif frac >= 0.5:
            part = 2
        elif frac >= 1.0 / 6.0:
            part = 1
        else:
            part = 0
        if part == 3:
            last_lit = k
            M.box(c, sx, 2, 2, 4, ramp[4])
            M.box(c, sx, 2, 2, 1, ramp[5])
            M.box(c, sx, 3, 1, 1, ramp[6])
            M.box(c, sx, 5, 2, 1, ramp[3])
            # bloom into the gap and onto the glass above/below
            M.box(c, sx + 2, 2, 1, 4, ramp[2], 0.75)
            M.box(c, sx, 1, 2, 1, ramp[3], 0.55)
            M.box(c, sx + 2, 1, 1, 1, ramp[2], 0.35)
        elif part == 2:
            M.box(c, sx, 2, 2, 4, ramp[3])
            M.box(c, sx, 2, 2, 1, ramp[4])
            M.box(c, sx, 5, 2, 1, ramp[2])
            M.box(c, sx, 1, 2, 1, ramp[2], 0.4)
        elif part == 1:
            M.box(c, sx, 2, 2, 4, ramp[2])
            M.box(c, sx, 2, 2, 1, ramp[3], 0.7)
            M.box(c, sx, 5, 2, 1, ramp[1])
        else:
            M.box(c, sx, 2, 2, 4, ramp[1])
            M.box(c, sx, 2, 2, 1, ramp[2], 0.55)
            M.box(c, sx, 5, 2, 1, ramp[0])
    if last_lit >= 0:
        ramp = ladder_colour(last_lit / max(1, nseg - 1))
        M.hl(c, x0, x0 + (last_lit + 1) * 3 - 2, 6, ramp[3], 0.25)   # glow on the lip
    # smoked-glass reflection: a thin cool glint along the top of the window
    M.hl(c, 2, w // 3, 1, (150, 170, 180), 0.10)
    # ruler strip: a tick under every segment gap, a long tick every fifth,
    # inked in the zone colour of the segments above it
    for k in range(nseg + 1):
        tx = x0 + k * 3 - 1
        if tx > w - 2:
            break
        f = k / max(1, nseg)
        col = P.LEGEND[2] if f < 0.56 else (P.LAMP_AMBER[4] if f < 0.8 else P.RED[4])
        M.pset(c, tx, 8, col, 0.85)
        if k % 5 == 0:
            M.pset(c, tx, 9, col, 0.85)
            M.pset(c, tx, 10, col, 0.6)


def knob(c, pressed: bool, seed: int = 0, vertical: bool = False):
    """Small knurled steel slider knob (opaque sprite): dark machined body,
    grooved grips either side of a paint-filled index.  Pressed: index lit."""
    w, h = c.w, c.h
    M.box(c, 0, 0, w, h, P.GUN[0])
    bw, bh = w - 1, h - 1                     # last row / column = its shadow on the panel
    M.box(c, 0, h - 1, w, 1, P.SHADOW)
    M.box(c, w - 1, 0, 1, h, P.SHADOW)
    M.pset(c, 0, h - 1, P.GUN[1])
    M.pset(c, w - 1, 0, P.GUN[1])
    d = 1 if pressed else 0
    ramp = [P.STEEL[5 - d], P.STEEL[4 - d], P.STEEL[3 - d], P.STEEL[3 - d], P.STEEL[2 - d],
            P.STEEL[2 - d], P.STEEL[1]]
    if not vertical:
        n = bh - 2
        for j in range(n):
            col = ramp[min(len(ramp) - 1, int(j * len(ramp) / n))]
            M.hl(c, 1, bw - 2, 1 + j, col)
        M.hl(c, 1, bw - 2, bh - 1, P.STEEL[0])
        M.vl(c, 1, 1, bh - 2, P.STEEL[5 - d], 0.75)
        M.vl(c, bw - 2, 1, bh - 1, P.STEEL[0], 0.85)
        M.pset(c, 1, 1, P.STEEL[6])
        cx = (bw - 1) // 2
        for gx in (cx - 5, cx - 3, cx + 4, cx + 6):
            if 2 <= gx <= bw - 3:
                M.vl(c, gx, 2, bh - 2, P.GUN[0], 0.8)
                M.vl(c, gx + 1, 2, bh - 3, P.STEEL[5], 0.35)
        # index: a slot with a paint-filled line
        M.box(c, cx - 1, 1, 4, bh - 1, P.GUN[0])
        idx = (P.ORANGE[4], P.ORANGE[3]) if not pressed else (P.ORANGE[6], P.ORANGE[5])
        M.vl(c, cx, 2, bh - 2, idx[0])
        M.vl(c, cx + 1, 2, bh - 2, idx[1])
        if pressed:
            M.pset(c, cx, 3, (255, 246, 226))
            M.vl(c, cx - 1, 2, bh - 2, P.ORANGE[4], 0.55)
            M.vl(c, cx + 2, 2, bh - 2, P.ORANGE[4], 0.55)
            M.vl(c, cx - 2, 2, bh - 2, P.ORANGE[4], 0.22)
            M.vl(c, cx + 3, 2, bh - 2, P.ORANGE[4], 0.22)
    else:
        # lit from the top-left: left face bright, a vertical-grooved barrel
        n = bw - 2
        for i in range(n):
            col = ramp[min(len(ramp) - 1, int(i * len(ramp) / n))]
            M.vl(c, 1 + i, 1, bh - 2, col)
        M.vl(c, bw - 2, 1, bh - 1, P.STEEL[0])
        M.hl(c, 1, bw - 2, 1, P.STEEL[5 - d], 0.8)
        M.hl(c, 1, bw - 2, bh - 1, P.STEEL[0], 0.85)
        M.pset(c, 1, 1, P.STEEL[6])
        cy = (bh - 1) // 2
        k = 2
        while cy - 1 - k >= 2:
            M.hl(c, 2, bw - 3, cy - 1 - k, P.GUN[0], 0.8)
            M.hl(c, 2, bw - 4, cy - k, P.STEEL[5], 0.25)
            M.hl(c, 2, bw - 3, cy + 2 + k, P.GUN[0], 0.8)
            k += 2
        M.box(c, 1, cy - 1, bw - 1, 4, P.GUN[0])
        idx = (P.ORANGE[4], P.ORANGE[3]) if not pressed else (P.ORANGE[6], P.ORANGE[5])
        M.hl(c, 2, bw - 2, cy, idx[0])
        M.hl(c, 2, bw - 2, cy + 1, idx[1])
        if pressed:
            M.pset(c, 3, cy, (255, 246, 226))
            M.hl(c, 2, bw - 2, cy - 1, P.ORANGE[4], 0.55)
            M.hl(c, 2, bw - 2, cy + 2, P.ORANGE[4], 0.55)
            M.hl(c, 2, bw - 2, cy - 2, P.ORANGE[4], 0.22)
            M.hl(c, 2, bw - 2, cy + 3, P.ORANGE[4], 0.22)
    c.a[:, :, 3] = 255


# ---------------------------------------------------------------------------
# grab-rail title strip
# ---------------------------------------------------------------------------

def rail_tube(c, x0: int, x1: int, y0: int = 3, y1: int = 10, active: bool = True, seed: int = 0,
              knurl=((0.0, 1.0),), wrap_px: int | None = None):
    """A horizontal steel grab-rail from x0..x1 (inclusive), rows y0..y1, with
    knurled grip sections.  ``knurl`` = fractional (start, end) spans."""
    n = y1 - y0 + 1
    prof = np.array([0.30, 0.80, 0.92, 0.74, 0.60, 0.48, 0.36, 0.26, 0.20, 0.30, 0.22, 0.18])
    idx = np.clip(np.rint(np.linspace(0, 8, n)).astype(int), 0, 8)
    tones = prof[idx]
    tones[-1] = 0.30 if n > 3 else tones[-1]            # reflected light under the tube
    if n > 4:
        tones[-2] = 0.17
    if not active:
        tones = tones * 0.80
    w = x1 - x0 + 1
    sub = c.sub(x0, y0, w, n)
    X, Y = M.grid(sub)
    if wrap_px:
        Xn = np.mod(X, wrap_px)
        streak = M.vnoise(Xn, Y, wrap_px / 2.0, 1.0, seed + 61, wrapx=2)
    else:
        streak = M.vnoise(X, Y, 23.0, 1.0, seed + 61)
    t = tones[:, None] + (streak - 0.5) * 0.06
    # knurl: crossed diagonal cuts
    kmask = np.zeros((n, w), dtype=bool)
    for (a, b) in knurl:
        xa, xb = int(round(a * (w - 1))), int(round(b * (w - 1)))
        kmask[:, xa:xb + 1] = True
    Xi, Yi = X.astype(int), Y.astype(int)
    cut = ((Xi + Yi) % 3 == 0)
    t = np.where(kmask, t * 0.80, t)
    t = np.where(kmask & cut, t * 0.50, t)
    M.put_rgb(sub, M.tone_rgb(t, P.STEEL_LUT, 40))
    # section collars at the ends of each knurled span
    for (a, b) in knurl:
        for xx in (int(round(a * (w - 1))), int(round(b * (w - 1)))):
            M.vl(c, x0 + xx, y0, y1, P.STEEL[0], 0.8)
            if xx + 1 < w:
                M.vl(c, x0 + xx + 1, y0, y1 - 1, P.STEEL[5], 0.35)
    # shadow of the rail on the strip below it
    M.hl(c, x0 + 1, x1 + 1, y1 + 1, P.SHADOW, 0.55)


def title_strip_base(c, active: bool, seed: int = 0, wrap_px: int | None = None, rows: int = 14):
    """The channel the rail is mounted in: dark parkerised strip with a lit
    lower lip; identical for every title variant at the far left / right."""
    sub = c.sub(0, 0, c.w, rows)
    t = M.plate_tone(sub, seed=seed + 40, base=0.30, wrapx_px=wrap_px, vgrad=0.0)
    M.put_rgb(sub, M.tone_rgb(t, P.GUN_LUT))
    M.hl(c, 0, c.w - 1, 0, P.GUN[0])
    M.hl(c, 1, c.w - 2, 1, P.GUN[6], 0.7)
    M.hl(c, 1, c.w - 2, 2, P.GUN[4], 0.35)
    M.hl(c, 0, c.w - 1, rows - 1, P.GUN[0])
    M.hl(c, 1, c.w - 2, rows - 2, P.GUN[1], 0.8)


def mini_key(c, which: str, pressed: bool):
    """9x9 square key for the title strip: dark cap in a steel collar with a
    paint-filled pictogram (close = red)."""
    M.box(c, 0, 0, 9, 9, P.GUN[0])
    M.box(c, 1, 1, 7, 7, P.GUN[2] if not pressed else P.GUN[1])
    if not pressed:
        M.hl(c, 1, 6, 1, P.GUN[6], 0.85)
        M.vl(c, 1, 2, 6, P.GUN[5], 0.7)
        M.hl(c, 2, 7, 7, P.GUN[0], 0.9)
        M.vl(c, 7, 2, 7, P.GUN[0], 0.8)
        M.pset(c, 1, 1, P.STEEL[5])
    else:
        M.hl(c, 1, 7, 1, P.SHADOW, 0.95)
        M.vl(c, 1, 2, 7, P.SHADOW, 0.85)
        M.hl(c, 2, 7, 7, P.GUN[4], 0.7)
        M.vl(c, 7, 2, 6, P.GUN[4], 0.6)
    d = 1 if pressed else 0
    ink = P.LEGEND[3] if not pressed else P.LEGEND[4]
    if which == "close":
        ink = P.RED[4] if not pressed else P.RED[5]
    ox, oy = 2 + d, 2 + d
    pics = {
        "options": ["#####", ".....", "#####", ".....", "#####"],
        "minimize": [".....", ".....", ".....", "#####", "#####"],
        "shade": ["#####", "#####", ".....", ".....", "....."],
        "unshade": ["#####", "#...#", "#...#", "#...#", "#####"],
        "close": ["#...#", ".#.#.", "..#..", ".#.#.", "#...#"],
    }[which]
    n = 5 - d
    for j, row in enumerate(pics[:n]):
        for i, ch in enumerate(row[:n]):
            if ch == "#":
                M.pset(c, ox + i, oy + j, ink)
    if pressed:
        M.blend_mask(c, np.full((5, 5), 0.18, dtype=np.float32), ink, 2, 2)
    c.a[:, :, 3] = 255


# ---------------------------------------------------------------------------
# plates, louvres, conduit
# ---------------------------------------------------------------------------

def label_plate(c, x, y, w, h, lines, seed: int = 0, brass: bool = False, rivets: bool = True,
                face=None, ink=None, line_gap: int = 1, align: str = "left"):
    """Riveted label plate standing 1px proud, stamped text."""
    face = T.MICRO if face is None else face
    m = M.full_mask(c, x, y, w, h, r=1)
    sub = c.sub(x, y, w, h)
    tone = M.steel_tone(sub, seed=seed, base=0.30 if not brass else 0.5, strength=0.6)
    lut = P.STEEL_LUT if not brass else P.lut([P.hx(v) for v in (
        "#2a2008", "#4a3a10", "#75601e", "#a08a34", "#c9b458", "#e8d98c")])
    rgb = M.tone_rgb(tone, lut, 40)
    M.put_rgb(sub, rgb, mask=M.round_mask(w, h, 1).astype(np.float32))
    M.raise_mask(c, m, a_hi=0.55, a_lo=0.6, contact=1, a_contact=0.5)
    ink = P.LEGEND[3] if ink is None else ink
    ty = y + max(1, (h - (len(lines) * face.h + (len(lines) - 1) * line_gap)) // 2)
    for ln in lines:
        tw = face.width(ln)
        tx = x + (w - tw) // 2 if align == "centre" else x + (5 if rivets else 2)
        T.draw(c, tx, ty, ln, face, ink, a=0.95)
        ty += face.h + line_gap
    if rivets:
        for (rx, ry) in ((x + 1, y + 1), (x + w - 3, y + 1), (x + 1, y + h - 3), (x + w - 3, y + h - 3)):
            M.pset(c, rx, ry, P.STEEL[5])
            M.pset(c, rx + 1, ry, P.STEEL[2])
            M.pset(c, rx, ry + 1, P.STEEL[2])
            M.pset(c, rx + 1, ry + 1, P.STEEL[0])


def louvres(c, x, y, w, n, pitch: int = 3):
    """Pressed louvre vent: each slot is a dark mouth under a lit hood."""
    for k in range(n):
        yy = y + k * pitch
        M.hl(c, x + 1, x + w - 2, yy, P.GUN[6], 0.75)           # hood catches light
        M.hl(c, x, x + w - 1, yy + 1, P.GUN[0])                 # the mouth
        M.pset(c, x, yy, P.GUN[5], 0.5)
        M.pset(c, x + w - 1, yy, P.GUN[3], 0.6)
        M.hl(c, x + 1, x + w - 1, yy + 2, P.SHADOW, 0.30)       # soft shadow under the mouth
        M.pset(c, x + w - 1, yy + 1, P.GUN[5], 0.6)             # far wall of the slot, lit


def conduit(c, x, y, w, h, seed: int = 0, vertical: bool = True):
    """Armoured flexible conduit: interlocked steel ribs over a round section."""
    # shadow on the plate, down-right
    M.box(c, x + 2, y + 1, w, h, P.SHADOW, 0.35)
    prof = np.array([0.22, 0.55, 0.86, 0.95, 0.74, 0.56, 0.40, 0.28, 0.18, 0.12])
    idx = np.clip(np.rint(np.linspace(0, len(prof) - 1, w)).astype(int), 0, len(prof) - 1)
    for j in range(h):
        rib = (j % 3)
        for i in range(w):
            t = prof[idx[i]]
            if rib == 2:
                t *= 0.42                                        # gap between ribs
            elif rib == 0:
                t = min(1.0, t * 1.08 + 0.03)
            # ribs bow slightly: ends of each rib drop one row on the round section
            M.pset(c, x + i, y + j, P.at(P.STEEL_LUT, t * 0.78))
    M.vl(c, x - 1, y, y + h - 1, P.SHADOW, 0.35)


def conduit_h(c, x, y, w, h, seed: int = 0):
    """Horizontal run of armoured conduit, h px thick, ribs every 3 px."""
    M.box(c, x + 1, y + h, w, 1, P.SHADOW, 0.5)
    M.box(c, x + 2, y + h + 1, w, 1, P.SHADOW, 0.22)
    prof = {3: [0.80, 0.50, 0.20], 4: [0.62, 0.92, 0.50, 0.20], 5: [0.55, 0.92, 0.70, 0.40, 0.18],
            6: [0.5, 0.9, 0.78, 0.55, 0.32, 0.16]}[h]
    for i in range(w):
        rib = i % 3
        for j in range(h):
            t = prof[j]
            if rib == 2:
                t *= 0.45
            elif rib == 0:
                t = min(1.0, t * 1.10 + 0.03)
            M.pset(c, x + i, y + j, P.at(P.STEEL_LUT, t * 0.80))
