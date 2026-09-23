"""win_main -- the main window: the closed book's front cover.

Everything is drawn in window coordinates through a Plate, so the same
function renders a zone into the 275x116 background and into any widget
porthole cut from it.
"""

from __future__ import annotations

import numpy as np

from skinkit.spec import Rect, lrect, lval, clutter_button_local, clutter_letters

from . import doodles as D
from . import marks
from . import materials as M
from . import palette as P
from . import pictos
from . import typeset as T
from .plate import Plate

# -- geometry (window coordinates) -------------------------------------------
PANEL_L = (20, 18, 82, 51)        # paper rect of the left label panel
PANEL_R = (107, 18, 161, 51)      # paper rect of the right label panel
SLOT = (17, 73, 246, 8)           # paper rect of the seek-bar slot
TITLE_H = 14


def spine_shade(w: int, h: int) -> np.ndarray:
    """Cloth is a touch darker toward the spine (left) and along the foot."""
    x = np.arange(w, dtype=np.float32)[None, :]
    y = np.arange(h, dtype=np.float32)[:, None]
    return (-0.060 * np.exp(-x / 16.0) - 0.030 * np.exp(-(h - 1 - y) / 9.0)
            + 0.0 * y).astype(np.float32)


class MainMixin:
    # ------------------------------------------------------------------
    # cover cloth, shared by main and EQ
    # ------------------------------------------------------------------
    def cover_cloth(self, p: Plate, window: str, w: int = 275, h: int = 116) -> None:
        extra = spine_shade(w, h)
        wear = M.edge_wear(w, h, M.SEED + (3 if window == "main" else 4))
        t = M.cloth_t(window)
        # rubbed edges: only the crowns of the weave go pale
        crown = np.clip((t - 0.5) / 0.08, 0, 1)
        extra = extra + wear * (0.035 + 0.075 * crown)
        M.lay_cloth(p, 0, 0, w, h, window=window, extra=extra)
        # the cloth turning over the board edge
        p.hline(0, w - 1, 0, P.CLAY_PALE, 0.55)
        p.vline(0, 1, h - 1, P.CLAY_PALE, 0.42)
        p.hline(1, w - 2, 1, P.CLAY_LIGHT, 0.30)
        p.vline(1, 2, h - 2, P.CLAY_LIGHT, 0.22)
        p.hline(0, w - 1, h - 1, P.CLAY_SHADOW, 0.80)
        p.vline(w - 1, 0, h - 1, P.CLAY_SHADOW, 0.70)
        p.hline(1, w - 2, h - 2, P.CLAY_DARK, 0.45)
        p.vline(w - 2, 1, h - 2, P.CLAY_DARK, 0.38)
        # corners rubbed through to the pale warp
        for cx, cy in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
            p.px(cx, cy, P.CLAY_PALE, 0.75)
        p.px(1, 1, P.CLAY_PALE, 0.5)
        p.px(w - 2, 1, P.CLAY_PALE, 0.35)

    def title_groove(self, p: Plate, w: int = 275) -> None:
        """The joint under the spine strip: a pressed groove with a lit lip."""
        p.hline(1, w - 2, TITLE_H, P.SHADOW_ON_CLOTH, 0.50)
        p.hline(1, w - 2, TITLE_H + 1, P.CLAY_LIGHT, 0.38)

    # ------------------------------------------------------------------
    # background
    # ------------------------------------------------------------------
    def paint_main_background(self, c) -> None:
        p = Plate(c)
        self.cover_cloth(p, "main")
        self.title_groove(p)
        self._spine_stitching(p)
        self._panel_left(p)
        self._panel_right(p)
        self._posbar_slot(p)
        self._cover_marks(p)
        p.opaque()

    def _spine_stitching(self, p: Plate) -> None:
        M.stitch_run(p, 4, 19, 94, vertical=True, pitch=8, stitch=5, seed=1)

    # -- left panel: play state, time, token-flow figure ----------------
    def _panel_left(self, p: Plate) -> None:
        x, y, w, h = PANEL_L
        M.cut_opening(p, x, y, w, h, window="main")
        # time plate-mark: minus + 4 digits as one impression
        M.plate_mark(p, 38, 26, 61, 13, margin=2)
        self.paint_time_frame(p.c)
        # visualiser plate-mark
        viz = lrect("main", "visualizer")
        M.plate_mark(p, viz.x, viz.y, viz.w, viz.h, margin=1)
        p.box(viz.x, viz.y, viz.w, viz.h, self.viz_bg)
        # figure caption under the visualiser, like a plate in a book
        T.letterpress(p, 25, 62, "FIG.1", "micro", ink=P.INK_SOFT)
        T.letterpress(p, 47, 62, "TOKEN FLOW", "micro", ink=P.INK_BODY)
        D.wobble_line(p, 47, 85, 68 - 0, P.CLAY_DEEP, a=0.0)   # reserved
        marks.mark(p, 95, 64, "tiny")
        # pencil guide-lines someone forgot to erase, above the time plate
        D.pencil_rule(p, 22, 99, 21, a=0.50, seed=2)

    def paint_time_frame(self, c) -> None:
        """The colon: two inked dots in the gap between digits 2 and 3."""
        p = Plate(c)
        for gy in (30, 35):
            p.box(72, gy, 2, 2, P.INK_BODY)
            p.px(71, gy, P.INK_GREY, 0.35)
            p.px(74, gy + 1, P.INK_GREY, 0.35)
            p.hline(72, 73, gy + 2, P.PAPER_HI, 0.9)

    # -- right panel: marquee, numeric fields, stamps, gauges -----------
    def _panel_right(self, p: Plate) -> None:
        x, y, w, h = PANEL_R
        M.cut_opening(p, x, y, w, h, window="main")
        # Marquee first: its plate-mark lays a shadow on the two rows above
        # itself, which would otherwise bite the bottom off the running head.
        # margin=1 keeps that shadow clear of the caption's last row.
        mq = lrect("main", "marquee")
        M.plate_mark(p, mq.x, mq.y, mq.w, mq.h, margin=1)
        # running head, with a rule running out to the edge of the page
        T.letterpress(p, 111, 19, "CLAUDE USAGE", "micro", ink=P.INK_BODY)
        p.hline(161, 253, 21, P.INK_GREY, 0.55)
        p.hline(161, 253, 22, P.PAPER_HI, 0.8)
        marks.mark(p, 260, 21, "tiny")
        for key in ("kbps", "khz"):
            r = lrect("main", key)
            M.plate_mark(p, r.x, r.y, r.w, r.h, margin=2)
        T.letterpress(p, 131, 44, "K/MIN", "micro", ink=P.INK_SOFT)
        T.letterpress(p, 171, 44, "ACTIVE", "micro", ink=P.INK_SOFT)
        # gauge captions
        T.letterpress(p, 110, 51, "SESSION", "micro", ink=P.INK_BODY)
        T.letterpress(p, 180, 51, "WEEK", "micro", ink=P.INK_BODY)

    # -- seek-bar slot --------------------------------------------------
    def _posbar_slot(self, p: Plate) -> None:
        x, y, w, h = SLOT
        M.cut_opening(p, x, y, w, h, window="main", depth=2)
        # hand-ruled scale: baseline with ticks rising from it
        rng = np.random.RandomState(M.SEED + 31)
        base_y = y + h - 2
        x0, x1 = 30, 249              # thumb-centre travel in window coords
        for xx in range(x0 - 3, x1 + 4):
            p.px(xx, base_y, P.INK_BODY, 0.80 + 0.2 * rng.rand())
        for k in range(41):
            tx = int(round(x0 + (x1 - x0) * k / 40.0))
            if k % 10 == 0:
                ln = 4
            elif k % 5 == 0:
                ln = 3
            else:
                ln = 1 + int(rng.rand() < 0.35)
            for i in range(1, ln + 1):
                p.px(tx, base_y - i, P.INK_BODY, 0.9 if i < ln else 0.6)
        for k, lab in ((0, "0"), (10, "25"), (20, "50"), (30, "75")):
            tx = int(round(x0 + (x1 - x0) * k / 40.0))
            T.letterpress(p, tx + 2, y, lab, "micro", ink=P.INK_SOFT, lip=0.0)

    def _cover_marks(self, p: Plate) -> None:
        """Blind-debossed maker's line along the foot of the cover, and the
        monogram roundel -- the primary mark -- in the clear cloth at the
        lower right."""
        T.blind(p, 18, 109, "HAND BOUND · TOKENAMP · No 5.1", "micro", on="cloth")
        marks.hero(p)

    def paint_about_logo(self, c) -> None:
        """The monogram roundel seen through the about-logo porthole; the
        full roundel is painted by ``_cover_marks`` and spills beyond this
        rect."""
        marks.hero(Plate(c))

    # ------------------------------------------------------------------
    # title bar
    # ------------------------------------------------------------------
    def _spine_cloth(self, p: Plate, active: bool, w: int = 275, window: str = "main") -> None:
        t = M.cloth_t(window)[0:TITLE_H, 0:w]
        dark = M.cloth_rgb(t, dye=-0.150)
        if active:
            rgb = dark
        else:
            faded = M.cloth_rgb(t, dye=-0.03, fade=0.62)
            x = np.arange(w, dtype=np.float32)
            m = np.clip((x - 20) / 10.0, 0, 1) * np.clip((240 - x) / 10.0, 0, 1)
            rgb = dark + (faded - dark) * m[None, :, None]
        p.paste(0, 0, rgb)
        p.hline(0, w - 1, 0, P.CLAY_LIGHT, 0.55)
        p.vline(0, 1, TITLE_H - 1, P.CLAY_LIGHT, 0.40)
        p.vline(w - 1, 0, TITLE_H - 1, P.CLAY_SHADOW, 0.75)
        p.hline(0, w - 1, TITLE_H - 1, P.SHADOW_ON_CLOTH, 0.55)
        p.hline(1, w - 2, 1, P.CLAY_LIGHT, 0.18)

    def _headband(self, p: Plate, x: int) -> None:
        """Striped silk head-band threads wrapped round the end of the spine."""
        for i, yy in enumerate(range(2, 12)):
            col = (P.THREAD[2], P.THREAD[1], P.INK_SOFT, P.INK_BODY)[i % 4] if False else \
                (P.THREAD[2] if (i // 2) % 2 == 0 else P.CLAY_SHADOW)
            p.hline(x, x + 2, yy, col)
            p.px(x, yy, P.PAPER_HI if (i // 2) % 2 == 0 else P.CLAY_DARK, 0.6)
            p.px(x + 2, yy, P.SHADOW_ON_CLOTH, 0.35)
        p.vline(x + 3, 3, 12, P.SHADOW_ON_CLOTH, 0.40)
        p.hline(x, x + 2, 12, P.SHADOW_ON_CLOTH, 0.45)

    def _title_text(self, p: Plate, text: str, active: bool, w: int = 275, y: int = 1,
                    spacing: int = 2):
        cov = T.coverage(text, "list", spacing=spacing, space=5)
        tw = cov.shape[1]
        tx = (w - tw) // 2
        T.foil(p, tx, y, "", cov=cov, dull=0.0 if active else 0.55, seed=len(text))
        return tx, tw

    def paint_title_bar(self, c, active: bool, variant: str) -> None:
        p = Plate(c, origin=(0, 0))
        self._spine_cloth(p, active)
        self._headband(p, 17)
        self._headband(p, 238)
        if variant == "shade":
            self._shade_furniture(p, active)
            p.opaque()
            return
        text = "TOKENAMP"
        tx, tw = self._title_text(p, text, active)
        if variant == "easter":
            # a foil lozenge either side of the title, a word space off its ink
            cov = T.coverage(text, "list", spacing=2, space=5)
            ink = np.nonzero((cov >= 0.5).any(axis=0))[0]
            half = marks.mask("tiny").shape[1] // 2
            lx, rx = tx + int(ink[0]) - 6 - half, tx + int(ink[-1]) + 6 + half
            marks.foil_mark(p, lx, 6)
            marks.foil_mark(p, rx, 6)
            left_end, right_start = lx - half - 3, rx + half + 4
        else:
            left_end, right_start = tx - 8, tx + tw + 8
        # a line of stitches either side of the title.  Beside the lozenges the
        # left run is set from its inner end, so both runs stop the same two
        # pixels short of their lozenge.
        n = left_end - 26
        M.stitch_run(p, 26, 6, n, vertical=False, pitch=7, stitch=4, seed=11,
                     phase=(n - 4) % 7 if variant == "easter" else 0)
        M.stitch_run(p, right_start, 6, 232 - right_start, vertical=False, pitch=7,
                     stitch=4, seed=12)
        p.opaque()

    def _shade_furniture(self, p: Plate, active: bool) -> None:
        # paper labels let into the strip: mini visualiser and the countdown
        mv = lrect("shade", "miniVisualizer")
        M.cut_opening(p, mv.x - 1, mv.y - 1, mv.w + 2, mv.h + 2, paper=False, depth=0)
        p.box(mv.x - 1, mv.y - 1, mv.w + 2, mv.h + 2, self.viz_bg)
        p.hline(mv.x - 1, mv.x + mv.w, mv.y - 1, P.SHADOW_ON_PAPER, 0.28)
        glyphs = lval("shade", "timeGlyphs")
        gx0, gy = int(glyphs[0][0]) - 2, int(glyphs[0][1])
        gx1 = int(glyphs[-1][0]) + 5 + 1
        M.cut_opening(p, gx0, gy - 1, gx1 - gx0, 8, paper=False, depth=0)
        p.box(gx0, gy - 1, gx1 - gx0, 8, self.text_background())
        p.hline(gx0, gx1 - 1, gy - 1, P.SHADOW_ON_PAPER, 0.28)
        cx = int(glyphs[1][0]) + 5
        p.px(cx, gy + 1, P.INK_BODY)
        p.px(cx, gy + 4, P.INK_BODY)
        T.foil(p, 24, 1, "", cov=T.coverage("T", "list"), dull=0.0 if active else 0.55, seed=3)
        marks.shade_mark(p)
        M.stitch_run(p, 47, 6, 26, vertical=False, pitch=7, stitch=4, seed=13)
        for key in ("previous", "play", "pause", "stop", "next", "eject"):
            r = lrect("shade", key)
            m = pictos.MINI[key]
            T.foil(p, r.x + (r.w - m.shape[1]) // 2, r.y + 1, "", cov=m,
                   dull=0.0 if active else 0.5, seed=r.x)

    def paint_title_button(self, c, which: str, pressed: bool) -> None:
        p = Plate(c)
        x, y = p.ox, p.oy
        # a blind-stamped square in the spine cloth
        t = M.cloth_t("main")[y:y + 9, x:x + 9]
        p.paste(x, y, M.cloth_rgb(t, dye=-0.245 if pressed else -0.195))
        p.hline(x, x + 8, y, P.SHADOW_ON_CLOTH, 0.55)
        p.vline(x, y + 1, y + 8, P.SHADOW_ON_CLOTH, 0.45)
        p.hline(x + 1, x + 8, y + 8, P.CLAY_LIGHT, 0.45)
        p.vline(x + 8, y + 1, y + 7, P.CLAY_LIGHT, 0.35)
        if pressed:
            p.hline(x + 1, x + 7, y + 1, P.SHADOW_ON_CLOTH, 0.35)
            p.vline(x + 1, y + 2, y + 7, P.SHADOW_ON_CLOTH, 0.28)
        d = 1 if pressed else 0
        m = pictos.TITLE[which]
        if pressed:
            p.mask(x + 2 + d, y + 2 + d, m, P.CLAY_PALE)
        else:
            T.foil(p, x + 2, y + 2, "", cov=m, seed=ord(which[0]))
        p.opaque()
