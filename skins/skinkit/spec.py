"""Loads ``skinspec/sprites.json`` -- the single source of truth.

NOTHING in skinkit may hardcode a coordinate that exists in that file.  Every
sheet size, sprite rect, slider frame rect, window layout rect and font cell
comes from here.

The JSON is found by walking up from this package until a ``skinspec``
directory appears, so the toolkit works from any working directory and from
inside a copied skin folder.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Iterable, NamedTuple

__all__ = [
    "SPEC_PATH", "SPEC", "SHEETS", "LAYOUT", "FONT", "TEXT_FILES",
    "Rect", "sheet", "sheet_file", "sheet_size", "sheet_names", "sheet_required",
    "sprite", "sprite_names", "find_sprite", "has_sprite",
    "frames", "frame", "frame_count",
    "layout", "lrect", "lval",
    "font_cells", "font_chars", "glyph_cell", "glyph_rect",
    "clutter_column", "clutter_letters", "clutter_button_local",
    "text_file_doc",
]


class Rect(NamedTuple):
    """An [x, y, w, h] rectangle in skin pixels, origin top-left, y down."""

    x: int
    y: int
    w: int
    h: int

    # -- derived edges -------------------------------------------------
    @property
    def x1(self) -> int:
        """One past the right edge."""
        return self.x + self.w

    @property
    def y1(self) -> int:
        """One past the bottom edge."""
        return self.y + self.h

    @property
    def right(self) -> int:
        """Rightmost pixel column (inclusive)."""
        return self.x + self.w - 1

    @property
    def bottom(self) -> int:
        """Bottom-most pixel row (inclusive)."""
        return self.y + self.h - 1

    @property
    def size(self) -> tuple[int, int]:
        return (self.w, self.h)

    @property
    def origin(self) -> tuple[int, int]:
        return (self.x, self.y)

    def moved(self, x: int, y: int) -> "Rect":
        """Same size, new top-left."""
        return Rect(x, y, self.w, self.h)

    def offset(self, dx: int, dy: int) -> "Rect":
        return Rect(self.x + dx, self.y + dy, self.w, self.h)

    def inset(self, n: int) -> "Rect":
        return Rect(self.x + n, self.y + n, max(0, self.w - 2 * n), max(0, self.h - 2 * n))

    def contains(self, x: int, y: int) -> bool:
        return self.x <= x < self.x1 and self.y <= y < self.y1

    def __str__(self) -> str:  # pragma: no cover - debug aid
        return f"[{self.x},{self.y} {self.w}x{self.h}]"


# ---------------------------------------------------------------------------
# locating and loading the JSON
# ---------------------------------------------------------------------------

def _find_spec_path() -> Path:
    here = Path(__file__).resolve()
    for base in [here.parent, *here.parents]:
        cand = base / "skinspec" / "sprites.json"
        if cand.is_file():
            return cand
    raise FileNotFoundError(
        "skinkit: could not find skinspec/sprites.json by walking up from "
        f"{here.parent}. The toolkit must live inside the project checkout."
    )


SPEC_PATH: Path = _find_spec_path()
SPEC: dict[str, Any] = json.loads(SPEC_PATH.read_text(encoding="utf-8"))

SHEETS: dict[str, Any] = SPEC["sheets"]
LAYOUT: dict[str, Any] = SPEC["layout"]
FONT: dict[str, Any] = SPEC["font"]
TEXT_FILES: dict[str, str] = SPEC["textFiles"]


# ---------------------------------------------------------------------------
# sheets and sprites
# ---------------------------------------------------------------------------

def sheet_names() -> list[str]:
    """All sheet keys, in JSON order (``main``, ``titlebar``, ...)."""
    return [k for k in SHEETS if not k.startswith("_")]


def sheet(name: str) -> dict[str, Any]:
    try:
        return SHEETS[name]
    except KeyError:
        raise KeyError(f"skinkit.spec: no sheet named {name!r}. "
                       f"Known: {', '.join(sheet_names())}") from None


def sheet_file(name: str) -> str:
    """The on-disk filename for a sheet, e.g. ``main`` -> ``main.bmp``."""
    return sheet(name)["file"]


def sheet_size(name: str) -> tuple[int, int]:
    s = sheet(name)
    return (int(s["width"]), int(s["height"]))


def sheet_required(name: str) -> bool:
    return bool(sheet(name).get("required", False))


def sprite_names(sheet_name: str) -> list[str]:
    return list(sheet(sheet_name).get("sprites", {}))


def has_sprite(sheet_name: str, sprite_name: str) -> bool:
    return sprite_name in sheet(sheet_name).get("sprites", {})


def sprite(sheet_name: str, sprite_name: str) -> Rect:
    """Rect of a named sprite inside its sheet."""
    sprites = sheet(sheet_name).get("sprites", {})
    try:
        return Rect(*sprites[sprite_name])
    except KeyError:
        raise KeyError(
            f"skinkit.spec: sheet {sheet_name!r} has no sprite {sprite_name!r}. "
            f"Known: {', '.join(sorted(sprites))}"
        ) from None


def find_sprite(sprite_name: str) -> tuple[str, Rect]:
    """Locate a sprite by name across all sheets -> ``(sheet_name, rect)``."""
    for sn in sheet_names():
        sprites = SHEETS[sn].get("sprites", {})
        if sprite_name in sprites:
            return sn, Rect(*sprites[sprite_name])
    raise KeyError(f"skinkit.spec: no sprite named {sprite_name!r} in any sheet")


# ---------------------------------------------------------------------------
# slider frame strips (volume / balance / eqmain)
# ---------------------------------------------------------------------------

def frame_count(sheet_name: str) -> int:
    f = sheet(sheet_name).get("frames")
    if not f:
        raise KeyError(f"skinkit.spec: sheet {sheet_name!r} has no 'frames' block")
    return int(f["count"])


def frame(sheet_name: str, i: int) -> Rect:
    """Rect of slider background frame ``i`` inside its sheet.

    Handles both frame-strip shapes used by the classic format:

    * a single vertical column (``volume``, ``balance``): ``x``/``y0``/``strideY``
    * a wrapped grid (``eqmain``): ``x0``/``y0``/``strideX``/``strideY``/``perRow``
    """
    f = sheet(sheet_name).get("frames")
    if not f:
        raise KeyError(f"skinkit.spec: sheet {sheet_name!r} has no 'frames' block")
    n = int(f["count"])
    if not 0 <= i < n:
        raise IndexError(f"skinkit.spec: frame {i} out of range 0..{n - 1} for {sheet_name!r}")
    w, h = int(f["w"]), int(f["h"])
    if "perRow" in f:
        per = int(f["perRow"])
        col, row = i % per, i // per
        x = int(f["x0"]) + int(f["strideX"]) * col
        y = int(f["y0"]) + int(f["strideY"]) * row
    else:
        x = int(f["x"])
        y = int(f["y0"]) + int(f["strideY"]) * i
    return Rect(x, y, w, h)


def frames(sheet_name: str) -> list[Rect]:
    """All frame rects of a sheet, index order."""
    return [frame(sheet_name, i) for i in range(frame_count(sheet_name))]


# ---------------------------------------------------------------------------
# window layout
# ---------------------------------------------------------------------------

def layout(window: str) -> dict[str, Any]:
    try:
        return LAYOUT[window]
    except KeyError:
        raise KeyError(f"skinkit.spec: no layout for window {window!r}. "
                       f"Known: {', '.join(LAYOUT)}") from None


def lval(window: str, key: str) -> Any:
    """Raw layout value (for non-rect entries like ``volumeThumbTravel``)."""
    d = layout(window)
    try:
        return d[key]
    except KeyError:
        raise KeyError(f"skinkit.spec: layout.{window} has no key {key!r}. "
                       f"Known: {', '.join(sorted(d))}") from None


def lrect(window: str, key: str) -> Rect:
    """A 4-element layout entry as a :class:`Rect`."""
    v = lval(window, key)
    if not (isinstance(v, (list, tuple)) and len(v) == 4):
        raise TypeError(f"skinkit.spec: layout.{window}.{key} is not an [x,y,w,h] rect: {v!r}")
    return Rect(*v)


def window_size(window: str) -> tuple[int, int]:
    d = layout(window)
    key = "size" if "size" in d else "defaultSize"
    w, h = d[key]
    return int(w), int(h)


# ---------------------------------------------------------------------------
# font map
# ---------------------------------------------------------------------------

def _font_cells() -> dict[str, tuple[int, int]]:
    """char -> (row, col) in text.bmp."""
    cells: dict[str, tuple[int, int]] = {}
    for r, row in enumerate(FONT["rows"]):
        for c, ch in enumerate(row):
            cells.setdefault(ch, (r, c))
    sr, sc = FONT["space"]
    cells[" "] = (int(sr), int(sc))
    return cells


_FONT_CELLS = _font_cells()


def font_cells() -> dict[str, tuple[int, int]]:
    """Mapping ``char -> (row, col)`` of every character text.bmp carries."""
    return dict(_FONT_CELLS)


def font_chars() -> list[str]:
    """Every character text.bmp carries, in sheet order (space last)."""
    out: list[str] = []
    for row in FONT["rows"]:
        out.extend(row)
    out.append(" ")
    return out


def glyph_cell(ch: str) -> tuple[int, int]:
    """``(row, col)`` for a character; unmapped characters fall back to space."""
    return _FONT_CELLS.get(ch.upper() if len(ch) == 1 else ch, _FONT_CELLS[" "])


def glyph_rect(ch: str) -> Rect:
    """Rect of a character's glyph inside ``text.bmp``."""
    gw, gh = int(FONT["glyphWidth"]), int(FONT["glyphHeight"])
    r, c = glyph_cell(ch)
    return Rect(c * gw, r * gh, gw, gh)


def glyph_rect_at(row: int, col: int) -> Rect:
    gw, gh = int(FONT["glyphWidth"]), int(FONT["glyphHeight"])
    return Rect(col * gw, row * gh, gw, gh)


GLYPH_W: int = int(FONT["glyphWidth"])
GLYPH_H: int = int(FONT["glyphHeight"])
FONT_COLUMNS: int = int(FONT["columns"])
FONT_ROWS: int = len(FONT["rows"])


# ---------------------------------------------------------------------------
# clutter bar helpers
# ---------------------------------------------------------------------------

CLUTTER_LETTERS = ("O", "A", "I", "D", "V")


def clutter_letters() -> tuple[str, ...]:
    return CLUTTER_LETTERS


def _clutter_geometry() -> tuple[int, int, int, int]:
    """(x0, y0, w, h) of clutter-bar pressed column 0 inside titlebar.bmp.

    Derived, not hardcoded: the five ``*_SELECTED`` sprites are sub-rects of
    the five full-height columns, so column 0's left edge is the O sprite's x
    and the column top is ``O.y - (layout O.y - layout clutterBar.y)``.
    """
    bar = lrect("main", "clutterBar")
    btn_o = Rect(*lval("main", "clutterButtons")["O"])
    spr_o = sprite("titlebar", "MAIN_CLUTTER_BAR_BUTTON_O_SELECTED")
    y0 = spr_o.y - (btn_o.y - bar.y)
    return (spr_o.x, y0, bar.w, bar.h)


def clutter_column(letter: str) -> Rect:
    """Rect in ``titlebar.bmp`` of the full 8x43 clutter bar whose ``letter``
    is pressed.  Columns run left to right in O A I D V order."""
    letter = letter.upper()
    if letter not in CLUTTER_LETTERS:
        raise KeyError(f"skinkit.spec: clutter letter must be one of {CLUTTER_LETTERS}, got {letter!r}")
    x0, y0, w, h = _clutter_geometry()
    i = CLUTTER_LETTERS.index(letter)
    return Rect(x0 + w * i, y0, w, h)


def clutter_button_local(letter: str) -> Rect:
    """A clutter button's rect *relative to the 8x43 clutter bar canvas*."""
    bar = lrect("main", "clutterBar")
    btn = Rect(*lval("main", "clutterButtons")[letter.upper()])
    return Rect(btn.x - bar.x, btn.y - bar.y, btn.w, btn.h)


def text_file_doc(name: str) -> str:
    return TEXT_FILES.get(name, "")


# ---------------------------------------------------------------------------
# convenience: every sprite rect that the builder must fill, grouped
# ---------------------------------------------------------------------------

def all_sprites() -> Iterable[tuple[str, str, Rect]]:
    """Yield ``(sheet_name, sprite_name, rect)`` for every sprite in the spec."""
    for sn in sheet_names():
        for name, r in SHEETS[sn].get("sprites", {}).items():
            yield sn, name, Rect(*r)
