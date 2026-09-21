"""Bulkhead -- a control module unbolted from the engineering deck of a
long-haul freighter and put to work monitoring token flow.

Heavy gunmetal plate, paint chipped back to bare steel, oil-dark seams, hazard
striping, stencilled inventory codes, and an amber phosphor CRT behind thick
glass.  Every painter hook of ``skinkit.theme.Theme`` is overridden; nothing of
the Base art remains.

Module map (all inside this folder):
    bh_palette    ramps
    bh_materials  plate / steel / rubber / paint / hazard, relief, fasteners
    bh_type       MICRO 3x5, LEGEND 4x5, STENCIL 5x7, CRT 5x6 faces
    bh_plfont     the Sessions-list typeface
    bh_digits     amber CRT time numerals
    bh_parts      frames, CRT glass, rail, keycaps, toggles, ladders, knobs ...
    bh_main / bh_eq / bh_playlist   the three windows
    bh_field      the Token Flow frame (gen.bmp)
"""

from __future__ import annotations

import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent))
sys.path.insert(0, str(_HERE))

from skinkit.theme import Theme  # noqa: E402

import bh_eq  # noqa: E402
import bh_field  # noqa: E402
import bh_main  # noqa: E402
import bh_palette as P  # noqa: E402
import bh_playlist  # noqa: E402


class Bulkhead(bh_main.MainMixin, bh_eq.EqMixin, bh_playlist.PlaylistMixin,
               bh_field.FieldMixin, Theme):
    name = "Bulkhead"
    author = "Tokenamp"
    description = ("Engineering-deck control module: worn gunmetal plate, chipped safety "
                   "orange, hazard striping and an amber phosphor CRT.")
    seed = 404

    # palette tokens the builder / base class read directly
    sheet_filler = P.hexs(P.GUN[0])
    face = P.hexs(P.GUN[3])
    face_hi = P.hexs(P.GUN[4])
    face_lo = P.hexs(P.GUN[2])
    btn_face = P.hexs(P.STEEL[2])
    well_bg = P.hexs(P.AMBER_WELL)
    viz_bg = P.hexs(P.AMBER_WELL)
    viz_dots = P.hexs(P.AMBER_GHOST)
    text_fg = P.hexs(P.AMBER_BRIGHT)
    text_dim = P.hexs(P.AMBER_LOW)
    digit_on = P.hexs(P.AMBER_BRIGHT)
    pl_face = P.hexs(P.GUN[3])
    pl_list_bg = P.hexs(P.AMBER_WELL)

    def readme(self) -> str:
        return ("Bulkhead\r\n========\r\n\r\n"
                "A control module unbolted from the engineering deck of a long-haul\r\n"
                "freighter and put to work monitoring token flow.  Gunmetal plate, chipped\r\n"
                "safety orange, hazard striping, stencilled inventory codes and an amber\r\n"
                "phosphor CRT behind thick glass.\r\n\r\n"
                "Classic Winamp 2.x skin for Tokenamp, painted in code with skinkit.\r\n"
                "Typefaces (all drawn for this skin): MU/TH 8 list face (plfont), CRT 5x6\r\n"
                "marquee face, amber seven-segment tube numerals, 5x7 DIN stencil,\r\n"
                "4x5 key legends, 3x5 inventory micro caps.\r\n"
                "Author: Tokenamp\r\n")


THEME = Bulkhead()
