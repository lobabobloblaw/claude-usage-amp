"""theme -- the artist-facing base class.

``Theme`` *is* the Base skin.  Subclass it, override the painters you care
about, and the rest stays Base.  Every painter is handed a
:class:`~skinkit.canvas.Canvas` that is

* exactly the size of the sprite it paints,
* already positioned (``c.origin`` = the widget's window coordinate,
  ``c.window`` = ``"main"`` / ``"eq"`` / ``"playlist"`` / ``"shade"``), and
* **already pre-filled with whatever lies underneath it** -- for main-window
  widgets that is the pixels ``paint_main_background`` produced at that exact
  rect, for EQ widgets the pixels ``paint_eq_background`` produced.

So a painter only has to draw the widget, never its surroundings, and a
texture that is sampled in window coordinates (everything in :mod:`skinkit.fx`
is) lines up across the cut automatically.

The hook list, with sprite sizes, is in ``skins/skinkit/README.md``.
"""

from __future__ import annotations

from typing import Sequence

import numpy as np

from . import fonts, fx
from .canvas import Canvas, Colour, darken, lighten, mix, parse_colour, with_alpha
from .spec import Rect, lrect, lval


class Theme:
    """The Base skin, and the base class for every other skin."""

    # ------------------------------------------------------------------
    # identity
    # ------------------------------------------------------------------
    name = "Base"
    author = "Tokenamp"
    description = "Dark graphite hi-fi faceplate with a green phosphor display."
    seed = 11

    # ------------------------------------------------------------------
    # palette -- override these and most of the skin follows
    # ------------------------------------------------------------------
    #: colour used for the unreachable parts of each sheet
    sheet_filler = "#0d1013"

    # faceplate
    face_hi = "#454c55"          #: top of the faceplate gradient
    face = "#343b43"             #: faceplate mid tone
    face_lo = "#232930"          #: bottom of the faceplate gradient
    edge_light = "#6f7b89"       #: outer bevel highlight
    edge_mid = "#525c68"
    edge_shadow = "#171b20"      #: outer bevel shadow
    edge_black = "#0b0d10"

    # displays
    well_bg = "#0a1310"          #: LCD background (glyph + digit background)
    well_rim = "#080a0c"
    viz_bg = "#060d0a"           #: visualiser well -- MUST equal viscolor[0]
    viz_dots = "#12241c"         #: visualiser dot grid -- viscolor[1]
    text_fg = "#7ff0a4"          #: phosphor text
    text_dim = "#39795a"
    digit_on = "#84ffb0"         #: lit segment
    digit_off = None             #: unlit segment ghost (None = clean LCD)

    # buttons
    btn_face = "#3b424b"
    btn_hi = "#79838f"
    btn_lo = "#171b20"
    btn_inner_hi = "#4d5661"
    btn_inner_lo = "#252b32"
    btn_pressed_face = "#2b3138"
    icon = "#d3dbe4"             #: transport glyph colour
    icon_dim = "#8a939d"

    # lamps and labels
    lamp_on = "#6cff9a"
    lamp_off = "#1e3a2b"
    lamp_alt_on = "#ffcf5a"
    label = "#aab5c3"            #: micro-label ink
    label_relief = "#090b0e"     #: 1px shadow drawn under a micro label
    accent = "#5fe08a"

    # sliders
    groove_bg = "#14181d"
    groove_rim_hi = "#5a636e"
    groove_rim_lo = "#0c0e11"
    heat_cool = "#2fd257"
    heat_warm = "#e6d044"
    heat_hot = "#e34530"

    # title bar
    title_active_hi = "#4d5661"
    title_active_lo = "#2a3038"
    title_inactive_hi = "#3a4048"
    title_inactive_lo = "#252a31"
    title_text_on = "#cfe8d8"
    title_text_off = "#6d7d75"
    title_grip_hi = "#5d6873"
    title_grip_lo = "#1b1f25"

    # playlist
    pl_face = "#2e343b"
    pl_face_hi = "#3c434c"
    pl_list_bg = "#0a1310"

    # ==================================================================
    # small shared helpers (all overridable)
    # ==================================================================
    def faceplate(self, c: Canvas) -> None:
        """Fill a canvas with the faceplate material, continuous in window space."""
        fx.linear_gradient(c, self.face_hi, self.face_lo, direction="v",
                           dither=0.05, window_space=True)
        fx.apply_noise(c, amount=7.0, scale=2.2, seed=self.seed, octaves=2)
        fx.apply_noise(c, amount=3.0, scale=24.0, seed=self.seed + 3, octaves=3)

    def micro(self, c: Canvas, x: int, y: int, text: str, colour: Colour | None = None,
              font=None, spacing: int | None = None, relief: Colour | None = ...) -> None:
        """A tiny panel label: ``label`` ink over a 1px ``label_relief`` shadow
        one pixel down-right.  At 3x5 this reads far better than a true engrave,
        which turns to mush; use :func:`fx.engrave_text` on light plates.

        ``relief=None`` draws flat text (what you want on an LCD)."""
        f = font if font is not None else fonts.MICRO_3x5
        ink = self.label if colour is None else colour
        rel = self.label_relief if relief is ... else relief
        if rel is not None:
            fonts.draw_text(c, x + 1, y + 1, text, f, rel, spacing=spacing)
        fonts.draw_text(c, x, y, text, f, ink, spacing=spacing)

    def lcd_text(self, c: Canvas, x: int, y: int, text: str, colour: Colour | None = None,
                 font=None, spacing: int | None = None) -> None:
        """Flat phosphor text for the inside of a display well."""
        fonts.draw_text(c, x, y, text, font if font is not None else fonts.MICRO_3x5,
                        self.text_dim if colour is None else colour, spacing=spacing)

    def lamp(self, c: Canvas, x: int, y: int, w: int, h: int, on: bool,
             colour: Colour | None = None, bloom: int = 1) -> None:
        """A small indicator lamp with an off state that still reads as a lamp."""
        col = self.lamp_on if colour is None else colour
        fx.led(c, x, y, w, h, col, on=on, bloom=bloom,
               off_colour=self.lamp_off if colour is None else darken(col, 0.74),
               bezel=self.btn_lo, strength=0.85)

    def button_face(self, c: Canvas, pressed: bool = False, rect=None,
                    double: bool = True) -> None:
        """A raised (or pressed) button plate filling the canvas."""
        v = c if rect is None else c.sub(rect)
        if pressed:
            fx.linear_gradient(v, darken(self.btn_face, 0.40), darken(self.btn_face, 0.14),
                               direction="v", window_space=False, dither=0.04)
            fx.apply_noise(v, amount=5.0, scale=2.0, seed=self.seed + 5)
            if double:
                fx.bevel_double(v, outer_light=self.btn_hi, outer_shadow=self.btn_lo,
                                inner_light=self.btn_inner_hi, inner_shadow=self.btn_inner_lo,
                                raised=False)
            else:
                fx.bevel_sunken(v, light=self.btn_hi, shadow=self.btn_lo)
        else:
            fx.linear_gradient(v, lighten(self.btn_face, 0.16), darken(self.btn_face, 0.16),
                               direction="v", window_space=False, dither=0.04)
            fx.apply_noise(v, amount=5.0, scale=2.0, seed=self.seed + 5)
            if double:
                fx.bevel_double(v, outer_light=self.btn_hi, outer_shadow=self.btn_lo,
                                inner_light=self.btn_inner_hi, inner_shadow=self.btn_inner_lo,
                                raised=True)
            else:
                fx.bevel_raised(v, light=self.btn_hi, shadow=self.btn_lo)

    def press_offset(self, pressed: bool) -> tuple[int, int]:
        """How far a button's artwork moves when pressed.  Classic skins use +1,+1."""
        return (1, 1) if pressed else (0, 0)

    def well(self, c: Canvas, rect, colour: Colour | None = None,
             rim_hi: Colour | None = None, rim_lo: Colour | None = None,
             shadow_depth: int = 2) -> Canvas:
        """Cut a recessed display well and return a view of its interior.

        The 1px rim is drawn *around* ``rect``, so the interior is exactly
        ``rect`` -- which matters because glyph and digit cells have to sit on
        a flat, known colour.
        """
        x, y, w, h = int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3])
        lo = self.groove_rim_lo if rim_lo is None else rim_lo
        hi = self.groove_rim_hi if rim_hi is None else rim_hi
        c.rect(x - 1, y - 1, w + 2, h + 2, lo)
        c.hline(x - 1, x + w, y + h, hi)
        c.vline(x + w, y - 1, y + h, hi)
        inner = c.sub(x, y, w, h)
        inner.fill(self.well_bg if colour is None else colour)
        if shadow_depth:
            fx.inner_shadow(inner, colour=self.well_rim, depth=shadow_depth,
                            strength=0.45, sides="tl")
        return inner

    # -- icon primitives ------------------------------------------------
    def _tri(self, c: Canvas, x: int, y: int, w: int, h: int, direction: str,
             colour: Colour) -> None:
        """Solid pixel triangle; ``direction`` in ``left right up down``."""
        for i in range(w if direction in ("left", "right") else h):
            if direction == "right":      # flat left edge, apex on the right
                k = int(round((h - 1) / 2 * (i / max(1, w - 1))))
                c.vline(x + i, y + k, y + h - 1 - k, colour)
            elif direction == "left":     # apex on the left, flat right edge
                k = int(round((h - 1) / 2 * (1 - i / max(1, w - 1))))
                c.vline(x + i, y + k, y + h - 1 - k, colour)
            elif direction == "up":       # apex on top, flat bottom edge
                k = int(round((w - 1) / 2 * (1 - i / max(1, h - 1))))
                c.hline(x + k, x + w - 1 - k, y + i, colour)
            else:                         # "down": flat top edge, apex below
                k = int(round((w - 1) / 2 * (i / max(1, h - 1))))
                c.hline(x + k, x + w - 1 - k, y + i, colour)

    # ==================================================================
    # MAIN WINDOW
    # ==================================================================
    # geometry of the Base skin's display wells (window coords).  Override
    # these in a subclass and the wells move; the widgets do not.
    #: the left display well: work/play icons, the four time digits, the
    #: visualiser.  x 20..104, y 18..60.
    WELL_LEFT = (20, 18, 85, 43)
    #: the right display well: marquee, kbps/khz fields, mono/stereo lamps and
    #: the SESSION / WEEK gauge captions.  x 107..267, y 18..54.  One row taller
    #: than the lamps need, so the gauge captions clear the kbps/khz row.
    WELL_RIGHT = (107, 18, 161, 37)
    #: screw positions on the main faceplate (all four are in clear space --
    #: the display wells reach the bezel at the top, so there is no room there)
    MAIN_SCREWS = ((6, 78), (6, 108), (268, 78), (268, 108))

    def paint_main_background(self, c: Canvas) -> None:
        """275x116 at window (0,0) -- everything static about the main window.

        Everything a widget will later be cut out of lives here: the faceplate,
        the bezel, all four display wells, the engraved labels from SPEC 5.1,
        the screws and the colon between the time digits.  Nothing dynamic.
        """
        self.faceplate(c)
        fx.glass_glare(c, strength=0.05, angle=-0.55, width=0.5, offset=-0.28)

        # outer bezel
        fx.bevel_double(c, outer_light=self.edge_light, outer_shadow=self.edge_black,
                        inner_light=self.edge_mid, inner_shadow=self.edge_shadow,
                        raised=True)

        # a hairline separating the title bar strip from the faceplate
        c.hline(2, c.w - 3, 14, darken(self.edge_shadow, 0.2))
        c.hline(2, c.w - 3, 15, lighten(self.face_hi, 0.06))

        # ---- display wells -------------------------------------------
        # Two wells, separated by a 2px rib at x=105/106.  They reach the same
        # flat colour everywhere a glyph or digit lands, which is what lets
        # paint_glyph and paint_digit use one background colour (see README).
        left = self.well(c, self.WELL_LEFT)
        right = self.well(c, self.WELL_RIGHT)
        fx.scanlines(left, every=3, amount=0.09, window_space=True)
        fx.scanlines(right, every=3, amount=0.09, window_space=True)

        # deeper inset for the visualiser; its interior is viscolor[0]
        viz = lrect("main", "visualizer")
        c.rect(viz.x - 1, viz.y - 1, viz.w + 2, viz.h + 2, self.well_rim)
        c.sub(viz).fill(self.viz_bg)

        self.paint_time_frame(c)

        # ---- field outlines inside the wells -------------------------
        for key in ("marquee", "kbps", "khz"):
            r = lrect("main", key)
            c.rect(r.x - 1, r.y - 1, r.w + 2, r.h + 2, self.well_rim)
            c.sub(r).fill(self.text_background())

        # ---- SPEC 5.1 baked labels (all inside the right well, as LCD text)
        kb = lrect("main", "kbps")
        kz = lrect("main", "khz")
        self.lcd_text(c, kb.x1 + 4, kb.y - 1, "K/MIN", font=fonts.MICRO_4x5)
        self.lcd_text(c, kz.x1 + 4, kz.y - 1, "ACTIVE", font=fonts.MICRO_4x5)
        vol = lrect("main", "volume")
        bal = lrect("main", "balance")
        cap_y = self.WELL_RIGHT[1] + self.WELL_RIGHT[3] - 5
        self.lcd_text(c, vol.x + 1, cap_y, "SESSION", font=fonts.MICRO_4x5)
        self.lcd_text(c, bal.x + 1, cap_y, "WEEK", font=fonts.MICRO_4x5)

        # ---- clutter-bar surround, screws, logo ----------------------
        cb = lrect("main", "clutterBar")
        c.rect(cb.x - 1, cb.y - 1, cb.w + 2, cb.h + 2, self.edge_black)
        c.hline(cb.x - 1, cb.x1, cb.y1, lighten(self.face_hi, 0.12))
        c.vline(cb.x1, cb.y - 1, cb.y1, lighten(self.face_hi, 0.12))

        for sx, sy in self.MAIN_SCREWS:
            fx.screw(c, sx, sy, r=2, style="slot", body=self.edge_mid,
                     light=self.edge_light, shadow=self.edge_black, angle=45)

        self.paint_about_logo(c.sub(lrect("main", "aboutLogo")))

    def paint_time_frame(self, c: Canvas) -> None:
        """A 1px outline around the four 9x13 time digits, plus the colon.

        Deliberately an *outline*: the digit cells must sit on the flat well
        colour that :meth:`digit_background` returns, so nothing may be painted
        inside them.
        """
        digits = [Rect(*d) for d in lval("main", "digits")]
        minus = lrect("main", "minusSignEx")
        x0 = min(minus.x, digits[0].x) - 1
        x1 = max(d.x1 for d in digits) + 1
        y0, y1 = digits[0].y - 1, digits[0].y1 + 1
        c.rect(x0, y0, x1 - x0, y1 - y0, darken(self.well_bg, 0.55))
        c.hline(x0, x1 - 1, y1 - 1, lighten(self.well_bg, 0.10))
        # colon in the gap between digit 2 and digit 3
        gx = (digits[1].x1 + digits[2].x) // 2 - 1
        for gy in (digits[0].y + 3, digits[0].y + 8):
            c.box(gx, gy, 2, 2, self.digit_on)

    def digit_background(self) -> Colour:
        """Background of the 9x13 digit cells == interior of the time well."""
        return self.well_bg

    def text_background(self) -> Colour:
        """Background of 5x6 glyph cells == the marquee / kbps / khz wells."""
        return self.well_bg

    def paint_about_logo(self, c: Canvas) -> None:
        """13x15 decorative mark at the bottom right of the main window."""
        fx.linear_gradient(c, darken(self.face, 0.1), darken(self.face, 0.3),
                           direction="v", window_space=False)
        fx.bevel_sunken(c, light=self.edge_mid, shadow=self.edge_black)
        for i, ch in enumerate("TA"):
            fonts.draw_text(c, 2 + i * 5, 5, ch, fonts.MICRO_4x5, self.accent)

    # -- title bar ------------------------------------------------------
    def paint_title_bar(self, c: Canvas, active: bool, variant: str) -> None:
        """275x14 at window (0,0).

        ``variant`` is ``"main"`` (the normal title bar), ``"shade"`` (the
        window-shade strip, which also carries the mini transport, mini
        visualiser and mini position bar) or ``"easter"`` (the easter-egg
        title bar).  Keep the far-left and far-right 20px identical between the
        active and inactive variants: the title *buttons* are one sprite pair
        shared by both, so anything that changes there will show a seam.
        """
        hi = self.title_active_hi if active else self.title_inactive_hi
        lo = self.title_active_lo if active else self.title_inactive_lo
        fx.linear_gradient(c, hi, lo, direction="v", window_space=False, dither=0.05)
        fx.apply_noise(c, amount=6.0, scale=2.0, seed=self.seed + 1)
        # identical top and bottom border rows for every variant: the two shade
        # sprites overlap by one row inside titlebar.bmp (see README traps).
        c.hline(0, c.w - 1, 0, self.edge_black)
        c.hline(0, c.w - 1, c.h - 1, self.edge_black)
        c.hline(1, c.w - 2, 1, lighten(hi, 0.18))

        title = {"main": "TOKENAMP", "shade": "TOKENAMP", "easter": "TOKENAMP"}[variant]
        tcol = self.title_text_on if active else self.title_text_off
        if variant == "easter":
            tcol = self.lamp_alt_on if active else darken(self.lamp_alt_on, 0.45)

        if variant == "shade":
            # the shade strip is busy; a short mark on the left is enough
            self.micro(c, 20, 4, "TA", tcol, font=fonts.MICRO_4x5, relief=None)
            self._shade_furniture(c)
            return

        # grip stripes either side of the centred title
        tw = fonts.text_width(title, fonts.MICRO_4x5)
        tx = (c.w - tw) // 2
        for gx in range(24, tx - 6, 4):
            c.vline(gx, 4, 9, self.title_grip_lo)
            c.vline(gx + 1, 4, 9, self.title_grip_hi)
        for gx in range(tx + tw + 5, c.w - 34, 4):
            c.vline(gx, 4, 9, self.title_grip_lo)
            c.vline(gx + 1, 4, 9, self.title_grip_hi)
        c.box(tx - 4, 3, tw + 8, 9, mix(lo, self.edge_black, 0.35))
        fx.bevel_sunken(c, (tx - 4, 3, tw + 8, 9), light=lighten(hi, 0.1),
                        shadow=self.edge_black)
        fonts.draw_text(c, tx, 5, title, fonts.MICRO_4x5, tcol)
        if active:
            fx.glow(c, c.colour_mask(tcol, tolerance=10), tcol, radius=1, strength=0.25)

    def _shade_furniture(self, c: Canvas) -> None:
        """Wells for the shade strip's mini visualiser, digits and position bar."""
        mv = lrect("shade", "miniVisualizer")
        c.rect(mv.x - 1, mv.y - 1, mv.w + 2, mv.h + 2, self.well_rim)
        c.sub(mv).fill(self.viz_bg)
        glyphs = lval("shade", "timeGlyphs")
        gx0 = int(glyphs[0][0]) - 2
        gx1 = int(glyphs[-1][0]) + 5 + 2
        gy = int(glyphs[0][1])
        c.rect(gx0 - 1, gy - 2, (gx1 - gx0) + 2, 10, self.well_rim)
        c.sub(gx0, gy - 1, gx1 - gx0, 8).fill(self.text_background())
        c.box(int(glyphs[1][0]) + 6, gy + 2, 1, 1, self.text_fg)
        c.box(int(glyphs[1][0]) + 6, gy + 4, 1, 1, self.text_fg)
        # mini transport icons, baked (the shade strip has no button sprites)
        col = self.icon_dim
        for key, draw in (("previous", "prev"), ("play", "play"), ("pause", "pause"),
                          ("stop", "stop"), ("next", "next"), ("eject", "eject")):
            r = lrect("shade", key)
            self._mini_icon(c, r, draw, col)

    def _mini_icon(self, c: Canvas, r: Rect, kind: str, colour: Colour) -> None:
        x, y, w, h = r.x, r.y, r.w, r.h
        cy = y + h // 2
        if kind == "prev":
            self._tri(c, x + 1, y + 1, 3, 5, "left", colour)
            self._tri(c, x + 4, y + 1, 3, 5, "left", colour)
        elif kind == "next":
            self._tri(c, x + 2, y + 1, 3, 5, "right", colour)
            self._tri(c, x + 5, y + 1, 3, 5, "right", colour)
        elif kind == "play":
            self._tri(c, x + 3, y + 1, 4, 5, "right", colour)
        elif kind == "pause":
            c.box(x + 3, y + 1, 2, 5, colour)
            c.box(x + 6, y + 1, 2, 5, colour)
        elif kind == "stop":
            c.box(x + 2, y + 1, 5, 5, colour)
        elif kind == "eject":
            self._tri(c, x + 2, y + 1, 5, 3, "up", colour)
            c.box(x + 2, y + 5, 5, 1, colour)
        del cy

    def paint_title_button(self, c: Canvas, which: str, pressed: bool) -> None:
        """9x9 title-bar button.

        ``which`` is ``options``, ``minimize``, ``shade``, ``close`` or
        ``unshade`` (the shade button's selected state, shown while the window
        is already shaded).
        """
        self.button_face(c, pressed, double=False)
        dx, dy = self.press_offset(pressed)
        col = self.icon if not pressed else lighten(self.icon, 0.15)
        if which == "options":
            for i in range(3):
                c.hline(2 + dx, 6 + dx, 2 + i * 2 + dy, col)
        elif which == "minimize":
            c.hline(2 + dx, 6 + dx, 6 + dy, col)
        elif which == "shade":
            c.hline(2 + dx, 6 + dx, 3 + dy, col)
            c.hline(2 + dx, 6 + dx, 5 + dy, col)
        elif which == "unshade":
            c.hline(2 + dx, 6 + dx, 3 + dy, col)
            c.rect(2 + dx, 4 + dy, 5, 3, col)
        elif which == "close":
            for i in range(5):
                c.px(2 + i + dx, 2 + i + dy, col)
                c.px(6 - i + dx, 2 + i + dy, col)
        else:
            raise ValueError(f"paint_title_button: unknown button {which!r}")

    # -- clutter bar ----------------------------------------------------
    def paint_clutter_bar(self, c: Canvas, pressed: str | None = None,
                          disabled: bool = False) -> None:
        """8x43 at window (10,22): the O A I D V strip.

        ``pressed`` is ``None`` or one of ``"O" "A" "I" "D" "V"`` -- the whole
        column is repainted with that one letter pushed in.  ``disabled`` is
        the greyed-out variant.
        """
        from .spec import clutter_button_local, clutter_letters
        fx.linear_gradient(c, darken(self.face, 0.08), darken(self.face, 0.3),
                           direction="v", window_space=False, dither=0.04)
        fx.apply_noise(c, amount=5.0, scale=2.0, seed=self.seed + 9)
        fx.bevel_sunken(c, light=self.edge_mid, shadow=self.edge_black)
        for letter in clutter_letters():
            r = clutter_button_local(letter)
            hit = (pressed is not None and letter == pressed.upper())
            ink = self.icon_dim if not disabled else mix(self.icon_dim, self.face, 0.6)
            if hit:
                c.box(r.x, r.y, r.w, r.h, darken(self.btn_face, 0.3))
                fx.bevel_sunken(c, (r.x, r.y, r.w, r.h), light=self.btn_inner_hi,
                                shadow=self.btn_lo)
                ink = self.accent
            gx = r.x + (r.w - 4) // 2 + (1 if hit else 0)
            gy = r.y + (r.h - 5) // 2 + (1 if hit else 0)
            fonts.draw_text(c, gx, gy, letter, fonts.MICRO_4x5, ink)

    # -- transport ------------------------------------------------------
    def paint_transport(self, c: Canvas, which: str, pressed: bool) -> None:
        """23x18 (``previous play pause stop next``) or 22x16 (``eject``)."""
        self.button_face(c, pressed)
        dx, dy = self.press_offset(pressed)
        col = self.icon
        w, h = c.w, c.h
        cx, cy = w // 2 + dx, h // 2 + dy
        if which == "previous":
            c.box(cx - 6, cy - 4, 2, 9, col)
            self._tri(c, cx - 3, cy - 4, 4, 9, "left", col)
            self._tri(c, cx + 1, cy - 4, 4, 9, "left", col)
        elif which == "next":
            self._tri(c, cx - 5, cy - 4, 4, 9, "right", col)
            self._tri(c, cx - 1, cy - 4, 4, 9, "right", col)
            c.box(cx + 4, cy - 4, 2, 9, col)
        elif which == "play":
            self._tri(c, cx - 3, cy - 4, 7, 9, "right", col)
        elif which == "pause":
            c.box(cx - 4, cy - 4, 3, 9, col)
            c.box(cx + 1, cy - 4, 3, 9, col)
        elif which == "stop":
            c.box(cx - 4, cy - 4, 8, 8, col)
        elif which == "eject":
            self._tri(c, cx - 4, cy - 4, 9, 5, "up", col)
            c.box(cx - 4, cy + 2, 9, 2, col)
        else:
            raise ValueError(f"paint_transport: unknown button {which!r}")

    # -- toggles --------------------------------------------------------
    def _toggle(self, c: Canvas, pressed: bool, selected: bool, text: str,
                font=None, lamp_w: int = 4) -> None:
        self.button_face(c, pressed)
        dx, dy = self.press_offset(pressed)
        f = font if font is not None else fonts.MICRO_4x5
        tw = fonts.text_width(text, f)
        lamp_slot = lamp_w + 3 if lamp_w else 0
        tx = (c.w - (tw + lamp_slot)) // 2 + lamp_slot + dx
        ty = (c.h - f.h) // 2 + dy
        ink = self.icon if selected else self.icon_dim
        fonts.draw_text(c, tx, ty, text, f, ink)
        if lamp_w:
            self.lamp(c, tx - lamp_slot, ty + (f.h - 3) // 2, lamp_w, 3, selected)

    def paint_shuffle(self, c: Canvas, pressed: bool, selected: bool) -> None:
        """47x15 at window (164,89).  SPEC 5.1 relabels SHUFFLE as ``CYCLE``."""
        self._toggle(c, pressed, selected, "CYCLE", fonts.MICRO_4x5, lamp_w=5)

    def paint_repeat(self, c: Canvas, pressed: bool, selected: bool) -> None:
        """28x15 at window (210,89).  SPEC 5.1 relabels REPEAT as ``ALERT``."""
        self._toggle(c, pressed, selected, "ALERT", fonts.MICRO_3x5, lamp_w=3)

    def paint_eq_toggle(self, c: Canvas, pressed: bool, selected: bool) -> None:
        """23x12 at window (219,58) -- shows/hides the equaliser window."""
        self._toggle(c, pressed, selected, "EQ", fonts.MICRO_4x5, lamp_w=3)

    def paint_pl_toggle(self, c: Canvas, pressed: bool, selected: bool) -> None:
        """23x12 at window (242,58) -- shows/hides the playlist window."""
        self._toggle(c, pressed, selected, "PL", fonts.MICRO_4x5, lamp_w=3)

    # -- position bar ---------------------------------------------------
    def paint_posbar_background(self, c: Canvas) -> None:
        """248x10 at window (16,72) -- the groove only, never the thumb."""
        fx.linear_gradient(c, darken(self.face, 0.05), darken(self.face, 0.22),
                           direction="v", window_space=False)
        fx.bevel_raised(c, light=self.edge_mid, shadow=self.edge_black)
        groove = c.sub(2, 3, c.w - 4, 4)
        groove.fill(self.groove_bg)
        fx.bevel_sunken(groove, light=self.groove_rim_hi, shadow=self.groove_rim_lo)
        for x in range(6, c.w - 6, 12):
            c.px(x, 1, lighten(self.face, 0.12))
            c.px(x, c.h - 2, darken(self.face, 0.3))

    def paint_posbar_thumb(self, c: Canvas, pressed: bool) -> None:
        """29x10 -- an opaque thumb that floats over the groove."""
        self.button_face(c, pressed)
        dx, dy = self.press_offset(pressed)
        for i in range(-1, 2):
            x = c.w // 2 + i * 3 + dx
            c.vline(x, 3 + dy, c.h - 4 + dy, self.btn_lo)
            c.vline(x + 1, 3 + dy, c.h - 4 + dy, lighten(self.btn_face, 0.28))

    # -- volume / balance ------------------------------------------------
    def _gauge_frame(self, c: Canvas, i: int, n: int = 28, label: str | None = None) -> None:
        """Shared art for the 28 volume / balance background frames."""
        fx.linear_gradient(c, lighten(self.face, 0.06), darken(self.face, 0.22),
                           direction="v", window_space=True, dither=0.04)
        fx.apply_noise(c, amount=5.0, scale=2.0, seed=self.seed + 4)
        # the thumb is 11px tall sitting at y=1, so the groove lives in rows 2..10
        groove = c.sub(1, 2, c.w - 2, 9)
        groove.fill(self.groove_bg)
        fx.bevel_sunken(groove, light=self.groove_rim_hi, shadow=self.groove_rim_lo)
        fx.inner_shadow(groove, colour="#000000", depth=2, strength=0.5, sides="tl")
        t = i / max(1, n - 1)
        span = c.w - 4
        fill_w = int(round(span * t))
        if fill_w > 0:
            bar = c.sub(2, 4, fill_w, 5)
            for x in range(bar.w):
                col = fx.heat_colour((x + 1) / max(1, span), self.heat_cool,
                                     self.heat_warm, self.heat_hot)
                bar.vline(x, 0, bar.h - 1, col)
                bar.px(x, 0, lighten(col, 0.30))
                bar.px(x, bar.h - 1, darken(col, 0.35))
        # a faint scale etched into the unfilled part of the groove
        for x in range(2 + fill_w + 1, c.w - 2, 4):
            c.vline(x, 4, 8, lighten(self.groove_bg, 0.12))
        c.hline(0, c.w - 1, 0, lighten(self.face, 0.20))
        c.hline(0, c.w - 1, c.h - 1, darken(self.face, 0.42))
        if label:
            self.micro(c, 2, c.h - 6, label, self.label)

    def paint_volume_frame(self, c: Canvas, i: int) -> None:
        """68x13 at window (107,57).  ``i`` 0..27, 0 = empty/cool, 27 = full/hot."""
        self._gauge_frame(c, i)

    def paint_volume_thumb(self, c: Canvas, pressed: bool) -> None:
        """14x11 -- fully opaque; it rides over the frame, not through it."""
        self._slider_thumb(c, pressed)

    def paint_balance_frame(self, c: Canvas, i: int) -> None:
        """38x13 at window (177,57).  ``i`` 0..27 like the volume frame."""
        self._gauge_frame(c, i)

    def paint_balance_thumb(self, c: Canvas, pressed: bool) -> None:
        """14x11 -- fully opaque."""
        self._slider_thumb(c, pressed)

    def _slider_thumb(self, c: Canvas, pressed: bool) -> None:
        c.fill(self.btn_face)
        self.button_face(c, pressed)
        dx, dy = self.press_offset(pressed)
        cx = c.w // 2 + dx
        c.vline(cx - 1, 3 + dy, c.h - 4 + dy, self.btn_lo)
        c.vline(cx, 3 + dy, c.h - 4 + dy, lighten(self.btn_face, 0.35))
        c.vline(cx + 1, 3 + dy, c.h - 4 + dy, self.btn_lo)
        c.a[:, :, 3] = 255

    # -- lamps and indicators -------------------------------------------
    def paint_mono(self, c: Canvas, on: bool) -> None:
        """27x12 at window (212,41).  SPEC 5.1 relabels ``mono`` as ``LOCAL``."""
        self._lamp_plate(c, "LOCAL", on)

    def paint_stereo(self, c: Canvas, on: bool) -> None:
        """29x12 at window (239,41).  SPEC 5.1 relabels ``stereo`` as ``LIVE``."""
        self._lamp_plate(c, "LIVE", on, fonts.MICRO_4x5)

    def _lamp_plate(self, c: Canvas, text: str, on: bool, font=None) -> None:
        f = font if font is not None else fonts.MICRO_3x5
        c.fill(self.well_bg)
        ink = self.text_fg if on else self.text_dim
        tw = fonts.text_width(text, f)
        tx = (c.w - (tw + 6)) // 2 + 6
        fonts.draw_text(c, tx, (c.h - 5) // 2, text, f, ink)
        self.lamp(c, tx - 6, (c.h - 3) // 2, 3, 3, on,
                  colour=self.lamp_on if on else self.lamp_off, bloom=1 if on else 0)
        c.a[:, :, 3] = 255

    def paint_play_state(self, c: Canvas, state: str) -> None:
        """9x9 at window (26,28).  ``state`` in ``playing paused stopped``."""
        c.fill(self.well_bg)
        col = self.text_fg if state == "playing" else self.text_dim
        if state == "playing":
            self._tri(c, 2, 1, 5, 7, "right", col)
        elif state == "paused":
            c.box(2, 1, 2, 7, col)
            c.box(5, 1, 2, 7, col)
        else:
            c.box(2, 2, 6, 6, col)
        c.a[:, :, 3] = 255

    def paint_work_indicator(self, c: Canvas, working: bool) -> None:
        """3x9 at window (24,28).  Only its left 2 columns are ever visible --
        the 9x9 play-state icon at (26,28) overlaps its third column."""
        c.fill(self.well_bg)
        if working:
            c.box(0, 1, 2, 7, self.lamp_on)
            fx.glow(c, c.colour_mask(self.lamp_on, tolerance=8), self.lamp_on,
                    radius=1, strength=0.5)
        else:
            c.box(0, 1, 2, 7, darken(self.text_dim, 0.55))
        c.a[:, :, 3] = 255

    # -- digits and glyphs ----------------------------------------------
    def paint_digit(self, c: Canvas, d) -> None:
        """9x13 time digit.  ``d`` is 0..9, ``"blank"`` or ``"minus"``.

        The cell background MUST match the time well painted by
        ``paint_main_background`` -- see :meth:`digit_background`.
        """
        c.fill(self.digit_background())
        fonts.seven_segment(c, d, on=self.digit_on, off=self.digit_off,
                            slant=0.18, thickness=2)
        c.a[:, :, 3] = 255

    def paint_glyph(self, c: Canvas, ch: str) -> None:
        """5x6 bitmap-font cell.  Background must match the marquee well."""
        c.fill(self.text_background())
        fonts.draw_text(c, 0, 0, ch, fonts.FONT_5x6, self.text_fg)
        c.a[:, :, 3] = 255

    # -- window shade ---------------------------------------------------
    def paint_shade_position_background(self, c: Canvas) -> None:
        """17x7 mini position bar for the window-shade strip."""
        c.fill(darken(self.face, 0.12))
        fx.bevel_sunken(c, light=self.edge_mid, shadow=self.edge_black)
        c.sub(1, 2, c.w - 2, 3).fill(self.groove_bg)

    def paint_shade_position_thumb(self, c: Canvas, which: str) -> None:
        """3x7 mini thumb; ``which`` is ``left``, ``center`` or ``right`` --
        the third of the handle that is showing at that end of the travel."""
        c.fill(self.btn_face)
        col = {"left": lighten(self.btn_face, 0.3),
               "center": lighten(self.btn_face, 0.45),
               "right": darken(self.btn_face, 0.2)}[which]
        c.fill(col)
        c.vline(0, 0, c.h - 1, self.btn_hi if which != "right" else self.btn_lo)
        c.vline(c.w - 1, 0, c.h - 1, self.btn_lo)
        c.hline(0, c.w - 1, 0, lighten(col, 0.25))
        c.hline(0, c.w - 1, c.h - 1, darken(col, 0.4))
        c.a[:, :, 3] = 255

    # ==================================================================
    # data hooks
    # ==================================================================
    def viscolors(self) -> list[tuple[int, int, int]]:
        """24 RGB triples for ``viscolor.txt``.

        0 = visualiser background (**must** equal the colour painted at
        ``layout.main.visualizer``), 1 = background dots, 2..17 = spectrum bars
        from top to bottom, 18..22 = oscilloscope (18 brightest), 23 = peak caps.
        """
        out: list[tuple[int, int, int]] = []
        out.append(parse_colour(self.viz_bg)[:3])
        out.append(parse_colour(self.viz_dots)[:3])
        for i in range(16):  # 2..17, top -> bottom
            t = 1.0 - i / 15.0
            out.append(fx.heat_colour(t, self.heat_cool, self.heat_warm, self.heat_hot)[:3])
        base = parse_colour(self.text_fg)
        for i in range(5):  # 18..22, brightest first
            out.append(darken(base, i * 0.17)[:3])
        out.append(parse_colour(lighten(self.text_fg, 0.55))[:3])  # 23 peak caps
        return [tuple(int(v) for v in c) for c in out]

    def pledit_colours(self) -> dict[str, str]:
        """``pledit.txt`` values: Normal / Current / NormalBG / SelectedBG / Font."""
        def hx(c):
            r, g, b, _ = parse_colour(c)
            return f"#{r:02X}{g:02X}{b:02X}"
        return {
            "Normal": hx(self.text_fg),
            "Current": hx(lighten(self.text_fg, 0.45)),
            "NormalBG": hx(self.pl_list_bg),
            "SelectedBG": hx(mix(self.pl_list_bg, self.accent, 0.28)),
            "Font": "Arial",
        }

    def readme(self) -> str:
        """Contents of ``readme.txt`` inside the .wsz."""
        return (f"{self.name}\n"
                f"{'=' * len(self.name)}\n\n"
                f"{self.description}\n\n"
                f"A classic Winamp 2.x skin for Tokenamp, painted with skinkit.\n"
                f"Author: {self.author}\n")

    # ==================================================================
    # EQUALISER WINDOW  (275x116, window="eq")
    # ==================================================================
    EQ_TROUGH_PREAMP = (19, 36, 18, 66)
    EQ_TROUGH_BANDS = (76, 36, 180, 66)

    #: SPEC 5.1 band captions, oldest bucket first
    EQ_BAND_CAPTIONS = ("-9", "-8", "-7", "-6", "-5", "-4", "-3", "-2", "-1", "NOW")

    def paint_eq_background(self, c: Canvas) -> None:
        """275x116 at window (0,0) of the EQ window -- everything static.

        Slider grooves, the graph well, and the SPEC 5.1 captions (``WEEK`` for
        the preamp, ``-9 … NOW`` for the bands, ``MAX``/``MID``/``0`` for the
        scale).  The builder bakes slider frame 0 and the normal buttons on top.
        """
        self.faceplate(c)
        fx.glass_glare(c, strength=0.05, angle=-0.55, width=0.5, offset=-0.3)
        fx.bevel_double(c, outer_light=self.edge_light, outer_shadow=self.edge_black,
                        inner_light=self.edge_mid, inner_shadow=self.edge_shadow,
                        raised=True)
        c.hline(2, c.w - 3, 14, darken(self.edge_shadow, 0.2))
        c.hline(2, c.w - 3, 15, lighten(self.face_hi, 0.06))

        graph = lrect("eq", "graph")
        g = self.well(c, graph)
        fx.scanlines(g, every=3, amount=0.12, window_space=True)
        for gx in range(0, g.w, 16):
            g.vline(gx, 0, g.h - 1, lighten(self.viz_bg, 0.10))
        g.hline(0, g.w - 1, g.h // 2, lighten(self.viz_bg, 0.16))

        for trough in (self.EQ_TROUGH_PREAMP, self.EQ_TROUGH_BANDS):
            t = c.sub(trough)
            fx.linear_gradient(t, darken(self.face, 0.22), darken(self.face, 0.08),
                               direction="v", window_space=False, dither=0.04)
            fx.bevel_sunken(t, light=self.edge_mid, shadow=self.edge_black)

        pre = lrect("eq", "preampSlider")
        self.micro(c, pre.x - 3, pre.y1 + 3, "WEEK", font=fonts.MICRO_4x5)
        bands = lval("eq", "bandSliders")
        for i in range(int(bands["count"])):
            bx = int(bands["x0"]) + int(bands["strideX"]) * i
            cap = self.EQ_BAND_CAPTIONS[i] if i < len(self.EQ_BAND_CAPTIONS) else str(i)
            tw = fonts.text_width(cap, fonts.MICRO_4x5)
            self.micro(c, bx + (int(bands["w"]) - tw) // 2,
                       int(bands["y"]) + int(bands["h"]) + 3, cap, font=fonts.MICRO_4x5)
        for text, yy in (("MAX", 38), ("MID", 66), ("0", 95)):
            self.micro(c, 3, yy, text, font=fonts.MICRO_4x5)

        for sx, sy in ((6, 19), (6, 108), (268, 19), (268, 108)):
            fx.screw(c, sx, sy, r=2, style="slot", body=self.edge_mid,
                     light=self.edge_light, shadow=self.edge_black, angle=45)

    def paint_eq_title_bar(self, c: Canvas, active: bool) -> None:
        """275x14.  SPEC 5.1: ``USAGE EQUALIZER``."""
        hi = self.title_active_hi if active else self.title_inactive_hi
        lo = self.title_active_lo if active else self.title_inactive_lo
        fx.linear_gradient(c, hi, lo, direction="v", window_space=False, dither=0.05)
        fx.apply_noise(c, amount=6.0, scale=2.0, seed=self.seed + 2)
        c.hline(0, c.w - 1, 0, self.edge_black)
        c.hline(0, c.w - 1, c.h - 1, self.edge_black)
        c.hline(1, c.w - 2, 1, lighten(hi, 0.18))
        title = "USAGE EQUALIZER"
        tcol = self.title_text_on if active else self.title_text_off
        tw = fonts.text_width(title, fonts.MICRO_4x5)
        tx = (c.w - tw) // 2
        for gx in range(24, tx - 6, 4):
            c.vline(gx, 4, 9, self.title_grip_lo)
            c.vline(gx + 1, 4, 9, self.title_grip_hi)
        for gx in range(tx + tw + 5, c.w - 20, 4):
            c.vline(gx, 4, 9, self.title_grip_lo)
            c.vline(gx + 1, 4, 9, self.title_grip_hi)
        c.box(tx - 4, 3, tw + 8, 9, mix(lo, self.edge_black, 0.35))
        fx.bevel_sunken(c, (tx - 4, 3, tw + 8, 9), light=lighten(hi, 0.1),
                        shadow=self.edge_black)
        fonts.draw_text(c, tx, 5, title, fonts.MICRO_4x5, tcol)

    def paint_eq_close(self, c: Canvas, pressed: bool) -> None:
        """9x9 at window (264,3) of the EQ window."""
        self.paint_title_button(c, "close", pressed)

    def paint_eq_on(self, c: Canvas, pressed: bool, selected: bool) -> None:
        """26x12 at window (14,18).  SPEC 5.1 keeps the caption ``ON``."""
        self._toggle(c, pressed, selected, "ON", fonts.MICRO_4x5, lamp_w=3)

    def paint_eq_auto(self, c: Canvas, pressed: bool, selected: bool) -> None:
        """32x12 at window (40,18).  SPEC 5.1 keeps the caption ``AUTO``."""
        self._toggle(c, pressed, selected, "AUTO", fonts.MICRO_4x5, lamp_w=3)

    def paint_eq_presets(self, c: Canvas, pressed: bool) -> None:
        """44x12 at window (217,18).  SPEC 5.1 relabels PRESETS as ``RANGE``."""
        self.button_face(c, pressed)
        dx, dy = self.press_offset(pressed)
        text = "RANGE"
        tw = fonts.text_width(text, fonts.MICRO_4x5)
        fonts.draw_text(c, (c.w - tw) // 2 - 3 + dx, (c.h - 5) // 2 + dy, text,
                        fonts.MICRO_4x5, self.icon)
        self._tri(c, c.w - 10 + dx, c.h // 2 - 1 + dy, 5, 3, "down", self.icon_dim)

    def paint_eq_slider_frame(self, c: Canvas, i: int) -> None:
        """14x63 EQ band/preamp background.

        ``i`` 0..27; 0 = thumb at the bottom (min), 27 = thumb at the top (max).
        The groove heats up as ``i`` rises.  This sprite is drawn at eleven
        different x positions, so keep its art x-invariant.
        """
        fx.linear_gradient(c, darken(self.face, 0.2), darken(self.face, 0.06),
                           direction="v", window_space=False, dither=0.04)
        fx.apply_noise(c, amount=5.0, scale=2.0, seed=self.seed + 6)
        groove = c.sub(4, 1, 6, c.h - 2)
        groove.fill(self.groove_bg)
        fx.bevel_sunken(groove, light=self.groove_rim_hi, shadow=self.groove_rim_lo)
        inner = c.sub(5, 2, 4, c.h - 4)
        t = i / 27.0
        fill_h = int(round(t * (inner.h - 1)))
        for k in range(fill_h):
            y = inner.h - 1 - k
            col = fx.heat_colour(k / max(1, inner.h - 1), self.heat_cool,
                                 self.heat_warm, self.heat_hot)
            inner.hline(0, inner.w - 1, y, col)
        if fill_h:
            inner.hline(0, inner.w - 1, inner.h - fill_h, "#ffffff50")
        for y in range(3, c.h - 3, 6):
            c.px(1, y, darken(self.face, 0.4))
            c.px(2, y, lighten(self.face, 0.14))
            c.px(c.w - 3, y, darken(self.face, 0.4))
            c.px(c.w - 2, y, lighten(self.face, 0.14))

    def paint_eq_thumb(self, c: Canvas, pressed: bool) -> None:
        """11x11 EQ slider thumb -- fully opaque, rides over the frame."""
        c.fill(self.btn_face)
        self.button_face(c, pressed)
        dx, dy = self.press_offset(pressed)
        cy = c.h // 2 + dy
        c.hline(2 + dx, c.w - 3 + dx, cy - 1, self.btn_lo)
        c.hline(2 + dx, c.w - 3 + dx, cy, lighten(self.btn_face, 0.4))
        c.hline(2 + dx, c.w - 3 + dx, cy + 1, self.btn_lo)
        c.a[:, :, 3] = 255

    def paint_eq_graph_background(self, c: Canvas) -> None:
        """113x19 at window (86,17) -- the curve well, no curve."""
        c.fill(self.viz_bg)
        fx.inner_shadow(c, colour="#000000", depth=2, strength=0.5, sides="tl")
        fx.scanlines(c, every=3, amount=0.12, window_space=True)
        for gx in range(0, c.w, 16):
            c.vline(gx, 0, c.h - 1, lighten(self.viz_bg, 0.10))
        c.hline(0, c.w - 1, c.h // 2, lighten(self.viz_bg, 0.18))
        c.a[:, :, 3] = 255

    def eq_graph_line_colours(self) -> list[tuple[int, int, int]]:
        """19 RGB triples, row 0 = top of the graph, row 18 = bottom."""
        out = []
        for y in range(19):
            t = 1.0 - y / 18.0
            out.append(tuple(int(v) for v in
                             fx.heat_colour(t, self.heat_cool, self.heat_warm, self.heat_hot)[:3]))
        return out

    def paint_eq_preamp_line(self, c: Canvas) -> None:
        """113x1 -- the colour strip used to draw the preamp level line."""
        for x in range(c.w):
            c.px(x, 0, self.text_dim if (x % 4) < 2 else darken(self.text_dim, 0.4))
        c.a[:, :, 3] = 255

    # ==================================================================
    # PLAYLIST WINDOW  (tiled, window="playlist")
    # ==================================================================
    def _pl_plate(self, c: Canvas, repeat: str | None = None) -> None:
        """Playlist frame material.

        ``repeat`` says which axis this piece is tiled along, and the material
        is made invariant along it -- otherwise every tile boundary shows as a
        seam.  ``"v"`` = tiled down an edge (left/right rails), ``"h"`` = tiled
        across an edge (top/bottom), ``None`` = a corner, drawn once.
        """
        if repeat == "v":
            fx.linear_gradient(c, self.pl_face_hi, darken(self.pl_face, 0.18),
                               direction="h", window_space=False, dither=0.05)
            fx.apply_noise(c, amount=6.0, scale=2.2, seed=self.seed + 8,
                           sx=2.2, sy=1e6)
        elif repeat == "h":
            fx.linear_gradient(c, self.pl_face_hi, darken(self.pl_face, 0.18),
                               direction="v", window_space=False, dither=0.05)
            fx.apply_noise(c, amount=6.0, scale=2.2, seed=self.seed + 8,
                           sx=1e6, sy=2.2)
        else:
            fx.linear_gradient(c, self.pl_face_hi, darken(self.pl_face, 0.18),
                               direction="v", window_space=False, dither=0.05)
            fx.apply_noise(c, amount=6.0, scale=2.2, seed=self.seed + 8)

    def _pl_title_strip(self, c: Canvas, active: bool) -> None:
        hi = self.title_active_hi if active else self.title_inactive_hi
        lo = self.title_active_lo if active else self.title_inactive_lo
        fx.linear_gradient(c, hi, lo, direction="v", window_space=False, dither=0.05)
        fx.apply_noise(c, amount=6.0, scale=2.0, seed=self.seed + 7)
        c.hline(0, c.w - 1, 0, self.edge_black)
        c.hline(1, c.w - 2, 1, lighten(hi, 0.16))

    def paint_pl_top_left(self, c: Canvas, active: bool) -> None:
        """25x20 -- top-left corner of the playlist frame."""
        self._pl_title_strip(c, active)
        c.vline(0, 0, c.h - 1, self.edge_black)
        c.vline(1, 2, c.h - 1, self.edge_light)

    def paint_pl_title(self, c: Canvas, active: bool) -> None:
        """100x20 -- the centred title piece.  SPEC 5.1: ``SESSIONS``."""
        self._pl_title_strip(c, active)
        title = "SESSIONS"
        tcol = self.title_text_on if active else self.title_text_off
        tw = fonts.text_width(title, fonts.MICRO_4x5)
        tx = (c.w - tw) // 2
        c.box(tx - 5, 4, tw + 10, 11, mix(self.title_active_lo, self.edge_black, 0.35))
        fx.bevel_sunken(c, (tx - 5, 4, tw + 10, 11), light=self.edge_mid,
                        shadow=self.edge_black)
        fonts.draw_text(c, tx, 7, title, fonts.MICRO_4x5, tcol)

    def paint_pl_top_tile(self, c: Canvas, active: bool) -> None:
        """25x20 -- repeated horizontally along the top edge."""
        self._pl_title_strip(c, active)
        # pitch must divide the tile width or the grip jumps at every seam
        pitch = 5 if c.w % 5 == 0 else 4
        for gx in range(0, c.w, pitch):
            c.vline(gx, 5, 13, self.title_grip_lo)
            c.vline(gx + 1, 5, 13, self.title_grip_hi)

    def paint_pl_top_right(self, c: Canvas, active: bool) -> None:
        """25x20 -- top-right corner; the playlist close button's *normal*
        state is baked in at local (14, 3) by the builder."""
        self._pl_title_strip(c, active)
        c.vline(c.w - 1, 0, c.h - 1, self.edge_black)
        c.vline(c.w - 2, 2, c.h - 1, self.edge_mid)

    def paint_pl_left_tile(self, c: Canvas) -> None:
        """12x29 -- repeated down the left edge.  Must be y-invariant."""
        self._pl_plate(c, repeat="v")
        c.vline(0, 0, c.h - 1, self.edge_black)
        c.vline(1, 0, c.h - 1, self.edge_light)
        c.vline(c.w - 1, 0, c.h - 1, self.edge_black)
        c.vline(c.w - 2, 0, c.h - 1, darken(self.pl_face, 0.35))
        c.sub(c.w - 1, 0, 1, c.h).fill(self.pl_list_bg)

    def paint_pl_right_tile(self, c: Canvas) -> None:
        """20x29 -- repeated down the right edge; carries the scrollbar groove.

        The scroll handle rides at window ``x = W - 15``, i.e. local x 5..12.
        """
        self._pl_plate(c, repeat="v")
        c.sub(0, 0, 1, c.h).fill(self.pl_list_bg)
        c.vline(1, 0, c.h - 1, self.edge_black)
        c.vline(2, 0, c.h - 1, lighten(self.pl_face, 0.2))
        c.sub(4, 0, 10, c.h).fill(self.groove_bg)
        # vertical rims only: a bevel with horizontal edges would print a seam
        # across the groove at every 29px tile boundary
        c.vline(4, 0, c.h - 1, self.groove_rim_lo)
        c.vline(5, 0, c.h - 1, darken(self.groove_bg, 0.35))
        c.vline(13, 0, c.h - 1, self.groove_rim_hi)
        c.vline(c.w - 1, 0, c.h - 1, self.edge_black)
        c.vline(c.w - 2, 0, c.h - 1, self.edge_mid)

    def paint_pl_bottom_tile(self, c: Canvas) -> None:
        """25x38 -- repeated along the bottom edge on wide windows.  x-invariant."""
        self._pl_plate(c, repeat="h")
        c.hline(0, c.w - 1, c.h - 1, self.edge_black)
        c.hline(0, c.w - 1, c.h - 2, self.edge_mid)
        c.hline(0, c.w - 1, 0, darken(self.pl_face, 0.4))

    def paint_pl_bottom_left(self, c: Canvas) -> None:
        """125x38 -- bottom-left corner (buttons area in classic skins)."""
        self._pl_plate(c)
        c.hline(0, c.w - 1, 0, darken(self.pl_face, 0.4))
        c.vline(0, 0, c.h - 1, self.edge_black)
        c.vline(1, 0, c.h - 3, self.edge_light)
        c.hline(0, c.w - 1, c.h - 1, self.edge_black)
        c.hline(2, c.w - 1, c.h - 2, self.edge_mid)
        fx.vent(c, (8, 8, 46, 22), slots=5, direction="h", gap=2, slot_thickness=2,
                dark=darken(self.pl_face, 0.55), light=lighten(self.pl_face, 0.18))
        self.micro(c, 62, 12, "SESSIONS", font=fonts.MICRO_4x5)
        self.micro(c, 62, 22, "TODAY", font=fonts.MICRO_4x5)

    def paint_pl_bottom_right(self, c: Canvas) -> None:
        """150x38 -- bottom-right corner; carries the info and mini-time wells.

        Their window positions come from ``layout.playlist``
        (``runningInfoFromBottomRight``, ``miniTimeFromBottomRight``); this
        piece starts at window ``x = W - 150, y = H - 38``.
        """
        self._pl_plate(c)
        c.hline(0, c.w - 1, 0, darken(self.pl_face, 0.4))
        c.vline(c.w - 1, 0, c.h - 1, self.edge_black)
        c.vline(c.w - 2, 0, c.h - 2, self.edge_mid)
        c.hline(0, c.w - 1, c.h - 1, self.edge_black)
        c.hline(0, c.w - 2, c.h - 2, self.edge_mid)
        info_x, info_y = [int(v) for v in lval("playlist", "runningInfoFromBottomRight")]
        mini_x, mini_y = [int(v) for v in lval("playlist", "miniTimeFromBottomRight")]
        # convert "from bottom-right of the window" to local coords of this piece
        lx = info_x + 150
        ly = info_y + 38
        self.well(c, (lx - 2, ly - 1, 104, 8), colour=self.text_background(),
                  shadow_depth=0)
        mx = mini_x + 150
        my = mini_y + 38
        self.well(c, (mx - 2, my - 1, 30, 8), colour=self.text_background(),
                  shadow_depth=0)
        fx.screw(c, c.w - 8, 8, r=2, style="slot", body=self.edge_mid,
                 light=self.edge_light, shadow=self.edge_black, angle=45)

    def paint_pl_visualizer_background(self, c: Canvas) -> None:
        """75x38 -- the playlist's optional mini-visualiser well.

        Tokenamp does not place this piece in its own layout; it exists so
        third-party-compatible sheets are complete.  Keep it the same family as
        the main visualiser well.
        """
        c.fill(self.pl_face)
        self.well(c, (2, 2, c.w - 4, c.h - 4), colour=self.viz_bg)
        c.a[:, :, 3] = 255

    def paint_pl_scroll_handle(self, c: Canvas, pressed: bool) -> None:
        """8x18 -- opaque scrollbar handle."""
        c.fill(self.btn_face)
        self.button_face(c, pressed, double=False)
        dx, dy = self.press_offset(pressed)
        for k in range(-1, 2):
            y = c.h // 2 + k * 3 + dy
            c.hline(2 + dx, c.w - 3 + dx, y, self.btn_lo)
            c.hline(2 + dx, c.w - 3 + dx, y + 1, lighten(self.btn_face, 0.3))
        c.a[:, :, 3] = 255

    def paint_pl_close(self, c: Canvas, pressed: bool) -> None:
        """9x9 -- playlist close button (top-right corner)."""
        self.paint_title_button(c, "close", pressed)

    def paint_pl_collapse(self, c: Canvas, pressed: bool) -> None:
        """9x9 -- playlist window-shade (collapse) button."""
        self.paint_title_button(c, "shade", pressed)

    # ==================================================================
    # plfont -- the Sessions-list typeface (SPEC 3.2)
    # ==================================================================
    # The playlist rows are drawn with the skin's own bitmap face, never a
    # system font.  The builder writes a 16x6 grid (cell k = character code
    # 32+k, last cell = the ellipsis) to ``plfont.bmp``, and ``plfont.txt``
    # carries the metrics.  Pixels are an INK MASK: black = nothing, white =
    # full ink, grey = partial.  The app tints the mask with the pledit
    # ``Normal`` / ``Current`` colour over ``NormalBG`` / ``SelectedBG``, so a
    # grey halo reads as a phosphor glow in whatever colour the skin declares.

    #: subtlety of the Base face's phosphor halo (0 disables it)
    pl_font_halo = 0.28

    def pl_font_cell(self) -> tuple[int, int]:
        """``(cellW, cellH)`` of one plfont cell.  The sheet is 16x6 cells, so
        the default (8, 10) produces a 128x60 ``plfont.bmp``.

        Cap height 7, x-height 5, descenders 2, baseline on row 7; keep ink out
        of columns 0 and the last column so the halo has room.
        """
        return (8, 10)

    def paint_pl_font_glyph(self, c: Canvas, ch: str) -> None:
        """One plfont cell, already sized by :meth:`pl_font_cell` and pre-filled
        black.  Paint white for full ink and greys for partial coverage.

        ``ch`` is the character; the ellipsis cell is passed as ``"…"``.
        """
        fonts.draw_plfont_glyph(c, ch, ink="#ffffff")
        if self.pl_font_halo:
            fonts.halo(c, radius=1, strength=self.pl_font_halo)

    def pl_font_metrics(self) -> dict:
        """``plfont.txt`` ``[PlaylistFont]`` values.  A ``None`` value is
        omitted so the app's own default applies.

        * ``Monospace`` 0/1 -- 1 blits the whole cell and advances ``cellW``
        * ``Spacing``   pixels inserted between glyphs (proportional mode)
        * ``SpaceWidth`` advance of a blank cell (default ``max(2, cellW//2-1)``)
        * ``RowHeight`` row pitch of the list, **replacing**
          ``layout.playlist.rowHeight`` (default ``cellH + 1``)
        * ``OffsetY``   top of the cell within the row
        """
        cw, ch = self.pl_font_cell()
        return {"Monospace": 0, "Spacing": 1, "SpaceWidth": max(2, cw // 2 - 1),
                "RowHeight": ch + 1, "OffsetY": 0}

