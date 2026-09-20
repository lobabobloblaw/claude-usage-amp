"""selftest -- exercise the toolkit itself, not a built skin.

``python3 -m skinkit.selftest`` (from ``skins/``) does two things:

1. **Smoke test** every public primitive, effect and font helper, so a change
   to the toolkit cannot silently break a call an artist depends on.
2. **Prove the underlay model** with a throwaway theme whose only override is a
   loud diagonal background: sprites cut for widgets that paint nothing must
   come out byte-identical to the background at their layout rect, the baked
   ``main.bmp`` must agree with the sheet sprites, and a window-space texture
   must be identical whether it is painted whole or cut.

:mod:`skinkit.validate` checks a *built skin*; this checks the *toolkit*.
Run both.
"""

from __future__ import annotations

import sys
import traceback

import numpy as np

from . import fonts, fx, spec
from .canvas import Canvas

__all__ = ["run", "main"]


class _Runner:
    def __init__(self, verbose: bool = False):
        self.failures: list[tuple[str, BaseException]] = []
        self.passed = 0
        self.verbose = verbose

    def check(self, name: str, cond: bool, detail: str = "") -> None:
        if cond:
            self.passed += 1
            if self.verbose:
                print(f"  ok   {name}")
        else:
            self.failures.append((name, AssertionError(detail or name)))
            print(f"  FAIL {name}{': ' + detail if detail else ''}")

    def call(self, name: str, fn) -> None:
        try:
            fn()
            self.passed += 1
            if self.verbose:
                print(f"  ok   {name}")
        except Exception as exc:  # noqa: BLE001 - reporting is the point
            self.failures.append((name, exc))
            print(f"  FAIL {name}: {exc!r}")
            if self.verbose:
                traceback.print_exc()


def _smoke(r: _Runner) -> None:
    def c() -> Canvas:
        return Canvas(40, 24, origin=(17, 33), window="main", fill="#404850")

    r.call("gradients", lambda: (
        fx.linear_gradient(c(), "#123456", "#abcdef"),
        fx.linear_gradient(c(), "#123456", "#abcdef", dither=0.06, steps=6, direction=(1, -1)),
        fx.linear_gradient(c(), stops=[(0, "#000"), (0.5, "#f00"), (1, "#fff")], direction="dl"),
        fx.gradient_fill(c(), [(0, "#111"), (1, "#eee")]),
        fx.radial_gradient(c(), 20, 12, 18, "#fff", "#000", dither=0.05, aspect=1.6),
        *[fx.linear_gradient(c(), "#000", "#fff", direction=d)
          for d in ("v", "h", "up", "left", "d", "dl")]))
    r.call("noise", lambda: (
        fx.value_noise(c(), 8.0, 3), fx.fbm(c(), 16.0, 4, seed=2),
        fx.apply_noise(c(), 8, 2.5, 1, octaves=3, tint_colour="#ff0000"),
        fx.speckle(c(), 0.06, 4, light="#fff", dark="#000"),
        fx.bayer_field(c()), fx.window_grid(c()),
        fx.ramp([(0, "#000"), (1, "#fff")], 0.3), fx.heat_colour(0.7)))
    r.call("bevels", lambda: (
        fx.bevel_raised(c(), n=2), fx.bevel_sunken(c(), n=2),
        fx.bevel_double(c(), raised=False), fx.bevel_double(c(), raised=True),
        *[fx.bevel(c(), corner=k) for k in ("mix", "light", "shadow", "split", "skip", None)]))
    r.call("shadows and glow", lambda: (
        fx.inner_shadow(c(), depth=3, sides="tlbr"), fx.drop_shadow(c(), blur=1),
        fx.glow(c(), np.zeros((24, 40), bool), "#0f0", 2),
        fx.glow(c(), [(5, 5), (9, 9)], "#0f0", 3)))
    r.call("materials", lambda: (
        *[fx.brushed_metal(c(), "#8d949c", d, 0.2, 3) for d in ("h", "v")],
        fx.wood_grain(c(), ["#c8a070", "#9a6a3c", "#5c3518"], 5, rings=7),
        fx.scanlines(c(), every=3, colour="#fff"), fx.glass_glare(c(), strength=0.2)))
    r.call("hardware", lambda: (
        *[fx.screw(c(), 10, 10, 3, s) for s in ("slot", "phillips", "hex")],
        fx.rivet(c(), 10, 10, 2),
        *[fx.vent(c(), (2, 2, 30, 18), 4, d) for d in ("h", "v")],
        fx.grille(c(), pitch=3, light="#fff"), fx.perforation(c(), pitch=3, r=1),
        *[fx.led(c(), 5, 5, 4, 3, "#5fe07a", on=b) for b in (True, False)],
        fx.hazard_stripes(c(), width=5, slope=-1)))
    r.call("text relief and palette", lambda: (
        fx.emboss_text(c(), 2, 2, "ABC"), fx.engrave_text(c(), 2, 9, "XYZ"),
        fx.quantize(c(), 16, dither=True), fx.palette_lock(c(), ["#000", "#888", "#fff"])))
    r.call("canvas primitives", lambda: (lambda k: (
        k.px(1, 1, "#f00"), k.poke(2, 2, (0, 255, 0, 128)), k.hline(0, 9, 3, "#fff"),
        k.vline(3, 0, 9, "#fff"), k.rect(1, 1, 10, 10, "#0ff"), k.frame("#f0f", 2),
        k.line(0, 0, 39, 23, "#ff0"), k.polyline([(1, 1), (9, 3), (4, 9)], "#fff", closed=True),
        k.polygon([(5, 5), (20, 7), (12, 18)], "#080", outline="#0f0"),
        k.circle(20, 12, 6, "#fff"), k.disc(10, 10, 4, "#f00"),
        k.ellipse(2, 2, 16, 9, "#0ff", fill=True), k.tint("#f00", 0.3),
        k.adjust(5, 1.1, 1.2), k.multiply(0.9), k.set_alpha(255),
        k.apply_mask(k.colour_mask("#f00", 8), "#00f"), k.mask_keep(k.alpha_mask()),
        k.luma(), k.masked_copy(k.alpha_mask()),
        k.paste_array(np.zeros((4, 4), np.uint8), 1, 1),
        k.blit(Canvas(5, 5, fill="#fff"), 2, 2, alpha=False),
        k.over(Canvas(5, 5, fill=(255, 0, 0, 128)), 3, 3),
        k.crop(0, 0, 8, 8), k.sub(0, 0, 8, 8), k.copy(), k.opaque("#000"),
        k.to_pil(), k.get(1, 1), k.get_rgb(1, 1)))(c()))
    r.call("fonts", lambda: (
        *[fonts.draw_text(c(), 1, 1, "AZ09 MW", f, "#fff", shadow="#000")
          for f in (fonts.FONT_5x6, fonts.MICRO_4x5, fonts.MICRO_3x5)],
        fonts.draw_text(c(), 0, 1, "MID", fonts.MICRO_4x5, "#fff", align="center", width=40),
        fonts.text_mask("HELLO", fonts.MICRO_4x5),
        *[fonts.draw_glyph(c(), 0, 0, ch, fonts.FONT_5x6, "#fff") for ch in spec.font_chars()],
        *[fonts.seven_segment(Canvas(9, 13, fill="#000"), d, "#0f0", "#030", slant=0.2)
          for d in list(range(10)) + ["blank", "minus", "-"]],
        *[fonts.dot_matrix(Canvas(9, 13, fill="#000"), d, "#0f0", "#020")
          for d in list(range(10)) + ["blank", "minus"]]))
    r.call("plfont helpers", lambda: (
        fonts.plfont_cell_chars(), fonts.plfont_cell_index("A"),
        fonts.plfont_cell_rect("z", 8, 10),
        fonts.plfont_advance(np.zeros((10, 8, 3), np.uint8)),
        fonts.fold_to_ascii("Ångström — “x”…"),
        fonts.embolden(fonts.plfont_rows("A")),
        fonts.slant_rows(fonts.plfont_rows("A"), 0.3),
        fonts.dot_matrixise(fonts.plfont_rows("A"), 2, 1, (16, 20)),
        fonts.halo(Canvas(8, 10, fill="#fff"), 1, 0.3)))

    # the font grid must cover every character sprites.json declares
    missing = [ch for ch in spec.font_chars() if not fonts.FONT_5x6.has(ch)]
    r.check("FONT_5x6 covers every font.rows character", not missing,
            f"missing {missing!r}")
    # Column 4 of a 5x6 cell is the inter-glyph gap.  M, W and the ellipsis are
    # the documented exceptions: they cannot be drawn legibly in four columns,
    # and the real classic player font lets them use the full cell too, so they
    # may touch the glyph that follows them.
    gap_exempt = {"…", "M", "W"}
    wide = [ch for ch in spec.font_chars()
            if ch not in gap_exempt
            and any(row[4] == "#" for row in fonts.FONT_5x6.rows(ch))]
    r.check("FONT_5x6 keeps column 4 clear except M, W and the ellipsis", not wide,
            f"ink in the gap column of {wide!r}")
    r.check("plfont data is complete (96 cells)",
            len(fonts.PLFONT_8x10) == fonts.PLFONT_CELLS,
            f"{len(fonts.PLFONT_8x10)} glyphs")
    # SPEC 3.2 blits source columns [L-1, R+1]; ink in the first or last cell
    # column loses its halo margin and can collide with the neighbour.
    margin = sorted(ch for ch, rows in fonts.PLFONT_8x10.items()
                    if any(r[0] == "#" or r[-1] == "#" for r in rows))
    r.check("plfont keeps the halo margin columns clear", not margin,
            f"ink in column 0 or {len(next(iter(fonts.PLFONT_8x10.values()))[0]) - 1} "
            f"of {margin!r}")


def _underlay(r: _Runner) -> None:
    """The invariant the whole baked-widget model rests on."""
    from . import builder
    from .theme import Theme

    class Loud(Theme):
        name = "_SelftestUnderlay"

        def paint_main_background(self, c):
            fx.linear_gradient(c, "#ff0090", "#00ffd0", direction="d", window_space=True)
            fx.apply_noise(c, amount=40.0, scale=3.0, seed=5)

    class NoOp(Loud):
        def paint_transport(self, c, which, pressed): pass
        def paint_shuffle(self, c, pressed, selected): pass
        def paint_posbar_background(self, c): pass
        def paint_volume_frame(self, c, i): pass
        def paint_clutter_bar(self, c, pressed=None, disabled=False): pass

    b = builder._Builder(NoOp())
    b.build_main()
    bg, sheet_main = b.main_bg, b.sheets["main"]
    # sprites.json overlaps shuffle [164,89,47,15] with repeat [210,89,28,15]
    overlap = {"shuffle": {210}}
    for lkey, sheet, sname in (("play", "cbuttons", "MAIN_PLAY_BUTTON"),
                               ("eject", "cbuttons", "MAIN_EJECT_BUTTON"),
                               ("shuffle", "shufrep", "MAIN_SHUFFLE_BUTTON"),
                               ("posbar", "posbar", "MAIN_POSITION_SLIDER_BACKGROUND"),
                               ("volume", "volume", None),
                               ("clutterBar", "titlebar", "MAIN_CLUTTER_BAR_BACKGROUND")):
        lr = spec.lrect("main", lkey)
        sr = spec.frame("volume", 0) if sname is None else spec.sprite(sheet, sname)
        ref = bg.a[lr.y:lr.y1, lr.x:lr.x1, :3]
        cut = b.sheets[sheet].a[sr.y:sr.y1, sr.x:sr.x1, :3]
        r.check(f"{lkey}: sprite cut == background at {lr}", np.array_equal(cut, ref))
        baked = sheet_main.a[lr.y:lr.y1, lr.x:lr.x1, :3]
        cols = {int(lr.x + k) for k in np.nonzero((baked != ref).any(axis=(0, 2)))[0]}
        r.check(f"{lkey}: bake is a no-op", cols <= overlap.get(lkey, set()),
                f"differs at x={sorted(cols)}")

    b2 = builder._Builder(Loud())
    b2.build_main()
    ms = b2.sheets["main"]
    for lkey, sheet, sname in (("play", "cbuttons", "MAIN_PLAY_BUTTON"),
                               ("next", "cbuttons", "MAIN_NEXT_BUTTON"),
                               ("eject", "cbuttons", "MAIN_EJECT_BUTTON"),
                               ("repeat", "shufrep", "MAIN_REPEAT_BUTTON"),
                               ("eqButton", "shufrep", "MAIN_EQ_BUTTON"),
                               ("mono", "monoster", "MAIN_MONO"),
                               ("posbar", "posbar", "MAIN_POSITION_SLIDER_BACKGROUND")):
        lr, sr = spec.lrect("main", lkey), spec.sprite(sheet, sname)
        r.check(f"{lkey}: baked main.bmp == the normal sprite",
                np.array_equal(ms.a[lr.y:lr.y1, lr.x:lr.x1, :3],
                               b2.sheets[sheet].a[sr.y:sr.y1, sr.x:sr.x1, :3]))

    whole = Canvas(*spec.window_size("main"), origin=(0, 0), window="main")
    Loud().paint_main_background(whole)
    lr = spec.lrect("main", "next")
    piece = Canvas(lr.w, lr.h, origin=(lr.x, lr.y), window="main")
    Loud().paint_main_background(piece)
    r.check("window-space texture is identical painted whole or cut",
            np.array_equal(piece.a[:, :, :3], whole.a[lr.y:lr.y1, lr.x:lr.x1, :3]))

    # thumbs must end up fully opaque
    for sheet, sname in (("posbar", "MAIN_POSITION_SLIDER_THUMB"),
                         ("volume", "MAIN_VOLUME_THUMB"),
                         ("balance", "MAIN_BALANCE_THUMB")):
        sr = spec.sprite(sheet, sname)
        a = b2.sheets[sheet].a[sr.y:sr.y1, sr.x:sr.x1, 3]
        r.check(f"{sname} is fully opaque", bool((a == 255).all()))


def run(verbose: bool = False) -> int:
    r = _Runner(verbose)
    print("smoke test")
    _smoke(r)
    print("underlay model")
    _underlay(r)
    print()
    if r.failures:
        print(f"SELFTEST FAILED: {len(r.failures)} of {r.passed + len(r.failures)} checks")
        return 1
    print(f"SELFTEST OK: {r.passed} checks")
    return 0


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    return run(verbose="-v" in argv or "--verbose" in argv)


if __name__ == "__main__":
    raise SystemExit(main())
