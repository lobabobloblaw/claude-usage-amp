"""builder -- turns a Theme into a complete classic skin.

Build order (this is the whole seamlessness story):

1. ``paint_main_background`` fills a pristine 275x116 ``main_bg``.
2. Every main-window widget gets a canvas that is a **copy of ``main_bg`` at
   that widget's layout rect**, with ``origin`` set to the rect's top-left.
   Its *normal* state is painted, kept as a sprite, and baked back into
   ``main.bmp`` at the same rect -- so ``main.bmp`` shows the window idle,
   exactly as a hand-made skin would.
3. Every other state starts again from a fresh copy of ``main_bg`` at the same
   rect, so pressed / selected art composites over the identical underlay and
   can never disagree with the baked version by a pixel.
4. Thumbs (position / volume / balance / EQ) float over frames rather than sit
   in the background, so they start from their own neutral fill and must end
   up fully opaque.
5. The EQ window repeats 1-4 with ``eq_bg``.  The playlist is tiled, so its
   pieces start from a flat plate fill; tiles must be invariant along the axis
   they repeat on.

Unused sheet area is filled with ``theme.sheet_filler``.
"""

from __future__ import annotations

import io
import os
import zipfile
from pathlib import Path
from typing import Any, Callable, Iterable

import numpy as np

from . import spec
from .canvas import Canvas, parse_colour
from .spec import Rect

__all__ = ["build_skin", "BuildResult", "skins_root", "dist_dir"]

#: Fixed timestamp stamped on every entry of a built ``.wsz``, so the archive
#: is reproducible.  Winamp 2.6 shipped in June 1999.
WSZ_TIMESTAMP = (1999, 6, 1, 0, 0, 0)


def skins_root() -> Path:
    """The ``skins/`` directory (the parent of this package)."""
    return Path(__file__).resolve().parent.parent


def dist_dir() -> Path:
    return skins_root() / "dist"


class BuildResult:
    """What a build produced."""

    def __init__(self, theme, out_dir: Path, wsz: Path, sheets: dict[str, Canvas],
                 files: list[Path]):
        self.theme = theme
        self.out_dir = out_dir
        self.wsz = wsz
        self.sheets = sheets
        self.files = files

    def __repr__(self) -> str:  # pragma: no cover
        return f"<BuildResult {self.theme.name} -> {self.wsz}>"


# ---------------------------------------------------------------------------

class _Builder:
    def __init__(self, theme):
        self.t = theme
        self.filler = theme.sheet_filler
        self.sheets: dict[str, Canvas] = {}
        for name in spec.sheet_names():
            w, h = spec.sheet_size(name)
            self.sheets[name] = Canvas(w, h, fill=self.filler)
            self.sheets[name].a[:, :, 3] = 255

    # -- plumbing ------------------------------------------------------
    def place(self, sheet: str, sprite_name: str, c: Canvas) -> None:
        """Copy a finished sprite into its sheet slot, byte for byte."""
        r = spec.sprite(sheet, sprite_name)
        if (c.w, c.h) != (r.w, r.h):
            raise ValueError(
                f"skinkit.builder: painter for {sprite_name} produced {c.w}x{c.h} "
                f"but {spec.sheet_file(sheet)} needs {r.w}x{r.h} at {r}")
        self.sheets[sheet].sub(r).a[:, :] = c.opaque(self.filler).a

    def place_rect(self, sheet: str, r: Rect, c: Canvas) -> None:
        if (c.w, c.h) != (r.w, r.h):
            raise ValueError(f"skinkit.builder: sprite is {c.w}x{c.h}, slot {r} is {r.w}x{r.h}")
        self.sheets[sheet].sub(r).a[:, :] = c.opaque(self.filler).a

    @staticmethod
    def cut(bg: Canvas, r: Rect, window: str | None = None) -> Canvas:
        """A fresh copy of the background at ``r``, origin and window set."""
        v = bg.crop(r.x, r.y, r.w, r.h)
        if window is not None:
            v.window = window
        return v

    @staticmethod
    def bake(dst: Canvas, r: Rect, c: Canvas) -> None:
        dst.sub(r.x, r.y, r.w, r.h).blit(c, 0, 0, alpha=True)

    def free(self, w: int, h: int, origin=(0, 0), window: str | None = None,
             fill=None) -> Canvas:
        """A free-floating canvas (thumbs, digits, glyphs)."""
        return Canvas(w, h, origin=origin, window=window,
                      fill=self.filler if fill is None else fill)

    # -- main window ---------------------------------------------------
    def build_main(self) -> None:
        t = self.t
        L = lambda k: spec.lrect("main", k)  # noqa: E731

        main_bg = Canvas(*spec.window_size("main"), origin=(0, 0), window="main",
                         fill=t.face)
        t.paint_main_background(main_bg)
        main_bg.a[:, :, 3] = 255
        self.main_bg = main_bg
        sheet_main = main_bg.copy()

        # ---- title bars and their buttons ----------------------------
        tb_rect = L("titleBar")
        variants = [
            ("MAIN_TITLE_BAR_SELECTED", True, "main", "main"),
            ("MAIN_TITLE_BAR", False, "main", "main"),
            ("MAIN_SHADE_BACKGROUND_SELECTED", True, "shade", "shade"),
            ("MAIN_SHADE_BACKGROUND", False, "shade", "shade"),
            ("MAIN_EASTER_EGG_TITLE_BAR_SELECTED", True, "easter", "main"),
            ("MAIN_EASTER_EGG_TITLE_BAR", False, "easter", "main"),
        ]
        painted: dict[str, Canvas] = {}
        for sprite_name, active, variant, win in variants:
            c = self.cut(main_bg, tb_rect, window=win)
            c.origin = (0, 0)
            t.paint_title_bar(c, active, variant)
            painted[sprite_name] = c

        # buttons: underlay is the ACTIVE main title bar, so one sprite pair
        # sits correctly on every variant (see the note in paint_title_bar).
        active_tb = painted["MAIN_TITLE_BAR_SELECTED"]
        btn_layout = {
            "options": ("MAIN_OPTIONS_BUTTON", "MAIN_OPTIONS_BUTTON_DEPRESSED", "optionsButton"),
            "minimize": ("MAIN_MINIMIZE_BUTTON", "MAIN_MINIMIZE_BUTTON_DEPRESSED", "minimizeButton"),
            "close": ("MAIN_CLOSE_BUTTON", "MAIN_CLOSE_BUTTON_DEPRESSED", "closeButton"),
            "shade": ("MAIN_SHADE_BUTTON", "MAIN_SHADE_BUTTON_DEPRESSED", "shadeButton"),
            "unshade": ("MAIN_SHADE_BUTTON_SELECTED", "MAIN_SHADE_BUTTON_SELECTED_DEPRESSED",
                        "shadeButton"),
        }
        normals: dict[str, Canvas] = {}
        for which, (n_name, p_name, lkey) in btn_layout.items():
            r = L(lkey)
            for pressed, sname in ((False, n_name), (True, p_name)):
                c = self.cut(active_tb, r, window="main")
                c.origin = (r.x, r.y)
                t.paint_title_button(c, which, pressed)
                self.place("titlebar", sname, c)
                if not pressed:
                    normals[which] = c

        # the shade strip's mini position bar is baked into both shade variants
        # at its layout rect, exactly like the title buttons
        shade_pos = spec.lrect("shade", "position")
        c = self.free(shade_pos.w, shade_pos.h, origin=(shade_pos.x, shade_pos.y),
                      window="shade", fill=t.face)
        t.paint_shade_position_background(c)
        self.place("titlebar", "MAIN_SHADE_POSITION_BACKGROUND", c)
        shade_pos_normal = c

        for sprite_name, active, variant, win in variants:
            tb = painted[sprite_name]
            for which, (_n, _p, lkey) in btn_layout.items():
                if variant == "shade" and which == "shade":
                    continue          # a shaded window shows the *unshade* button
                if variant != "shade" and which == "unshade":
                    continue
                self.bake(tb, L(lkey), normals[which])
            if variant == "shade":
                self.bake(tb, shade_pos, shade_pos_normal)
            self.place("titlebar", sprite_name, tb)
        self.bake(sheet_main, tb_rect, painted["MAIN_TITLE_BAR_SELECTED"])

        # ---- clutter bar ---------------------------------------------
        cb = L("clutterBar")
        c = self.cut(main_bg, cb, window="main")
        t.paint_clutter_bar(c, None, False)
        self.place("titlebar", "MAIN_CLUTTER_BAR_BACKGROUND", c)
        self.bake(sheet_main, cb, c)
        c = self.cut(main_bg, cb, window="main")
        t.paint_clutter_bar(c, None, True)
        self.place("titlebar", "MAIN_CLUTTER_BAR_BACKGROUND_DISABLED", c)
        for letter in spec.clutter_letters():
            c = self.cut(main_bg, cb, window="main")
            t.paint_clutter_bar(c, letter, False)
            self.place_rect("titlebar", spec.clutter_column(letter), c)

        # ---- shade-strip thumbs --------------------------------------
        pos = shade_pos
        for which, sname in (("left", "MAIN_SHADE_POSITION_THUMB_LEFT"),
                             ("center", "MAIN_SHADE_POSITION_THUMB"),
                             ("right", "MAIN_SHADE_POSITION_THUMB_RIGHT")):
            r = spec.sprite("titlebar", sname)
            c = self.free(r.w, r.h, origin=(pos.x, pos.y), window="shade", fill=t.btn_face)
            t.paint_shade_position_thumb(c, which)
            self.place("titlebar", sname, c)

        # ---- transport -----------------------------------------------
        for which, n_name, p_name in (
                ("previous", "MAIN_PREVIOUS_BUTTON", "MAIN_PREVIOUS_BUTTON_ACTIVE"),
                ("play", "MAIN_PLAY_BUTTON", "MAIN_PLAY_BUTTON_ACTIVE"),
                ("pause", "MAIN_PAUSE_BUTTON", "MAIN_PAUSE_BUTTON_ACTIVE"),
                ("stop", "MAIN_STOP_BUTTON", "MAIN_STOP_BUTTON_ACTIVE"),
                ("next", "MAIN_NEXT_BUTTON", "MAIN_NEXT_BUTTON_ACTIVE"),
                ("eject", "MAIN_EJECT_BUTTON", "MAIN_EJECT_BUTTON_ACTIVE")):
            r = L(which)
            for pressed, sname in ((False, n_name), (True, p_name)):
                c = self.cut(main_bg, r, window="main")
                t.paint_transport(c, which, pressed)
                self.place("cbuttons", sname, c)
                if not pressed:
                    self.bake(sheet_main, r, c)

        # ---- shuffle / repeat / eq / pl -------------------------------
        toggles = [
            ("shuffle", t.paint_shuffle, "MAIN_SHUFFLE_BUTTON", "MAIN_SHUFFLE_BUTTON_DEPRESSED",
             "MAIN_SHUFFLE_BUTTON_SELECTED", "MAIN_SHUFFLE_BUTTON_SELECTED_DEPRESSED"),
            ("repeat", t.paint_repeat, "MAIN_REPEAT_BUTTON", "MAIN_REPEAT_BUTTON_DEPRESSED",
             "MAIN_REPEAT_BUTTON_SELECTED", "MAIN_REPEAT_BUTTON_SELECTED_DEPRESSED"),
            ("eqButton", t.paint_eq_toggle, "MAIN_EQ_BUTTON", "MAIN_EQ_BUTTON_DEPRESSED",
             "MAIN_EQ_BUTTON_SELECTED", "MAIN_EQ_BUTTON_DEPRESSED_SELECTED"),
            ("plButton", t.paint_pl_toggle, "MAIN_PLAYLIST_BUTTON", "MAIN_PLAYLIST_BUTTON_DEPRESSED",
             "MAIN_PLAYLIST_BUTTON_SELECTED", "MAIN_PLAYLIST_BUTTON_DEPRESSED_SELECTED"),
        ]
        for lkey, painter, n, d, s, sd in toggles:
            r = L(lkey)
            for pressed, selected, sname in ((False, False, n), (True, False, d),
                                             (False, True, s), (True, True, sd)):
                cv = self.cut(main_bg, r, window="main")
                painter(cv, pressed, selected)
                self.place("shufrep", sname, cv)
                if not pressed and not selected:
                    self.bake(sheet_main, r, cv)

        # ---- position bar --------------------------------------------
        r = L("posbar")
        c = self.cut(main_bg, r, window="main")
        t.paint_posbar_background(c)
        self.place("posbar", "MAIN_POSITION_SLIDER_BACKGROUND", c)
        self.bake(sheet_main, r, c)
        for pressed, sname in ((False, "MAIN_POSITION_SLIDER_THUMB"),
                               (True, "MAIN_POSITION_SLIDER_THUMB_SELECTED")):
            sr = spec.sprite("posbar", sname)
            c = self.free(sr.w, sr.h, origin=(r.x, r.y), window="main", fill=t.btn_face)
            t.paint_posbar_thumb(c, pressed)
            self.place("posbar", sname, c)

        # ---- volume / balance ----------------------------------------
        for sheet, lkey, frame_painter, thumb_painter, thumb_n, thumb_s in (
                ("volume", "volume", t.paint_volume_frame, t.paint_volume_thumb,
                 "MAIN_VOLUME_THUMB", "MAIN_VOLUME_THUMB_SELECTED"),
                ("balance", "balance", t.paint_balance_frame, t.paint_balance_thumb,
                 "MAIN_BALANCE_THUMB", "MAIN_BALANCE_THUMB_SELECTED")):
            r = L(lkey)
            for i in range(spec.frame_count(sheet)):
                c = self.cut(main_bg, r, window="main")
                frame_painter(c, i)
                self.place_rect(sheet, spec.frame(sheet, i), c)
                if i == 0:
                    self.bake(sheet_main, r, c)
            for pressed, sname in ((False, thumb_n), (True, thumb_s)):
                sr = spec.sprite(sheet, sname)
                c = self.free(sr.w, sr.h, origin=(r.x, r.y), window="main", fill=t.btn_face)
                thumb_painter(c, pressed)
                self.place(sheet, sname, c)

        # ---- mono / stereo lamps -------------------------------------
        for lkey, painter, on_name, off_name in (
                ("mono", t.paint_mono, "MAIN_MONO_SELECTED", "MAIN_MONO"),
                ("stereo", t.paint_stereo, "MAIN_STEREO_SELECTED", "MAIN_STEREO")):
            r = L(lkey)
            for on, sname in ((True, on_name), (False, off_name)):
                c = self.cut(main_bg, r, window="main")
                painter(c, on)
                self.place("monoster", sname, c)
                if not on:
                    self.bake(sheet_main, r, c)

        # ---- play state and work indicator ---------------------------
        r = L("workIndicator")
        for working, sname in ((False, "MAIN_NOT_WORKING_INDICATOR"),
                               (True, "MAIN_WORKING_INDICATOR")):
            c = self.cut(main_bg, r, window="main")
            t.paint_work_indicator(c, working)
            self.place("playpaus", sname, c)
            if not working:
                self.bake(sheet_main, r, c)
        r = L("playPauseIndicator")
        for state, sname in (("playing", "MAIN_PLAYING_INDICATOR"),
                             ("paused", "MAIN_PAUSED_INDICATOR"),
                             ("stopped", "MAIN_STOPPED_INDICATOR")):
            c = self.cut(main_bg, r, window="main")
            t.paint_play_state(c, state)
            self.place("playpaus", sname, c)
            if state == "stopped":
                self.bake(sheet_main, r, c)

        # ---- digits ---------------------------------------------------
        digit_origin = Rect(*spec.lval("main", "digits")[0])
        for sheet in ("numbers", "nums_ex"):
            for name, key in [(f"DIGIT_{d}", d) for d in range(10)] + \
                             [("DIGIT_BLANK", "blank"), ("DIGIT_MINUS", "minus")]:
                if not spec.has_sprite(sheet, name):
                    continue
                sr = spec.sprite(sheet, name)
                c = self.free(sr.w, sr.h, origin=(digit_origin.x, digit_origin.y),
                              window="main", fill=t.digit_background())
                t.paint_digit(c, key)
                self.place(sheet, name, c)
            if sheet == "numbers":
                self._patch_legacy_minus()

        # ---- text.bmp -------------------------------------------------
        self._build_text()

        self.sheets["main"] = sheet_main

    def _patch_legacy_minus(self) -> None:
        """numbers.bmp encodes the minus sign as a 5x1 strip inside the "2"
        cell, and its erase state as the same strip inside the "1" cell.  The
        stock 7-segment digits satisfy that by construction; patch anyway so a
        theme with an exotic digit face still produces a usable legacy sheet."""
        t = self.t
        sheet = self.sheets["numbers"]
        minus = spec.sprite("numbers", "MINUS_SIGN")
        nominus = spec.sprite("numbers", "NO_MINUS_SIGN")
        sheet.sub(minus).fill(t.digit_on)
        sheet.sub(nominus).fill(t.digit_background())
        sheet.a[:, :, 3] = 255

    def _build_text(self) -> None:
        t = self.t
        sheet = self.sheets["text"]
        marquee = spec.lrect("main", "marquee")
        gw, gh = spec.GLYPH_W, spec.GLYPH_H
        # the glyph band gets the text background so unused cells read as blanks
        sheet.sub(0, 0, spec.FONT_COLUMNS * gw, spec.FONT_ROWS * gh).fill(t.text_background())
        for r_i, row in enumerate(spec.FONT["rows"]):
            for c_i, ch in enumerate(row):
                cell = spec.glyph_rect_at(r_i, c_i)
                c = self.free(gw, gh, origin=(marquee.x, marquee.y), window="main",
                              fill=t.text_background())
                t.paint_glyph(c, ch)
                self.place_rect("text", cell, c)
        sr, sc = spec.FONT["space"]
        c = self.free(gw, gh, origin=(marquee.x, marquee.y), window="main",
                      fill=t.text_background())
        t.paint_glyph(c, " ")
        self.place_rect("text", spec.glyph_rect_at(int(sr), int(sc)), c)

    # -- EQ window -----------------------------------------------------
    def build_eq(self) -> None:
        t = self.t
        L = lambda k: spec.lrect("eq", k)  # noqa: E731
        eq_bg = Canvas(*spec.window_size("eq"), origin=(0, 0), window="eq", fill=t.face)
        t.paint_eq_background(eq_bg)
        eq_bg.a[:, :, 3] = 255
        self.eq_bg = eq_bg
        sheet_bg = eq_bg.copy()

        tb = L("titleBar")
        bars: dict[str, Canvas] = {}
        for active, sname in ((True, "EQ_TITLE_BAR_SELECTED"), (False, "EQ_TITLE_BAR")):
            c = self.cut(eq_bg, tb, window="eq")
            c.origin = (0, 0)
            t.paint_eq_title_bar(c, active)
            bars[sname] = c

        close_r = L("closeButton")
        close_normal = None
        for pressed, sname in ((False, "EQ_CLOSE_BUTTON"), (True, "EQ_CLOSE_BUTTON_ACTIVE")):
            c = self.cut(bars["EQ_TITLE_BAR_SELECTED"], close_r, window="eq")
            c.origin = (close_r.x, close_r.y)
            t.paint_eq_close(c, pressed)
            self.place("eqmain", sname, c)
            if not pressed:
                close_normal = c
        for sname, bar in bars.items():
            self.bake(bar, close_r, close_normal)
            self.place("eqmain", sname, bar)
        self.bake(sheet_bg, tb, bars["EQ_TITLE_BAR_SELECTED"])

        for lkey, painter, n, d, s, sd in (
                ("onButton", t.paint_eq_on, "EQ_ON_BUTTON", "EQ_ON_BUTTON_DEPRESSED",
                 "EQ_ON_BUTTON_SELECTED", "EQ_ON_BUTTON_SELECTED_DEPRESSED"),
                ("autoButton", t.paint_eq_auto, "EQ_AUTO_BUTTON", "EQ_AUTO_BUTTON_DEPRESSED",
                 "EQ_AUTO_BUTTON_SELECTED", "EQ_AUTO_BUTTON_SELECTED_DEPRESSED")):
            r = L(lkey)
            for pressed, selected, sname in ((False, False, n), (True, False, d),
                                             (False, True, s), (True, True, sd)):
                c = self.cut(eq_bg, r, window="eq")
                painter(c, pressed, selected)
                self.place("eqmain", sname, c)
                if not pressed and not selected:
                    self.bake(sheet_bg, r, c)

        r = L("presetsButton")
        for pressed, sname in ((False, "EQ_PRESETS_BUTTON"), (True, "EQ_PRESETS_BUTTON_SELECTED")):
            c = self.cut(eq_bg, r, window="eq")
            t.paint_eq_presets(c, pressed)
            self.place("eqmain", sname, c)
            if not pressed:
                self.bake(sheet_bg, r, c)

        # slider frames: drawn at eleven x positions, so the underlay is taken
        # from the first band slider and the art must be x-invariant.
        bands = spec.lval("eq", "bandSliders")
        band_rect = Rect(int(bands["x0"]), int(bands["y"]), int(bands["w"]), int(bands["h"]))
        preamp = L("preampSlider")
        for i in range(spec.frame_count("eqmain")):
            c = self.cut(eq_bg, band_rect, window="eq")
            t.paint_eq_slider_frame(c, i)
            self.place_rect("eqmain", spec.frame("eqmain", i), c)
            if i == 0:
                self.bake(sheet_bg, preamp, c)
                for b in range(int(bands["count"])):
                    self.bake(sheet_bg,
                              band_rect.moved(int(bands["x0"]) + int(bands["strideX"]) * b,
                                              band_rect.y), c)
        for pressed, sname in ((False, "EQ_SLIDER_THUMB"), (True, "EQ_SLIDER_THUMB_SELECTED")):
            sr = spec.sprite("eqmain", sname)
            c = self.free(sr.w, sr.h, origin=(band_rect.x + int(spec.lval("eq", "sliderThumbOffsetX")),
                                              band_rect.y), window="eq", fill=t.btn_face)
            t.paint_eq_thumb(c, pressed)
            self.place("eqmain", sname, c)

        r = L("graph")
        c = self.cut(eq_bg, r, window="eq")
        t.paint_eq_graph_background(c)
        self.place("eqmain", "EQ_GRAPH_BACKGROUND", c)
        self.bake(sheet_bg, r, c)

        sr = spec.sprite("eqmain", "EQ_GRAPH_LINE_COLORS")
        strip = self.free(sr.w, sr.h, origin=(r.x, r.y), window="eq")
        cols = t.eq_graph_line_colours()
        if len(cols) != sr.h:
            raise ValueError(f"eq_graph_line_colours() must return {sr.h} colours, got {len(cols)}")
        for y, col in enumerate(cols):
            strip.hline(0, sr.w - 1, y, col)
        self.place("eqmain", "EQ_GRAPH_LINE_COLORS", strip)

        sr = spec.sprite("eqmain", "EQ_PREAMP_LINE")
        c = self.free(sr.w, sr.h, origin=(r.x, r.y + r.h // 2), window="eq")
        t.paint_eq_preamp_line(c)
        self.place("eqmain", "EQ_PREAMP_LINE", c)

        self.place("eqmain", "EQ_WINDOW_BACKGROUND", sheet_bg)
        self.eq_sheet_bg = sheet_bg

    # -- playlist ------------------------------------------------------
    def build_playlist(self) -> None:
        t = self.t
        P = spec.layout("playlist")
        W, H = [int(v) for v in P["defaultSize"]]
        title_h = int(P["titleHeight"])
        bottom_h = int(P["bottomHeight"])
        left_w = int(P["leftWidth"])
        right_w = int(P["rightWidth"])
        corner_w = spec.sprite("pledit", "PLAYLIST_TOP_LEFT_SELECTED").w
        title_w = spec.sprite("pledit", "PLAYLIST_TITLE_BAR_SELECTED").w
        title_x = (W - title_w) // 2
        close_r = Rect(W + int(P["closeButtonFromTopRight"][0]),
                       int(P["closeButtonFromTopRight"][1]),
                       int(P["closeButtonFromTopRight"][2]),
                       int(P["closeButtonFromTopRight"][3]))

        def piece(sprite_name: str, origin, painter, *args) -> Canvas:
            r = spec.sprite("pledit", sprite_name)
            c = self.free(r.w, r.h, origin=origin, window="playlist", fill=t.pl_face)
            painter(c, *args)
            return c

        top_specs = [
            ("PLAYLIST_TOP_LEFT_SELECTED", "PLAYLIST_TOP_LEFT_CORNER",
             (0, 0), t.paint_pl_top_left),
            ("PLAYLIST_TITLE_BAR_SELECTED", "PLAYLIST_TITLE_BAR",
             (title_x, 0), t.paint_pl_title),
            ("PLAYLIST_TOP_TILE_SELECTED", "PLAYLIST_TOP_TILE",
             (corner_w, 0), t.paint_pl_top_tile),
            ("PLAYLIST_TOP_RIGHT_CORNER_SELECTED", "PLAYLIST_TOP_RIGHT_CORNER",
             (W - corner_w, 0), t.paint_pl_top_right),
        ]
        # the close button's normal state is baked into both top-right corners
        corner_origin = (W - corner_w, 0)
        close_local = Rect(close_r.x - corner_origin[0], close_r.y, close_r.w, close_r.h)
        tmp = piece("PLAYLIST_TOP_RIGHT_CORNER_SELECTED", corner_origin, t.paint_pl_top_right, True)
        close_normal = tmp.crop(close_local.x, close_local.y, close_local.w, close_local.h)
        close_normal.origin = (close_r.x, close_r.y)
        t.paint_pl_close(close_normal, False)

        for sel_name, norm_name, origin, painter in top_specs:
            for active, sname in ((True, sel_name), (False, norm_name)):
                c = piece(sname, origin, painter, active)
                if "TOP_RIGHT" in sname:
                    self.bake(c, close_local, close_normal)
                self.place("pledit", sname, c)

        self.place("pledit", "PLAYLIST_LEFT_TILE",
                   piece("PLAYLIST_LEFT_TILE", (0, title_h), t.paint_pl_left_tile))
        self.place("pledit", "PLAYLIST_RIGHT_TILE",
                   piece("PLAYLIST_RIGHT_TILE", (W - right_w, title_h), t.paint_pl_right_tile))
        self.place("pledit", "PLAYLIST_BOTTOM_TILE",
                   piece("PLAYLIST_BOTTOM_TILE", (left_w, H - bottom_h), t.paint_pl_bottom_tile))
        self.place("pledit", "PLAYLIST_BOTTOM_LEFT_CORNER",
                   piece("PLAYLIST_BOTTOM_LEFT_CORNER", (0, H - bottom_h), t.paint_pl_bottom_left))
        br_w = spec.sprite("pledit", "PLAYLIST_BOTTOM_RIGHT_CORNER").w
        self.place("pledit", "PLAYLIST_BOTTOM_RIGHT_CORNER",
                   piece("PLAYLIST_BOTTOM_RIGHT_CORNER", (W - br_w, H - bottom_h),
                         t.paint_pl_bottom_right))
        self.place("pledit", "PLAYLIST_VISUALIZER_BACKGROUND",
                   piece("PLAYLIST_VISUALIZER_BACKGROUND", (W - br_w, H - bottom_h),
                         t.paint_pl_visualizer_background))

        handle_x = W + int(P["scrollHandleFromRight"])
        for pressed, sname in ((False, "PLAYLIST_SCROLL_HANDLE"),
                               (True, "PLAYLIST_SCROLL_HANDLE_SELECTED")):
            self.place("pledit", sname,
                       piece(sname, (handle_x, title_h), t.paint_pl_scroll_handle, pressed))
        self.place("pledit", "PLAYLIST_CLOSE_SELECTED",
                   piece("PLAYLIST_CLOSE_SELECTED", (close_r.x, close_r.y), t.paint_pl_close, True))
        self.place("pledit", "PLAYLIST_COLLAPSE_SELECTED",
                   piece("PLAYLIST_COLLAPSE_SELECTED", (close_r.x - 10, close_r.y),
                         t.paint_pl_collapse, True))
        self.pl_geometry = dict(W=W, H=H, title_h=title_h, bottom_h=bottom_h,
                                left_w=left_w, right_w=right_w, corner_w=corner_w,
                                title_w=title_w, title_x=title_x)

    def build_gen(self) -> None:
        """The Token Flow window frame (SPEC 3.3).

        Pieces are painted in *window* space at the position they will occupy in
        a default-size window, so a theme's materials line up across the cuts
        exactly as they do for the playlist frame.
        """
        t = self.t
        F = spec.layout("field")
        W, H = [int(v) for v in F["defaultSize"]]
        title_h = int(F["titleHeight"])
        bottom_h = int(F["bottomHeight"])
        left_w = int(F["leftWidth"])
        right_w = int(F["rightWidth"])
        title_w = spec.sprite("gen", "GEN_TITLE_PLATE").w
        close_r = [int(v) for v in F["closeButtonFromTopRight"]]
        lamp_r = [int(v) for v in F["lampFromTopRight"]]

        def piece(sprite_name: str, origin, painter, *args) -> Canvas:
            r = spec.sprite("gen", sprite_name)
            c = self.free(r.w, r.h, origin=origin, window="field", fill=t.pl_face)
            painter(c, *args)
            return c

        self.place("gen", "GEN_TOP_LEFT",
                   piece("GEN_TOP_LEFT", (0, 0), t.paint_gen_top_left))
        # The tiles are painted at x=0, not at the corner width: `FieldRenderer` lays the whole
        # top and bottom edge from x=0 and stamps the corners over it, so x=0 is the phase the
        # app actually shows. (The playlist gets away with the corner origin only because there
        # its corner and its tile are both 25 px wide.)
        self.place("gen", "GEN_TOP_TILE",
                   piece("GEN_TOP_TILE", (0, 0), t.paint_gen_top_tile))
        self.place("gen", "GEN_TOP_RIGHT",
                   piece("GEN_TOP_RIGHT", (W - right_w, 0), t.paint_gen_top_right))
        self.place("gen", "GEN_TITLE_PLATE",
                   piece("GEN_TITLE_PLATE", ((W - title_w) // 2, 0), t.paint_gen_title_plate))
        self.place("gen", "GEN_LEFT_TILE",
                   piece("GEN_LEFT_TILE", (0, title_h), t.paint_gen_left_tile))
        self.place("gen", "GEN_RIGHT_TILE",
                   piece("GEN_RIGHT_TILE", (W - right_w, title_h), t.paint_gen_right_tile))
        self.place("gen", "GEN_BOTTOM_LEFT",
                   piece("GEN_BOTTOM_LEFT", (0, H - bottom_h), t.paint_gen_bottom_left))
        self.place("gen", "GEN_BOTTOM_TILE",
                   piece("GEN_BOTTOM_TILE", (0, H - bottom_h), t.paint_gen_bottom_tile))
        self.place("gen", "GEN_BOTTOM_RIGHT",
                   piece("GEN_BOTTOM_RIGHT", (W - right_w, H - bottom_h), t.paint_gen_bottom_right))
        for pressed, name in ((False, "GEN_CLOSE"), (True, "GEN_CLOSE_PRESSED")):
            self.place("gen", name,
                       piece(name, (W + close_r[0], close_r[1]), t.paint_gen_close, pressed))
        for lit, name in ((True, "GEN_LAMP_ON"), (False, "GEN_LAMP_OFF")):
            self.place("gen", name,
                       piece(name, (W + lamp_r[0], lamp_r[1]), t.paint_gen_lamp, lit))



# ---------------------------------------------------------------------------
# text files
# ---------------------------------------------------------------------------

_VISCOLOR_COMMENTS = [
    "visualiser background", "background dots",
    *[f"spectrum bar {i} ({'top' if i == 0 else 'bottom' if i == 15 else 'band'})"
      for i in range(16)],
    "oscilloscope 1 (brightest)", "oscilloscope 2", "oscilloscope 3",
    "oscilloscope 4", "oscilloscope 5", "spectrum peak caps",
]


def _viscolor_text(theme) -> str:
    cols = theme.viscolors()
    if len(cols) != 24:
        raise ValueError(f"viscolors() must return 24 colours, got {len(cols)}")
    lines = []
    for i, (r, g, b) in enumerate(cols):
        lines.append(f"{int(r)},{int(g)},{int(b)}, // {i} {_VISCOLOR_COMMENTS[i]}")
    return "\r\n".join(lines) + "\r\n"


def _pledit_text(theme) -> str:
    d = theme.pledit_colours()
    for key in ("Normal", "Current", "NormalBG", "SelectedBG", "Font"):
        if key not in d:
            raise ValueError(f"pledit_colours() is missing {key!r}")
    return ("[Text]\r\n"
            f"Normal={d['Normal']}\r\n"
            f"Current={d['Current']}\r\n"
            f"NormalBG={d['NormalBG']}\r\n"
            f"SelectedBG={d['SelectedBG']}\r\n"
            f"Font={d['Font']}\r\n")


def build_plfont(theme) -> Canvas:
    """Paint the Sessions-list typeface sheet (SPEC 3.2).

    16 columns x 6 rows; cell *k* holds character code 32+*k*, and the last
    cell holds the ellipsis.  Each cell canvas is pre-filled black and the
    theme paints an ink mask into it.
    """
    from . import fonts
    cw, ch = [int(v) for v in theme.pl_font_cell()]
    if cw < 3 or ch < 5:
        raise ValueError(f"pl_font_cell() is {cw}x{ch}; that is too small to be legible")
    sheet = Canvas(fonts.PLFONT_COLUMNS * cw, fonts.PLFONT_ROWS * ch, fill="#000000")
    sheet.a[:, :, 3] = 255
    for k, character in enumerate(fonts.plfont_cell_chars()):
        x, y = (k % fonts.PLFONT_COLUMNS) * cw, (k // fonts.PLFONT_COLUMNS) * ch
        cell = Canvas(cw, ch, origin=(x, y), window=None, fill="#000000")
        cell.a[:, :, 3] = 255
        theme.paint_pl_font_glyph(cell, character)
        sheet.sub(x, y, cw, ch).a[:, :] = cell.opaque("#000000").a
    return sheet


def _plfont_text(theme) -> str:
    m = theme.pl_font_metrics() or {}
    lines = ["[PlaylistFont]"]
    for key in ("Monospace", "Spacing", "SpaceWidth", "RowHeight", "OffsetY"):
        v = m.get(key)
        if v is not None:
            lines.append(f"{key}={int(v)}")
    return "\r\n".join(lines) + "\r\n"


def _write_bmp(c: Canvas, path: Path) -> None:
    """24-bit uncompressed BMP, exactly the canvas's size."""
    img = c.to_pil().convert("RGB")
    img.save(str(path), format="BMP")


# ---------------------------------------------------------------------------

def build_skin(theme, out_dir, dist: Path | None = None, quiet: bool = False) -> BuildResult:
    """Paint ``theme`` into a complete skin.

    Writes the loose sheets and text files to ``<out_dir>/out/`` and a flat
    deflated ``<Name>.wsz`` into ``skins/dist/``.
    """
    out_dir = Path(out_dir)
    b = _Builder(theme)
    b.build_main()
    b.build_eq()
    b.build_playlist()
    b.build_gen()

    loose = out_dir / "out"
    loose.mkdir(parents=True, exist_ok=True)
    files: list[Path] = []
    for name in spec.sheet_names():
        w, h = spec.sheet_size(name)
        c = b.sheets[name]
        if (c.w, c.h) != (w, h):
            raise ValueError(f"skinkit.builder: sheet {name} is {c.w}x{c.h}, spec says {w}x{h}")
        p = loose / spec.sheet_file(name)
        _write_bmp(c, p)
        files.append(p)
    # the Sessions-list typeface (SPEC 3.2) -- not a sprites.json sheet
    plfont = build_plfont(theme)
    p = loose / "plfont.bmp"
    _write_bmp(plfont, p)
    files.append(p)

    for fname, text in (("viscolor.txt", _viscolor_text(theme)),
                        ("pledit.txt", _pledit_text(theme)),
                        ("plfont.txt", _plfont_text(theme)),
                        ("readme.txt", theme.readme())):
        p = loose / fname
        p.write_text(text, encoding="utf-8", newline="")
        files.append(p)

    dist_path = Path(dist) if dist is not None else dist_dir()
    dist_path.mkdir(parents=True, exist_ok=True)
    wsz = dist_path / f"{getattr(theme, 'dist_name', None) or theme.name}.wsz"
    with zipfile.ZipFile(wsz, "w", compression=zipfile.ZIP_DEFLATED) as z:
        for p in files:
            # FLAT: basename only, no directory prefix.  The entry is stamped
            # with a fixed date rather than the file's mtime so a .wsz is a
            # pure function of the art -- rebuilding unchanged art produces a
            # byte-identical archive and leaves the tracked binary alone.
            info = zipfile.ZipInfo(p.name, date_time=WSZ_TIMESTAMP)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, p.read_bytes())
    if not quiet:
        print(f"  built {len(files)} files -> {loose}")
        print(f"  packed {wsz}")
    return BuildResult(theme, out_dir, wsz, b.sheets, files)
