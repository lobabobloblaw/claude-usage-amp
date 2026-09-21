"""Bookcloth -- the player as a hand-bound stationery object.

A cover wrapped in clay-orange book cloth with the weave showing, paper panels
let into the boards with bevelled cut edges, labels letterpressed into the
stock so they cast a deboss shadow, linen thread stitching, and slate ink that
has bled a hair into the fibres.  The only light skin in the set.

The art lives in ``bookcloth_art``; this file maps the skinkit hooks onto it
and supplies the tokens, the palettes and the readme.

Fan-made tribute skin.  It evokes a warm, humane, hand-made visual language
through materials, palette, type and its own hand-drawn burst motif; it does
not reproduce anyone's logo or wordmark.
"""

from __future__ import annotations

import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent))
sys.path.insert(0, str(_HERE))

from skinkit.theme import Theme  # noqa: E402

from bookcloth_art import palette as P  # noqa: E402
from bookcloth_art.win_eq import EqMixin  # noqa: E402
from bookcloth_art.win_field import FieldMixin  # noqa: E402
from bookcloth_art.win_main import MainMixin  # noqa: E402
from bookcloth_art.win_playlist import PlaylistMixin  # noqa: E402
from bookcloth_art.win_widgets import WidgetMixin  # noqa: E402


class Bookcloth(MainMixin, WidgetMixin, EqMixin, PlaylistMixin, FieldMixin, Theme):
    name = "Bookcloth"
    author = "Tokenamp"
    description = ("Hand-bound in clay-orange book cloth and ivory laid paper, with "
                   "letterpress labels and slate ink. The one light skin.")
    seed = 5101

    # -- tokens the builder and the app read directly ---------------------
    # Every sprite is painted by the mixins; these describe the surfaces the
    # app composites its own pixels onto, and the sheet filler behind them.
    sheet_filler = P.PAPER_DEEP
    face = P.CLAY_DEEP
    face_hi = P.CLAY_LIGHT
    face_lo = P.CLAY_DARK
    btn_face = P.PAPER_FLAT
    well_bg = P.PAPER_FLAT
    viz_bg = P.PAPER_FLAT
    viz_dots = P.PAPER_SH
    text_fg = P.INK_BODY
    text_dim = P.INK_GREY
    digit_on = P.INK_CORE
    label = P.INK_BODY
    accent = P.CLAY_DEEP
    pl_face = P.CLAY_DEEP
    pl_list_bg = P.PAPER_FLAT

    # -- data -------------------------------------------------------------
    def viscolors(self):
        """Strokes of gouache on the page: kraft at the foot rising through
        clay to the deep book-cloth note, with slate-ink peak caps."""
        out = [P.rgb(P.PAPER_FLAT), P.rgb(P.PAPER_SH)]
        bars = (P.CLOTH[0], P.CLOTH[1], P.CLAY_DEEP, P.CLAY, P.KRAFT[2], P.KRAFT[3])
        for i in range(16):          # 2..17, top -> bottom
            out.append(P.ramp(bars, i / 15.0))
        scope = (P.INK_CORE, P.INK_BODY, P.INK_SOFT, P.INK_GREY, P.INK_PALE)
        for i in range(5):           # 18..22, brightest (darkest ink) first
            out.append(P.rgb(scope[i]))
        out.append(P.rgb(P.INK_CORE))                                # 23 peak caps
        return [tuple(int(round(v)) for v in c[:3]) for c in out]

    def readme(self) -> str:
        return ("Bookcloth\r\n=========\r\n\r\n"
                "The player as a hand-bound stationery object: a cover wrapped in\r\n"
                "clay-orange book cloth, paper panels let into the boards, labels\r\n"
                "letterpressed into the stock, linen thread stitching and slate ink\r\n"
                "that has bled a hair into the fibres.  The equaliser is a page from a\r\n"
                "lab notebook; the Sessions window is a ledger card.\r\n\r\n"
                "Classic Winamp 2.x skin for Tokenamp, painted in code with skinkit.\r\n"
                "Typefaces (all drawn for this skin): a literary old-style serif for\r\n"
                "the Sessions list (plfont), a 5x6 letterpress proofing face for the\r\n"
                "marquee, 9x13 Clarendon time figures, and five-row small capitals.\r\n"
                "Author: Tokenamp\r\n\r\n"
                "Fan-made tribute skin. Not affiliated with or endorsed by Anthropic.\r\n")


THEME = Bookcloth()
