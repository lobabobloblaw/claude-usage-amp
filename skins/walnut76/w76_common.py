"""Walnut 76 -- shared construction helpers (cabinet, fascia, lettering)."""

from __future__ import annotations

import numpy as np

from skinkit import fonts
from skinkit.canvas import Canvas, mix, parse_colour

import w76_materials as M
import w76_palette as P
from w76_microfonts import PANEL, SERIF, TINY

CHEEK = 7                      # walnut cheek width, all three windows
RAIL_H = 14                    # top rail height


# ---------------------------------------------------------------------------
# lettering
# ---------------------------------------------------------------------------

def tw(text: str, font=TINY, spacing: int | None = None) -> int:
    return fonts.text_width(text, font, spacing)


def engrave(c: Canvas, x: int, y: int, text: str, font=TINY, spacing: int | None = None,
            ink=P.INK, lip: int = 120) -> int:
    """Black-filled engraving in aluminium: ink in the groove, and the groove's
    lower lip catching the top-left light."""
    if lip:
        fonts.draw_text(c, x, y + 1, text, font, (251, 247, 234, lip), spacing=spacing)
    return fonts.draw_text(c, x, y, text, font, ink, spacing=spacing)


def engrave_c(c: Canvas, cx: int, y: int, text: str, font=TINY, spacing=None, **kw) -> int:
    return engrave(c, cx - tw(text, font, spacing) // 2, y, text, font, spacing, **kw)


def legend(c: Canvas, x: int, y: int, text: str, font=TINY, colour=P.TEAL[1],
           spacing: int | None = None, halo: float = 0.0) -> int:
    """A backlit legend on the glass."""
    if halo:
        m = np.zeros((c.h, c.w), dtype=bool)
        tm = fonts.text_mask(text, font, spacing)
        x0, y0 = int(x), int(y)
        hh, ww = tm.shape
        ys0, xs0 = max(0, y0), max(0, x0)
        ys1, xs1 = min(c.h, y0 + hh), min(c.w, x0 + ww)
        if ys1 > ys0 and xs1 > xs0:
            m[ys0:ys1, xs0:xs1] = tm[ys0 - y0:ys1 - y0, xs0 - x0:xs1 - x0]
            M.glow_mask(c, m, colour, strength=halo, diag=0.4)
    return fonts.draw_text(c, x, y, text, font, colour, spacing=spacing)


def silk(c: Canvas, x: int, y: int, text: str, font=TINY, colour=P.CREAM, spacing=None) -> int:
    """Cream silk-screen on black plastic."""
    return fonts.draw_text(c, x, y, text, font, colour, spacing=spacing)


# ---------------------------------------------------------------------------
# cabinet
# ---------------------------------------------------------------------------

def cheeks(c: Canvas, y0: int, knots_left=(), knots_right=(), period=None) -> None:
    """The two walnut end-cheeks from local row ``y0`` down (window coords are
    taken from the canvas).  Vertical grain, satin sheen line, lit outer-left
    edge, dark outer-right edge, contact shadow onto the fascia."""
    h = c.h - y0
    W = c.w
    left = c.sub(0, y0, CHEEK, h)
    right = c.sub(W - CHEEK, y0, CHEEK, h)
    M.walnut(left, "v", seed=76, knots=knots_left, period=period)
    M.walnut(right, "v", seed=91, knots=knots_right, period=period, tone=-0.02)
    # satin sheen line + edges (left cheek)
    M.shade_cols(left, {0: 1.28, 1: 1.10, 2: 1.16, CHEEK - 1: 0.62, CHEEK - 2: 0.88})
    # right cheek: inner edge faces the light
    M.shade_cols(right, {0: 1.30, 1: 1.08, 3: 1.12, CHEEK - 1: 0.50, CHEEK - 2: 0.80})


def cheek_shadow(c: Canvas, y0: int, y1: int) -> None:
    """Contact shadow the left cheek throws onto the fascia (light is top-left)
    and the dark seam where the fascia tucks under the right cheek."""
    M.shade_box(c, CHEEK, y0, 1, y1 - y0 + 1, 0.62)
    M.shade_box(c, CHEEK + 1, y0, 1, y1 - y0 + 1, 0.86)
    M.shade_box(c, c.w - CHEEK - 1, y0, 1, y1 - y0 + 1, 0.80)


def rail(c: Canvas, knots=(), period=None, h: int = RAIL_H) -> None:
    """The cabinet's top rail: the front edge of the walnut lid.  Horizontal
    grain, darker end-grain blocks where the cheeks' tops show at either end,
    a lit top arris, a dark underside."""
    r = c.sub(0, 0, c.w, h)
    M.walnut(r, "h", seed=53, knots=knots, period=period, tone=0.03)
    M.shade_rows(r, {0: 1.45, 1: 1.18, 2: 1.04, h - 3: 0.94, h - 2: 0.80, h - 1: 0.50})
    r.hline(0, c.w - 1, 0, mix(P.WALNUT[6], "#ffffff", 0.12))
    r.px(0, 0, P.WALNUT[5])
    r.px(c.w - 1, 0, P.WALNUT[4])


def rail_ends(c: Canvas, h: int = RAIL_H) -> None:
    """End-grain of the side panels showing at the two ends of the rail, with
    the joint line.  Identical for every title-bar variant."""
    for x0, lit in ((0, True), (c.w - CHEEK, False)):
        blk = c.sub(x0, 0, CHEEK, h)
        # end grain: darker, speckled with open pores rather than lined
        X, Y = M.grid(blk)
        n = M._hash01(X.astype(np.int64), Y.astype(np.int64), 4242)
        n2 = M.vnoise(X, Y, 2.0, 2.0, 99)
        t = 0.10 + 0.20 * n2 + np.where(n > 0.82, -0.08, 0.0) + np.where(n < 0.1, 0.07, 0.0)
        M._put(blk, M._ramp_map(P.WALNUT, t))
        M.shade_rows(blk, {0: 1.5, 1: 1.15, h - 1: 0.55})
    # joint lines between lid and side panels
    c.vline(CHEEK, 1, h - 1, P.WALNUT[0])
    M.shade_box(c, CHEEK + 1, 1, 1, h - 2, 1.18)
    c.vline(c.w - CHEEK - 1, 1, h - 1, P.WALNUT[0])
    M.shade_box(c, c.w - CHEEK, 1, 1, h - 2, 1.12)
    c.vline(0, 0, h - 1, P.WALNUT[5])
    c.vline(c.w - 1, 0, h - 1, P.WALNUT[0])
    c.px(0, 0, P.WALNUT[6])


def name_strip(c: Canvas, x: int, y: int, w: int, h: int, text: str, active: bool,
               spacing: int = 2, seed: int = 7) -> None:
    """An aluminium strip inlaid flush in the walnut rail, engraved with a
    serif legend.  Inactive: the strip goes dull and the ink greys."""
    s = c.sub(x, y, w, h)
    M.aluminium(s, seed=seed, level=0.66 if active else 0.40, sheen=0.7 if active else 0.25,
                win_w=max(c.w, 275))
    # inlay shadow line in the wood around it (strip is flush: hairline only)
    c.rect(x - 1, y - 1, w + 2, h + 2, P.WALNUT[0])
    c.hline(x, x + w - 1, y + h, mix(P.WALNUT[5], P.WALNUT[6], 0.3))
    c.vline(x + w, y, y + h, P.WALNUT[4])
    # strip's own edges
    s.hline(0, w - 1, 0, P.ALU[6] if active else P.ALU[4])
    s.hline(0, w - 1, h - 1, P.ALU[1] if active else P.ALU[0])
    s.vline(0, 0, h - 1, P.ALU[5] if active else P.ALU[3])
    s.vline(w - 1, 0, h - 1, P.ALU[1] if active else P.ALU[0])
    tx = (w - tw(text, SERIF, spacing)) // 2
    engrave(s, tx, (h - 7) // 2, text, SERIF, spacing,
            ink=P.INK if active else "#4a4438", lip=110 if active else 40)
    # tiny pins holding the strip
    for px_ in (3, w - 4):
        s.px(px_, h // 2, P.ALU[0])
        s.px(px_, h // 2 + 1, P.ALU[6] if active else P.ALU[4])


def fascia(c: Canvas, y0: int = RAIL_H) -> None:
    """Brushed champagne fascia from row ``y0`` down, between the cheeks, with
    the rail's contact shadow at the top and a chamfered bottom edge."""
    f = c.sub(CHEEK, y0, c.w - 2 * CHEEK, c.h - y0)
    M.aluminium(f)
    # the lid overhangs the fascia: soft contact shadow
    M.shade_rows(f, {0: 0.58, 1: 0.82, 2: 0.94})
    # bottom chamfer + foot shadow
    M.shade_rows(f, {f.h - 3: 1.06, f.h - 2: 0.80, f.h - 1: 0.45})


def glass_pane(c: Canvas, x: int, y: int, w: int, h: int, shadow: bool = True) -> Canvas:
    """A rectangular black-glass window set in a chrome trim ring.  ``x,y,w,h``
    is the *interior*.  Returns the interior view."""
    M.chrome_ring(c, x - 2, y - 2, w + 4, h + 4)
    c.rect(x - 1, y - 1, w + 2, h + 2, "#000000")
    # lower/right inner wall catches a little light
    c.hline(x, x + w, y + h, "#15191b")
    c.vline(x + w, y, y + h, "#15191b")
    # ring's contact shadow on the aluminium below/right
    M.shade_box(c, x - 1, y + h + 2, w + 4, 1, 0.80)
    M.shade_box(c, x + w + 2, y - 1, 1, h + 4, 0.84)
    g = c.sub(x, y, w, h)
    g.fill(P.GLASS_FLAT)
    return g


def _dilate(m: np.ndarray, n: int = 1) -> np.ndarray:
    out = m.copy()
    for _ in range(n):
        p = np.pad(out, 1)
        h, w = out.shape
        acc = np.zeros_like(out)
        for dy in (0, 1, 2):
            for dx in (0, 1, 2):
                acc |= p[dy:dy + h, dx:dx + w]
        out = acc
    return out


def glass_shape(c: Canvas, interior: np.ndarray, glints=()) -> None:
    """Black glass of any rectilinear outline (``interior`` is a bool mask the
    size of the canvas) in a 1 px chrome trim ring with a black inner wall.

    Ring pixels facing the light (top / left runs) are bright chrome, the
    others mid chrome; the ring throws a soft contact shadow down-right onto
    the fascia; the inner wall's lower/right faces catch a little light."""
    h, w = interior.shape
    d1 = _dilate(interior, 1)
    d2 = _dilate(interior, 2)
    wall = d1 & ~interior
    ring = d2 & ~d1
    # contact shadow (outside the ring, down-right of it)
    sh = np.zeros_like(interior)
    sh[1:, 1:] = d2[:-1, :-1]
    sh &= ~d2
    cur = c.a[:, :, :3].astype(np.float32)
    cur[sh] *= 0.80
    c.a[:, :, :3] = np.clip(np.rint(cur), 0, 255).astype(np.uint8)
    # is the glass down/right of this ring pixel?  then it is a lit run
    lit = np.zeros_like(interior)
    lit[:-2, :] |= d1[2:, :] & ring[:-2, :]
    lit[:, :-2] |= d1[:, 2:] & ring[:, :-2]
    below = np.zeros_like(interior)
    below[2:, :] |= d1[:-2, :] & ring[2:, :]
    below[:, 2:] |= d1[:, :-2] & ring[:, 2:]
    bright = ring & lit & ~below
    c.a[:, :, :3][ring] = parse_colour(P.CHROME[1])[:3]
    c.a[:, :, :3][bright] = parse_colour(P.CHROME[2])[:3]
    c.a[:, :, :3][wall] = (0, 0, 0)
    # lower/right inner wall faces the light
    wl = np.zeros_like(interior)
    wl[1:, :] |= interior[:-1, :] & wall[1:, :]
    wl[:, 1:] |= interior[:, :-1] & wall[:, 1:]
    c.a[:, :, :3][wl] = parse_colour("#171c1e")[:3]
    c.a[:, :, :3][interior] = parse_colour(P.GLASS_FLAT)[:3]
    for (gx, gy, col) in glints:
        c.px(gx, gy, col)


def rect_mask(shape_hw, *rects) -> np.ndarray:
    m = np.zeros(shape_hw, dtype=bool)
    for (x, y, w, h) in rects:
        m[y:y + h, x:x + w] = True
    return m


def pane_inner_shadow(g: Canvas) -> None:
    """Glass is recessed: the top and left of the pane sit in the ring's
    shadow.  Only ever darkens toward pure black."""
    g.hline(0, g.w - 1, 0, "#010202")
    g.hline(0, g.w - 1, 1, "#030405")
    g.vline(0, 0, g.h - 1, "#010202")
    g.vline(1, 1, g.h - 1, "#030405")
