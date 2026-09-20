"""fonts -- bitmap fonts and the 9x13 time-digit helpers.

Three fonts:

* :data:`FONT_5x6` -- the player font that fills ``text.bmp``.  Cells are 5x6
  but the ink only ever uses columns 0..3; **column 4 is the inter-glyph gap**,
  which is why its natural spacing is 0.  (The one exception is ``…``.)
* :data:`MICRO_4x5` -- a 4x5 face for engraved panel labels.
* :data:`MICRO_3x5` -- a 3x5 face for labels that have to fit in nothing.

Digits for the four 9x13 time cells come from :func:`seven_segment` (the
default, and the one that satisfies the legacy ``numbers.bmp`` minus-sign
constraint by construction) or :func:`dot_matrix`.
"""

from __future__ import annotations

from typing import Iterable, Mapping, Sequence

import numpy as np

from ._glyphdata import GLYPHS_3x5, GLYPHS_4x5, GLYPHS_5x6
from .canvas import Canvas, Colour, darken, lighten, parse_colour

__all__ = [
    "BitmapFont", "FONT_5x6", "MICRO_3x5", "MICRO_4x5", "FONTS",
    "draw_text", "draw_glyph", "text_width", "glyph_mask", "text_mask",
    "seven_segment", "dot_matrix", "SEVEN_SEGMENT_MAP", "DOT_MATRIX_MAP",
]


class BitmapFont:
    """A fixed-cell bitmap face.

    :param glyphs: ``char -> rows of '#'/'.'``
    :param w, h: nominal cell size.  ``h`` is fixed for every glyph; ``w`` is
        the *usual* width -- a glyph may be wider (``M`` and ``W`` need five
        columns to read at all) unless ``fixed_width`` is set.
    :param default_spacing: extra pixels inserted between glyphs by
        :func:`draw_text` when the caller does not say otherwise.  ``FONT_5x6``
        uses 0 because its gap column is inside the cell.
    :param fixed_width: every glyph must be exactly ``w`` wide.  ``FONT_5x6``
        needs this because ``text.bmp`` is a rigid 5px grid.
    """

    __slots__ = ("glyphs", "w", "h", "name", "default_spacing", "fixed_width",
                 "widths", "_masks")

    def __init__(self, glyphs: Mapping[str, Sequence[str]], w: int, h: int,
                 name: str, default_spacing: int = 1, fixed_width: bool = False):
        self.glyphs = dict(glyphs)
        self.w, self.h = int(w), int(h)
        self.name = name
        self.default_spacing = int(default_spacing)
        self.fixed_width = bool(fixed_width)
        self._masks: dict[str, np.ndarray] = {}
        self.widths: dict[str, int] = {}
        for ch, rows in self.glyphs.items():
            gw = len(rows[0]) if rows else 0
            if len(rows) != self.h or any(len(r) != gw for r in rows):
                raise ValueError(
                    f"skinkit.fonts: glyph {ch!r} of {name} is ragged: "
                    f"{len(rows)} rows of {[len(r) for r in rows]} (need {h} rows)")
            if self.fixed_width and gw != self.w:
                raise ValueError(
                    f"skinkit.fonts: glyph {ch!r} of {name} is {gw} wide but "
                    f"{name} is a fixed {w}px grid")
            self.widths[ch] = gw

    # -- lookup --------------------------------------------------------
    def key(self, ch: str) -> str:
        """Map a character onto an available glyph (uppercase, else space)."""
        if ch in self.glyphs:
            return ch
        u = ch.upper()
        if u in self.glyphs:
            return u
        return " " if " " in self.glyphs else next(iter(self.glyphs))

    def has(self, ch: str) -> bool:
        return ch in self.glyphs or ch.upper() in self.glyphs

    def rows(self, ch: str) -> tuple[str, ...]:
        return tuple(self.glyphs[self.key(ch)])

    def mask(self, ch: str) -> np.ndarray:
        """Boolean ``(h, w)`` ink mask for a character (cached)."""
        k = self.key(ch)
        m = self._masks.get(k)
        if m is None:
            rows = self.glyphs[k]
            m = np.array([[c == "#" for c in row] for row in rows], dtype=bool)
            self._masks[k] = m
        return m

    def width(self, ch: str) -> int:
        """Width of one glyph in pixels (may exceed the nominal cell width)."""
        return self.widths[self.key(ch)]

    def chars(self) -> list[str]:
        return sorted(self.glyphs)

    def __repr__(self) -> str:  # pragma: no cover
        return f"<BitmapFont {self.name} {self.w}x{self.h} {len(self.glyphs)} glyphs>"


FONT_5x6 = BitmapFont(GLYPHS_5x6, 5, 6, "text5x6", default_spacing=0,
                      fixed_width=True)
MICRO_4x5 = BitmapFont(GLYPHS_4x5, 4, 5, "micro4x5", default_spacing=1)
MICRO_3x5 = BitmapFont(GLYPHS_3x5, 3, 5, "micro3x5", default_spacing=1)

FONTS = {"text5x6": FONT_5x6, "micro4x5": MICRO_4x5, "micro3x5": MICRO_3x5}


# ---------------------------------------------------------------------------
# text drawing
# ---------------------------------------------------------------------------

def _spacing(font: BitmapFont, spacing: int | None) -> int:
    return font.default_spacing if spacing is None else int(spacing)


def advance(font: BitmapFont = FONT_5x6, spacing: int | None = None,
            ch: str | None = None) -> int:
    """Pixels from one glyph's left edge to the next.

    With ``ch`` this is that glyph's own advance; without it, the font's
    nominal one (the two differ only for the wide glyphs of a variable-width
    face, i.e. ``M`` and ``W`` in the micro fonts).
    """
    w = font.w if ch is None else font.width(ch)
    return w + _spacing(font, spacing)


def text_width(text: str, font: BitmapFont = FONT_5x6, spacing: int | None = None) -> int:
    """Width in pixels of ``text`` (no trailing gap)."""
    if not text:
        return 0
    sp = _spacing(font, spacing)
    return sum(font.width(c) for c in text) + (len(text) - 1) * sp


def glyph_mask(ch: str, font: BitmapFont = FONT_5x6) -> np.ndarray:
    return font.mask(ch)


def text_mask(text: str, font: BitmapFont = FONT_5x6, spacing: int | None = None) -> np.ndarray:
    """Boolean mask of a whole string, ``(font.h, text_width)``."""
    w = max(1, text_width(text, font, spacing))
    out = np.zeros((font.h, w), dtype=bool)
    sp = _spacing(font, spacing)
    x = 0
    for ch in text:
        m = font.mask(ch)
        gw = font.width(ch)
        out[:, x:x + gw] |= m
        x += gw + sp
    return out


def draw_glyph(c: Canvas, x: int, y: int, ch: str, font: BitmapFont = FONT_5x6,
               colour: Colour = "#ffffff") -> int:
    """Draw one character; returns that glyph's width."""
    m = font.mask(ch)
    gw = font.width(ch)
    col = parse_colour(colour)
    for gy in range(font.h):
        row = m[gy]
        gx = 0
        while gx < gw:
            if row[gx]:
                run = gx
                while run < gw and row[run]:
                    run += 1
                c.hline(x + gx, x + run - 1, y + gy, col)
                gx = run
            else:
                gx += 1
    return gw


def draw_text(c: Canvas, x: int, y: int, text: str, font: BitmapFont = FONT_5x6,
              colour: Colour = "#ffffff", spacing: int | None = None,
              shadow: Colour | None = None, shadow_offset: tuple[int, int] = (1, 1),
              align: str = "left", width: int | None = None) -> int:
    """Draw a string and return the x just past the last glyph.

    ``spacing=None`` uses the font's natural spacing (0 for ``FONT_5x6``,
    whose gap column lives inside the cell; 1 for the micro faces).
    ``shadow`` draws an offset copy first.  ``align`` (``"left"``/``"center"``/
    ``"right"``) needs ``width`` and shifts ``x`` inside that box.

    ``fonts.draw_text(c, 2, 2, "SESSION", fonts.MICRO_3x5, "#8fe6a8")``
    """
    if align != "left":
        box = c.w if width is None else int(width)
        tw = text_width(text, font, spacing)
        if align in ("center", "centre"):
            x = x + (box - tw) // 2
        elif align == "right":
            x = x + box - tw
    if shadow is not None:
        draw_text(c, x + shadow_offset[0], y + shadow_offset[1], text, font,
                  shadow, spacing=spacing)
    sp = _spacing(font, spacing)
    cx = int(x)
    for ch in text:
        cx += draw_glyph(c, cx, int(y), ch, font, colour) + sp
    return cx - sp if text else int(x)


# ---------------------------------------------------------------------------
# 9x13 time digits
# ---------------------------------------------------------------------------

#: which of the seven segments each digit lights (a b c d e f g)
SEVEN_SEGMENT_MAP: dict[str, str] = {
    "0": "abcdef",
    "1": "bc",
    "2": "abged",
    "3": "abgcd",
    "4": "fgbc",
    "5": "afgcd",
    "6": "afgedc",
    "7": "abc",
    "8": "abcdefg",
    "9": "abcfgd",
    "-": "g",
    "minus": "g",
}

_BLANKS = {None, "", " ", "blank", "BLANK", "none"}


def _seg_rects(w: int, h: int, thickness: int) -> dict[str, tuple[int, int, int, int]]:
    """Segment rectangles for a ``w x h`` digit cell.

    Tuned so that the middle segment of a 9x13 cell lands on exactly
    ``x = 2..6, y = 6``, which is what the legacy ``numbers.bmp`` MINUS_SIGN
    sprite ``[20, 6, 5, 1]`` reads out of the "2" cell -- and so that "1" keeps
    ``x = 0..4, y = 6`` clear, which is what NO_MINUS_SIGN ``[9, 6, 5, 1]``
    reads out of the "1" cell.
    """
    t = max(1, int(thickness))
    left, right = 1, w - 2                 # 1 .. 7 for w=9
    top, bottom = 1, h - 2                 # 1 .. 11 for h=13
    mid = (h - 1) // 2                     # 6 for h=13
    hx0, hx1 = left + 1, right - 1         # 2 .. 6 for w=9
    return {
        "a": (hx0, top, hx1 - hx0 + 1, t),
        "g": (hx0, mid, hx1 - hx0 + 1, t),
        "d": (hx0, bottom - t + 1, hx1 - hx0 + 1, t),
        "f": (left, top + 1, t, mid - top - 1 + t),
        "b": (right - t + 1, top + 1, t, mid - top - 1 + t),
        "e": (left, mid + t, t, bottom - mid - t),
        "c": (right - t + 1, mid + t, t, bottom - mid - t),
    }


def seven_segment(c: Canvas, digit, on: Colour = "#6cf08a", off: Colour | None = None,
                  slant: float = 0.0, thickness: int = 2, pivot_row: int | None = None,
                  glow_colour: Colour | None = None) -> Canvas:
    """Draw a 7-segment digit filling the canvas (designed for 9x13).

    ``digit`` is ``0..9``, ``"blank"``/``None``, or ``"minus"``/``"-"``.
    ``off`` draws unlit segments faintly (leave ``None`` for a clean LCD).
    ``slant`` italicises: each row is shifted by ``(pivot_row - y) * slant``.
    The pivot defaults to the middle-segment row, so the minus-sign strip is
    never displaced.

    ``fonts.seven_segment(c, 7, on="#7dff9b", slant=0.18)``
    """
    w, h = c.w, c.h
    rects = _seg_rects(w, h, thickness)
    mid = (h - 1) // 2 if pivot_row is None else int(pivot_row)

    key = digit
    if isinstance(digit, (int, np.integer)):
        key = str(int(digit))
    if key in _BLANKS:
        return c
    lit = SEVEN_SEGMENT_MAP.get(str(key), "")

    def paint(seg: str, colour: Colour) -> None:
        x, y, sw, sh = rects[seg]
        for row in range(y, y + sh):
            dx = int(round((mid - row) * float(slant)))
            c.box(x + dx, row, sw, 1, colour)

    if off is not None:
        for seg in "abcdefg":
            if seg in lit:
                continue
            # never ghost the middle bar of "1": NO_MINUS_SIGN is cut from it
            if seg == "g" and str(key) == "1":
                continue
            paint(seg, off)
    for seg in lit:
        paint(seg, on)
    if glow_colour is not None and lit:
        from . import fx
        fx.glow(c, c.colour_mask(on, tolerance=6), glow_colour, radius=1, strength=0.35)
    return c


#: 5x7 dot patterns, drawn on a 2px pitch -> exactly 9x13
DOT_MATRIX_MAP: dict[str, tuple[str, ...]] = {
    "0": ("01110", "10001", "10011", "10101", "11001", "10001", "01110"),
    "1": ("00100", "01100", "00100", "00100", "00100", "00100", "01110"),
    "2": ("01110", "10001", "00001", "00010", "00100", "01000", "11111"),
    "3": ("11111", "00010", "00100", "00010", "00001", "10001", "01110"),
    "4": ("00010", "00110", "01010", "10010", "11111", "00010", "00010"),
    "5": ("11111", "10000", "11110", "00001", "00001", "10001", "01110"),
    "6": ("00110", "01000", "10000", "11110", "10001", "10001", "01110"),
    "7": ("11111", "00001", "00010", "00100", "01000", "01000", "01000"),
    "8": ("01110", "10001", "10001", "01110", "10001", "10001", "01110"),
    "9": ("01110", "10001", "10001", "01111", "00001", "00010", "01100"),
    "-": ("00000", "00000", "00000", "11111", "00000", "00000", "00000"),
    "minus": ("00000", "00000", "00000", "11111", "00000", "00000", "00000"),
}


def dot_matrix(c: Canvas, digit, on: Colour = "#6cf08a", off: Colour | None = None,
               pitch: int = 2, dot: int = 1) -> Canvas:
    """Draw a digit as a 5x7 dot matrix on a ``pitch``-pixel grid.

    At the default ``pitch=2, dot=1`` a 5x7 pattern is exactly 9x13, so it
    drops straight into the time-digit cells.  ``off`` lights the dark dots
    faintly, which gives the classic "unlit LED panel" look.

    Note: unlike :func:`seven_segment`, a dot-matrix "2" cannot supply the
    legacy ``numbers.bmp`` minus bar; the builder patches that strip itself.
    """
    key = digit
    if isinstance(digit, (int, np.integer)):
        key = str(int(digit))
    pat = DOT_MATRIX_MAP.get(str(key)) if key not in _BLANKS else None
    rows = 7
    cols = 5
    x0 = (c.w - ((cols - 1) * pitch + dot)) // 2
    y0 = (c.h - ((rows - 1) * pitch + dot)) // 2
    for j in range(rows):
        for i in range(cols):
            lit = bool(pat) and pat[j][i] == "1"
            colour = on if lit else off
            if colour is None:
                continue
            c.box(x0 + i * pitch, y0 + j * pitch, dot, dot, colour)
    return c


# ---------------------------------------------------------------------------
# plfont -- the Sessions-list typeface (SPEC 3.2)
# ---------------------------------------------------------------------------
#
# A 16x6 grid, row-major.  Cell k (0..95) holds character code 32+k, except the
# last cell, which holds the ellipsis.  Pixels are an INK MASK, not colours:
# coverage = mean(r, g, b) / 255, so greys give a phosphor halo.  The app tints
# the mask with the pledit Normal / Current colour.

try:  # the default face lives in its own data module
    from ._plfontdata import PLFONT_8x10
except ImportError:  # pragma: no cover - only while the data file is missing
    PLFONT_8x10: dict[str, tuple[str, ...]] = {}

PLFONT_COLUMNS = 16
PLFONT_ROWS = 6
PLFONT_CELLS = PLFONT_COLUMNS * PLFONT_ROWS  # 96
PLFONT_ELLIPSIS = "…"

__all__ += [
    "PLFONT_8x10", "PLFONT_COLUMNS", "PLFONT_ROWS", "PLFONT_CELLS", "PLFONT_ELLIPSIS",
    "plfont_cell_chars", "plfont_cell_index", "plfont_cell_rect", "plfont_rows",
    "draw_plfont_glyph", "plfont_ink_columns", "plfont_advance", "fold_to_ascii",
    "embolden", "slant_rows", "dot_matrixise", "halo",
]


def plfont_cell_chars() -> list[str]:
    """The 96 characters of the grid, in cell order (codes 32..126, then U+2026)."""
    return [chr(32 + k) for k in range(PLFONT_CELLS - 1)] + [PLFONT_ELLIPSIS]


def plfont_cell_index(ch: str) -> int:
    """Grid cell number for a character, or the ``?`` cell if unmapped."""
    if ch == PLFONT_ELLIPSIS:
        return PLFONT_CELLS - 1
    code = ord(ch)
    if 32 <= code <= 126:
        return code - 32
    return ord("?") - 32


def plfont_cell_rect(ch: str, cell_w: int, cell_h: int):
    """``(x, y, w, h)`` of a character's cell inside the plfont sheet."""
    k = plfont_cell_index(ch)
    return (k % PLFONT_COLUMNS * cell_w, k // PLFONT_COLUMNS * cell_h, cell_w, cell_h)


def plfont_rows(ch: str, glyphs=None) -> tuple[str, ...]:
    """The ``'#'``/``'.'`` rows of a character in the default face."""
    g = PLFONT_8x10 if glyphs is None else glyphs
    if not g:
        raise RuntimeError("skinkit.fonts: skinkit/_plfontdata.py is missing or empty")
    if ch in g:
        return tuple(g[ch])
    return tuple(g.get("?", g[" "]))


def draw_plfont_glyph(c: Canvas, ch: str, glyphs=None, ink: Colour = "#ffffff",
                      x: int = 0, y: int = 0) -> Canvas:
    """Paint one plfont glyph as a full-coverage ink mask onto a cell canvas."""
    rows = plfont_rows(ch, glyphs)
    col = parse_colour(ink)
    for gy, row in enumerate(rows):
        gx = 0
        while gx < len(row):
            if row[gx] == "#":
                run = gx
                while run < len(row) and row[run] == "#":
                    run += 1
                c.hline(x + gx, x + run - 1, y + gy, col)
                gx = run
            else:
                gx += 1
    return c


# -- the SPEC 3.2 advance rule (shared by the builder, the validator and any
#    preview compositor, so all three agree to the pixel) --------------------

def plfont_ink_columns(cell: np.ndarray, threshold: float = 0.5):
    """``(L, R)`` first/last column of a cell whose coverage reaches
    ``threshold``, or ``None`` when the cell has no ink.

    ``cell`` is an ``(h, w, 3|4)`` uint8 array or an ``(h, w)`` coverage array.
    """
    a = np.asarray(cell)
    if a.ndim == 3:
        cov = a[:, :, :3].astype(np.float32).mean(axis=2) / 255.0
        if a.shape[2] == 4:
            cov = cov * (a[:, :, 3].astype(np.float32) / 255.0)
    else:
        cov = a.astype(np.float32)
        if cov.max(initial=0.0) > 1.0:
            cov = cov / 255.0
    cols = np.nonzero((cov >= float(threshold)).any(axis=0))[0]
    if cols.size == 0:
        return None
    return int(cols[0]), int(cols[-1])


def plfont_advance(cell: np.ndarray, spacing: int = 1, space_width: int | None = None,
                   monospace: bool = False) -> int:
    """Pen advance for one glyph cell, per SPEC 3.2."""
    w = int(np.asarray(cell).shape[1])
    if monospace:
        return w
    if space_width is None:
        space_width = max(2, w // 2 - 1)
    ink = plfont_ink_columns(cell)
    if ink is None:
        return int(space_width)
    return ink[1] - ink[0] + 1 + int(spacing)


_ASCII_FOLD = {
    "‘": "'", "’": "'", "‚": ",", "‛": "'",
    "“": '"', "”": '"', "„": '"',
    "‐": "-", "‑": "-", "‒": "-", "–": "-", "—": "-",
    "―": "-", "−": "-", " ": " ", " ": " ", " ": " ",
    "×": "x", "•": ".", "·": ".",
}


def fold_to_ascii(text: str, keep: str = PLFONT_ELLIPSIS) -> str:
    """SPEC 3.2 text policy: strip diacritics, map smart punctuation, and turn
    anything still outside 32..126 into ``?`` (``keep`` survives untouched)."""
    import unicodedata
    out = []
    for ch in text:
        if ch in keep:
            out.append(ch)
            continue
        ch = _ASCII_FOLD.get(ch, ch)
        if not (32 <= ord(ch) <= 126):
            d = unicodedata.normalize("NFKD", ch)
            ch = "".join(k for k in d if not unicodedata.combining(k)) or "?"
            ch = ch[0] if ch else "?"
        out.append(ch if 32 <= ord(ch) <= 126 else "?")
    return "".join(out)


# -- helpers for deriving a face from glyph data ---------------------------

def embolden(rows: Sequence[str], dx: int = 1, dy: int = 0) -> tuple[str, ...]:
    """Smear ink by ``(dx, dy)`` -- a one-line way to get a bold cut.

    ``fonts.embolden(fonts.plfont_rows("a"))``
    """
    h, w = len(rows), len(rows[0])
    out = [[c for c in r] for r in rows]
    for y in range(h):
        for x in range(w):
            if rows[y][x] != "#":
                continue
            for sy in range(0, int(dy) + 1):
                for sx in range(0, int(dx) + 1):
                    ny, nx = y + sy, x + sx
                    if 0 <= ny < h and 0 <= nx < w:
                        out[ny][nx] = "#"
    return tuple("".join(r) for r in out)


def slant_rows(rows: Sequence[str], amount: float = 0.25,
               pivot: int | None = None) -> tuple[str, ...]:
    """Italicise: row ``y`` shifts by ``round((pivot - y) * amount)``.

    ``fonts.slant_rows(fonts.plfont_rows("M"), 0.3)``
    """
    h, w = len(rows), len(rows[0])
    p = (h - 1) if pivot is None else int(pivot)
    out = []
    for y, row in enumerate(rows):
        d = int(round((p - y) * float(amount)))
        line = ["."] * w
        for x, ch in enumerate(row):
            if ch == "#" and 0 <= x + d < w:
                line[x + d] = "#"
        out.append("".join(line))
    return tuple(out)


def dot_matrixise(rows: Sequence[str], pitch: int = 2, dot: int = 1,
                  cell: tuple[int, int] | None = None) -> tuple[str, ...]:
    """Explode a glyph onto a dot grid: each ink pixel becomes a ``dot``x``dot``
    block on a ``pitch``-pixel lattice, giving an LED-panel face.

    ``fonts.dot_matrixise(fonts.plfont_rows("5"), pitch=2)`` turns an 8x10
    glyph into a 15x19 one (pass ``cell`` to pad or crop to a fixed size).
    """
    h, w = len(rows), len(rows[0])
    ow = (w - 1) * pitch + dot
    oh = (h - 1) * pitch + dot
    grid = [["."] * ow for _ in range(oh)]
    for y in range(h):
        for x in range(w):
            if rows[y][x] != "#":
                continue
            for sy in range(dot):
                for sx in range(dot):
                    grid[y * pitch + sy][x * pitch + sx] = "#"
    out = ["".join(r) for r in grid]
    if cell is not None:
        cw, ch_ = int(cell[0]), int(cell[1])
        out = [(r + "." * cw)[:cw] for r in out[:ch_]]
        out += ["." * cw] * max(0, ch_ - len(out))
    return tuple(out)


def halo(c: Canvas, radius: int = 1, strength: float = 0.35,
         threshold: int = 128, colour: Colour = "#ffffff") -> Canvas:
    """Add grey partial-ink coverage around a glyph's solid ink.

    plfont pixels are a coverage mask, so grey pixels read as a soft phosphor
    glow once the app tints them.  Existing full-ink pixels are never dimmed.

    ``fonts.halo(c, radius=1, strength=0.3)``
    """
    from . import fx
    ink = c.luma() >= float(threshold)
    if not ink.any():
        return c
    spread = fx._box_blur(ink.astype(np.float32), max(1, int(radius)))
    if spread.max() > 0:
        spread = spread / spread.max()
    glow = np.clip(spread * float(strength), 0.0, 1.0)
    glow[ink] = 1.0
    col = np.array(parse_colour(colour)[:3], dtype=np.float32)
    cur = c.a[:, :, :3].astype(np.float32)
    target = col[None, None, :] * glow[:, :, None]
    c.a[:, :, :3] = np.clip(np.rint(np.maximum(cur, target)), 0, 255).astype(np.uint8)
    c.a[:, :, 3] = 255
    return c
