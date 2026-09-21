"""Amethyst palette -- every colour in the skin belongs to one of these ramps.

Ramps run shadow -> highlight.  Shadows are hue-shifted cooler and more
saturated, highlights warmer and lighter (ART_DIRECTION point 5).
"""

from __future__ import annotations


def h(s: str) -> tuple[int, int, int, int]:
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), 255)


def ramp(*cols: str):
    return tuple(h(c) for c in cols)


def lerp(a, b, t: float):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3)) + (255,)


def sample(r, t: float):
    """Sample a ramp (tuple of colours) at t in 0..1, linear between steps."""
    t = 0.0 if t < 0 else 1.0 if t > 1 else t
    f = t * (len(r) - 1)
    i = min(int(f), len(r) - 2)
    return lerp(r[i], r[i + 1], f - i)


# -- the board ---------------------------------------------------------------
MASK = ramp("#0e0619", "#160a24", "#231038", "#32174f", "#432066", "#57307f", "#6d45a0")
POUR = ramp("#2c1550", "#3b2066", "#4b2a78", "#5a3a8c", "#6f4aa6", "#8a66c0")
FR4 = ramp("#3a3018", "#5e5030", "#8a7848", "#b8a468", "#d8c890")
GOLD = ramp("#3a2a04", "#5c4408", "#8f6b10", "#c4981e", "#e8c440", "#fff0a0")
SILK = ramp("#6f6a8a", "#9a94b4", "#b9b3cc", "#e9e6f2", "#ffffff")
TIN = ramp("#24282e", "#4a5058", "#6a7078", "#8a9098", "#a9b0b8", "#cdd3d9", "#f4f7fa")
EPOXY = ramp("#060608", "#0c0c0e", "#1a1b1f", "#2a2c32", "#3c3f47", "#565a64")
ETCH = h("#7c808a")

# -- displays ----------------------------------------------------------------
SEG_FACE = h("#160606")
SEG_FACE_HI = h("#220a0a")
SEG_GHOST = h("#3a0a08")
SEG_GHOST_HI = h("#4a100c")
SEG = ramp("#5a0c08", "#a81408", "#ff2a1a", "#ff6a50", "#ffb0a0", "#ffe4dc")
SEG_BODY = ramp("#8a8c90", "#b4b6b8", "#d8d9da")      # the module's grey-white plastic

LCD_FIELD = h("#a4bf1a")
LCD_SHADE = h("#8aa510")
LCD_DEEP = h("#6f8a0c")
LCD_GLOW = h("#d4ee5a")
LCD_PIXEL = h("#1c2808")
LCD_PIXEL_SOFT = h("#34440f")
LCD_GHOST = h("#97b216")
BEZEL = ramp("#060708", "#101114", "#1b1d22", "#2a2d34")

BAR_FACE = h("#08090b")

# -- SMD LEDs: off-lens -> body -> hot core -----------------------------------
LED_G = ramp("#062a0e", "#0a3a12", "#14a83c", "#38ff6a", "#c8ffd4", "#ffffff")
LED_A = ramp("#2a1a02", "#3a2604", "#c87a08", "#ffb020", "#ffe6a0", "#ffffff")
LED_R = ramp("#2a0404", "#3a0606", "#c01810", "#ff3324", "#ffb4a8", "#ffffff")
LED_B = ramp("#040c2a", "#06123a", "#1c50c8", "#4a8cff", "#c0dcff", "#ffffff")

# -- passives ----------------------------------------------------------------
CERAMIC = ramp("#5e4c30", "#8f7750", "#b89868", "#d8bc8c", "#f0dcb4")
TANT = ramp("#6a4406", "#a06a0c", "#d89a1e", "#f4c04a", "#ffe08a")
RES = ramp("#050506", "#0e0e10", "#1c1c20", "#2c2c32")
CAN = ramp("#30343a", "#5a6068", "#8a9098", "#b8bec6", "#e6eaee")    # electrolytic top
STICKER = ramp("#a8a498", "#d4d0c4", "#f2efe6")
CAP = ramp("#050506", "#0e0f12", "#1c1e24", "#2e3138", "#464a54", "#6c717c")  # knobs / plungers
RED_CAP = ramp("#2a0504", "#4a0a08", "#7a100c", "#c02018", "#e84a3a", "#ffa898")
BLUE_POT = ramp("#0a1c4a", "#12307a", "#1c48b0", "#3a6ee0", "#8ab0ff")


def led_ramp(kind: str):
    return {"g": LED_G, "a": LED_A, "r": LED_R, "b": LED_B}[kind]
