"""Walnut 76 -- main-window controls: piano keys, push switches, the tuning
dial and its needle, slide-pot gauges, glass annunciators, digits, glyphs."""

from __future__ import annotations

import numpy as np

from skinkit import fonts
from skinkit.canvas import Canvas, mix

import w76_common as K
import w76_digits as D
import w76_materials as M
import w76_palette as P
import w76_textfont as TF
from w76_microfonts import PANEL, TINY

SEAM = "#16130d"


def _mask_draw(c: Canvas, m: np.ndarray, colour) -> None:
    from skinkit.canvas import parse_colour
    c.a[:, :, :3][m] = parse_colour(colour)[:3]


class Widgets:
    """Mixin: main-window widget painters."""

    def press_offset(self, pressed: bool):
        return (1, 1) if pressed else (0, 0)

    # ------------------------------------------------------------------
    # transport: machined aluminium piano keys
    # ------------------------------------------------------------------
    def _key(self, c: Canvas, pressed: bool, first: bool = False) -> Canvas:
        """Paint one key; returns the face view icons are engraved into."""
        w, h = c.w, c.h
        c.fill(SEAM)
        kw = w - 1                                    # last column = hairline gap
        if not pressed:
            body = c.sub(0, 0, kw, h - 1)             # last row = shadow in the recess
            M.aluminium(body, level=0.70, sheen=0.9, seed=61)
            body.hline(0, kw - 1, 0, P.ALU[6])        # top chamfer, full highlight
            body.hline(1, kw - 2, 1, mix(P.ALU[6], P.ALU[5], 0.5))
            body.vline(0, 1, body.h - 1, P.ALU[5])
            body.vline(kw - 1, 1, body.h - 1, P.ALU[2])
            body.hline(1, kw - 2, body.h - 3, P.ALU[3])   # lower chamfer
            body.hline(0, kw - 1, body.h - 2, P.ALU[2])
            body.hline(0, kw - 1, body.h - 1, P.ALU[0])   # front edge
            body.px(0, 0, "#ffffff")
            body.px(1, 0, "#ffffff")
            c.hline(0, kw - 1, h - 1, "#0b0906")          # contact shadow
            return body
        body = c.sub(0, 0, kw, h)
        M.aluminium(body, level=0.50, sheen=0.5, seed=61)
        # tilted away from the light: no top highlight, neighbour's shadow falls
        # across the left edge, bottom closes up against the recess
        body.hline(0, kw - 1, 0, P.ALU[1])
        body.hline(0, kw - 1, 1, P.ALU[2])
        body.vline(0, 0, h - 1, P.ALU[0])
        M.shade_box(body, 1, 1, 1, h - 1, 0.80)
        body.vline(kw - 1, 1, h - 1, P.ALU[3])
        body.hline(1, kw - 1, h - 1, P.ALU[1])
        return body

    def _icon(self, face: Canvas, which: str, dx: int, dy: int, pressed: bool) -> None:
        w, h = face.w, face.h
        cx, cy = w // 2 + dx, (h - 2) // 2 + dy + (0 if pressed else 0)
        for pas, col in ((1, (251, 247, 234, 150 if not pressed else 70)), (0, P.INK)):
            oy = pas
            if which == "previous":
                face.box(cx - 5, cy - 3 + oy, 2, 7, col)
                self._tri(face, cx - 2, cy - 3 + oy, 4, 7, "left", col)
                self._tri(face, cx + 2, cy - 3 + oy, 4, 7, "left", col)
            elif which == "next":
                self._tri(face, cx - 5, cy - 3 + oy, 4, 7, "right", col)
                self._tri(face, cx - 1, cy - 3 + oy, 4, 7, "right", col)
                face.box(cx + 4, cy - 3 + oy, 2, 7, col)
            elif which == "play":
                self._tri(face, cx - 3, cy - 4 + oy, 7, 9, "right", col)
            elif which == "pause":
                face.box(cx - 3, cy - 3 + oy, 2, 7, col)
                face.box(cx + 1, cy - 3 + oy, 2, 7, col)
            elif which == "stop":
                face.box(cx - 3, cy - 3 + oy, 7, 7, col)
            elif which == "eject":
                self._tri(face, cx - 4, cy - 4 + oy, 9, 5, "up", col)
                face.box(cx - 4, cy + 2 + oy, 9, 2, col)
            else:
                raise ValueError(which)

    def paint_transport(self, c: Canvas, which: str, pressed: bool) -> None:
        face = self._key(c, pressed)
        dx, dy = self.press_offset(pressed)
        self._icon(face, which, dx, dy, pressed)
        c.a[:, :, 3] = 255

    # ------------------------------------------------------------------
    # push switches: black plastic cap + amber jewel
    # ------------------------------------------------------------------
    def _switch(self, c: Canvas, pressed: bool, selected: bool, text: str, font=TINY,
                jewel_r: int = 2, spacing: int | None = None, lamp: bool = True,
                arrow: bool = False) -> None:
        w, h = c.w, c.h
        o = 1 if pressed else 0
        # seam round the cap (the cap sits in a slot in the fascia)
        c.hline(0, w - 1, 0, SEAM)
        c.vline(0, 0, h - 1, SEAM)
        if pressed:
            c.hline(0, w - 1, 1, SEAM)
            c.vline(1, 0, h - 1, SEAM)
            c.hline(1, w - 1, h - 1, P.ALU[6])
            c.vline(w - 1, 1, h - 1, P.ALU[6])
        else:
            # raised cap throws a contact shadow down-right, slot lip is lit
            c.hline(1, w - 1, h - 1, SEAM)
            c.vline(w - 1, 1, h - 1, SEAM)
        cap = c.sub(1 + o, 1 + o, w - 2 - o, h - 2 - o)
        M.plastic(cap, level=0.62 if not pressed else 0.38, seed=17, pressed=pressed)
        if not pressed:
            cap.hline(0, cap.w - 1, 0, "#55595e")
            cap.vline(0, 1, cap.h - 1, P.PLASTIC[3])
            cap.px(0, 0, "#7d8187")
            cap.hline(1, cap.w - 1, cap.h - 1, "#040405")
            cap.vline(cap.w - 1, 1, cap.h - 1, "#040405")
            cap.hline(1, cap.w - 2, cap.h - 2, P.PLASTIC[1])
        else:
            cap.hline(0, cap.w - 1, 0, "#000000")
            cap.vline(0, 0, cap.h - 1, "#000000")
            cap.hline(1, cap.w - 1, cap.h - 1, P.PLASTIC[2])
        cy = cap.h // 2
        x = 2
        if lamp:
            jx = x + jewel_r
            M.jewel(cap, jx, cy, selected, r=jewel_r, halo=1.0)
            x = jx + jewel_r + 3
        tw_ = K.tw(text, font, spacing)
        avail = cap.w - x - (7 if arrow else 1)
        tx = x + max(0, (avail - tw_) // 2)
        ty = (cap.h - font.h) // 2
        ink = "#fff3d2" if selected else P.CREAM
        if pressed and not selected:
            ink = P.CREAM_DIM
        fonts.draw_text(cap, tx, ty, text, font, ink, spacing=spacing)
        if arrow:
            self._tri(cap, cap.w - 8, cy - 1, 5, 3, "down", ink)
        c.a[:, :, 3] = 255

    def paint_shuffle(self, c: Canvas, pressed: bool, selected: bool) -> None:
        # column 46 is shared with ALERT's column 0: always the seam
        self._switch(c.sub(0, 0, c.w - 1, c.h), pressed, selected, "CYCLE", PANEL, spacing=2)
        c.vline(c.w - 1, 0, c.h - 1, SEAM)
        c.a[:, :, 3] = 255

    def paint_repeat(self, c: Canvas, pressed: bool, selected: bool) -> None:
        self._switch(c, pressed, selected, "ALERT", TINY, jewel_r=1)

    def paint_eq_toggle(self, c: Canvas, pressed: bool, selected: bool) -> None:
        self._switch(c, pressed, selected, "EQ", PANEL, jewel_r=1)

    def paint_pl_toggle(self, c: Canvas, pressed: bool, selected: bool) -> None:
        self._switch(c, pressed, selected, "PL", PANEL, jewel_r=1)

    # ------------------------------------------------------------------
    # the tuning dial
    # ------------------------------------------------------------------
    def paint_posbar_background(self, c: Canvas) -> None:
        c.fill(P.GLASS_FLAT)
        c.hline(0, c.w - 1, 0, "#000000")
        c.vline(0, 0, c.h - 1, "#000000")
        c.hline(1, c.w - 1, c.h - 1, "#171c1e")
        c.vline(c.w - 1, 1, c.h - 1, "#171c1e")
        ghost, dim, mid = "#07262a", P.TEAL[1], P.TEAL[2]
        x0, span = 14.0, 219.0
        c.hline(3, c.w - 4, 1, ghost)
        for k in range(51):
            tx = int(round(x0 + span * k / 50.0))
            if k % 5 == 0:
                c.vline(tx, 1, 4, mid)
                label = str(k // 5)
                lx = tx + 2 if k < 50 else tx - K.tw(label, TINY) - 1
                K.legend(c, lx, 4, label, TINY, mid if k % 25 == 0 else dim)
            else:
                c.vline(tx, 1, 2, dim)
        # half marks
        for k in range(10):
            tx = int(round(x0 + span * (k + 0.5) / 10.0))
            c.vline(tx, 1, 3, dim)
        # end stops and a soft glare run on the static glass
        K.legend(c, 3, 3, "<", TINY, ghost)
        M.glare(c, 196, slope=-0.55, width=5.0, strength=0.16)
        c.hline(0, c.w - 1, 0, "#000000")
        c.a[:, :, 3] = 255

    def paint_posbar_thumb(self, c: Canvas, pressed: bool) -> None:
        w, h = c.w, c.h
        c.fill("#080c0e")                                  # smoked cursor lens
        # carriage rails
        c.hline(0, w - 1, 0, P.CHROME[2])
        c.hline(0, w - 1, h - 1, P.CHROME[1])
        for x0 in (0, w - 4):
            blk = c.sub(x0, 0, 4, h)
            blk.fill(P.CHROME[1])
            blk.vline(0, 0, h - 1, P.CHROME[2])
            blk.vline(1, 1, h - 2, P.CHROME[3] if x0 == 0 else P.CHROME[2])
            blk.vline(3, 0, h - 1, P.CHROME[0])
            blk.hline(0, 3, 0, P.CHROME[3])
            blk.hline(0, 3, h - 1, P.CHROME[0])
            for yy in (3, 5):                               # knurl notches
                blk.px(2, yy, P.CHROME[0])
        c.px(4, 0, P.CHROME[3])
        c.px(5, 0, P.CHROME[3])
        c.hline(12, 16, 0, P.CHROME[1])
        # lens: glare along the top, magnified ghost ticks
        c.hline(5, w - 6, 1, "#1a2427")
        c.hline(5, 9, 2, "#121a1d")
        for tx in (8, 20):
            c.vline(tx, 2, 4, P.TEAL[1])
        # the needle
        nx = w // 2
        core = P.RED_CORE if pressed else P.RED[2]
        M.bloom(c.sub(4, 1, w - 8, h - 2), nx - 4, 3.5, P.RED[2],
                radius=7.5 if pressed else 5.0, strength=0.85 if pressed else 0.55, aspect=0.8)
        c.vline(nx - 1, 1, h - 2, P.RED[1] if not pressed else P.RED[2])
        c.vline(nx + 1, 1, h - 2, P.RED[1] if not pressed else P.RED[2])
        c.vline(nx, 1, h - 2, core)
        c.px(nx, 0, P.RED[2])
        c.px(nx, h - 1, P.RED[1])
        if pressed:
            c.px(nx, 1, "#ffffff")
        c.a[:, :, 3] = 255

    # ------------------------------------------------------------------
    # slide-pot gauges (volume = SESSION, balance = WEEK)
    # ------------------------------------------------------------------
    def _gauge(self, c: Canvas, i: int, nseg: int, centre0: float, travel: float) -> None:
        w = c.w
        # --- backlit level scale: a slit of glass above the slot -------------
        gx0, gx1 = 2, w - 3
        c.box(gx0 - 1, 1, gx1 - gx0 + 3, 5, "#000000")
        c.hline(gx0, gx1 + 1, 5, P.ALU[6])
        c.vline(gx1 + 1, 2, 5, P.ALU[6])
        c.box(gx0, 2, gx1 - gx0 + 1, 3, P.GLASS_FLAT)
        # The lit run grows with the frame index, and the leading segment fades
        # up fractionally rather than snapping on.  That reads as a smoother
        # sweep and keeps all 28 frames distinct on the short balance ladder,
        # where only 11 segments fit across the slit.
        lit = i / 27.0 * nseg
        lit_n = int(lit)
        lead = lit - lit_n
        for k in range(nseg):
            t = k / max(1, nseg - 1)
            sx = gx0 + 1 + k * 3
            if sx + 1 > gx1:
                break
            ghost = P.level_ghost(t)
            if k < lit_n:
                col = P.level_colour(t)
            elif k == lit_n and lead > 0.0:
                col = mix(ghost, P.level_colour(t), lead)
            else:
                c.box(sx, 2, 2, 3, ghost)
                continue
            c.box(sx, 2, 2, 3, col)
            c.px(sx, 2, mix(col, "#ffffff", 0.55))
            c.px(sx + 1, 4, mix(col, "#000000", 0.25))
            # bleed into the gap after it
            c.vline(sx + 2, 2, 4, mix(col, P.GLASS_FLAT, 0.72))
        # --- the pot slot ---------------------------------------------------
        sx0, sx1 = 4, w - 5
        c.hline(sx0, sx1, 7, "#000000")
        c.hline(sx0 - 1, sx1 + 1, 8, P.PLASTIC[0])
        c.hline(sx0 - 1, sx1 + 1, 9, P.PLASTIC[0])
        c.hline(sx0, sx1, 10, P.ALU[6])
        c.px(sx0 - 1, 7, P.ALU[1])
        c.px(sx1 + 1, 7, P.ALU[1])
        c.px(sx1 + 2, 8, P.ALU[6])
        c.px(sx1 + 2, 9, P.ALU[6])
        c.hline(sx0 + 2, sx1 - 2, 9, P.PLASTIC[1])
        # --- engraved index ticks under the slot -----------------------------
        for k in range(11):
            tx = int(round(centre0 + travel * k / 10.0))
            c.px(tx, 11, P.INK)
            if k % 5 == 0:
                c.px(tx, 12, P.INK)
        c.a[:, :, 3] = 255

    def paint_volume_frame(self, c: Canvas, i: int) -> None:
        self._gauge(c, i, 21, 7.0, 51.0)

    def paint_balance_frame(self, c: Canvas, i: int) -> None:
        self._gauge(c, i, 11, 7.0, 24.0)

    def _slider_cap(self, c: Canvas, pressed: bool, vertical: bool = False) -> None:
        """Knurled aluminium slider cap, black index line, bright top edge."""
        w, h = c.w, c.h
        M.aluminium(c, level=0.72 if not pressed else 0.52, sheen=0.0, seed=88,
                    fixed_origin=(0, 0), streak=0.6)
        n = h if vertical else w
        for k in range(1, n - 1):
            if vertical:
                if k % 2 == 0:
                    M.shade_box(c, 1, k, w - 2, 1, 0.74)
                else:
                    M.shade_box(c, 1, k, w - 2, 1, 1.10)
            else:
                if k % 2 == 0:
                    M.shade_box(c, k, 1, 1, h - 2, 0.74)
                else:
                    M.shade_box(c, k, 1, 1, h - 2, 1.10)
        hi = P.ALU[6] if not pressed else P.ALU[3]
        c.hline(0, w - 1, 0, hi)
        c.vline(0, 0, h - 1, P.ALU[5] if not pressed else P.ALU[2])
        c.hline(0, w - 1, h - 1, P.ALU[0])
        c.vline(w - 1, 0, h - 1, P.ALU[0] if not pressed else P.ALU[1])
        if not pressed:
            c.hline(1, w - 2, 1, mix(P.ALU[6], P.ALU[5], 0.4))
            c.px(0, 0, "#ffffff")
            c.px(1, 0, "#ffffff")
        # index line in a polished flat
        if vertical:
            cy = h // 2
            c.box(1, cy - 1, w - 2, 3, P.ALU[5] if not pressed else P.ALU[3])
            c.hline(1, w - 2, cy, P.INK if not pressed else P.RED[1])
            c.hline(1, w - 2, cy + 1, P.ALU[6] if not pressed else P.ALU[4])
        else:
            cx = w // 2
            c.box(cx - 1, 1, 3, h - 2, P.ALU[5] if not pressed else P.ALU[3])
            c.vline(cx, 1, h - 2, P.INK if not pressed else P.RED[1])
            c.vline(cx + 1, 1, h - 2, P.ALU[6] if not pressed else P.ALU[4])
        c.a[:, :, 3] = 255

    def paint_volume_thumb(self, c: Canvas, pressed: bool) -> None:
        self._slider_cap(c, pressed)

    def paint_balance_thumb(self, c: Canvas, pressed: bool) -> None:
        self._slider_cap(c, pressed)

    # ------------------------------------------------------------------
    # annunciators behind the glass
    # ------------------------------------------------------------------
    def _beacon(self, c: Canvas, text: str, on: bool, ramp, x: int) -> None:
        ghost, body, core = ramp
        m = np.zeros((c.h, c.w), dtype=bool)
        tm = fonts.text_mask(text, TINY)
        ty = (c.h - 5) // 2 + 1
        m[ty:ty + 5, x + 5:x + 5 + tm.shape[1]] = tm
        dot = np.zeros_like(m)
        dot[ty + 1:ty + 4, x:x + 3] = True
        dot[ty + 1, x] = dot[ty + 3, x] = dot[ty + 1, x + 2] = dot[ty + 3, x + 2] = False
        dot[ty + 1, x + 1] = dot[ty + 3, x + 1] = True
        if on:
            M.glow_mask(c, m | dot, body, strength=0.42, diag=0.5)
            _mask_draw(c, m, body)
            _mask_draw(c, dot, body)
            c.px(x + 1, ty + 2, core)
            # a second, wider veil of light in the glass
            M.bloom(c, x + 1, ty + 2, body, radius=5.0, strength=0.22)
            _mask_draw(c, m, mix(body, core, 0.25))
            c.px(x + 1, ty + 2, core)
        else:
            _mask_draw(c, m, ghost)
            _mask_draw(c, dot, ghost)
        c.a[:, :, 3] = 255

    def paint_mono(self, c: Canvas, on: bool) -> None:
        self._beacon(c, "LOCAL", on, ("#082b2e", P.TEAL[3], P.TEAL[4]), 1)

    def paint_stereo(self, c: Canvas, on: bool) -> None:
        self._beacon(c, "LIVE", on, ("#2c0a07", P.RED[2], P.RED_CORE), 3)

    def paint_play_state(self, c: Canvas, state: str) -> None:
        m = np.zeros((c.h, c.w), dtype=bool)
        if state == "playing":
            for i in range(5):
                k = abs(i - 2) if False else 0
            rowsp = ["#....", "###..", "#####", "###..", "#...."]
            for j, r in enumerate(rowsp):
                for i, ch in enumerate(r):
                    if ch == "#":
                        m[2 + j, 2 + i] = True
            m[1, 2] = m[7, 2] = True
            m[2, 3] = m[6, 3] = True
            col, core = "#8af3e6", P.TEAL[4]
        elif state == "paused":
            m[1:8, 2:4] = True
            m[1:8, 5:7] = True
            col, core = P.PILOT[2], P.PILOT[3]
        else:
            m[2:7, 2:7] = True
            col, core = P.RED[1], P.RED[2]
        M.glow_mask(c, m, col, strength=0.36, diag=0.4)
        _mask_draw(c, m, col)
        c.a[:, :, 3] = 255

    def paint_work_indicator(self, c: Canvas, working: bool) -> None:
        if working:
            M.bloom(c, 0.5, 4, P.PILOT[2], radius=3.2, strength=0.5)
            c.box(0, 2, 2, 5, P.PILOT[2])
            c.vline(0, 3, 5, P.PILOT[3])
        else:
            c.box(0, 2, 2, 5, "#2a1804")
            c.px(0, 2, "#3a2206")
        c.a[:, :, 3] = 255

    # ------------------------------------------------------------------
    # digits and the marquee face
    # ------------------------------------------------------------------
    digit_on = D.ON

    def paint_digit(self, c: Canvas, d) -> None:
        D.paint(c, d, self.digit_background())

    def paint_glyph(self, c: Canvas, ch: str) -> None:
        c.fill(self.text_background())
        full, soft = "#7feee0", mix(P.TEAL[2], P.GLASS_FLAT, 0.30)
        for y, row in enumerate(TF.rows(ch)):
            for x, k in enumerate(row):
                if k == "#":
                    c.px(x, y, full)
                elif k == "+":
                    c.px(x, y, soft)
        c.a[:, :, 3] = 255

    # ------------------------------------------------------------------
    # window-shade mini dial
    # ------------------------------------------------------------------
    def paint_shade_position_background(self, c: Canvas) -> None:
        c.fill(P.GLASS_FLAT)
        for x in range(1, c.w - 1, 3):
            c.vline(x, 0, 1 if (x - 1) % 6 else 2, P.TEAL[1])
        c.hline(0, c.w - 1, c.h - 1, "#07262a")
        c.a[:, :, 3] = 255

    def paint_shade_position_thumb(self, c: Canvas, which: str) -> None:
        c.fill(P.GLASS_FLAT)
        core = {"left": P.RED[2], "center": P.RED_CORE, "right": "#ff7a5e"}[which]
        c.vline(0, 0, c.h - 1, P.RED[0])
        c.vline(2, 0, c.h - 1, P.RED[0])
        c.vline(1, 0, c.h - 1, core)
        if which == "left":
            c.px(0, 0, P.RED[1])
        elif which == "right":
            c.px(2, c.h - 1, P.RED[1])
        else:
            c.px(0, 3, P.RED[1])
            c.px(2, 3, P.RED[1])
        c.a[:, :, 3] = 255
