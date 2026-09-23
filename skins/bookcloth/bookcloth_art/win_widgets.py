"""win_widgets -- every moving part of the main window.

Card-stock transport keys lifted off the cloth, paper tabs with hand-drawn
checkboxes, a ribbon bookmark riding a hand-ruled scale, gouache wash gauges,
rubber-stamped beacons, and the letterpress figures and glyphs.

As everywhere in this skin the painters draw in *window* coordinates through a
Plate, so a widget porthole reproduces exactly the pixels the full-window pass
would have made there.
"""

from __future__ import annotations

import numpy as np

from skinkit.spec import clutter_button_local, clutter_letters, lrect, lval

from . import marks
from . import materials as M
from . import palette as P
from . import pictos
from . import type_marquee, type_numerals
from . import typeset as T
from .plate import Plate

# The card inside a transport sprite leaves this much room for its cast shadow.
KEY_MARGIN = 3


def _centre(outer_x: int, outer_w: int, inner_w: int) -> int:
    return outer_x + (outer_w - inner_w) // 2


class WidgetMixin:
    # ==================================================================
    # flat colours the app composites its own pixels onto
    # ==================================================================
    def digit_background(self):
        return P.PAPER_FLAT

    def text_background(self):
        return P.PAPER_FLAT

    # ==================================================================
    # clutter bar -- five index tabs cut into the page edge
    # ==================================================================
    def paint_clutter_bar(self, c, pressed=None, disabled: bool = False) -> None:
        p = Plate(c)
        bar = lrect("main", "clutterBar")
        # the strip the tabs are cut from: a sliver of page showing past the cloth
        M.cut_opening(p, bar.x, bar.y, bar.w, bar.h, window="main", depth=1)
        for letter in clutter_letters():
            r = clutter_button_local(letter)
            x, y = bar.x + r.x, bar.y + r.y
            down = (pressed or "").upper() == letter
            # each tab is a little card of page stock, the pressed one pushed in
            M.card(p, x + 1, y, r.w - 2, r.h - 1, window="main", on="paper",
                   pressed=down, notch=False, shadow=not down)
            cov = T.coverage(letter, "micro")
            tx = _centre(x + 1, r.w - 2, cov.shape[1])
            ty = y + (r.h - 1 - cov.shape[0]) // 2
            if down:
                T.letterpress(p, tx + 1, ty, "", cov=cov, ink=P.CLAY_DEEP, lip=0.0)
            elif disabled:
                T.blind(p, tx, ty, "", cov=cov, on="paper", strength=0.55)
            else:
                T.letterpress(p, tx, ty, "", cov=cov, ink=P.INK_SOFT, lip=0.7)
        p.opaque()

    # ==================================================================
    # transport -- six keys cut from ivory card stock
    # ==================================================================
    def paint_transport(self, c, which: str, pressed: bool) -> None:
        p = Plate(c)
        r = lrect("main", which)
        dx, dy = self.press_offset(pressed)
        kw, kh = r.w - KEY_MARGIN, r.h - KEY_MARGIN
        M.card(p, r.x + dx, r.y + dy, kw, kh, window="main", on="cloth", pressed=pressed)
        m = pictos.transport(which)
        ix = _centre(r.x + dx, kw, m.shape[1])
        iy = r.y + dy + (kh - m.shape[0]) // 2
        # play is inked in clay; everything else slate until it is pressed, when
        # it reads as freshly re-inked
        if pressed:
            ink = P.CLAY_DEEP
        elif which == "play":
            ink = P.CLAY_DARK
        else:
            ink = P.INK_BODY
        T.letterpress(p, ix, iy, "", cov=m, ink=ink, lip=0.0 if pressed else 0.75)
        p.opaque()

    # ==================================================================
    # paper tabs with a hand-drawn checkbox
    # ==================================================================
    def _tab(self, p: Plate, r, pressed: bool, selected: bool, label: str,
             seed: int = 0, on: str = "cloth") -> None:
        dx, dy = self.press_offset(pressed)
        tw, th = r.w - 2, r.h - 2
        M.card(p, r.x + dx, r.y + dy, tw, th, window="main", on=on, pressed=pressed,
               notch=False)
        # Box and label travel together as one group, centred on the tab, and
        # the letter-spacing closes up if the label would otherwise overrun --
        # ALERT only has 26 px of card to live on.
        BOX, GAP = 5, 2
        spacing = 1
        cov = T.coverage(label, "micro", spacing=spacing)
        if BOX + GAP + cov.shape[1] > tw - 2:
            spacing = 0
            cov = T.coverage(label, "micro", spacing=spacing)
        group = BOX + GAP + cov.shape[1]
        gx = r.x + dx + max(1, (tw - group) // 2)
        bx, by = gx, r.y + dy + (th - 5) // 2
        # the box, ruled by hand: the corners do not quite meet
        p.rect(bx, by, 5, 5, P.INK_SOFT, 0.90)
        p.px(bx, by, P.PAPER_FLAT, 0.55)
        p.px(bx + 4, by + 4, P.INK_BODY, 0.65)
        if selected:
            # filled in clay, with a little overshoot outside the lines
            p.box(bx + 1, by + 1, 3, 3, P.CLAY_DEEP)
            rng = np.random.RandomState(4100 + seed)
            for _ in range(3):
                ox = bx + int(rng.randint(0, 5))
                oy = by + int(rng.randint(0, 5))
                p.px(ox, oy, P.CLAY, 0.55)
            p.px(bx + 5, by + 1, P.CLAY, 0.45)
        tx = bx + BOX + GAP
        ty = r.y + dy + (th - cov.shape[0]) // 2
        T.letterpress(p, tx, ty, "", cov=cov,
                      ink=P.INK_BODY if selected else P.INK_SOFT,
                      lip=0.0 if pressed else 0.8)
        p.opaque()

    def paint_shuffle(self, c, pressed: bool, selected: bool) -> None:
        self._tab(Plate(c), lrect("main", "shuffle"), pressed, selected, "CYCLE", 1)

    def paint_repeat(self, c, pressed: bool, selected: bool) -> None:
        self._tab(Plate(c), lrect("main", "repeat"), pressed, selected, "ALERT", 2)

    def paint_eq_toggle(self, c, pressed: bool, selected: bool) -> None:
        self._tab(Plate(c), lrect("main", "eqButton"), pressed, selected, "EQ", 3,
                  on="paper")

    def paint_pl_toggle(self, c, pressed: bool, selected: bool) -> None:
        self._tab(Plate(c), lrect("main", "plButton"), pressed, selected, "PL", 4,
                  on="paper")

    # ==================================================================
    # seek bar -- the hand-ruled scale and its ribbon bookmark
    # ==================================================================
    def paint_posbar_background(self, c) -> None:
        # The slot and its ruled scale belong to the cover; redrawing them
        # through this porthole reproduces the background exactly.
        p = Plate(c)
        self.cover_cloth(p, "main")
        self._posbar_slot(p)
        p.opaque()

    def paint_posbar_thumb(self, c, pressed: bool) -> None:
        p = Plate(c)
        x, y = p.ox, p.oy
        w, h = c.w, c.h
        deep = pressed
        # a clay ribbon tab: the woven edge, a glazed highlight, a notched tail
        body = P.CLAY_DEEP if deep else P.CLAY
        p.box(x + 1, y, w - 2, h, body)
        p.box(x + 1, y, w - 2, 1, P.CLAY_LIGHT, 0.85)
        p.box(x + 1, y + h - 1, w - 2, 1, P.CLAY_SHADOW, 0.85)
        p.vline(x, y + 1, y + h - 2, P.CLAY_DARK, 0.85)
        p.vline(x + w - 1, y + 1, y + h - 2, P.CLAY_SHADOW, 0.9)
        # glaze: a soft diagonal sheen across the top third
        for k in range(2, w - 3):
            p.px(x + k, y + 1, P.CLAY_PALE, 0.55 if (k % 7) else 0.85)
        p.hline(x + 2, x + w - 4, y + 2, P.CLAY_LIGHT, 0.30)
        # the swallow-tail notch at the free end
        p.px(x + w - 2, y + h // 2, P.CLAY_DARK, 0.7)
        p.px(x + w - 3, y + h // 2, P.CLAY_DARK, 0.4)
        # a couple of loose threads where the ribbon was cut
        p.px(x + 1, y + 2, P.CLAY_PALE, 0.6)
        p.px(x + 1, y + h - 3, P.CLAY_PALE, 0.4)
        if not deep:
            M.soft_shadow(p, x + 1, y, w - 2, h, P.SHADOW_ON_PAPER, strength=0.30,
                          spread=1, dx=1, dy=1)
        p.opaque()

    # ==================================================================
    # gauges -- a band of gouache wash on a ruled paper strip
    # ==================================================================
    def _gauge(self, p: Plate, r, i: int, caption_seed: int) -> None:
        """A ruled paper trough with a band of wash growing along it.

        The sprite is 13 rows; the trough takes rows 1..9 so the impression's
        lit lip still has a row to fall on inside the panel's paper.
        """
        x, y, w = r.x, r.y, r.w
        bx0, bx1 = x + 2, x + w - 3
        by, bh = y + 2, 7
        M.plate_mark(p, bx0, by, bx1 - bx0 + 1, bh, margin=1)
        # the scale is ruled first, so the wash runs over its own tick marks
        rng = np.random.RandomState(4200 + caption_seed)
        for k in range(11):
            tx = int(round(bx0 + (bx1 - bx0) * k / 10.0))
            major = (k % 5 == 0)
            p.vline(tx, by + bh - (3 if major else 2), by + bh - 1,
                    P.INK_GREY, 0.70 if major else 0.45)
        p.hline(bx0, bx1, by + bh - 1, P.INK_GREY, 0.35)
        # the wash: grows left to right with the frame index
        run = int(round((bx1 - bx0 + 1) * i / 27.0))
        if run > 0:
            cols = np.stack([P.heat(k / max(1.0, bx1 - bx0)) for k in range(run)])
            lead = np.ones((bh - 1, run), dtype=np.float32)
            # a hand-painted leading edge: the brush does not stop square, and
            # the pigment thins as it runs out
            if run >= 2:
                for row in range(bh - 1):
                    lead[row, run - 1] = 0.30 + 0.60 * rng.rand()
                    if run >= 3:
                        lead[row, run - 2] = 0.80 + 0.20 * rng.rand()
                lead[0, run - 1] *= 0.55
                lead[-1, run - 1] *= 0.55
            M.wash_band(p, bx0, by, run, bh - 1, cols, seed=caption_seed, lead=lead)
            # pigment pools where the stroke began and along its lower edge
            p.vline(bx0, by, by + bh - 2, P.INK_SOFT, 0.12)

    def paint_volume_frame(self, c, i: int) -> None:
        p = Plate(c)
        self._gauge(p, lrect("main", "volume"), i, 1)
        p.opaque()

    def paint_balance_frame(self, c, i: int) -> None:
        p = Plate(c)
        self._gauge(p, lrect("main", "balance"), i, 2)
        p.opaque()

    def _tile_thumb(self, p: Plate, x: int, y: int, w: int, h: int,
                    pressed: bool) -> None:
        """A small terracotta tile: glazed face, darker biscuit edge."""
        face = P.CLAY_DEEP if pressed else P.CLAY
        if not pressed:
            M.soft_shadow(p, x, y, w, h, P.SHADOW_ON_PAPER, strength=0.34,
                          spread=1, dx=1, dy=1)
        p.box(x, y, w, h, face)
        # glaze: pooled and paler across the upper face, thinning downward
        for k in range(h):
            t = k / max(1, h - 1)
            if t < 0.45:
                p.hline(x, x + w - 1, y + k, P.CLAY_PALE,
                        (0.42 - 0.9 * t) * (0.5 if pressed else 1.0))
            elif t > 0.70:
                p.hline(x, x + w - 1, y + k, P.CLAY_DARK, (t - 0.70) * 0.9)
        p.hline(x, x + w - 1, y, P.CLAY_LIGHT, 0.85)
        p.hline(x, x + w - 1, y + h - 1, P.CLAY_SHADOW, 0.95)
        p.vline(x, y, y + h - 1, P.CLAY_LIGHT, 0.50)
        p.vline(x + w - 1, y, y + h - 1, P.CLAY_SHADOW, 0.85)
        p.px(x + 1, y + 1, P.PAPER_HI, 0.60 if not pressed else 0.25)
        # a fired tile has nipped corners, not square ones
        for cx, cy, col in ((x, y, P.CLAY_DARK), (x + w - 1, y, P.CLAY_DARK),
                            (x, y + h - 1, P.CLAY_SHADOW),
                            (x + w - 1, y + h - 1, P.CLAY_SHADOW)):
            p.px(cx, cy, col, 0.75)
        p.opaque()

    def paint_volume_thumb(self, c, pressed: bool) -> None:
        p = Plate(c)
        self._tile_thumb(p, p.ox + 1, p.oy + 1, c.w - 2, c.h - 2, pressed)

    def paint_balance_thumb(self, c, pressed: bool) -> None:
        self.paint_volume_thumb(c, pressed)

    # ==================================================================
    # beacons -- rubber stamps, not lamps
    # ==================================================================
    def _stamp(self, c, text: str, on: bool, ink, seed: int) -> None:
        p = Plate(c)
        r = lrect("main", "mono" if text == "LOCAL" else "stereo")
        cov = T.coverage(text, "micro")
        x = _centre(r.x, r.w, cov.shape[1])
        y = r.y + (r.h - cov.shape[0]) // 2
        if text == "LIVE":
            # the stamp carries the lozenge ahead of the word; set the pair
            # as one group, centred, so the lozenge stays inside the sprite
            sw = marks.mask("tiny").shape[1]
            gx = _centre(r.x, r.w, sw + 2 + cov.shape[1])
            x = gx + sw + 2
        if on:
            T.rubber_stamp(p, x, y, cov, ink=ink, seed=seed)
            if text == "LIVE":
                marks.stamp_mark(p, gx + sw // 2, y + 2, seed=seed)
        else:
            # off is not dark, it is simply not stamped: a blind deboss
            T.blind(p, x, y, "", cov=cov, on="paper", strength=0.75)
        p.opaque()

    def paint_mono(self, c, on: bool) -> None:
        self._stamp(c, "LOCAL", on, P.INK_BODY, 1)

    def paint_stereo(self, c, on: bool) -> None:
        self._stamp(c, "LIVE", on, P.CLAY_DEEP, 2)

    # ==================================================================
    # play state and the work lozenge
    # ==================================================================
    def paint_play_state(self, c, state: str) -> None:
        p = Plate(c)
        m = pictos.STATE[state]
        x = _centre(p.ox, c.w, m.shape[1])
        y = p.oy + (c.h - m.shape[0]) // 2
        ink = P.CLAY_DARK if state == "playing" else P.INK_BODY
        T.letterpress(p, x, y, "", cov=m, ink=ink, lip=0.8)
        p.opaque()

    def paint_work_indicator(self, c, working: bool) -> None:
        p = Plate(c)
        if working:
            marks.work(p, p.ox, p.oy, c.h)
        else:
            p.px(p.ox, p.oy + 4, P.PAPER_SH, 0.85)
            p.px(p.ox + 1, p.oy + 4, P.PAPER_DEEP, 0.55)
        p.opaque()

    # ==================================================================
    # the letterpress figures and the marquee face
    # ==================================================================
    def paint_digit(self, c, d) -> None:
        p = Plate(c, origin=(0, 0))
        c.fill(P.PAPER_FLAT)
        rows = type_numerals.DIGITS[d]
        cov = np.array([[{"#": 1.0, "+": 0.55, ".": 0.0}[k] for k in row]
                        for row in rows], dtype=np.float32)
        T.letterpress(p, 0, 0, "", cov=cov, ink=P.INK_CORE, lip=0.85)
        p.opaque()

    def paint_glyph(self, c, ch: str) -> None:
        p = Plate(c, origin=(0, 0))
        c.fill(P.PAPER_FLAT)
        g = type_marquee.GLYPHS
        rows = g.get(ch) or g.get(ch.upper()) or g[" "]
        cov = np.array([[{"#": 1.0, "+": 0.55, ":": 0.30, ".": 0.0}[k] for k in row]
                        for row in rows], dtype=np.float32)
        T.letterpress(p, 0, 0, "", cov=cov, ink=P.INK_BODY, lip=0.55)
        p.opaque()

    # ==================================================================
    # window-shade position strip
    # ==================================================================
    def paint_shade_position_background(self, c) -> None:
        p = Plate(c)
        x, y, w, h = p.ox, p.oy, c.w, c.h
        M.cut_opening(p, x, y, w, h, paper=False, depth=0)
        p.box(x, y, w, h, P.PAPER_FLAT)
        p.hline(x, x + w - 1, y, P.PAPER_DEEP, 0.75)
        p.vline(x, y, y + h - 1, P.PAPER_DEEP, 0.55)
        p.hline(x, x + w - 1, y + h - 1, P.PAPER_HI, 0.85)
        for k in range(1, w - 1, 3):
            p.px(x + k, y + h - 3, P.INK_GREY, 0.55)
        p.opaque()

    def paint_shade_position_thumb(self, c, which: str) -> None:
        p = Plate(c)
        x, y, w, h = p.ox, p.oy, c.w, c.h
        p.box(x, y, w, h, P.CLAY)
        p.hline(x, x + w - 1, y, P.CLAY_LIGHT, 0.9)
        p.hline(x, x + w - 1, y + h - 1, P.CLAY_SHADOW, 0.9)
        if which == "left":
            p.vline(x, y, y + h - 1, P.CLAY_LIGHT, 0.7)
        elif which == "right":
            p.vline(x + w - 1, y, y + h - 1, P.CLAY_SHADOW, 0.9)
        p.opaque()
