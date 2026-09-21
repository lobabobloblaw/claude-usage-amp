"""Bulkhead -- palette ramps.

Every colour on the skin comes from one of these ramps (or is a blend of two
neighbouring steps of one).  Ramps run shadow -> highlight; shadows lean cool
and saturated, highlights lean warm and light.
"""

from __future__ import annotations

import numpy as np


def hx(s: str) -> tuple[int, int, int]:
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16))


# -- gunmetal plate (8 steps) -------------------------------------------------
GUN = [hx(c) for c in ("#0d1013", "#181d22", "#252c33", "#343d46",
                       "#47525c", "#5e6b76", "#7d8b96", "#a7b3bb")]
# -- bare worn steel: chips, exposed edges, machined parts ----------------------
STEEL = [hx(c) for c in ("#2b3138", "#424b53", "#59626a", "#808b93",
                         "#aab4ba", "#d7dee2", "#f2f6f7")]
# -- safety orange paint ------------------------------------------------------
ORANGE = [hx(c) for c in ("#2e1206", "#4a1f08", "#7a330c", "#b04e10",
                          "#e06a14", "#ff8c2a", "#ffb060")]
# -- hazard yellow / black ----------------------------------------------------
HAZ_Y = [hx(c) for c in ("#6e5208", "#b88a0c", "#e8b618", "#ffd84a")]
HAZ_K = [hx(c) for c in ("#0e0e0d", "#1a1a18", "#2a2925", "#3a3832")]
# -- amber phosphor -----------------------------------------------------------
AMBER_WELL = hx("#0a0602")
AMBER_SCAN = hx("#0f0903")       # lighter scanline row of the static glass
AMBER_GHOST = hx("#1c0f02")
AMBER_GHOST2 = hx("#2a1603")
AMBER_DIM = hx("#5a2f04")
AMBER_LOW = hx("#8a4a06")
AMBER_MID = hx("#c46a08")
AMBER_BRIGHT = hx("#ffa91f")
AMBER_CORE = hx("#ffe2a0")
AMBER_WHITE = hx("#fff3d2")
AMBER = [AMBER_WELL, AMBER_GHOST, AMBER_DIM, AMBER_LOW, AMBER_MID,
         AMBER_BRIGHT, AMBER_CORE, AMBER_WHITE]
GLASS_GREEN = hx("#050a07")      # green-black at the rim of the tube
# -- lamps ----------------------------------------------------------------------
RED = [hx(c) for c in ("#1c0303", "#3a0606", "#7a100a", "#c8241a",
                       "#ff3b24", "#ff8a70", "#ffc0b0")]
GREEN = [hx(c) for c in ("#04160a", "#07280e", "#0f5a24", "#1fb04a",
                         "#3dff6e", "#96ffb0", "#d0ffe0")]
LAMP_AMBER = [hx(c) for c in ("#1c0f02", "#3a1e03", "#7a4206", "#c46a08",
                              "#ffa91f", "#ffd27a", "#fff0c8")]
# -- rubber / gasket ------------------------------------------------------------
RUBBER = [hx(c) for c in ("#050607", "#08090a", "#121416", "#1e2124",
                          "#2b2f33", "#3c4146")]
# -- legend paint (yellowed white) ---------------------------------------------
LEGEND = [hx(c) for c in ("#5c5842", "#8e8868", "#c4bc96", "#e6dfba", "#fbf6dc")]
# -- oil / grime ----------------------------------------------------------------
OIL = hx("#0b0a08")
SHADOW = hx("#07090b")
HILITE = hx("#dfe7ea")


def lut(stops, n: int = 256) -> np.ndarray:
    """(n, 3) float32 lookup interpolated through equally spaced ``stops``."""
    stops = np.asarray(stops, dtype=np.float32)
    k = len(stops)
    t = np.linspace(0, k - 1, n)
    i0 = np.clip(np.floor(t).astype(int), 0, k - 2)
    f = (t - i0)[:, None]
    return stops[i0] * (1 - f) + stops[i0 + 1] * f


GUN_LUT = lut(GUN)
STEEL_LUT = lut(STEEL)
ORANGE_LUT = lut(ORANGE)
RUBBER_LUT = lut(RUBBER)
HAZ_Y_LUT = lut(HAZ_Y)
HAZ_K_LUT = lut(HAZ_K)


def at(ramp_lut: np.ndarray, t: float) -> tuple[int, int, int]:
    i = int(round(max(0.0, min(1.0, t)) * (len(ramp_lut) - 1)))
    r, g, b = ramp_lut[i]
    return (int(round(r)), int(round(g)), int(round(b)))


def mixc(a, b, t: float) -> tuple[int, int, int]:
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def hexs(c) -> str:
    return "#%02X%02X%02X" % (int(c[0]), int(c[1]), int(c[2]))
