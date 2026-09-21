"""Amethyst -- the player with its case off.

A bare development board in deep purple solder mask with ENIG gold: red
seven-segment time, a yellow-green STN character LCD for text, an LED bargraph
for token flow, tact switches, slide switches, slide pots and LED ladders.
All art lives in ``amethyst_art``; this file only maps skinkit hooks onto it.
"""

from __future__ import annotations

import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent))
sys.path.insert(0, str(_HERE))

from skinkit.theme import Theme                                   # noqa: E402

from amethyst_art import palette as P                             # noqa: E402
from amethyst_art import displays, main_bg, main_widgets as MW    # noqa: E402
from amethyst_art import eq_window as EQ, pl_window as PL         # noqa: E402
from amethyst_art.pen import Pen                                  # noqa: E402


def _hex(c):
    return "#%02X%02X%02X" % tuple(c[:3])


class Amethyst(Theme):
    name = "Amethyst"
    author = "Tokenamp"
    description = ("Case-off development board: purple solder mask and ENIG gold, red "
                   "seven-segment time, an STN character LCD and LED ladders.")
    seed = 41

    # tokens the builder itself reads
    sheet_filler = _hex(P.MASK[0])
    face = _hex(P.MASK[3])
    btn_face = _hex(P.CAP[2])
    pl_face = _hex(P.MASK[3])
    digit_on = _hex(displays.DIGIT_ON)

    # ---- main ----------------------------------------------------------
    def paint_main_background(self, c): main_bg.paint(c, self)
    def paint_time_frame(self, c): pass
    def paint_about_logo(self, c): pass
    def digit_background(self): return P.SEG_FACE
    def text_background(self): return P.LCD_FIELD
    def paint_title_bar(self, c, active, variant): MW.title_bar(c, active, variant)
    def paint_title_button(self, c, which, pressed): MW.title_button(c, which, pressed)

    def paint_clutter_bar(self, c, pressed=None, disabled=False):
        MW.clutter(c, pressed.upper() if pressed else None, disabled)

    def paint_transport(self, c, which, pressed): MW.transport(c, which, pressed)
    def paint_shuffle(self, c, pressed, selected): MW.shuffle(c, pressed, selected)
    def paint_repeat(self, c, pressed, selected): MW.repeat(c, pressed, selected)
    def paint_eq_toggle(self, c, pressed, selected): MW.small_toggle(c, pressed, selected, "EQ", "a")
    def paint_pl_toggle(self, c, pressed, selected): MW.small_toggle(c, pressed, selected, "PL", "a")
    def paint_posbar_background(self, c): MW.posbar(c)
    def paint_posbar_thumb(self, c, pressed): MW.posbar_thumb(c, pressed)
    def paint_volume_frame(self, c, i): MW.gauge(c, i, "SESSION", 14)
    def paint_balance_frame(self, c, i): MW.gauge(c, i, "WEEK", 7)
    def paint_volume_thumb(self, c, pressed): MW.gauge_thumb(c, pressed)
    def paint_balance_thumb(self, c, pressed): MW.gauge_thumb(c, pressed)
    def paint_mono(self, c, on): MW.lamp(c, "LOCAL", "a", on)
    def paint_stereo(self, c, on): MW.lamp(c, "LIVE", "g", on)
    def paint_play_state(self, c, state): MW.play_state(c, state)
    def paint_work_indicator(self, c, working): MW.work_led(c, working)
    def paint_digit(self, c, d): displays.digit(c, d)
    def paint_glyph(self, c, ch): displays.glyph(c, ch)
    def paint_shade_position_background(self, c): MW.shade_pos_bg(c)
    def paint_shade_position_thumb(self, c, which): MW.shade_pos_thumb(c, which)

    # ---- data ------------------------------------------------------------
    def viscolors(self):
        out = [P.BAR_FACE[:3], (22, 26, 30)]
        # 16 bar rows, top -> bottom: red, amber, then a long run of green
        for i in range(16):
            r = P.LED_R if i < 3 else P.LED_A if i < 7 else P.LED_G
            k = (i - 0) / 2.0 if i < 3 else (i - 3) / 3.0 if i < 7 else (i - 7) / 8.0
            out.append(P.lerp(r[3], r[2], min(1.0, k * 0.55))[:3])
        g = P.LED_G
        out += [g[4][:3], g[3][:3], P.lerp(g[3], g[2], 0.5)[:3], g[2][:3], P.lerp(g[2], g[1], 0.5)[:3]]
        out.append((214, 232, 255))
        return [tuple(int(v) for v in c) for c in out]

    def pledit_colours(self):
        return {"Normal": "#34440F", "Current": "#0B1203", "NormalBG": _hex(P.LCD_FIELD),
                "SelectedBG": "#86A012", "Font": "Arial"}

    def readme(self):
        return ("Amethyst\n========\n\n" + self.description + "\n\n"
                "A classic Winamp 2.x skin for Tokenamp, painted in code with skinkit.\n"
                "Board: TA-5100 REV C.  MADE ON EARTH.\n")

    # ---- equaliser ---------------------------------------------------------
    def paint_eq_background(self, c): EQ.paint(c, self)
    def paint_eq_title_bar(self, c, active): EQ.title_bar(c, active)
    def paint_eq_close(self, c, pressed): MW.title_button(c, "close", pressed)
    def paint_eq_on(self, c, pressed, selected): EQ.toggle(c, pressed, selected, "ON", "g")
    def paint_eq_auto(self, c, pressed, selected): EQ.toggle(c, pressed, selected, "AUTO", "a")
    def paint_eq_presets(self, c, pressed): EQ.presets(c, pressed)
    def paint_eq_slider_frame(self, c, i): EQ.slider_frame(c, i)
    def paint_eq_thumb(self, c, pressed): EQ.thumb(c, pressed)
    def paint_eq_graph_background(self, c): EQ.graph_bg(c)
    def eq_graph_line_colours(self): return EQ.line_colours()
    def paint_eq_preamp_line(self, c): EQ.preamp_line(c)

    # ---- playlist ----------------------------------------------------------
    def paint_pl_top_left(self, c, active): PL.top_left(c, active)
    def paint_pl_title(self, c, active): PL.title(c, active)
    def paint_pl_top_tile(self, c, active): PL.top_tile(c, active)
    def paint_pl_top_right(self, c, active): PL.top_right(c, active)
    def paint_pl_left_tile(self, c): PL.left_tile(c)
    def paint_pl_right_tile(self, c): PL.right_tile(c)
    def paint_pl_bottom_tile(self, c): PL.bottom_tile(c)
    def paint_pl_bottom_left(self, c): PL.bottom_left(c)
    def paint_pl_bottom_right(self, c): PL.bottom_right(c)
    def paint_pl_visualizer_background(self, c): PL.vis_bg(c)
    def paint_pl_scroll_handle(self, c, pressed): PL.scroll_handle(c, pressed)
    def paint_pl_close(self, c, pressed): MW.title_button(c, "close", pressed)
    def paint_pl_collapse(self, c, pressed): MW.title_button(c, "shade", pressed)

    # ---- plfont --------------------------------------------------------------
    def pl_font_cell(self): return displays.PL_CELL
    def paint_pl_font_glyph(self, c, ch): displays.pl_glyph(c, ch)

    def pl_font_metrics(self):
        return {"Monospace": 1, "Spacing": 0, "SpaceWidth": 6, "RowHeight": 10, "OffsetY": 0}


THEME = Amethyst()
