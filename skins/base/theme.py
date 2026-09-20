"""Base -- the reference Tokenamp skin.

A restrained dark-graphite hi-fi faceplate: a vertical gradient with fine
noise, crisp double bevels, recessed near-black display wells with a soft green
phosphor palette, small engraved micro-font labels, raised buttons with clear
icons, lamps that visibly light, and a green -> amber -> red heat ramp across
the 28 volume / balance / EQ frames.

This is the skin the app falls back to for any sheet a third-party skin is
missing, so it has to be complete and legible at 1x.  Everything it draws comes
from ``skinkit.theme.Theme``; the subclass below only sets the palette and
identity, which is exactly how an art skin should start.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from skinkit.theme import Theme


class BaseTheme(Theme):
    name = "Base"
    author = "Tokenamp"
    description = ("Dark graphite hi-fi faceplate with a green phosphor display. "
                   "The reference skin and the app's fallback for missing sheets.")
    seed = 11

    # -- faceplate ------------------------------------------------------
    sheet_filler = "#0c0f12"
    face_hi = "#464d56"
    face = "#353c44"
    face_lo = "#222830"
    edge_light = "#737f8d"
    edge_mid = "#525c69"
    edge_shadow = "#171b21"
    edge_black = "#0a0c0f"

    # -- displays -------------------------------------------------------
    well_bg = "#0a1512"
    well_rim = "#050907"
    viz_bg = "#061009"
    viz_dots = "#12271c"
    text_fg = "#7cf0a6"
    text_dim = "#3a7d5d"
    digit_on = "#8affb4"
    digit_off = None

    # -- buttons --------------------------------------------------------
    btn_face = "#3c434c"
    btn_hi = "#7c8794"
    btn_lo = "#161a1f"
    btn_inner_hi = "#4e5762"
    btn_inner_lo = "#262c34"
    icon = "#d6dee7"
    icon_dim = "#8d969f"

    # -- lamps and labels -----------------------------------------------
    lamp_on = "#65ff96"
    lamp_off = "#1d3a2b"
    lamp_alt_on = "#ffd25e"
    label = "#adb8c6"
    label_relief = "#080a0d"
    accent = "#5ee08b"

    # -- sliders --------------------------------------------------------
    groove_bg = "#13181d"
    groove_rim_hi = "#5d6672"
    groove_rim_lo = "#0b0e11"
    heat_cool = "#2ed257"
    heat_warm = "#e8d246"
    heat_hot = "#e34530"

    # -- title bars -----------------------------------------------------
    title_active_hi = "#4f5863"
    title_active_lo = "#2b3139"
    title_inactive_hi = "#3b414a"
    title_inactive_lo = "#262b32"
    title_text_on = "#d2ead9"
    title_text_off = "#6f7e76"
    title_grip_hi = "#606b77"
    title_grip_lo = "#1a1e24"

    # -- playlist -------------------------------------------------------
    pl_face = "#2f353d"
    pl_face_hi = "#3d444e"
    pl_list_bg = "#0a1512"


THEME = BaseTheme()
