"""Walnut 76 -- palette ramps.

Every colour in the skin belongs to one of these ramps.  Ramps run shadow ->
highlight; shadows lean cooler / more saturated, highlights warmer / lighter.
"""

from __future__ import annotations

import numpy as np

# -- materials ---------------------------------------------------------------
WALNUT = ["#1e0f07", "#35190b", "#4f2810", "#6b3a18", "#8a5226", "#a96d38", "#c58a52"]
ALU = ["#5d5546", "#7d745f", "#9c927a", "#b9af95", "#d4cbb2", "#ece5d0", "#fbf7ea"]
GLASS = ["#050708", "#0b1012", "#121a1d"]
GLARE = "#2a3a3e"
TEAL = ["#062a2c", "#0f5e60", "#1fa6a0", "#55e0d2", "#c8fff6"]   # ghost dim mid bright core
RED = ["#5a0c08", "#c21e12", "#ff4a30"]
RED_CORE = "#ffc2b0"
PILOT = ["#3a1c04", "#a35a0c", "#ffb642", "#fff0c0"]
CHROME = ["#2b2f33", "#6e777f", "#c9d1d6", "#ffffff"]
PLASTIC = ["#0a0a0b", "#17181a", "#26282b", "#3a3d41"]

# engraving ink (black paint fill in an engraved groove) and its lit lower lip
INK = "#1b1812"
INK_SOFT = "#3a3428"
LIP = "#fbf7ea"

# silk-screen cream on black plastic
CREAM = "#d9d0b4"
CREAM_DIM = "#8f8870"

# the flat colours that the app composites dynamic things over
GLASS_FLAT = GLASS[0]          # marquee / kbps / khz / glyph cells / playlist wells
VIZ_BG = "#040607"             # visualiser well == viscolors()[0]
LIST_BG = "#070a0b"            # playlist NormalBG


def hex_to_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def ramp_lut(ramp: list[str], n: int = 256) -> np.ndarray:
    """(n, 3) float32 lookup table interpolating a ramp evenly."""
    cols = np.array([hex_to_rgb(c) for c in ramp], dtype=np.float32)
    pos = np.linspace(0.0, 1.0, len(cols))
    t = np.linspace(0.0, 1.0, n)
    out = np.stack([np.interp(t, pos, cols[:, k]) for k in range(3)], axis=1)
    return out.astype(np.float32)


def ramp_at(ramp: list[str], t: float) -> tuple[int, int, int]:
    lut = ramp_lut(ramp, 256)
    i = int(round(max(0.0, min(1.0, float(t))) * 255))
    return tuple(int(round(v)) for v in lut[i])  # type: ignore[return-value]


def level_colour(t: float) -> tuple[int, int, int]:
    """Gauge ladder colour along its travel: teal, turning amber then red over
    the last quarter."""
    if t < 0.74:
        return hex_to_rgb(TEAL[3])
    if t < 0.88:
        return hex_to_rgb(PILOT[2])
    return hex_to_rgb(RED[2])


def level_ghost(t: float) -> tuple[int, int, int]:
    if t < 0.74:
        return hex_to_rgb(TEAL[0])
    if t < 0.88:
        return hex_to_rgb("#2a1804")
    return hex_to_rgb("#2e0906")
