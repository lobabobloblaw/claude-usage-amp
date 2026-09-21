"""The parts bin -- every component on the Amethyst boards, drawn with a Pen
in window coordinates.  One light source, top-left: highlights on top/left
edges, core shadow bottom/right, contact shadow cast down-right on the mask.
"""

from __future__ import annotations

from . import palette as P
from .type_small import SILK

M, G, T, E, S = P.MASK, P.GOLD, P.TIN, P.EPOXY, P.SILK


# ---------------------------------------------------------------------------
# copper: traces, vias, pads
# ---------------------------------------------------------------------------

def _walk(pts):
    """Pixels of a polyline whose segments are H, V or exact 45 degrees."""
    out = []
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        dx, dy = x1 - x0, y1 - y0
        assert dx == 0 or dy == 0 or abs(dx) == abs(dy), f"trace bend not 45deg: {(x0, y0)}->{(x1, y1)}"
        n = max(abs(dx), abs(dy))
        sx = (dx > 0) - (dx < 0)
        sy = (dy > 0) - (dy < 0)
        for i in range(n + 1):
            q = (x0 + sx * i, y0 + sy * i)
            if not out or out[-1] != q:
                out.append(q)
    return out


def traces(p, lines, col=None, width=1):
    """Route a set of traces (mask over copper).  Shadows of the whole set go
    down first so parallel buses keep clean, even gaps."""
    col = P.POUR[3] if col is None else col
    paths = [_walk(l) for l in lines]
    for path in paths:
        for x, y in path:
            p.shade(x + 1, y + 1, width, width, 0.80)
    for path in paths:
        for i, (x, y) in enumerate(path):
            p.box(x, y, width, width, col)
    # the lit lip of the copper step: every 3rd pixel a touch lighter reads as
    # sheen along the run without turning the trace into a stripe of noise
    for path in paths:
        for i, (x, y) in enumerate(path):
            if (x * 3 + y * 5) % 7 == 0:
                p.px(x, y, P.POUR[4])


def _offset_path(pts, k, pitch, side):
    """Offset an H/V/45 polyline sideways by k traces, mitring each corner so
    the spacing stays even round 45-degree bends."""
    if k == 0:
        return [tuple(q) for q in pts]
    diag = int(round(pitch * 1.4142))
    lines = []
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        dx, dy = x1 - x0, y1 - y0
        sx, sy = (dx > 0) - (dx < 0), (dy > 0) - (dy < 0)
        nx, ny = -sy * side, sx * side                       # integer normal
        off = k * (diag if (sx and sy) else pitch)
        lines.append((nx, ny, nx * x0 + ny * y0 + off))
    out = []
    nx, ny, c0 = lines[0]
    x0, y0 = pts[0]
    d = c0 - (nx * x0 + ny * y0)
    out.append((x0 + nx * d // (nx * nx + ny * ny), y0 + ny * d // (nx * nx + ny * ny)))
    for (a1, b1, c1), (a2, b2, c2) in zip(lines, lines[1:]):
        det = a1 * b2 - a2 * b1
        out.append(((c1 * b2 - c2 * b1) // det, (a1 * c2 - a2 * c1) // det))
    nx, ny, c0 = lines[-1]
    x0, y0 = pts[-1]
    d = c0 - (nx * x0 + ny * y0)
    out.append((x0 + nx * d // (nx * nx + ny * ny), y0 + ny * d // (nx * nx + ny * ny)))
    return out


def bus(p, pts, n, pitch=2, side=1, col=None, draw=True):
    """``n`` parallel traces following ``pts`` (trace 0), the others nested
    on ``side`` (+1 = right of travel... in screen space: clockwise normal)."""
    lines = [_offset_path(pts, k, pitch, side) for k in range(n)]
    if draw:
        traces(p, lines, col)
    return lines


def via(p, x, y):
    """3x3 plated via: gold annulus, drilled hole."""
    p.rows(x - 1, y - 1, ("aAa", "AoB", "aBb"),
           {"A": G[4], "a": G[3], "B": G[3], "b": G[1], "o": M[0]})
    p.shade(x + 2, y, 1, 2, 0.8)
    p.shade(x, y + 2, 3, 1, 0.8)


def via_tented(p, x, y):
    """A via under the mask: only a lighter bump with a dimple."""
    p.rows(x - 1, y - 1, (".a.", "aoa", ".a."), {"a": P.POUR[3], "o": P.POUR[0]})
    p.px(x, y - 1, P.POUR[4])


def pad(p, x, y, w, h, tin=False):
    """Rectangular SMD land: ENIG gold, or tinned."""
    r = T if tin else G
    lo, mid, hi = (r[2], r[4], r[6]) if tin else (r[2], r[3], r[4])
    p.box(x, y, w, h, mid)
    p.hline(x, x + w - 1, y, hi)
    if h > 1:
        p.hline(x, x + w - 1, y + h - 1, lo)
    if w > 2 and h > 1:
        p.px(x + 1, y, r[-1])                # single-pixel specular glint


def test_point(p, x, y, label=None, lx=None, ly=None):
    """Round gold test pad, 3x3, with its silk designator."""
    p.rows(x - 1, y - 1, ("aAa", "AWA", "bab"), {"A": G[4], "a": G[3], "b": G[2], "W": G[5]})
    if label:
        silk(p, x + 3 if lx is None else lx, y - 2 if ly is None else ly, label)


def fiducial(p, x, y):
    """Bare copper dot in a round mask opening."""
    p.rows(x - 2, y - 2, (".ooo.", "o...o", "o.g.o", "o...o", ".ooo."), {"o": M[1], "g": G[4]})
    p.rows(x - 1, y - 1, ("fff", "fgf", "fff"), {"f": P.FR4[0], "g": G[4]})
    p.px(x, y - 1, G[3]); p.px(x - 1, y, G[3]); p.px(x + 1, y, G[2]); p.px(x, y + 1, G[2])


def mount_hole(p, cx, cy):
    """Plated mounting hole: 9 px gold annulus round a 3 px bore."""
    p.cast(cx - 3, cy - 3, 7, 7, depth=1, strength=0.3)
    for j in range(-4, 5):
        for i in range(-4, 5):
            d = (i * i + j * j) ** 0.5
            if d <= 1.5:
                col = (5, 3, 10, 255) if (i + j) < 1 else P.FR4[0] if (i + j) == 1 else P.FR4[1]
            elif d <= 4.3:
                t = 0.62 - (i + j) * 0.075 + (0.12 if d > 3.4 and (i + j) < 0 else 0.0)
                col = P.sample(G, t)
            else:
                continue
            p.px(cx + i, cy + j, col)
    p.px(cx - 2, cy - 2, G[5]); p.px(cx - 1, cy - 3, G[5])


# ---------------------------------------------------------------------------
# silk
# ---------------------------------------------------------------------------

def silk(p, x, y, text, col=None, font=None, worn=0.0, spacing=None):
    """White epoxy legend ink.  ``worn`` 0..1 knocks a deterministic share of
    pixels back to the rubbed tone."""
    from skinkit import fonts
    f = SILK if font is None else font
    ink = S[3] if col is None else col
    end = p.text(x, y, text, f, ink, spacing=spacing)
    if worn:
        m = fonts.text_mask(text, f, spacing)
        for j in range(m.shape[0]):
            for i in range(m.shape[1]):
                if m[j, i] and ((x + i) * 7 + (y + j) * 13 + len(text)) % 100 < worn * 100:
                    p.px(x + i, y + j, S[1])
    return end


def silk_w(text, font=None, spacing=None):
    from skinkit import fonts
    return fonts.text_width(text, SILK if font is None else font, spacing)


def silk_box(p, x, y, w, h, col=None, gap=None):
    """Component courtyard outline in silk; ``gap`` = (side, a, b) leaves an opening."""
    col = S[2] if col is None else col
    p.hline(x + 1, x + w - 2, y, col); p.hline(x + 1, x + w - 2, y + h - 1, col)
    p.vline(x, y + 1, y + h - 2, col); p.vline(x + w - 1, y + 1, y + h - 2, col)


# ---------------------------------------------------------------------------
# passives
# ---------------------------------------------------------------------------

def _chip(p, x, y, n, horizontal, body, mark=None):
    """Generic two-terminal chip: tin end caps, ``n`` px of body between."""
    lo, mid, hi = body
    if horizontal:
        w, h = n + 2, 3
        p.cast(x, y, w, h, depth=1, strength=0.5)
        p.box(x + 1, y, n, 3, mid)
        p.hline(x + 1, x + n, y, hi)
        p.hline(x + 1, x + n, y + 2, lo)
        for ex in (x, x + n + 1):
            p.vline(ex, y, y + 2, T[4])
            p.px(ex, y, T[6])
            p.px(ex, y + 2, T[2])
        if mark:
            for k in range(0, n - 1, 2):
                p.px(x + 2 + k, y + 1, mark)
    else:
        w, h = 3, n + 2
        p.cast(x, y, w, h, depth=1, strength=0.5)
        p.box(x, y + 1, 3, n, mid)
        p.vline(x, y + 1, y + n, hi)
        p.vline(x + 2, y + 1, y + n, lo)
        for ey in (y, y + n + 1):
            p.hline(x, x + 2, ey, T[4])
            p.px(x, ey, T[6])
            p.px(x + 2, ey, T[2])
        if mark:
            for k in range(0, n - 1, 2):
                p.px(x + 1, y + 2 + k, mark)


def chip_r(p, x, y, horizontal=True, n=3):
    """Thick-film resistor: black glass, white numerals (as dots at this size)."""
    _chip(p, x, y, n, horizontal, (P.RES[0], P.RES[1], P.RES[3]), mark=S[1])


def chip_c(p, x, y, horizontal=True, n=3):
    """MLCC: bare tan ceramic, no marking."""
    _chip(p, x, y, n, horizontal, (P.CERAMIC[1], P.CERAMIC[2], P.CERAMIC[4]))


def tantalum(p, x, y, horizontal=True):
    """Moulded tantalum, 7x4, with its polarity bar at the + end."""
    lo, mid, hi = P.TANT[1], P.TANT[2], P.TANT[4]
    if horizontal:
        p.cast(x, y, 8, 4, depth=1, strength=0.5)
        p.box(x + 1, y, 6, 4, mid)
        p.hline(x + 1, x + 6, y, hi); p.hline(x + 1, x + 6, y + 3, lo)
        p.vline(x + 2, y, y + 3, P.TANT[0]); p.px(x + 2, y, P.TANT[1])
        for ex in (x, x + 7):
            p.vline(ex, y, y + 3, T[4]); p.px(ex, y, T[6]); p.px(ex, y + 3, T[2])
    else:
        p.cast(x, y, 4, 8, depth=1, strength=0.5)
        p.box(x, y + 1, 4, 6, mid)
        p.vline(x, y + 1, y + 6, hi); p.vline(x + 3, y + 1, y + 6, lo)
        p.hline(x, x + 3, y + 2, P.TANT[0]); p.px(x, y + 2, P.TANT[1])
        for ey in (y, y + 7):
            p.hline(x, x + 3, ey, T[4]); p.px(x, ey, T[6]); p.px(x + 3, ey, T[2])


def diode(p, x, y):
    """SOD-323: black body, white cathode band."""
    _chip(p, x, y, 4, True, (E[0], E[2], E[4]))
    p.vline(x + 1, y, y + 2, S[2]); p.px(x + 1, y, S[3])


def res_array(p, x, y, n=4):
    """Convex 4-resistor network: long black body, n terminations each side."""
    w = n * 2 + 1
    p.cast(x, y, w, 5, depth=1, strength=0.5)
    p.box(x, y + 1, w, 3, P.RES[1])
    p.hline(x, x + w - 1, y + 1, P.RES[3]); p.hline(x, x + w - 1, y + 3, P.RES[0])
    for k in range(n):
        px_ = x + 1 + 2 * k
        p.px(px_, y, T[5]); p.px(px_, y + 4, T[3])
        p.px(px_, y + 2, S[0])


def sot23(p, x, y, flip=False):
    """SOT-23 from above: 5x3 body, one leg one side, two the other."""
    p.cast(x, y + 1, 5, 3, depth=1, strength=0.5)
    p.box(x, y + 1, 5, 3, E[2])
    p.hline(x, x + 4, y + 1, E[4]); p.hline(x, x + 4, y + 3, E[0])
    one, two = (y + 4, y) if flip else (y, y + 4)
    p.px(x + 2, one, T[5])
    p.px(x, two, T[4]); p.px(x + 4, two, T[4])
    p.px(x + 1, y + 2, P.ETCH)


def inductor(p, x, y):
    """Shielded power inductor, 7x7, octagonal ferrite top."""
    rows = (".aAAAa.", "aAmmmmb", "AmmMmmb", "AmMMMmb", "AmmMmdb", "ammmddb", ".bbbbb.")
    p.cast(x, y, 7, 7, depth=2, strength=0.45)
    p.rows(x, y, rows, {"A": E[5], "a": E[4], "m": E[3], "M": E[2], "d": E[2], "b": E[0]})
    p.px(x + 2, y + 2, P.ETCH)


# ---------------------------------------------------------------------------
# LEDs
# ---------------------------------------------------------------------------

def led_smd(p, x, y, kind="g", level=0.0, horizontal=True, bloom=True, pads=True):
    """0603 LED, 5x3 (or 3x5): tin lands and a 3x3 lens.

    ``level`` 0 = off (dull tinted lens, still clearly a lens), 1 = fully lit:
    near-white core, saturated body, light spilling onto the mask around it.
    """
    r = P.led_ramp(kind)
    if horizontal:
        lx, ly = x + 1, y
        if pads:
            for ex in (x, x + 4):
                p.vline(ex, y, y + 2, T[4]); p.px(ex, y, T[6]); p.px(ex, y + 2, T[2])
    else:
        lx, ly = x, y + 1
        if pads:
            for ey in (y, y + 4):
                p.hline(x, x + 2, ey, T[4]); p.px(x, ey, T[6]); p.px(x + 2, ey, T[2])
    lens(p, lx, ly, 3, 3, r, level, bloom)


def lens(p, x, y, w, h, r, level, bloom=True, radius=None):
    """A w*h LED lens.  r = (off-shadow, off, body-dim, body, hot, white)."""
    if level <= 0.0:
        p.box(x, y, w, h, r[1])
        p.hline(x, x + w - 1, y + h - 1, r[0])
        p.px(x, y, P.lerp(r[1], r[2], 0.55))          # dull sky reflection
        return
    body = P.lerp(r[2], r[3], min(1.0, level * 1.15))
    hot = P.lerp(r[3], r[4], level)
    p.box(x, y, w, h, body)
    p.hline(x, x + w - 1, y + h - 1, P.lerp(r[2], r[3], level * 0.7))
    cx, cy = x + (w - 1) // 2, y + (h - 1) // 2
    p.px(cx, cy, hot if level < 0.75 else r[5] if level > 0.95 else r[4])
    if w >= 3 and level > 0.5:
        p.px(cx - 1, cy, hot); p.px(cx + 1, cy, hot)
        if h >= 3:
            p.px(cx, cy - 1, hot)
    if bloom:
        rad = (1.6 + 2.2 * level) if radius is None else radius
        p.light(x + (w - 1) / 2.0, y + (h - 1) / 2.0, r[3], radius=rad + max(w, h) / 2.0,
                strength=0.55 * level)
