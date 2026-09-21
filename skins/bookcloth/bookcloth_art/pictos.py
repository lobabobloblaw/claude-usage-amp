"""pictos -- letterpressed pictograms (transport, title buttons, indicators)."""

from __future__ import annotations

import numpy as np


def _m(art: str) -> np.ndarray:
    rows = art.strip("\n").split("\n")
    w = max(len(r) for r in rows)
    lut = {"#": 1.0, "+": 0.55, ":": 0.28}
    return np.array([[lut.get(k, 0.0) for k in r.ljust(w, ".")] for r in rows], dtype=np.float32)


PLAY = _m("""
#+.....
###+...
#####+.
#######
#####+.
###+...
#+.....
""")

PAUSE = _m("""
##..##
##..##
##..##
##..##
##..##
##..##
##..##
""")

STOP = _m("""
#######
#######
#######
#######
#######
#######
#######
""")

_TRI_L = _m("""
...+#
..###
+####
#####
+####
..###
...+#
""")

EJECT = _m("""
....#....
...###...
..#####..
.#######.
#########
.........
#########
#########
""")


def prev_icon() -> np.ndarray:
    bar = np.ones((7, 2), dtype=np.float32)
    gap = np.zeros((7, 1), dtype=np.float32)
    return np.concatenate([bar, gap, _TRI_L, _TRI_L], axis=1)


def next_icon() -> np.ndarray:
    return prev_icon()[:, ::-1]


def transport(which: str) -> np.ndarray:
    return {"previous": prev_icon(), "next": next_icon(), "play": PLAY, "pause": PAUSE,
            "stop": STOP, "eject": EJECT}[which]


# 5x5 title-bar pictograms (foil on cloth)
TITLE = {
    "options": _m("""
#####
.....
#####
.....
#####
"""),
    "minimize": _m("""
.....
.....
.....
.....
#####
"""),
    "shade": _m("""
#####
#####
.....
.....
.....
"""),
    "unshade": _m("""
#####
#...#
#...#
#...#
#####
"""),
    "close": _m("""
#...#
.#.#.
..#..
.#.#.
#...#
"""),
}

# 7x7 play-state pictograms (ink on the page)
STATE = {
    "playing": _m("""
#+.....
###+...
#####+.
#######
#####+.
###+...
#+.....
"""),
    "paused": _m("""
##...##
##...##
##...##
##...##
##...##
##...##
##...##
"""),
    "stopped": _m("""
#######
#######
##...##
##...##
##...##
#######
#######
"""),
}

# tiny shade-strip transport marks, 5 rows
MINI = {
    "previous": _m("""
#..#.
#.##.
####.
#.##.
#..#.
"""),
    "play": _m("""
#....
###..
#####
###..
#....
"""),
    "pause": _m("""
##.##
##.##
##.##
##.##
##.##
"""),
    "stop": _m("""
#####
#####
#####
#####
#####
"""),
    "next": _m("""
.#..#
.##.#
.####
.##.#
.#..#
"""),
    "eject": _m("""
..#..
.###.
#####
.....
#####
"""),
}
