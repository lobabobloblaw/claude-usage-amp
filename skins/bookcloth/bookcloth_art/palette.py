"""Bookcloth palette -- every colour in the skin belongs to one of these ramps.

Ramps run shadow -> highlight.  Shadows lean cooler / more saturated, highlights
warmer / lighter, as the art direction asks.  ``ramp(stops, t)`` interpolates a
ramp at ``t`` in 0..1 so materials can be shaded by a scalar field.
"""

from __future__ import annotations

import numpy as np


def rgb(h: str) -> np.ndarray:
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float32)


def hx(v) -> str:
    r, g, b = [int(max(0, min(255, round(float(x))))) for x in v[:3]]
    return f"#{r:02x}{g:02x}{b:02x}"


def mix(a, b, t: float) -> np.ndarray:
    a = rgb(a) if isinstance(a, str) else np.asarray(a, dtype=np.float32)
    b = rgb(b) if isinstance(b, str) else np.asarray(b, dtype=np.float32)
    return a + (b - a) * float(t)


# -- ramps -------------------------------------------------------------------
PAPER = ("#c9c3ae", "#ddd8c4", "#e8e6dc", "#f0eee6", "#faf9f5")
INK = ("#141413", "#262624", "#3d3d3a", "#5e5d59", "#87867f", "#b0aea5")
CLOTH = ("#7a3b26", "#9c4a2f", "#c15f3c", "#d97757", "#e8957a", "#f3bfa8")
KRAFT = ("#a67c52", "#c4966c", "#d4a27f", "#ebdbbc")
BLUE = ("#4f7fae", "#6a9bcc", "#a9c4e0")
GREEN = ("#5a6b44", "#788c5d", "#a7b68e")
THREAD = ("#9c8f6e", "#cfc4a2", "#e8e0c8")

# -- named tones -------------------------------------------------------------
PAPER_FLAT = "#f0eee6"      # every display well, glyph cell and list background
PAPER_HI = "#faf9f5"
PAPER_LO = "#e8e6dc"
PAPER_SH = "#ddd8c4"
PAPER_DEEP = "#c9c3ae"
GLINT = "#ffffff"           # rare fibre glints only

INK_CORE = "#262624"
INK_BODY = "#3d3d3a"
INK_SOFT = "#5e5d59"
INK_GREY = "#87867f"
INK_PALE = "#b0aea5"
PENCIL = "#b0aea5"

CLAY = "#d97757"
CLAY_DEEP = "#c15f3c"
CLAY_DARK = "#9c4a2f"
CLAY_SHADOW = "#7a3b26"
CLAY_LIGHT = "#e8957a"
CLAY_PALE = "#f3bfa8"

MANILLA = "#ebdbbc"
KRAFT_MID = "#d4a27f"
KRAFT_DEEP = "#c4966c"
KRAFT_DARK = "#a67c52"

# warm shadow tints (never neutral black)
SHADOW_ON_PAPER = "#5e5d59"
SHADOW_ON_CLOTH = "#5a2818"   # a deeper note of the cloth's own hue
BOARD_CORE = "#d9c9a6"        # grey-board core seen in a cut edge (kraft family)
BOARD_CORE_HI = "#ebdbbc"


def ramp(stops, t):
    """Interpolate a colour ramp.  ``t`` may be a scalar or an array (0..1);
    returns float RGB with a trailing axis of 3."""
    cols = np.stack([rgb(s) for s in stops])          # (n, 3)
    n = len(stops)
    tt = np.clip(np.asarray(t, dtype=np.float32), 0.0, 1.0) * (n - 1)
    i0 = np.clip(np.floor(tt).astype(int), 0, n - 2)
    f = (tt - i0)[..., None]
    return cols[i0] * (1 - f) + cols[i0 + 1] * f


def heat(t: float) -> np.ndarray:
    """The gauge wash: accent green -> kraft -> clay orange -> deep red clay."""
    stops = ((0.00, GREEN[1]), (0.22, GREEN[2]), (0.42, KRAFT[2]), (0.62, CLAY),
             (0.82, CLAY_DEEP), (1.00, "#a8412c"))
    t = max(0.0, min(1.0, float(t)))
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if t <= t1:
            return mix(c0, c1, (t - t0) / max(1e-6, t1 - t0))
    return rgb(stops[-1][1])
