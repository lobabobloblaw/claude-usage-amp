"""skinkit.preview -- an **independent** compositor for built skins.

This module deliberately knows nothing about themes.  It never imports
:mod:`skinkit.theme` or :mod:`skinkit.builder`, it never sees a palette, and it
has no idea which skin it is looking at.  All it does is open the finished
files -- ``main.bmp``, ``titlebar.bmp``, ..., ``plfont.bmp``, ``viscolor.txt``,
``pledit.txt``, ``plfont.txt`` -- read every coordinate out of
``skinspec/sprites.json`` via :mod:`skinkit.spec`, and paste rectangles.

That independence is the whole point.  If the previews look right, the *sheets*
are right: every sprite really is at the rect the spec promises, the sheets are
self-consistent, and a third-party player pointed at the same rects would draw
the same thing.  A builder bug cannot hide behind a compositor that shares the
builder's assumptions.

Mocked live state (SPEC 2.1--2.4): ``-02:47`` remaining, 42 % session, 17 %
weekly, 44 % through the hero window, play + work LEDs lit, EQ toggle selected,
the V clutter button pressed, stereo lamp lit.

::

    python3 -m skinkit.preview skins/base/out skins/base/preview

Outputs in ``out_dir``::

    main.png shade.png eq.png playlist.png all.png       (1x)
    main_4x.png shade_4x.png eq_4x.png playlist_4x.png all_4x.png
    sheets.png                                           (labelled contact sheet)
"""

from __future__ import annotations

import io
import math
import sys
import unicodedata
import zipfile
from pathlib import Path
from typing import Any, Sequence

import numpy as np
from PIL import Image, ImageDraw, ImageFont

try:  # package import (``from skinkit import preview``)
    from . import spec
    from .spec import Rect
except ImportError:  # pragma: no cover - direct script import
    import spec  # type: ignore[no-redef]
    from spec import Rect  # type: ignore[no-redef]

__all__ = ["render_previews", "main", "PREVIEW_NAMES", "SCALE"]


# ---------------------------------------------------------------------------
# constants -- the only hardcoded numbers here are *mock data*, never geometry
# ---------------------------------------------------------------------------

SCALE = 4  # nearest-neighbour factor for the ``*_4x.png`` files

PREVIEW_NAMES = ("main", "shade", "eq", "playlist", "field", "all")

#: anything the compositor could not find is left this colour, so a hole in a
#: sheet screams instead of blending into the art.
MISSING = (255, 0, 255, 255)

# -- mocked live state ------------------------------------------------------
TIME_DIGITS = "0247"           # -02:47 remaining
SHADE_GLYPHS = "-247"          # window-shade shows "-2:47" (colon is baked in)
SESSION_PCT = 42.0             # volume slider  (SPEC 2.1)
WEEK_PCT = 17.0                # balance slider
POSITION_FRAC = 0.44           # seek bar
MARQUEE = "1. SESSION (5H) - 42% USED - RESETS 6:50 PM ***"
KBPS_TEXT = "128"              # burn rate, 3 glyphs
KHZ_TEXT = " 2"                # active sessions, 2 glyphs right-aligned

#: 19 spectrum bar heights in rows (1..16), newest-at-the-right shape:
#: busy a few minutes ago, jagged, trailing off.  Pure decoration.
BAR_HEIGHTS = (13, 11, 14, 10, 12, 8, 11, 9, 7, 10, 6, 8, 5, 7, 4, 6, 3, 5, 2)

#: 10 EQ band values in 0..1 (SPEC 2.3: last 10 hours, cost measure).
EQ_BANDS = (0.22, 0.35, 0.30, 0.52, 0.68, 0.61, 0.80, 0.74, 0.90, 0.55)
EQ_PREAMP = 0.62

PLAYLIST_ROWS = (
    ("1. code/tokenamp - FABLE 5.1", "$12.40"),
    # long enough to exercise SPEC 3.2 ellipsis truncation
    ("2. tokenamp-ui/Sources/TokenampKit/SkinRenderer.swift - OPUS 5", "$8.15"),
    ("3. skinkit preview compositor - SONNET 5", "$3.90"),
    ("4. usage-core jsonl scanner - OPUS 5", "$2.75"),
    ("5. docs/SPEC.md - HAIKU 4.5", "$0.42"),
    ("6. scratch: quagga glyph jumping - SONNET 5", "$1.08"),
    ("7. walnut76 wood-grain study - OPUS 5", "$4.60"),
    ("8. amethyst/pcb-traces - FABLE 5.1", "$6.33"),
)
PLAYLIST_CURRENT_ROW = 2       # drawn in pledit.txt ``Current``
PLAYLIST_SELECTED_ROW = 5      # drawn on a ``SelectedBG`` bar
PLAYLIST_TEXT_X = 14
PLAYLIST_COST_RIGHT_X = 248    # exclusive right edge of the value column
PLAYLIST_VALUE_GAP = 4         # SPEC 3.2: left text never comes within 4 px
PLAYLIST_RUNNING_INFO = "8 SESS  $39.63"
PLAYLIST_MINI_TIME = "-02:47"

#: the playlist typeface (SPEC 3.2).  Not a sheet in ``sprites.json``: it is a
#: Tokenamp extension, so its file name lives here.
PLFONT_STEM = "plfont"

#: system faces, used **only** for the captions on the contact sheet.  No
#: window preview contains a single vector glyph (SPEC amendment A1): the
#: playlist rows come from the skin's own ``plfont``.
FONT_CANDIDATES = (
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "/Library/Fonts/Arial.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
)

#: fallbacks used only when ``viscolor.txt`` / ``pledit.txt`` are unreadable.
#: ``pledit.txt``'s ``Font`` key is ignored outright (SPEC 3.2).
_VISCOLOR_FALLBACK = [(0, 0, 0)] + [(40, 40, 40)] + [
    (255 - i * 12, 60 + i * 10, 40) for i in range(16)
] + [(200, 255, 200)] * 5 + [(255, 255, 255)]
_PLEDIT_FALLBACK = {
    "normal": "#00FF00", "current": "#FFFFFF",
    "normalbg": "#000000", "selectedbg": "#0000C6",
}


# ---------------------------------------------------------------------------
# tiny numeric helpers
# ---------------------------------------------------------------------------

def _r(v: float) -> int:
    """Round half **up** (``round()`` is banker's rounding, which drifts)."""
    return int(math.floor(float(v) + 0.5))


def _clamp(v: int, lo: int, hi: int) -> int:
    return lo if v < lo else (hi if v > hi else v)


# ---------------------------------------------------------------------------
# reading a built skin: a loose directory or a flat .wsz
# ---------------------------------------------------------------------------

class _Source:
    """Case-insensitive, directory-prefix-insensitive file lookup (SPEC 3)."""

    def __init__(self, path: str | Path):
        self.path = Path(path)
        self._index: dict[str, Any] = {}
        self._zip: zipfile.ZipFile | None = None
        self._images: dict[str, np.ndarray | None] = {}

        if self.path.is_dir():
            for p in sorted(self.path.rglob("*")):
                if p.is_file():
                    self._index.setdefault(p.name.lower(), p)
        elif self.path.is_file() and zipfile.is_zipfile(self.path):
            self._zip = zipfile.ZipFile(self.path)
            for name in self._zip.namelist():
                base = name.replace("\\", "/").rsplit("/", 1)[-1]
                if base:
                    self._index.setdefault(base.lower(), name)
        else:
            raise FileNotFoundError(
                f"skinkit.preview: {self.path} is neither a directory nor a zip/.wsz"
            )

    def read(self, filename: str) -> bytes | None:
        key = self._index.get(filename.lower())
        if key is None:
            return None
        if self._zip is not None:
            return self._zip.read(key)
        return Path(key).read_bytes()

    def text(self, filename: str) -> str | None:
        data = self.read(filename)
        if data is None:
            return None
        return data.decode("utf-8", errors="replace")

    def names(self) -> list[str]:
        """Every file this skin carries, lowercased base names."""
        return sorted(self._index)

    @staticmethod
    def decode(data: bytes | None) -> np.ndarray | None:
        if not data:
            return None
        try:
            return np.array(Image.open(io.BytesIO(data)).convert("RGBA"), dtype=np.uint8)
        except Exception:
            return None

    def image(self, stem: str) -> np.ndarray | None:
        """Load ``<stem>.png`` (preferred) or ``<stem>.bmp`` as RGBA."""
        for ext in (".png", ".bmp"):
            arr = self.decode(self.read(stem + ext))
            if arr is not None:
                return arr
        return None

    def sheet(self, sheet_name: str) -> np.ndarray | None:
        """A sheet as an ``(h, w, 4)`` uint8 array, or ``None`` if absent.

        A ``.png`` beside the ``.bmp`` wins, as the engine does (SPEC 3).
        """
        if sheet_name in self._images:
            return self._images[sheet_name]
        arr = self.image(spec.sheet_file(sheet_name).rsplit(".", 1)[0])
        self._images[sheet_name] = arr
        return arr

    def close(self) -> None:
        if self._zip is not None:
            self._zip.close()
            self._zip = None


# ---------------------------------------------------------------------------
# text-file parsing (viscolor.txt / pledit.txt)
# ---------------------------------------------------------------------------

def _parse_viscolor(text: str | None) -> list[tuple[int, int, int]]:
    """24 ``(r, g, b)`` entries; anything after the three ints is a comment."""
    out: list[tuple[int, int, int]] = []
    for line in (text or "").splitlines():
        line = line.strip()
        if not line or line.startswith(("//", "#", ";")):
            continue
        parts = line.replace("\t", " ").split(",")
        if len(parts) < 3:
            continue
        vals: list[int] = []
        for p in parts[:3]:
            tok = ""
            for ch in p.strip():
                if ch.isdigit() or (ch == "-" and not tok):
                    tok += ch
                else:
                    break
            if not tok:
                break
            vals.append(_clamp(int(tok), 0, 255))
        if len(vals) == 3:
            out.append((vals[0], vals[1], vals[2]))
        if len(out) == 24:
            break
    while len(out) < 24:
        out.append(_VISCOLOR_FALLBACK[len(out)])
    return out


def _parse_ini(text: str | None, want: str) -> dict[str, str]:
    """Keys of one INI section (plus any keys before the first header).

    Section and key names are matched case-insensitively, which is what both
    ``pledit.txt`` and ``plfont.txt`` promise.
    """
    out: dict[str, str] = {}
    section = ""
    for line in (text or "").splitlines():
        line = line.strip()
        if not line or line.startswith((";", "//")):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip().lower()
            continue
        if "=" not in line or section not in ("", want):
            continue
        k, _, v = line.partition("=")
        out[k.strip().lower()] = v.strip()
    return out


def _parse_pledit(text: str | None) -> dict[str, str]:
    """``[Text]`` INI -> lowercase key -> value.  ``#`` on colours is optional."""
    out = dict(_PLEDIT_FALLBACK)
    out.update(_parse_ini(text, "text"))
    return out


def _ascii_fold(s: str) -> str:
    """SPEC 3.2 text policy: fold to ASCII, then ``?`` for anything left over."""
    subs = {"‘": "'", "’": "'", "‚": "'", "‛": "'",
            "“": '"', "”": '"', "–": "-", "—": "-",
            "−": "-", " ": " ", "…": "..."}
    s = "".join(subs.get(ch, ch) for ch in s)
    s = unicodedata.normalize("NFKD", s)
    out: list[str] = []
    for ch in s:
        if unicodedata.combining(ch):
            continue
        out.append(ch if 32 <= ord(ch) <= 126 else "?")
    return "".join(out)


def _colour(value: str, default: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    s = (value or "").strip().lstrip("#")
    if len(s) == 3:
        s = "".join(c * 2 for c in s)
    if len(s) != 6:
        return default
    try:
        v = int(s, 16)
    except ValueError:
        return default
    return ((v >> 16) & 255, (v >> 8) & 255, v & 255, 255)


# ---------------------------------------------------------------------------
# blitting -- opaque rectangle copies, clipped on both sides
# ---------------------------------------------------------------------------

def _blit(dst: np.ndarray, dx: int, dy: int,
          src: np.ndarray | None, rect: Sequence[int] | None = None) -> bool:
    """Copy ``rect`` of ``src`` to ``(dx, dy)`` of ``dst``.  No blending.

    Clips instead of raising when the rect or the destination runs off an edge,
    so a wrong spec entry shows up as missing art rather than a traceback.
    """
    if src is None:
        return False
    dx, dy = int(dx), int(dy)
    sh, sw = int(src.shape[0]), int(src.shape[1])
    if rect is None:
        sx, sy, w, h = 0, 0, sw, sh
    else:
        sx, sy, w, h = (int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3]))
    # clip against the source
    if sx < 0:
        w += sx
        dx -= sx
        sx = 0
    if sy < 0:
        h += sy
        dy -= sy
        sy = 0
    w = min(w, sw - sx)
    h = min(h, sh - sy)
    if w <= 0 or h <= 0:
        return False
    # clip against the destination
    dh, dw = int(dst.shape[0]), int(dst.shape[1])
    if dx < 0:
        sx -= dx
        w += dx
        dx = 0
    if dy < 0:
        sy -= dy
        h += dy
        dy = 0
    w = min(w, dw - dx)
    h = min(h, dh - dy)
    if w <= 0 or h <= 0:
        return False
    dst[dy:dy + h, dx:dx + w] = src[sy:sy + h, sx:sx + w]
    return True


def _fill(dst: np.ndarray, x: int, y: int, w: int, h: int,
          colour: Sequence[int]) -> None:
    x0, y0 = max(0, int(x)), max(0, int(y))
    x1 = min(int(dst.shape[1]), int(x) + int(w))
    y1 = min(int(dst.shape[0]), int(y) + int(h))
    if x1 <= x0 or y1 <= y0:
        return
    c = tuple(colour) if len(colour) == 4 else (*colour, 255)
    dst[y0:y1, x0:x1] = c


def _px(dst: np.ndarray, x: int, y: int, colour: Sequence[int]) -> None:
    x, y = int(x), int(y)
    if 0 <= x < dst.shape[1] and 0 <= y < dst.shape[0]:
        dst[y, x] = tuple(colour) if len(colour) == 4 else (*colour, 255)


def _new(w: int, h: int) -> np.ndarray:
    a = np.empty((int(h), int(w), 4), dtype=np.uint8)
    a[:, :] = MISSING
    return a


# ---------------------------------------------------------------------------
# fonts
# ---------------------------------------------------------------------------

class _PlFont:
    """The skin's own playlist typeface (SPEC 3.2), reimplemented from scratch.

    A 16x6 row-major grid of ink-mask cells: cell *k* holds character code
    ``32 + k``, and the last cell (code 127) holds the ellipsis.  Pixels are
    coverage, not colour, so the same sheet works with any ``pledit.txt`` tint.
    """

    COLS, ROWS = 16, 6
    ELLIPSIS = "…"
    ELLIPSIS_INDEX = 95           # code 127 == 32 + 95

    def __init__(self, arr: np.ndarray, ini: dict[str, str]):
        h, w = int(arr.shape[0]), int(arr.shape[1])
        if w % self.COLS or h % self.ROWS or w < self.COLS or h < self.ROWS:
            raise ValueError(
                f"{w}x{h} does not divide into a {self.COLS}x{self.ROWS} cell grid")
        self.cell_w = w // self.COLS
        self.cell_h = h // self.ROWS

        cov = arr[:, :, :3].astype(np.float32).mean(axis=2) / 255.0
        if arr.shape[2] == 4:
            cov = cov * (arr[:, :, 3].astype(np.float32) / 255.0)
        self.cov = cov

        def iv(key: str, default: int) -> int:
            try:
                return int(str(ini.get(key, default)).strip())
            except (TypeError, ValueError):
                return default

        self.monospace = iv("monospace", 0) != 0
        self.spacing = max(0, iv("spacing", 1))
        self.space_width = max(1, iv("spacewidth", max(2, self.cell_w // 2 - 1)))
        self.row_height = max(1, iv("rowheight", self.cell_h + 1))
        self.offset_y = iv("offsety", 0)
        self._spans: dict[int, tuple[int, int] | None] = {}

    # -- glyph lookup --------------------------------------------------
    def index(self, ch: str) -> int:
        if ch == self.ELLIPSIS:
            return self.ELLIPSIS_INDEX
        o = ord(ch)
        return (o - 32) if 32 <= o <= 126 else (ord("?") - 32)

    def _cell(self, idx: int) -> np.ndarray:
        r, c = divmod(int(idx), self.COLS)
        return self.cov[r * self.cell_h:(r + 1) * self.cell_h,
                        c * self.cell_w:(c + 1) * self.cell_w]

    def ink_span(self, idx: int) -> tuple[int, int] | None:
        """First and last *ink column* (any pixel with coverage >= 0.5)."""
        if idx in self._spans:
            return self._spans[idx]
        cols = np.nonzero((self._cell(idx) >= 0.5).any(axis=0))[0]
        span = (int(cols[0]), int(cols[-1])) if cols.size else None
        self._spans[idx] = span
        return span

    # -- metrics -------------------------------------------------------
    def advance(self, idx: int) -> int:
        if self.monospace:
            return self.cell_w
        span = self.ink_span(idx)
        if span is None:
            return self.space_width
        return span[1] - span[0] + 1 + self.spacing

    def width(self, text: str) -> int:
        """Total pen advance for ``text``."""
        return sum(self.advance(self.index(ch)) for ch in text)

    def visual_width(self, text: str) -> int:
        """Pen advance minus the trailing inter-glyph gap -- what you see."""
        w = self.width(text)
        if text and not self.monospace and self.ink_span(self.index(text[-1])) is not None:
            w -= self.spacing
        return w

    def truncate(self, text: str, avail: int) -> str:
        """Shorten with the ellipsis glyph until it fits ``avail`` pixels."""
        if self.visual_width(text) <= avail:
            return text
        while text and self.visual_width(text + self.ELLIPSIS) > avail:
            text = text[:-1]
        return text + self.ELLIPSIS

    # -- drawing -------------------------------------------------------
    def draw(self, dst: np.ndarray, x: int, y: int, text: str,
             tint: Sequence[int], clip: Sequence[int] | None = None) -> int:
        """Composite ``tint * coverage`` over ``dst``; returns the pen advance.

        ``clip`` is an optional ``(x, y, w, h)`` viewport -- the list well --
        so a tall cell or a long descender can never spill onto the frame.
        """
        pen = int(x)
        for ch in text:
            idx = self.index(ch)
            if self.monospace:
                self._paste(dst, pen, y, idx, 0, self.cell_w - 1, tint, clip)
                pen += self.cell_w
                continue
            span = self.ink_span(idx)
            if span is None:
                pen += self.space_width
                continue
            lo, hi = span
            # blit [L-1, R+1] clipped to the cell, placed at pen-1, so a 1 px
            # halo survives and simply overlaps the spacing
            s0, s1 = max(0, lo - 1), min(self.cell_w - 1, hi + 1)
            self._paste(dst, (pen - 1) + (s0 - (lo - 1)), y, idx, s0, s1, tint, clip)
            pen += hi - lo + 1 + self.spacing
        return pen - int(x)

    def _paste(self, dst: np.ndarray, dx: int, dy: int, idx: int,
               s0: int, s1: int, tint: Sequence[int],
               clip: Sequence[int] | None = None) -> None:
        cell = self._cell(idx)[:, s0:s1 + 1]
        ch_, cw_ = int(cell.shape[0]), int(cell.shape[1])
        dx, dy = int(dx), int(dy)
        cx0, cy0 = 0, 0
        cx1, cy1 = int(dst.shape[1]), int(dst.shape[0])
        if clip is not None:
            cx0 = max(cx0, int(clip[0]))
            cy0 = max(cy0, int(clip[1]))
            cx1 = min(cx1, int(clip[0]) + int(clip[2]))
            cy1 = min(cy1, int(clip[1]) + int(clip[3]))
        sx0, sy0 = max(0, cx0 - dx), max(0, cy0 - dy)
        dx0, dy0 = max(cx0, dx), max(cy0, dy)
        w = min(cw_ - sx0, cx1 - dx0)
        h = min(ch_ - sy0, cy1 - dy0)
        if w <= 0 or h <= 0:
            return
        a = cell[sy0:sy0 + h, sx0:sx0 + w][:, :, None]
        under = dst[dy0:dy0 + h, dx0:dx0 + w, :3].astype(np.float32)
        t = np.array(tuple(tint)[:3], dtype=np.float32)
        dst[dy0:dy0 + h, dx0:dx0 + w, :3] = np.clip(
            np.rint(under * (1.0 - a) + t * a), 0, 255).astype(np.uint8)


def _load_font(size: int, prefer: str | None = None):
    """A TrueType face for the **contact-sheet captions only**.

    Nothing inside a window preview uses it: those are drawn entirely from the
    skin's own bitmaps (``text.bmp`` and ``plfont``).
    """
    paths: list[str] = []
    if prefer:
        name = prefer.strip()
        if name:
            paths += [f"/System/Library/Fonts/Supplemental/{name}.ttf",
                      f"/System/Library/Fonts/{name}.ttc",
                      f"/Library/Fonts/{name}.ttf"]
    paths += list(FONT_CANDIDATES)
    for p in paths:
        try:
            return ImageFont.truetype(p, size)
        except Exception:
            continue
    try:
        return ImageFont.load_default(size=size)
    except TypeError:  # pragma: no cover - very old Pillow
        return ImageFont.load_default()


# ---------------------------------------------------------------------------
# the compositor
# ---------------------------------------------------------------------------

class _Compositor:
    """Draws the mocked windows from nothing but the built files + the spec."""

    def __init__(self, source: _Source):
        self.src = source
        self.warnings: list[str] = []
        self.vis = _parse_viscolor(source.text("viscolor.txt"))
        self.pledit = _parse_pledit(source.text("pledit.txt"))
        self._plfont: _PlFont | None = None
        self._plfont_loaded = False

    def warn(self, msg: str) -> None:
        if msg not in self.warnings:
            self.warnings.append(msg)

    def pl_font(self) -> _PlFont | None:
        """The skin's playlist typeface, or ``None`` if it ships none."""
        if self._plfont_loaded:
            return self._plfont
        self._plfont_loaded = True
        arr = self.src.image(PLFONT_STEM)
        if arr is None:
            self.warn(f"no {PLFONT_STEM}.png/.bmp: playlist rows left empty")
        else:
            try:
                self._plfont = _PlFont(
                    arr, _parse_ini(self.src.text(f"{PLFONT_STEM}.txt"), "playlistfont"))
            except ValueError as exc:
                self.warn(f"{PLFONT_STEM} ignored: {exc}")
        return self._plfont

    # -- plumbing ------------------------------------------------------
    def sheet(self, name: str) -> np.ndarray | None:
        a = self.src.sheet(name)
        if a is None:
            self.warn(f"missing sheet {spec.sheet_file(name)!r}")
            return None
        want = spec.sheet_size(name)
        got = (int(a.shape[1]), int(a.shape[0]))
        if got != want:
            self.warn(f"{spec.sheet_file(name)} is {got[0]}x{got[1]}, "
                      f"spec says {want[0]}x{want[1]}")
        return a

    def spr(self, dst: np.ndarray, sheet: str, sprite: str,
            x: int, y: int) -> None:
        """Blit a named sprite to ``(x, y)`` in window coordinates."""
        _blit(dst, x, y, self.sheet(sheet), spec.sprite(sheet, sprite))

    def spr_at(self, dst: np.ndarray, sheet: str, sprite: str,
               window: str, key: str) -> None:
        """Blit a named sprite to the layout rect ``layout.<window>.<key>``."""
        r = spec.lrect(window, key)
        self.spr(dst, sheet, sprite, r.x, r.y)

    # -- the 5x6 bitmap font -------------------------------------------
    def bitmap_text(self, dst: np.ndarray, x: int, y: int, text: str,
                    max_width: int | None = None) -> int:
        """Draw ``text`` with ``text.bmp``; returns the width actually drawn.

        ``max_width`` clips the run *exactly*: the glyph straddling the edge is
        cut mid-column rather than skipped or allowed to overrun.
        """
        sheet = self.sheet("text")
        gw = spec.GLYPH_W
        drawn = 0
        for i, ch in enumerate(text):
            gx = x + i * gw
            w = gw
            if max_width is not None:
                avail = (x + int(max_width)) - gx
                if avail <= 0:
                    break
                w = min(w, avail)
            g = spec.glyph_rect(ch)
            _blit(dst, gx, y, sheet, Rect(g.x, g.y, w, g.h))
            drawn = (gx + w) - x
        return drawn

    # -- the spectrum analyser -----------------------------------------
    def spectrum(self, dst: np.ndarray, rect: Rect) -> None:
        """Winamp's 19-bar spectrum: 3 px bar + 1 px gap in a 76x16 well."""
        bg, dot = self.vis[0], self.vis[1]
        _fill(dst, rect.x, rect.y, rect.w, rect.h, bg)
        # background dot grid: even x on odd y (SPEC 2.1)
        for yy in range(1, rect.h, 2):
            for xx in range(0, rect.w, 2):
                _px(dst, rect.x + xx, rect.y + yy, dot)
        bar_w, gap = 3, 1
        stride = bar_w + gap
        top_idx, bottom_idx = 2, 17
        for j, height in enumerate(BAR_HEIGHTS):
            bx = j * stride
            if bx >= rect.w:
                break
            h = _clamp(int(height), 0, rect.h)
            for row in range(rect.h - h, rect.h):
                # colour 2 is the TOP row of the well, 17 the bottom
                ci = _clamp(top_idx + row, top_idx, bottom_idx)
                for k in range(bar_w):
                    if bx + k < rect.w:
                        _px(dst, rect.x + bx + k, rect.y + row, self.vis[ci])
            cap = rect.h - h - 2       # falling peak cap, 2 px above the bar
            if 0 <= cap < rect.h:
                for k in range(bar_w):
                    if bx + k < rect.w:
                        _px(dst, rect.x + bx + k, rect.y + cap, self.vis[23])

    def mini_spectrum(self, dst: np.ndarray, rect: Rect) -> None:
        """The window-shade mini analyser: 19 bars on a 2 px stride in 38x5."""
        stride = 2
        rows = rect.h
        for j, height in enumerate(BAR_HEIGHTS):
            bx = j * stride
            if bx >= rect.w:
                break
            h = _clamp(_r(height * rows / 16.0), 1, rows)
            for row in range(rows - h, rows):
                # viscolor 2..17 compressed onto ``rows`` rows
                ci = 2 + _r(row * 15.0 / max(1, rows - 1))
                _px(dst, rect.x + bx, rect.y + row, self.vis[_clamp(ci, 2, 17)])

    # -- main window ---------------------------------------------------
    def render_main(self) -> np.ndarray:
        w, h = spec.window_size("main")
        c = _new(w, h)
        L = "main"

        self.spr(c, "main", "MAIN_WINDOW_BACKGROUND", 0, 0)
        self.spr_at(c, "titlebar", "MAIN_TITLE_BAR_SELECTED", L, "titleBar")

        # -- time: -02:47 --------------------------------------------
        if self.src.sheet("nums_ex") is not None:
            digits_sheet, minus_sprite, minus_key = "nums_ex", "DIGIT_MINUS", "minusSignEx"
        else:
            digits_sheet, minus_sprite, minus_key = "numbers", "MINUS_SIGN", "minusSignLegacy"
        self.spr_at(c, digits_sheet, minus_sprite, L, minus_key)
        for rect, ch in zip(spec.lval(L, "digits"), TIME_DIGITS):
            r = Rect(*rect)
            self.spr(c, digits_sheet, f"DIGIT_{ch}", r.x, r.y)

        # -- play/work LEDs (they overlap by 1 px; work goes down first)
        self.spr_at(c, "playpaus", "MAIN_WORKING_INDICATOR", L, "workIndicator")
        self.spr_at(c, "playpaus", "MAIN_PLAYING_INDICATOR", L, "playPauseIndicator")

        # -- visualiser ----------------------------------------------
        self.spectrum(c, spec.lrect(L, "visualizer"))

        # -- marquee + small text fields -----------------------------
        mq = spec.lrect(L, "marquee")
        self.bitmap_text(c, mq.x, mq.y, MARQUEE, max_width=mq.w)
        kbps = spec.lrect(L, "kbps")
        self.bitmap_text(c, kbps.x, kbps.y, KBPS_TEXT, max_width=kbps.w)
        khz = spec.lrect(L, "khz")
        self.bitmap_text(c, khz.x, khz.y, KHZ_TEXT, max_width=khz.w)

        # -- source lamps: live data OK -> stereo lit, local-only unlit
        self.spr_at(c, "monoster", "MAIN_STEREO_SELECTED", L, "stereo")
        self.spr_at(c, "monoster", "MAIN_MONO", L, "mono")

        # -- volume (session %) and balance (weekly %) ----------------
        vmax = spec.frame_count("volume") - 1
        vol = spec.lrect(L, "volume")
        _blit(c, vol.x, vol.y, self.sheet("volume"),
              spec.frame("volume", _clamp(_r(SESSION_PCT * vmax / 100.0), 0, vmax)))
        vt = spec.lval(L, "volumeThumbTravel")
        self.spr(c, "volume", "MAIN_VOLUME_THUMB",
                 _r(vt[0] + SESSION_PCT * (vt[1] - vt[0]) / 100.0),
                 int(spec.lval(L, "volumeThumbY")))

        bmax = spec.frame_count("balance") - 1
        bal = spec.lrect(L, "balance")
        _blit(c, bal.x, bal.y, self.sheet("balance"),
              spec.frame("balance", _clamp(_r(WEEK_PCT * bmax / 100.0), 0, bmax)))
        bt = spec.lval(L, "balanceThumbTravel")
        self.spr(c, "balance", "MAIN_BALANCE_THUMB",
                 _r(bt[0] + WEEK_PCT * (bt[1] - bt[0]) / 100.0),
                 int(spec.lval(L, "balanceThumbY")))

        # -- position bar ---------------------------------------------
        pos = spec.lrect(L, "posbar")
        self.spr(c, "posbar", "MAIN_POSITION_SLIDER_BACKGROUND", pos.x, pos.y)
        pt = spec.lval(L, "posbarThumbTravel")
        self.spr(c, "posbar", "MAIN_POSITION_SLIDER_THUMB",
                 pt[0] + _r(POSITION_FRAC * (pt[1] - pt[0])), pos.y)

        # -- window toggles + transport --------------------------------
        self.spr_at(c, "shufrep", "MAIN_EQ_BUTTON_SELECTED", L, "eqButton")
        self.spr_at(c, "shufrep", "MAIN_PLAYLIST_BUTTON", L, "plButton")

        self.spr_at(c, "cbuttons", "MAIN_PREVIOUS_BUTTON", L, "previous")
        self.spr_at(c, "cbuttons", "MAIN_PLAY_BUTTON_ACTIVE", L, "play")
        self.spr_at(c, "cbuttons", "MAIN_PAUSE_BUTTON", L, "pause")
        self.spr_at(c, "cbuttons", "MAIN_STOP_BUTTON", L, "stop")
        self.spr_at(c, "cbuttons", "MAIN_NEXT_BUTTON", L, "next")
        self.spr_at(c, "cbuttons", "MAIN_EJECT_BUTTON", L, "eject")

        self.spr_at(c, "shufrep", "MAIN_SHUFFLE_BUTTON", L, "shuffle")
        self.spr_at(c, "shufrep", "MAIN_REPEAT_BUTTON", L, "repeat")

        # -- clutter bar with V held ----------------------------------
        cb = spec.lrect(L, "clutterBar")
        _blit(c, cb.x, cb.y, self.sheet("titlebar"), spec.clutter_column("V"))

        # -- title-bar buttons ----------------------------------------
        self._title_buttons(c, L)
        return c

    def _title_buttons(self, c: np.ndarray, window: str,
                       shade_selected: bool = False) -> None:
        self.spr_at(c, "titlebar", "MAIN_OPTIONS_BUTTON", window, "optionsButton")
        self.spr_at(c, "titlebar", "MAIN_MINIMIZE_BUTTON", window, "minimizeButton")
        self.spr_at(c, "titlebar",
                    "MAIN_SHADE_BUTTON_SELECTED" if shade_selected else "MAIN_SHADE_BUTTON",
                    window, "shadeButton")
        self.spr_at(c, "titlebar", "MAIN_CLOSE_BUTTON", window, "closeButton")

    # -- window shade ---------------------------------------------------
    def render_shade(self) -> np.ndarray:
        w, h = spec.window_size("shade")
        c = _new(w, h)
        L = "shade"

        self.spr(c, "titlebar", "MAIN_SHADE_BACKGROUND_SELECTED", 0, 0)
        # the shade button reads "selected" while the window *is* shaded
        self._title_buttons(c, L, shade_selected=True)

        self.mini_spectrum(c, spec.lrect(L, "miniVisualizer"))

        for (gx, gy), ch in zip(spec.lval(L, "timeGlyphs"), SHADE_GLYPHS):
            self.bitmap_text(c, int(gx), int(gy), ch)

        pos = spec.lrect(L, "position")
        self.spr(c, "titlebar", "MAIN_SHADE_POSITION_BACKGROUND", pos.x, pos.y)
        pt = spec.lval(L, "positionThumbTravel")
        self.spr(c, "titlebar", "MAIN_SHADE_POSITION_THUMB",
                 pt[0] + _r(POSITION_FRAC * (pt[1] - pt[0])), pos.y)
        return c

    # -- equaliser ------------------------------------------------------
    def render_eq(self) -> np.ndarray:
        w, h = spec.window_size("eq")
        c = _new(w, h)
        L = "eq"
        eq = self.sheet("eqmain")

        self.spr(c, "eqmain", "EQ_WINDOW_BACKGROUND", 0, 0)
        self.spr_at(c, "eqmain", "EQ_TITLE_BAR_SELECTED", L, "titleBar")
        self.spr_at(c, "eqmain", "EQ_CLOSE_BUTTON", L, "closeButton")
        self.spr_at(c, "eqmain", "EQ_ON_BUTTON_SELECTED", L, "onButton")
        self.spr_at(c, "eqmain", "EQ_AUTO_BUTTON", L, "autoButton")
        self.spr_at(c, "eqmain", "EQ_PRESETS_BUTTON", L, "presetsButton")

        fmax = spec.frame_count("eqmain") - 1
        travel = spec.lval(L, "sliderThumbTravelY")
        off_x = int(spec.lval(L, "sliderThumbOffsetX"))

        def slider(x: int, y: int, v: float) -> None:
            _blit(c, x, y, eq, spec.frame("eqmain", _clamp(_r(v * fmax), 0, fmax)))
            self.spr(c, "eqmain", "EQ_SLIDER_THUMB",
                     x + off_x, y + _r((1.0 - v) * (travel[1] - travel[0])) + travel[0])

        pre = spec.lrect(L, "preampSlider")
        slider(pre.x, pre.y, EQ_PREAMP)

        bands = spec.lval(L, "bandSliders")
        for i in range(int(bands["count"])):
            v = EQ_BANDS[i % len(EQ_BANDS)]
            slider(int(bands["x0"]) + int(bands["strideX"]) * i, int(bands["y"]), v)

        # -- the response graph ---------------------------------------
        g = spec.lrect(L, "graph")
        self.spr(c, "eqmain", "EQ_GRAPH_BACKGROUND", g.x, g.y)
        line_strip = spec.sprite("eqmain", "EQ_GRAPH_LINE_COLORS")

        def line_colour(row: int) -> tuple[int, int, int, int]:
            if eq is None:
                return MISSING
            sx = _clamp(line_strip.x, 0, eq.shape[1] - 1)
            sy = _clamp(line_strip.y + _clamp(row, 0, line_strip.h - 1), 0, eq.shape[0] - 1)
            return tuple(int(v) for v in eq[sy, sx])  # type: ignore[return-value]

        span = max(1, g.w - 1)
        rows = g.h - 1
        prev: int | None = None
        for px_ in range(g.w):
            t = px_ * (len(EQ_BANDS) - 1) / span
            v = min(1.0, max(0.0, _catmull_rom(EQ_BANDS, t)))
            row = _clamp(_r((1.0 - v) * rows), 0, rows)
            if prev is not None and abs(row - prev) > 1:
                step = 1 if row > prev else -1
                for rr in range(prev + step, row, step):
                    _px(c, g.x + px_, g.y + rr, line_colour(rr))
            _px(c, g.x + px_, g.y + row, line_colour(row))
            prev = row

        # -- preamp level ---------------------------------------------
        pre_row = _clamp(_r((1.0 - EQ_PREAMP) * rows), 0, rows)
        self.spr(c, "eqmain", "EQ_PREAMP_LINE", g.x, g.y + pre_row)
        return c

    # -- playlist -------------------------------------------------------
    def render_field(self) -> np.ndarray:
        """The Token Flow window (SPEC 2.9): the `gen` frame around a mocked field."""
        w, h = spec.window_size("field")
        c = _new(w, h)
        L = "field"
        gen = self.sheet("gen")

        top_h = int(spec.lval(L, "titleHeight"))
        bot_h = int(spec.lval(L, "bottomHeight"))
        left_w = int(spec.lval(L, "leftWidth"))
        right_w = int(spec.lval(L, "rightWidth"))

        tl = spec.sprite("gen", "GEN_TOP_LEFT")
        tile = spec.sprite("gen", "GEN_TOP_TILE")
        title = spec.sprite("gen", "GEN_TITLE_PLATE")
        tr = spec.sprite("gen", "GEN_TOP_RIGHT")
        lt = spec.sprite("gen", "GEN_LEFT_TILE")
        rt = spec.sprite("gen", "GEN_RIGHT_TILE")
        bl = spec.sprite("gen", "GEN_BOTTOM_LEFT")
        bt = spec.sprite("gen", "GEN_BOTTOM_TILE")
        br = spec.sprite("gen", "GEN_BOTTOM_RIGHT")

        right_edge = w - tr.w
        x = tl.w
        while x < right_edge:
            _blit(c, x, 0, gen, Rect(tile.x, tile.y, min(tile.w, right_edge - x), tile.h))
            x += tile.w
        _blit(c, 0, 0, gen, tl)
        _blit(c, (w - title.w) // 2, 0, gen, title)
        _blit(c, right_edge, 0, gen, tr)

        body_top, body_bot = top_h, h - bot_h
        y = body_top
        while y < body_bot:
            hh = min(lt.h, body_bot - y)
            _blit(c, 0, y, gen, Rect(lt.x, lt.y, lt.w, hh))
            _blit(c, w - right_w, y, gen, Rect(rt.x, rt.y, rt.w, hh))
            y += lt.h

        x = bl.w
        while x < w - br.w:
            _blit(c, x, body_bot, gen, Rect(bt.x, bt.y, min(bt.w, w - br.w - x), bt.h))
            x += bt.w
        _blit(c, 0, body_bot, gen, bl)
        _blit(c, w - br.w, body_bot, gen, br)

        cx, cy, cw, ch = spec.lval(L, "closeButtonFromTopRight")
        self.spr(c, "gen", "GEN_CLOSE", w + int(cx), int(cy))
        lx, ly, lw, lh = spec.lval(L, "lampFromTopRight")
        self.spr(c, "gen", "GEN_LAMP_ON", w + int(lx), int(ly))

        _field_trace(self, c, left_w, body_top, w - left_w - right_w, body_bot - body_top)

        # the app draws these three in the skin's own 5x6 face (SPEC 2.9)
        title_text = "TOKEN FLOW - AUTO"
        self.bitmap_text(c, (w - len(title_text) * 5) // 2, int(spec.lval(L, "titleTextY")), title_text)
        rx, ry = spec.lval(L, "readoutFromBottomLeft")
        self.bitmap_text(c, int(rx), h + int(ry), "SCOPE")
        vx, vy = spec.lval(L, "valueFromBottomRight")
        value = "19.8K/MIN  78%"
        self.bitmap_text(c, w + int(vx) - len(value) * 5, h + int(vy), value)
        return c

    def render_playlist(self) -> np.ndarray:
        w, h = spec.window_size("playlist")
        c = _new(w, h)
        L = "playlist"
        pl = self.sheet("pledit")

        top_h = int(spec.lval(L, "titleHeight"))
        bot_h = int(spec.lval(L, "bottomHeight"))
        left_w = int(spec.lval(L, "leftWidth"))
        right_w = int(spec.lval(L, "rightWidth"))

        tl = spec.sprite("pledit", "PLAYLIST_TOP_LEFT_SELECTED")
        tile = spec.sprite("pledit", "PLAYLIST_TOP_TILE_SELECTED")
        title = spec.sprite("pledit", "PLAYLIST_TITLE_BAR_SELECTED")
        tr = spec.sprite("pledit", "PLAYLIST_TOP_RIGHT_CORNER_SELECTED")
        lt = spec.sprite("pledit", "PLAYLIST_LEFT_TILE")
        rt = spec.sprite("pledit", "PLAYLIST_RIGHT_TILE")
        bl = spec.sprite("pledit", "PLAYLIST_BOTTOM_LEFT_CORNER")
        br = spec.sprite("pledit", "PLAYLIST_BOTTOM_RIGHT_CORNER")

        # top row: left corner, tiles, centred title piece, right corner
        _blit(c, 0, 0, pl, tl)
        x = tl.w
        right_edge = w - tr.w
        while x < right_edge:
            _blit(c, x, 0, pl, Rect(tile.x, tile.y, min(tile.w, right_edge - x), tile.h))
            x += tile.w
        _blit(c, (w - title.w) // 2, 0, pl, title)
        _blit(c, right_edge, 0, pl, tr)

        # sides
        body_top, body_bot = top_h, h - bot_h
        y = body_top
        while y < body_bot:
            hh = min(lt.h, body_bot - y)
            _blit(c, 0, y, pl, Rect(lt.x, lt.y, lt.w, hh))
            _blit(c, w - right_w, y, pl, Rect(rt.x, rt.y, rt.w, min(rt.h, body_bot - y)))
            y += lt.h

        # bottom corners
        _blit(c, 0, body_bot, pl, bl)
        _blit(c, bl.w, body_bot, pl, br)

        # list well
        bg = _colour(self.pledit.get("normalbg", ""), (0, 0, 0, 255))
        list_x, list_w = left_w, w - left_w - right_w
        _fill(c, list_x, body_top, list_w, body_bot - body_top, bg)

        # scroll handle
        self.spr(c, "pledit", "PLAYLIST_SCROLL_HANDLE",
                 w + int(spec.lval(L, "scrollHandleFromRight")), 26)

        # bottom-right readouts in the 5x6 bitmap font
        rdx, rdy = spec.lval(L, "runningInfoFromBottomRight")
        self.bitmap_text(c, w + int(rdx), h + int(rdy), PLAYLIST_RUNNING_INFO)
        mtx, mty = spec.lval(L, "miniTimeFromBottomRight")
        self.bitmap_text(c, w + int(mtx), h + int(mty), PLAYLIST_MINI_TIME)

        # -- session rows in the skin's own bitmap typeface (SPEC 2.4/3.2) --
        # No system font: the list has to be made of the same pixels as the
        # hardware around it.  pledit.txt's ``Font`` key is ignored.
        pf = self.pl_font()
        row_h = pf.row_height if pf is not None else int(spec.lval(L, "rowHeight"))
        first_y = body_top + 1
        normal = _colour(self.pledit.get("normal", ""), (0, 255, 0, 255))
        current = _colour(self.pledit.get("current", ""), (255, 255, 255, 255))
        sel_bg = _colour(self.pledit.get("selectedbg", ""), (0, 0, 198, 255))

        well = (list_x, body_top, list_w, body_bot - body_top)
        for i, (label, value) in enumerate(PLAYLIST_ROWS):
            top = first_y + row_h * i
            if top + row_h > body_bot:
                break
            if i == PLAYLIST_SELECTED_ROW:
                _fill(c, list_x, top, list_w, row_h, sel_bg)
            if pf is None:
                continue
            tint = current if i == PLAYLIST_CURRENT_ROW else normal
            gy = top + pf.offset_y
            val = _ascii_fold(value)
            val_w = pf.visual_width(val)
            avail = (PLAYLIST_COST_RIGHT_X - val_w - PLAYLIST_VALUE_GAP) - PLAYLIST_TEXT_X
            pf.draw(c, PLAYLIST_TEXT_X, gy,
                    pf.truncate(_ascii_fold(label), avail), tint, clip=well)
            pf.draw(c, PLAYLIST_COST_RIGHT_X - val_w, gy, val, tint, clip=well)

        return c

    # -- contact sheet ----------------------------------------------------
    #: a sheet this small in *both* axes is blown up in the contact sheet
    THUMB_UPSCALE_MAX = 160
    #: keep the contact sheet inside this box in either axis
    SHEET_MAX = 4000

    def render_sheets(self) -> Image.Image:
        pad, gap, cap_h, border = 10, 12, 15, 1
        caption_font = _load_font(12)

        # every sheet the spec names, then any extra bitmap the skin ships
        # (``plfont`` is a Tokenamp extension and is not in sprites.json)
        entries: list[tuple[str, np.ndarray | None, str]] = []
        seen: set[str] = set()
        for name in spec.sheet_names():
            fname = spec.sheet_file(name)
            seen.add(fname.rsplit(".", 1)[0].lower())
            w, h = spec.sheet_size(name)
            entries.append((fname, self.sheet(name), f"{w}x{h}"))
        for base in self.src.names():
            stem, _, ext = base.rpartition(".")
            if ext not in ("bmp", "png") or not stem or stem in seen:
                continue
            seen.add(stem)
            entries.append((base, self.src.image(stem), ""))

        cells: list[tuple[str, Image.Image | None, int, int]] = []
        for fname, arr, want in entries:
            if arr is None:
                cells.append((f"{fname}  -- MISSING", None, 170, 28))
                continue
            im = Image.fromarray(arr, "RGBA").convert("RGB")
            big = im.width <= self.THUMB_UPSCALE_MAX and im.height <= self.THUMB_UPSCALE_MAX
            scale = SCALE if big else 1
            if scale != 1:
                im = im.resize((im.width * scale, im.height * scale),
                               Image.Resampling.NEAREST)
            label = f"{fname}  {arr.shape[1]}x{arr.shape[0]}"
            if want and f"{arr.shape[1]}x{arr.shape[0]}" != want:
                label += f"  != spec {want}"
            if scale != 1:
                label += f"  ({scale}x)"
            cells.append((label, im, im.width, im.height))

        def cell_h(c) -> int:
            return cap_h + c[3] + 2 * border + gap

        def cell_w(c) -> int:
            return max(c[2] + 2 * border, 180)

        # Columns: a single 650x3000 strip is unreadable, so pick the column
        # count that gets closest to a 3:4 page and still fits SHEET_MAX.
        def pack(n: int) -> list[list]:
            if n <= 1:
                return [list(cells)]
            target = sum(cell_h(c) for c in cells) / float(n)
            cols: list[list] = [[]]
            run = 0.0
            for c in cells:
                if cols[-1] and len(cols) < n and run >= target:
                    cols.append([])
                    run = 0.0
                cols[-1].append(c)
                run += cell_h(c)
            while len(cols) < n:
                cols.append([])
            return cols

        best: tuple[float, int, list[list]] | None = None
        for n in (1, 2, 3, 4):
            cols = pack(n)
            col_w = [max((cell_w(c) for c in col), default=0) for col in cols]
            col_h = [sum(cell_h(c) for c in col) for col in cols]
            width = sum(col_w) + gap * (len(cols) + 1)
            height = max(col_h) + 2 * pad
            if width > self.SHEET_MAX or height > self.SHEET_MAX:
                continue
            score = abs(math.log((width / height) / 0.75))
            if best is None or score < best[0]:
                best = (score, n, cols)
        columns = best[2] if best else pack(4)
        columns = [c for c in columns if c]

        col_w = [max((cell_w(c) for c in col), default=0) for col in columns]
        col_h = [sum(cell_h(c) for c in col) for col in columns]
        width = sum(col_w) + gap * (len(columns) + 1)
        height = max(col_h) + 2 * pad

        sheet = Image.new("RGB", (width, height), (104, 104, 108))
        d = ImageDraw.Draw(sheet)
        x = gap
        for col, cw in zip(columns, col_w):
            y = pad
            for label, im, iw, ih in col:
                d.text((x, y + 1), label, font=caption_font, fill=(28, 28, 30))
                d.text((x, y), label, font=caption_font, fill=(246, 246, 250))
                by = y + cap_h
                d.rectangle([x, by, x + iw + 2 * border - 1, by + ih + 2 * border - 1],
                            fill=(255, 0, 255))
                if im is None:
                    d.rectangle([x + border, by + border,
                                 x + border + iw - 1, by + border + ih - 1],
                                fill=(40, 40, 44))
                else:
                    sheet.paste(im, (x + border, by + border))
                y = by + ih + 2 * border + gap
            x += cw + gap
        return sheet


def _catmull_rom(vals: Sequence[float], t: float) -> float:
    """Centripetal-ish Catmull-Rom through ``vals`` at parameter ``t``."""
    n = len(vals)
    if n == 0:
        return 0.0
    if n == 1:
        return float(vals[0])
    i = _clamp(int(math.floor(t)), 0, n - 2)
    f = t - i
    p0 = float(vals[max(0, i - 1)])
    p1 = float(vals[i])
    p2 = float(vals[min(n - 1, i + 1)])
    p3 = float(vals[min(n - 1, i + 2)])
    return 0.5 * ((2 * p1)
                  + (-p0 + p2) * f
                  + (2 * p0 - 5 * p1 + 4 * p2 - p3) * f * f
                  + (-p0 + 3 * p1 - 3 * p2 + p3) * f * f * f)


# ---------------------------------------------------------------------------
# public entry point
# ---------------------------------------------------------------------------

def _field_trace(comp, c, x0: int, y0: int, w: int, h: int) -> None:
    """A stand-in for the phosphor field (SPEC 3.3).

    The real display is drawn by the app, not by the toolkit, so this is only
    enough of a trace -- in the skin's own visualiser colours -- to show the
    artist how their frame sits around a live well.
    """
    import math

    bg, dot = comp.vis[0], comp.vis[1]
    _fill(c, x0, y0, w, h, bg)
    for yy in range(2, h, 4):
        for xx in range(2, w, 4):
            _px(c, x0 + xx, y0 + yy, dot)
    cy = y0 + h // 2
    for i in range(w):
        env = 0.25 + 0.75 * abs(math.sin(i * 0.035))
        amp = env * (h / 2 - 8) * (0.45 + 0.55 * abs(math.sin(i * 0.78)))
        top, bottom = int(cy - amp), int(cy + amp)
        for yy in range(top, bottom + 1):
            d = abs(yy - cy) / max(1.0, amp)
            # the real field runs hot only at its core, so keep the mock off the top of the ramp
            _px(c, x0 + i, yy, comp.vis[_clamp(int(5 + d * 12), 2, 17)])


def render_previews(built_dir, out_dir) -> dict[str, Path]:
    """Composite mocked window previews from a built skin.

    :param built_dir: a directory of loose skin files, or a ``.wsz``/``.zip``.
    :param out_dir: created if needed; receives ``main.png``, ``shade.png``,
        ``eq.png``, ``playlist.png``, ``field.png``, ``all.png``, their ``*_4x.png``
        nearest-neighbour blow-ups, and ``sheets.png``.
    :returns: ``{"main": Path(...), "main_4x": Path(...), ..., "sheets": Path(...)}``
    """
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)

    source = _Source(built_dir)
    try:
        comp = _Compositor(source)
        frames = {
            "main": comp.render_main(),
            "shade": comp.render_shade(),
            "eq": comp.render_eq(),
            "playlist": comp.render_playlist(),
            "field": comp.render_field(),
        }

        # docked stack: main / eq / playlist, no gaps (SPEC 2.7, 3.1)
        stack = [frames["main"], frames["eq"], frames["playlist"]]
        aw = max(int(a.shape[1]) for a in stack)
        ah = sum(int(a.shape[0]) for a in stack)
        all_arr = _new(aw, ah)
        y = 0
        for a in stack:
            all_arr[y:y + a.shape[0], 0:a.shape[1]] = a
            y += int(a.shape[0])
        frames["all"] = all_arr

        written: dict[str, Path] = {}
        for name in PREVIEW_NAMES:
            arr = frames[name]
            img = Image.fromarray(arr, "RGBA").convert("RGB")
            p = out / f"{name}.png"
            img.save(p)
            written[name] = p
            big = img.resize((img.width * SCALE, img.height * SCALE),
                             Image.Resampling.NEAREST)
            p4 = out / f"{name}_{SCALE}x.png"
            big.save(p4)
            written[f"{name}_{SCALE}x"] = p4

        sheets = comp.render_sheets()
        ps = out / "sheets.png"
        sheets.save(ps)
        written["sheets"] = ps

        for msg in comp.warnings:
            print(f"  preview: {msg}", file=sys.stderr)
        return written
    finally:
        source.close()


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if len(args) != 2 or args[0] in ("-h", "--help"):
        print(__doc__.strip().splitlines()[0], file=sys.stderr)
        print("usage: python3 -m skinkit.preview <built-dir-or-wsz> <out-dir>",
              file=sys.stderr)
        return 2
    try:
        written = render_previews(args[0], args[1])
    except FileNotFoundError as exc:
        print(f"skinkit.preview: {exc}", file=sys.stderr)
        return 1
    for key in sorted(written):
        print(f"  {key:>12s}  {written[key]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
