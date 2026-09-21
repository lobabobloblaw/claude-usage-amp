"""materials -- book cloth, laid paper, and the small constructions made of them.

Two ideas keep everything seamless:

* **Fields.**  Each window has one cloth field and one paper field: a full
  window-sized float RGB array, generated once (seeded, cached).  Painting
  "cloth" or "paper" anywhere means copying the matching slice of the field, so
  a widget porthole and the background can never disagree.
* **Periodic playlist cloth.**  The playlist frame is tiled (25 px across, 29 px
  down), so its cloth is woven on thread layouts that repeat exactly on those
  periods: eleven 2-px threads and one 3-px slub per 25 px, thirteen and one
  per 29 px.  An even thread count per period keeps the over/under parity
  intact across every tile seam.
"""

from __future__ import annotations

from functools import lru_cache

import numpy as np

from . import palette as P
from .plate import Plate

SEED = 5101

WINDOW_SIZES = {"main": (275, 116), "eq": (275, 116), "playlist": (275, 232),
                "shade": (275, 14)}


# ---------------------------------------------------------------------------
# noise
# ---------------------------------------------------------------------------

def _smooth(t):
    return t * t * (3 - 2 * t)


def value_noise(w: int, h: int, sx: float, sy: float, seed: int) -> np.ndarray:
    """Smooth value noise in 0..1 with cell size (sx, sy) pixels."""
    rng = np.random.RandomState(seed & 0x7FFFFFFF)
    gw, gh = int(w / sx) + 3, int(h / sy) + 3
    g = rng.rand(gh, gw).astype(np.float32)
    xs = np.arange(w, dtype=np.float32) / sx
    ys = np.arange(h, dtype=np.float32) / sy
    x0, y0 = np.floor(xs).astype(int), np.floor(ys).astype(int)
    fx, fy = _smooth(xs - x0)[None, :], _smooth(ys - y0)[:, None]
    a = g[y0[:, None], x0[None, :]]
    b = g[y0[:, None], x0[None, :] + 1]
    c = g[y0[:, None] + 1, x0[None, :]]
    d = g[y0[:, None] + 1, x0[None, :] + 1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(w, h, scale, seed, octaves=3):
    out = np.zeros((h, w), dtype=np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        s = max(1.5, scale / (2 ** o))
        out += amp * value_noise(w, h, s, s, seed + 17 * o)
        tot += amp
        amp *= 0.5
    return out / tot


def white(w, h, seed):
    return np.random.RandomState(seed & 0x7FFFFFFF).rand(h, w).astype(np.float32)


# ---------------------------------------------------------------------------
# book cloth
# ---------------------------------------------------------------------------

def _threads(n: int, rng, slub: float):
    """Thread layout along one axis: (thread index, position in thread, width)."""
    idx = np.zeros(n, dtype=int)
    pos = np.zeros(n, dtype=int)
    wid = np.zeros(n, dtype=int)
    i, t = 0, 0
    while i < n:
        w = 3 if rng.rand() < slub else 2
        for k in range(w):
            if i + k < n:
                idx[i + k], pos[i + k], wid[i + k] = t, k, w
        i += w
        t += 1
    return idx, pos, wid


def _threads_periodic(n: int, period: int, slub_at: int, start: int = 0,
                      lead: int = 0):
    """Layout that repeats every ``period`` px from ``start``; the ``lead``
    pixels before ``start`` are plain 2-px threads (``lead`` must be even and
    hold an even number of threads)."""
    widths = [2] * ((period - 3) // 2)
    widths.insert(slub_at, 3)
    assert sum(widths) == period and len(widths) % 2 == 0
    idx = np.zeros(n, dtype=int)
    pos = np.zeros(n, dtype=int)
    wid = np.zeros(n, dtype=int)
    lead_threads = lead // 2
    for i in range(min(lead, n)):
        idx[i], pos[i], wid[i] = i // 2, i % 2, 2
    cell = []
    for t, w in enumerate(widths):
        for k in range(w):
            cell.append((t, k, w))
    for i in range(start, n):
        ph = (i - start) % period
        rep = (i - start) // period
        t, k, w = cell[ph]
        idx[i] = lead_threads + rep * len(widths) + t
        pos[i], wid[i] = k, w
    return idx, pos, wid, len(widths), lead_threads


def _profile(pos, wid):
    """+1 on the lit flank of a thread, -1 on the shaded flank, 0 on a crown."""
    out = np.where(pos == 0, 1.0, -1.0).astype(np.float32)
    out = np.where((wid == 3) & (pos == 1), 0.15, out)
    return out


@lru_cache(maxsize=None)
def cloth_t(window: str) -> np.ndarray:
    """Scalar shade field (0..1 along the CLOTH ramp) for a window's cloth."""
    w, h = WINDOW_SIZES[window]
    seed = SEED + {"main": 0, "eq": 100, "playlist": 200, "shade": 0}[window]
    rng = np.random.RandomState(seed)
    if window == "playlist":
        ix, px, wx, nx, _ = _threads_periodic(w, 25, 7)
        iy, py, wy, ny, lead_t = _threads_periodic(h, 29, 9, start=20, lead=20)
        jx_tab = rng.randn(nx)
        jy_tab = rng.randn(ny)
        jx = jx_tab[ix % nx]
        jy_lead = rng.randn(lead_t)
        jy = np.where(np.arange(h) < 20, jy_lead[np.minimum(iy, lead_t - 1)],
                      jy_tab[(iy - lead_t) % ny])
        mottle = np.zeros((h, w), dtype=np.float32)
        fuzz = np.zeros((h, w), dtype=np.float32)
    else:
        ix, px, wx = _threads(w, rng, 0.045)
        iy, py, wy = _threads(h, rng, 0.045)
        jx = rng.randn(ix.max() + 1)[ix]
        jy = rng.randn(iy.max() + 1)[iy]
        mottle = (fbm(w, h, 34, seed + 5, 3) - 0.5) * 0.10
        fuzz = (white(w, h, seed + 9) - 0.5) * 0.030
    # Linen book cloth: every thread is a tiny cylinder lit from the top-left,
    # so warp and weft each contribute a lit flank and a shaded flank.  Summed,
    # that gives the fine grid of crowns and pits you see on buckram, and the
    # per-thread dye jitter gives the streaky linen "grain" in both directions.
    s = 0.5 * (_profile(px, wx)[None, :] + _profile(py, wy)[:, None])
    j = 0.5 * (np.clip(jx, -2, 2)[None, :] + np.clip(jy, -2, 2)[:, None])
    t = 0.50 + 0.078 * s + 0.034 * j + mottle + fuzz
    return t.astype(np.float32)


def cloth_rgb(t: np.ndarray, dye: float = 0.0, fade: float = 0.0) -> np.ndarray:
    """Shade field -> colour.  ``dye`` < 0 darkens toward the spine tone;
    ``fade`` sun-bleaches toward kraft."""
    col = P.ramp(P.CLOTH, np.clip(t + dye, 0, 1))
    if fade > 0:
        lum = (t - 0.5)
        kraft = P.ramp(("#b98a5f", P.KRAFT[1], P.KRAFT[2], "#e2bd9c"), np.clip(0.5 + lum * 2.2, 0, 1))
        col = col + (kraft - col) * fade
    return col


def edge_wear(w: int, h: int, seed: int, reach: float = 5.0) -> np.ndarray:
    """0..1 field that is strong along the outer edges and strongest in the
    corners -- where a cloth cover gets rubbed."""
    x = np.arange(w, dtype=np.float32)[None, :]
    y = np.arange(h, dtype=np.float32)[:, None]
    dx = np.minimum(x, w - 1 - x)
    dy = np.minimum(y, h - 1 - y)
    e = np.exp(-dx / reach) + np.exp(-dy / reach)
    corner = np.exp(-(dx + dy) / (reach * 1.6)) * 1.5
    n = value_noise(w, h, 5, 5, seed)
    return np.clip((e * 0.5 + corner) * (0.55 + 0.9 * n), 0, 1.6)


# ---------------------------------------------------------------------------
# paper
# ---------------------------------------------------------------------------

@lru_cache(maxsize=None)
def paper_delta(window: str, kind: str = "laid") -> np.ndarray:
    """Signed level offsets (about +-8) around the flat paper colour."""
    w, h = WINDOW_SIZES[window]
    seed = SEED + 1000 + {"main": 0, "eq": 100, "playlist": 200, "shade": 0}[window]
    rng = np.random.RandomState(seed)
    d = np.zeros((h, w), dtype=np.float32)
    # laid lines: a faint two-row rhythm, plus wider-spaced chain lines
    rows = np.arange(h)
    d += np.where(rows % 2 == 0, 0.9, -0.9)[:, None]
    chain = (np.arange(w) % 23) == 11
    d[:, chain] -= 2.2
    # mottle (formation of the sheet)
    d += (fbm(w, h, 18, seed + 3, 3) - 0.5) * 7.0
    d += (white(w, h, seed + 4) - 0.5) * 2.2
    # fibres: short dark strands and a few pale ones
    n_f = int(w * h / 95)
    for k in range(n_f):
        x, y = rng.randint(0, w), rng.randint(0, h)
        ln = rng.randint(2, 5)
        dx, dy = [(1, 0), (1, 1), (1, -1), (0, 1), (2, 1), (2, -1)][rng.randint(0, 6)]
        val = -5.5 if rng.rand() < 0.72 else 5.0
        for i in range(ln):
            xx, yy = x + (i * dx) // (2 if dx == 2 else 1), y + (i * dy if dx != 2 else (i // 2) * dy)
            if 0 <= xx < w and 0 <= yy < h:
                d[yy, xx] += val * (1.0 if 0 < i < ln - 1 else 0.6)
    return np.clip(d, -9, 8)


_PAPER_AXIS = np.array([1.0, 1.0, 1.25], dtype=np.float32)   # darker = warmer


def paper_rgb(delta: np.ndarray, base=P.PAPER_FLAT, tone: float = 0.0) -> np.ndarray:
    b = P.rgb(base) if isinstance(base, str) else np.asarray(base, dtype=np.float32)
    return np.clip(b[None, None, :] + (delta[..., None] + tone) * _PAPER_AXIS, 0, 255)


# ---------------------------------------------------------------------------
# painting helpers (all in window coordinates, through a Plate)
# ---------------------------------------------------------------------------

def window_of(p: Plate) -> str:
    w = p.c.window or "main"
    return w if w in WINDOW_SIZES else "main"


def lay_cloth(p: Plate, x, y, w, h, window=None, dye: float = 0.0, fade: float = 0.0,
              extra: np.ndarray | None = None):
    """Paint book cloth into a window rect.  ``extra`` is an optional (h, w)
    shade offset, e.g. a vignette."""
    win = window or window_of(p)
    W, H = WINDOW_SIZES[win]
    x0, y0 = max(0, int(x)), max(0, int(y))
    x1, y1 = min(W, int(x) + int(w)), min(H, int(y) + int(h))
    if x1 <= x0 or y1 <= y0:
        return
    t = cloth_t(win)[y0:y1, x0:x1]
    if extra is not None:
        t = t + extra[y0 - int(y):y1 - int(y), x0 - int(x):x1 - int(x)]
    p.paste(x0, y0, cloth_rgb(t, dye=dye, fade=fade))


def lay_paper(p: Plate, x, y, w, h, window=None, base=P.PAPER_FLAT, tone: float = 0.0,
              gain: float = 1.0):
    win = window or window_of(p)
    W, H = WINDOW_SIZES[win]
    x0, y0 = max(0, int(x)), max(0, int(y))
    x1, y1 = min(W, int(x) + int(w)), min(H, int(y) + int(h))
    if x1 <= x0 or y1 <= y0:
        return
    d = paper_delta(win)[y0:y1, x0:x1] * gain
    p.paste(x0, y0, paper_rgb(d, base=base, tone=tone))


def soft_shadow(p: Plate, x, y, w, h, col=P.SHADOW_ON_CLOTH, strength=0.42,
                spread=2, dx=1, dy=1):
    """Cast shadow of a w x h rectangle lifted off the surface: an offset,
    softened rectangle.  Draw it *before* the object."""
    pad = spread + 1
    m = np.zeros((h + 2 * pad, w + 2 * pad), dtype=np.float32)
    m[pad:pad + h, pad:pad + w] = 1.0
    for _ in range(spread):
        m = (m + np.roll(m, 1, 0) + np.roll(m, -1, 0) + np.roll(m, 1, 1) + np.roll(m, -1, 1)
             + 0.5 * (np.roll(np.roll(m, 1, 0), 1, 1) + np.roll(np.roll(m, -1, 0), -1, 1)
                      + np.roll(np.roll(m, 1, 0), -1, 1) + np.roll(np.roll(m, -1, 0), 1, 1))) / 7.0
    p.mask(x - pad + dx, y - pad + dy, m, col, strength)


def cut_opening(p: Plate, x, y, w, h, window=None, paper=True, base=P.PAPER_FLAT,
                depth: int = 2, tone: float = 0.0):
    """A window cut through the cloth-covered board, showing paper beneath.

    ``(x, y, w, h)`` is the paper rect.  The 1-px walls are drawn *outside* it:
    top and left walls face away from the light (deep cloth shadow), bottom and
    right walls face it and show the pale board core.  The paper carries the
    walls' cast shadow along its top and left."""
    if paper:
        lay_paper(p, x, y, w, h, window=window, base=base, tone=tone)
    # walls
    p.hline(x - 1, x + w, y - 1, P.CLAY_SHADOW)
    p.vline(x - 1, y - 1, y + h, P.CLAY_SHADOW)
    p.hline(x, x + w, y + h, P.BOARD_CORE_HI)
    p.vline(x + w, y, y + h, P.BOARD_CORE)
    p.px(x + w, y - 1, P.CLAY_DARK)
    p.px(x - 1, y + h, P.CLAY_DARK)
    p.px(x + w, y + h, P.BOARD_CORE_HI)
    # the cloth turning over the board edge: a lit lip above/left, a crease
    # below/right
    p.hline(x - 1, x + w, y - 2, P.CLAY_LIGHT, 0.30)
    p.vline(x - 2, y - 1, y + h, P.CLAY_LIGHT, 0.22)
    p.hline(x - 1, x + w + 1, y + h + 1, P.SHADOW_ON_CLOTH, 0.22)
    p.vline(x + w + 1, y - 1, y + h + 1, P.SHADOW_ON_CLOTH, 0.18)
    # cast shadow on the paper
    for i in range(depth):
        a = (0.30, 0.13, 0.05)[i] if i < 3 else 0.03
        p.hline(x, x + w - 1, y + i, P.SHADOW_ON_PAPER, a)
        p.vline(x + i, y + (i + 1 if i == 0 else i), y + h - 1, P.SHADOW_ON_PAPER, a * 0.85)


def plate_mark(p: Plate, x, y, w, h, flat=P.PAPER_FLAT, margin: int = 2):
    """A display well: the paper pressed smooth by a printing plate.

    ``(x, y, w, h)`` is the rect that must stay one flat colour.  The flat area
    extends ``margin`` px beyond it; the impression's edge is a soft shadow on
    its top/left and a lit lip on its bottom/right."""
    X, Y, W_, H_ = x - margin, y - margin, w + 2 * margin, h + 2 * margin
    p.box(X, Y, W_, H_, flat)
    p.hline(X, X + W_ - 1, Y - 1, P.PAPER_DEEP, 0.85)
    p.vline(X - 1, Y, Y + H_ - 1, P.PAPER_DEEP, 0.70)
    p.px(X - 1, Y - 1, P.PAPER_DEEP, 0.35)
    p.hline(X, X + W_ - 1, Y + H_, P.PAPER_HI)
    p.vline(X + W_, Y, Y + H_ - 1, P.PAPER_HI)
    p.px(X + W_, Y + H_, P.PAPER_HI, 0.6)
    p.hline(X, X + W_ - 1, Y - 2, P.PAPER_SH, 0.35)


def card(p: Plate, x, y, w, h, window=None, tone="ivory", pressed=False,
         on="cloth", notch: bool = True, shadow: bool = True):
    """A piece of cut card stock lying on the surface.

    Normal: lifted -- a soft warm cast shadow down-right, bright cut edge on
    the top/left, core shadow on the bottom/right.  Pressed: the caller shifts
    the rect by (+1, +1); the shadow collapses to a hairline and the stock
    darkens a step."""
    sh_col = P.SHADOW_ON_CLOTH if on == "cloth" else P.SHADOW_ON_PAPER
    if shadow:
        if pressed:
            p.hline(x + 1, x + w, y + h, sh_col, 0.30)
            p.vline(x + w, y + 1, y + h, sh_col, 0.30)
        else:
            k = 0.50 if on == "cloth" else 0.30
            soft_shadow(p, x, y, w, h, sh_col, strength=k, spread=1, dx=2, dy=2)
            p.hline(x + 1, x + w, y + h, sh_col, k * 0.75)
            p.vline(x + w, y + 1, y + h, sh_col, k * 0.75)
    if tone == "ivory":
        base, hi, lo, lo2 = P.PAPER_FLAT, P.PAPER_HI, P.PAPER_SH, P.PAPER_DEEP
    elif tone == "manilla":
        base, hi, lo, lo2 = P.MANILLA, "#f6ecd6", "#d9c49c", "#c4ad84"
    else:  # kraft
        base, hi, lo, lo2 = P.KRAFT_MID, "#e4bc9c", P.KRAFT_DEEP, P.KRAFT_DARK
    lay_paper(p, x, y, w, h, window=window, base=base, tone=-7.0 if pressed else 0.0,
              gain=0.8)
    if pressed:
        p.hline(x, x + w - 1, y, lo2, 0.55)
        p.vline(x, y, y + h - 1, lo2, 0.45)
        p.hline(x + 1, x + w - 1, y + h - 1, hi, 0.5)
        p.vline(x + w - 1, y + 1, y + h - 1, hi, 0.4)
    else:
        p.hline(x, x + w - 1, y, hi)
        p.vline(x, y, y + h - 1, hi)
        p.hline(x + 1, x + w - 1, y + h - 1, lo)
        p.vline(x + w - 1, y + 1, y + h - 1, lo)
        p.px(x + w - 1, y + h - 1, lo2)
    if notch:   # the corners of hand-cut card are never perfectly square
        p.px(x + w - 1, y, lo, 0.55)
        p.px(x, y + h - 1, lo, 0.55)


def stitch_run(p: Plate, x0, y0, length, vertical=True, pitch=6, stitch=4,
               seed=0, thread=P.THREAD, on="cloth", phase=0):
    """A run of linen-thread stitches: each stitch a 2-px-wide strand with a lit
    flank, a twist mark, a dark puncture at each end and a cast shadow."""
    rng = np.random.RandomState(SEED + seed)
    sh = P.SHADOW_ON_CLOTH if on == "cloth" else P.SHADOW_ON_PAPER
    k = phase
    while k + stitch <= length:
        wob = int(rng.rand() < 0.22)
        for i in range(stitch):
            if vertical:
                xx, yy = x0 + (wob if i >= stitch // 2 else 0) * 0, y0 + k + i
                p.px(xx + 2, yy + 1, sh, 0.40)
                p.px(xx, yy, thread[2] if i not in (0, stitch - 1) else thread[1])
                p.px(xx + 1, yy, thread[1] if i % 2 == 0 else thread[0])
            else:
                xx, yy = x0 + k + i, y0
                p.px(xx + 1, yy + 2, sh, 0.40)
                p.px(xx, yy, thread[2] if i not in (0, stitch - 1) else thread[1])
                p.px(xx, yy + 1, thread[1] if i % 2 == 0 else thread[0])
        # punctures where the thread dives through the cloth
        if vertical:
            p.px(x0, y0 + k - 1, sh, 0.55)
            p.px(x0 + 1, y0 + k - 1, sh, 0.40)
            p.px(x0, y0 + k + stitch, sh, 0.60)
            p.px(x0 + 1, y0 + k + stitch, sh, 0.60)
        else:
            p.px(x0 + k - 1, y0, sh, 0.55)
            p.px(x0 + k - 1, y0 + 1, sh, 0.40)
            p.px(x0 + k + stitch, y0, sh, 0.60)
            p.px(x0 + k + stitch, y0 + 1, sh, 0.60)
        k += pitch + (1 if rng.rand() < 0.18 else 0) * 0


def wash_band(p: Plate, x, y, w, h, colours, seed=0, edge_dark=0.22, horizontal=True,
              lead: np.ndarray | None = None):
    """A band of gouache / ink wash.  ``colours`` is an (n, 3) array along the
    band's length (n == w if horizontal else h).  Pigment pools darker along
    the band's outer edges and the brush leaves a faint streak."""
    rng = np.random.RandomState(SEED + 77 + seed)
    if w <= 0 or h <= 0:
        return
    colours = np.asarray(colours, dtype=np.float32)
    if horizontal:
        body = np.repeat(colours[None, :w, :], h, axis=0)
    else:
        body = np.repeat(colours[:h, None, :], w, axis=1)
    alpha = np.full((h, w), 0.90, dtype=np.float32)
    streak = (rng.rand(h, 1) if horizontal else rng.rand(1, w)).astype(np.float32)
    body = body * (1.0 - 0.07 * (streak[..., None] - 0.5) * 2)
    shade = np.ones((h, w), dtype=np.float32)
    if horizontal:
        shade[0, :] -= edge_dark * 0.6
        shade[-1, :] -= edge_dark
    else:
        shade[:, 0] -= edge_dark * 0.6
        shade[:, -1] -= edge_dark
    body = body * shade[..., None]
    if lead is not None:
        alpha = alpha * lead
    p.paste(x, y, body, alpha=alpha)
