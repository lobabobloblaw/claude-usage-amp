"""Walnut 76 -- a top-of-the-line 1976 stereo receiver, lovingly kept.

Oiled walnut end-cheeks, a brushed champagne-aluminium fascia, and across the
top one long black glass dial window whose legends glow teal from behind.  The
seek bar is the tuning dial and its thumb is the red tuning needle; the pilot
lamps are warm incandescent.  Its own marque: ``TOKENAMP - MODEL TA-76``.

Every painter hook of ``skinkit.theme.Theme`` is overridden by the four mixins
below, so nothing of the Base art survives.  This file only supplies the
identity, the handful of tokens the builder reads directly, and the three
hooks that have no home in a window module.

Module map (all inside this folder):
    w76_palette     ramps: walnut, champagne aluminium, glass, teal, needle red
    w76_materials   wood grain, brushed alu, glass, chrome, screws, jewels
    w76_common      engraving, silk-screen, cabinet cheeks, rail, glass panes
    w76_microfonts  TINY / PANEL / SERIF engraved faces
    w76_textfont    the teal VFD dot-matrix marquee face
    w76_digits      slanted VFD seven-segment numerals
    w76_plfont_data the Sessions-list humanist dial face
    w76_widgets     piano keys, switches, tuning dial, slide pots, beacons
    w76_main / w76_eq / w76_playlist   the three windows
"""

from __future__ import annotations

import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent))
sys.path.insert(0, str(_HERE))

from skinkit.theme import Theme  # noqa: E402

import w76_eq  # noqa: E402
import w76_main  # noqa: E402
import w76_palette as P  # noqa: E402
import w76_playlist  # noqa: E402
import w76_widgets  # noqa: E402


class Walnut76(w76_main.MainWindow, w76_eq.EqWindow, w76_playlist.PlaylistWindow,
               w76_widgets.Widgets, Theme):
    name = "Walnut 76"
    dist_name = "Walnut76"
    author = "Tokenamp"
    description = ("1976 walnut-and-champagne stereo receiver: oiled wood cheeks, brushed "
                   "aluminium fascia and a backlit teal dial behind black glass.")
    seed = 76

    # -- tokens the builder and the app read directly ---------------------
    # The mixins paint every sprite themselves and never read a Base colour
    # token, so these only have to describe the surfaces the app composites
    # its own pixels onto.
    sheet_filler = P.GLASS[0]
    face = P.ALU[3]
    face_hi = P.ALU[5]
    face_lo = P.ALU[1]
    btn_face = P.ALU[4]
    well_bg = P.GLASS_FLAT
    viz_bg = P.VIZ_BG
    viz_dots = "#07262a"
    text_fg = P.TEAL[3]
    text_dim = P.TEAL[1]
    digit_on = P.TEAL[4]
    pl_face = P.WALNUT[3]
    pl_list_bg = P.LIST_BG

    # -- hooks with no home in a window module ----------------------------
    def paint_time_frame(self, c) -> None:
        """No frame: the digits sit on the dial glass, and ``_dial_glass``
        has already drawn the pane, its chrome bezel and the colon."""

    def viscolors(self):
        """Teal at the base, aqua through the middle, near-white at the top,
        with needle-red peak caps -- the dial lit from behind."""
        out = [P.hex_to_rgb(P.VIZ_BG), P.hex_to_rgb(self.viz_dots)]

        # 2..17, top -> bottom: TEAL core -> bright -> mid -> dim
        bars = [P.TEAL[1], P.TEAL[2], P.TEAL[3], P.TEAL[4]]
        for i in range(16):
            out.append(P.ramp_at(bars, 1.0 - i / 15.0))

        # 18..22, oscilloscope, brightest first: bright aqua core falling off
        scope = [P.TEAL[1], P.TEAL[2], P.TEAL[3], P.TEAL[4]]
        for i in range(5):
            out.append(P.ramp_at(scope, 1.0 - i * 0.19))

        # 23, peak caps: the tuning needle
        out.append(P.hex_to_rgb(P.RED[2]))
        return [tuple(int(v) for v in c) for c in out]

    def readme(self) -> str:
        return ("Walnut 76\r\n=========\r\n\r\n"
                "A top-of-the-line 1976 stereo receiver, lovingly kept.  Oiled walnut\r\n"
                "cabinet cheeks, a brushed champagne-aluminium fascia and a long black\r\n"
                "glass dial window lit teal from behind, swept by a red tuning needle.\r\n"
                "TOKENAMP - MODEL TA-76 - SOLID STATE USAGE RECEIVER.\r\n\r\n"
                "Classic Winamp 2.x skin for Tokenamp, painted in code with skinkit.\r\n"
                "Typefaces (all drawn for this skin): a humanist dial face for the\r\n"
                "Sessions list (plfont), a teal VFD dot-matrix marquee face, slanted\r\n"
                "VFD seven-segment numerals, and engraved panel and micro caps.\r\n"
                "Author: Tokenamp\r\n")


THEME = Walnut76()
