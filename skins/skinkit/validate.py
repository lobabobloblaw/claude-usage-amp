"""validate -- structural checks on a built skin.

::

    cd skins && python3 -m skinkit.validate dist/Base.wsz
    cd skins && python3 -m skinkit.validate base/out

Exits non-zero with a list of problems.  Everything it checks is something an
artist can get wrong without noticing: a sheet that came out the wrong size, a
pressed state that is identical to the normal one, two digits that look the
same, a glyph cell left empty.
"""

from __future__ import annotations

import io
import sys
import zipfile
from pathlib import Path
from typing import Iterable

import numpy as np

from . import spec

__all__ = ["validate", "Problems", "main"]

REQUIRED_TEXT_FILES = ("viscolor.txt", "pledit.txt", "readme.txt")


class Problems(list):
    """Failures (the list itself) plus non-fatal ``warnings``."""

    def __init__(self, *a):
        super().__init__(*a)
        self.warnings: list[str] = []

    def add(self, msg: str) -> None:
        self.append(msg)

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)


class _Source:
    """Reads a skin from a directory or a .wsz/.zip, case-insensitively."""

    def __init__(self, path: Path):
        self.path = path
        self.flat = True
        self._zip: zipfile.ZipFile | None = None
        self._names: dict[str, str] = {}
        if path.is_dir():
            for p in path.iterdir():
                if p.is_file():
                    self._names[p.name.lower()] = p.name
        else:
            self._zip = zipfile.ZipFile(path)
            for info in self._zip.infolist():
                if info.is_dir():
                    self.flat = False
                    continue
                if "/" in info.filename or "\\" in info.filename:
                    self.flat = False
                self._names[Path(info.filename).name.lower()] = info.filename

    def has(self, name: str) -> bool:
        return name.lower() in self._names

    def read(self, name: str) -> bytes:
        real = self._names[name.lower()]
        if self._zip is not None:
            return self._zip.read(real)
        return (self.path / real).read_bytes()

    def image(self, name: str) -> np.ndarray:
        from PIL import Image
        img = Image.open(io.BytesIO(self.read(name))).convert("RGB")
        return np.array(img, dtype=np.uint8)

    def close(self) -> None:
        if self._zip is not None:
            self._zip.close()


def _sub(arr: np.ndarray, r: spec.Rect) -> np.ndarray:
    return arr[r.y:r.y + r.h, r.x:r.x + r.w]


def _same(a: np.ndarray, b: np.ndarray) -> bool:
    return a.shape == b.shape and bool(np.array_equal(a, b))


#: (sheet, normal sprite, alternate sprite, human label) triples that must differ
_DIFFER_PAIRS = [
    ("titlebar", "MAIN_OPTIONS_BUTTON", "MAIN_OPTIONS_BUTTON_DEPRESSED", "options button"),
    ("titlebar", "MAIN_MINIMIZE_BUTTON", "MAIN_MINIMIZE_BUTTON_DEPRESSED", "minimize button"),
    ("titlebar", "MAIN_CLOSE_BUTTON", "MAIN_CLOSE_BUTTON_DEPRESSED", "close button"),
    ("titlebar", "MAIN_SHADE_BUTTON", "MAIN_SHADE_BUTTON_DEPRESSED", "shade button"),
    ("titlebar", "MAIN_SHADE_BUTTON_SELECTED", "MAIN_SHADE_BUTTON_SELECTED_DEPRESSED",
     "shade button (selected)"),
    ("titlebar", "MAIN_TITLE_BAR_SELECTED", "MAIN_TITLE_BAR", "title bar active/inactive"),
    ("cbuttons", "MAIN_PREVIOUS_BUTTON", "MAIN_PREVIOUS_BUTTON_ACTIVE", "previous button"),
    ("cbuttons", "MAIN_PLAY_BUTTON", "MAIN_PLAY_BUTTON_ACTIVE", "play button"),
    ("cbuttons", "MAIN_PAUSE_BUTTON", "MAIN_PAUSE_BUTTON_ACTIVE", "pause button"),
    ("cbuttons", "MAIN_STOP_BUTTON", "MAIN_STOP_BUTTON_ACTIVE", "stop button"),
    ("cbuttons", "MAIN_NEXT_BUTTON", "MAIN_NEXT_BUTTON_ACTIVE", "next button"),
    ("cbuttons", "MAIN_EJECT_BUTTON", "MAIN_EJECT_BUTTON_ACTIVE", "eject button"),
    ("shufrep", "MAIN_REPEAT_BUTTON", "MAIN_REPEAT_BUTTON_DEPRESSED", "repeat button"),
    ("shufrep", "MAIN_REPEAT_BUTTON", "MAIN_REPEAT_BUTTON_SELECTED", "repeat selected"),
    ("shufrep", "MAIN_REPEAT_BUTTON_SELECTED", "MAIN_REPEAT_BUTTON_SELECTED_DEPRESSED",
     "repeat selected pressed"),
    ("shufrep", "MAIN_SHUFFLE_BUTTON", "MAIN_SHUFFLE_BUTTON_DEPRESSED", "shuffle button"),
    ("shufrep", "MAIN_SHUFFLE_BUTTON", "MAIN_SHUFFLE_BUTTON_SELECTED", "shuffle selected"),
    ("shufrep", "MAIN_SHUFFLE_BUTTON_SELECTED", "MAIN_SHUFFLE_BUTTON_SELECTED_DEPRESSED",
     "shuffle selected pressed"),
    ("shufrep", "MAIN_EQ_BUTTON", "MAIN_EQ_BUTTON_DEPRESSED", "EQ toggle"),
    ("shufrep", "MAIN_EQ_BUTTON", "MAIN_EQ_BUTTON_SELECTED", "EQ toggle selected"),
    ("shufrep", "MAIN_PLAYLIST_BUTTON", "MAIN_PLAYLIST_BUTTON_DEPRESSED", "PL toggle"),
    ("shufrep", "MAIN_PLAYLIST_BUTTON", "MAIN_PLAYLIST_BUTTON_SELECTED", "PL toggle selected"),
    ("posbar", "MAIN_POSITION_SLIDER_THUMB", "MAIN_POSITION_SLIDER_THUMB_SELECTED",
     "position thumb"),
    ("volume", "MAIN_VOLUME_THUMB", "MAIN_VOLUME_THUMB_SELECTED", "volume thumb"),
    ("balance", "MAIN_BALANCE_THUMB", "MAIN_BALANCE_THUMB_SELECTED", "balance thumb"),
    ("monoster", "MAIN_MONO", "MAIN_MONO_SELECTED", "mono lamp"),
    ("monoster", "MAIN_STEREO", "MAIN_STEREO_SELECTED", "stereo lamp"),
    ("playpaus", "MAIN_PLAYING_INDICATOR", "MAIN_PAUSED_INDICATOR", "play vs pause icon"),
    ("playpaus", "MAIN_PAUSED_INDICATOR", "MAIN_STOPPED_INDICATOR", "pause vs stop icon"),
    ("playpaus", "MAIN_NOT_WORKING_INDICATOR", "MAIN_WORKING_INDICATOR", "work LED"),
    ("eqmain", "EQ_CLOSE_BUTTON", "EQ_CLOSE_BUTTON_ACTIVE", "EQ close button"),
    ("eqmain", "EQ_ON_BUTTON", "EQ_ON_BUTTON_DEPRESSED", "EQ ON button"),
    ("eqmain", "EQ_ON_BUTTON", "EQ_ON_BUTTON_SELECTED", "EQ ON selected"),
    ("eqmain", "EQ_AUTO_BUTTON", "EQ_AUTO_BUTTON_DEPRESSED", "EQ AUTO button"),
    ("eqmain", "EQ_AUTO_BUTTON", "EQ_AUTO_BUTTON_SELECTED", "EQ AUTO selected"),
    ("eqmain", "EQ_PRESETS_BUTTON", "EQ_PRESETS_BUTTON_SELECTED", "EQ presets button"),
    ("eqmain", "EQ_SLIDER_THUMB", "EQ_SLIDER_THUMB_SELECTED", "EQ slider thumb"),
    ("eqmain", "EQ_TITLE_BAR_SELECTED", "EQ_TITLE_BAR", "EQ title bar active/inactive"),
    ("pledit", "PLAYLIST_SCROLL_HANDLE", "PLAYLIST_SCROLL_HANDLE_SELECTED", "scroll handle"),
    ("pledit", "PLAYLIST_TOP_LEFT_SELECTED", "PLAYLIST_TOP_LEFT_CORNER",
     "playlist top-left active/inactive"),
    ("pledit", "PLAYLIST_TITLE_BAR_SELECTED", "PLAYLIST_TITLE_BAR",
     "playlist title active/inactive"),
    ("gen", "GEN_CLOSE", "GEN_CLOSE_PRESSED", "Token Flow close button"),
    ("gen", "GEN_LAMP_ON", "GEN_LAMP_OFF", "Token Flow AUTO lamp"),
]


#: pairs that a reader confuses when a face is careless.  Reported as warnings.
_LOOKALIKES = (("I", "l"), ("I", "1"), ("l", "1"), ("l", "|"), ("I", "|"),
               ("O", "0"), ("S", "5"), ("Z", "2"), ("B", "8"), ("o", "0"),
               ("c", "e"), ("a", "o"), ("u", "v"), ("g", "q"))


def _validate_plfont(src: "_Source", p: "Problems", require: bool) -> None:
    """SPEC 3.2 checks for the Sessions-list typeface."""
    from . import fonts
    have_img = src.has("plfont.bmp") or src.has("plfont.png")
    if not have_img:
        if require:
            p.add("missing plfont.bmp -- Tokenamp's own skins must ship a "
                  "Sessions-list typeface (SPEC 3.2)")
        return
    name = "plfont.png" if src.has("plfont.png") else "plfont.bmp"
    try:
        arr = src.image(name)
    except Exception as exc:  # pragma: no cover
        p.add(f"{name}: cannot decode ({exc})")
        return
    h, w = arr.shape[0], arr.shape[1]
    if w % fonts.PLFONT_COLUMNS or h % fonts.PLFONT_ROWS:
        p.add(f"{name}: is {w}x{h}; width must divide by {fonts.PLFONT_COLUMNS} "
              f"and height by {fonts.PLFONT_ROWS} (SPEC 3.2 grid)")
        return
    cw, ch = w // fonts.PLFONT_COLUMNS, h // fonts.PLFONT_ROWS

    def cell(character: str) -> np.ndarray:
        x, y, _w, _h = fonts.plfont_cell_rect(character, cw, ch)
        return arr[y:y + ch, x:x + cw]

    seen: dict[bytes, str] = {}
    for character in fonts.plfont_cell_chars():
        if character == " ":
            continue
        cl = cell(character)
        if fonts.plfont_ink_columns(cl) is None:
            p.add(f"{name}: glyph {character!r} (code {ord(character)}) has no ink")
            continue
        if character.isalnum() or character == fonts.PLFONT_ELLIPSIS:
            key = cl.tobytes()
            if key in seen:
                p.add(f"{name}: glyph {character!r} is identical to {seen[key]!r}")
            seen[key] = character
    for a_ch, b_ch in _LOOKALIKES:
        ca, cb = cell(a_ch), cell(b_ch)
        if np.array_equal(ca, cb):
            continue
        diff = int((ca[:, :, :3].astype(np.int16) != cb[:, :, :3].astype(np.int16)).any(axis=2).sum())
        if diff <= 2:
            p.warn(f"{name}: {a_ch!r} and {b_ch!r} differ by only {diff} pixel(s) "
                   f"-- they will be hard to tell apart in a list")

    if src.has("plfont.txt"):
        raw = src.read("plfont.txt").decode("latin-1")
        low = raw.lower()
        if "[playlistfont]" not in low:
            p.add("plfont.txt: missing the [PlaylistFont] section")
        values: dict[str, int] = {}
        for line in raw.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
            s = line.strip()
            if not s or s.startswith(("[", ";", "//", "#")) or "=" not in s:
                continue
            k, _, v = s.partition("=")
            v = v.split(";")[0].split("//")[0].strip()
            try:
                values[k.strip().lower()] = int(v)
            except ValueError:
                p.add(f"plfont.txt: {k.strip()}={v!r} is not an integer")
        row_h = values.get("rowheight")
        if row_h is not None and row_h < ch:
            p.add(f"plfont.txt: RowHeight={row_h} is smaller than the {ch}px cell "
                  f"-- rows would clip each other")
        if values.get("monospace") not in (None, 0, 1):
            p.add(f"plfont.txt: Monospace={values['monospace']} must be 0 or 1")
    elif require:
        p.warn("no plfont.txt -- the app's default metrics will be used")


def validate(path, require_plfont: bool = False) -> Problems:
    """Check a built skin; returns a (possibly empty) list of problems.

    ``require_plfont`` makes a missing Sessions-list typeface a failure, which
    is what Tokenamp's own skins are held to (third-party skins fall back to
    the Base face, so for them it is optional).
    """
    path = Path(path)
    p = Problems()
    if not path.exists():
        p.add(f"{path} does not exist")
        return p
    src = _Source(path)
    try:
        if src._zip is not None and not src.flat:
            p.add(f"{path.name} is not a FLAT zip -- entries must have no directory prefix")

        images: dict[str, np.ndarray] = {}
        for name in spec.sheet_names():
            fname = spec.sheet_file(name)
            if not src.has(fname):
                p.add(f"missing sheet {fname}")
                continue
            try:
                arr = src.image(fname)
            except Exception as exc:  # pragma: no cover
                p.add(f"{fname}: cannot decode ({exc})")
                continue
            w, h = spec.sheet_size(name)
            if (arr.shape[1], arr.shape[0]) != (w, h):
                p.add(f"{fname}: is {arr.shape[1]}x{arr.shape[0]}, spec requires {w}x{h}")
                continue
            images[name] = arr

        for fname in REQUIRED_TEXT_FILES:
            if not src.has(fname):
                p.add(f"missing {fname}")

        # -- pressed/selected states must differ -----------------------
        for sheet, a_name, b_name, label in _DIFFER_PAIRS:
            if sheet not in images:
                continue
            arr = images[sheet]
            try:
                ra, rb = spec.sprite(sheet, a_name), spec.sprite(sheet, b_name)
            except KeyError as exc:  # pragma: no cover
                p.add(str(exc))
                continue
            if _same(_sub(arr, ra), _sub(arr, rb)):
                p.add(f"{spec.sheet_file(sheet)}: {label} -- {a_name} is identical to {b_name}")

        # -- clutter bar pressed columns -------------------------------
        if "titlebar" in images:
            arr = images["titlebar"]
            base = _sub(arr, spec.sprite("titlebar", "MAIN_CLUTTER_BAR_BACKGROUND"))
            seen: list[tuple[str, np.ndarray]] = []
            for letter in spec.clutter_letters():
                col = _sub(arr, spec.clutter_column(letter))
                if _same(col, base):
                    p.add(f"titlebar.bmp: clutter column {letter} is identical to the "
                          f"unpressed clutter bar")
                for other, prev in seen:
                    if _same(col, prev):
                        p.add(f"titlebar.bmp: clutter columns {other} and {letter} are identical")
                seen.append((letter, col))
            if _same(base, _sub(arr, spec.sprite("titlebar", "MAIN_CLUTTER_BAR_BACKGROUND_DISABLED"))):
                p.add("titlebar.bmp: the disabled clutter bar is identical to the normal one")
            for a_name, b_name in (("MAIN_SHADE_POSITION_THUMB_LEFT", "MAIN_SHADE_POSITION_THUMB"),
                                   ("MAIN_SHADE_POSITION_THUMB", "MAIN_SHADE_POSITION_THUMB_RIGHT")):
                if _same(_sub(arr, spec.sprite("titlebar", a_name)),
                         _sub(arr, spec.sprite("titlebar", b_name))):
                    p.add(f"titlebar.bmp: {a_name} is identical to {b_name}")

        # -- slider frame strips ---------------------------------------
        for sheet, label in (("volume", "volume"), ("balance", "balance"), ("eqmain", "EQ slider")):
            if sheet not in images:
                continue
            arr = images[sheet]
            n = spec.frame_count(sheet)
            first = _sub(arr, spec.frame(sheet, 0))
            last = _sub(arr, spec.frame(sheet, n - 1))
            if _same(first, last):
                p.add(f"{spec.sheet_file(sheet)}: {label} frame 0 is identical to frame {n - 1}")
            distinct = len({_sub(arr, spec.frame(sheet, i)).tobytes() for i in range(n)})
            if distinct <= 1:
                p.add(f"{spec.sheet_file(sheet)}: all {n} {label} frames are identical")
            elif distinct < n // 2:
                p.add(f"{spec.sheet_file(sheet)}: only {distinct} of {n} {label} frames differ")

        # -- digits ----------------------------------------------------
        for sheet in ("numbers", "nums_ex"):
            if sheet not in images:
                continue
            arr = images[sheet]
            seen: dict[bytes, str] = {}
            for d in range(10):
                name = f"DIGIT_{d}"
                cell = _sub(arr, spec.sprite(sheet, name)).tobytes()
                if cell in seen:
                    p.add(f"{spec.sheet_file(sheet)}: {name} is identical to {seen[cell]}")
                seen[cell] = name
            blank = _sub(arr, spec.sprite(sheet, "DIGIT_BLANK")).tobytes()
            if blank in seen:
                p.add(f"{spec.sheet_file(sheet)}: DIGIT_BLANK is identical to {seen[blank]}")
        if "numbers" in images:
            arr = images["numbers"]
            m = _sub(arr, spec.sprite("numbers", "MINUS_SIGN"))
            nm = _sub(arr, spec.sprite("numbers", "NO_MINUS_SIGN"))
            if _same(m, nm):
                p.add("numbers.bmp: MINUS_SIGN is identical to NO_MINUS_SIGN")

        # -- font ------------------------------------------------------
        if "text" in images:
            arr = images["text"]
            space_cell = _sub(arr, spec.glyph_rect(" "))
            seen_g: dict[bytes, str] = {}
            for ch in spec.font_chars():
                r = spec.glyph_rect(ch)
                cell = _sub(arr, r)
                if ch != " " and _same(cell, space_cell):
                    p.add(f"text.bmp: glyph {ch!r} at {r} is blank")
                    continue
                key = cell.tobytes()
                if ch != " " and key in seen_g:
                    p.add(f"text.bmp: glyph {ch!r} is identical to {seen_g[key]!r}")
                seen_g[key] = ch

        # -- text files ------------------------------------------------
        if src.has("viscolor.txt"):
            raw = src.read("viscolor.txt").decode("latin-1")
            rows = []
            for line in raw.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
                s = line.strip()
                if not s or s.startswith("//") or s.startswith(";") or s.startswith("#"):
                    continue
                parts = s.replace("//", ",").split(",")
                nums = []
                for token in parts[:3]:
                    token = token.strip()
                    if not token.lstrip("+-").isdigit():
                        break
                    nums.append(int(token))
                if len(nums) == 3 and all(0 <= v <= 255 for v in nums):
                    rows.append(tuple(nums))
            if len(rows) != 24:
                p.add(f"viscolor.txt: parsed {len(rows)} colour lines, need exactly 24")
            elif "main" in images:
                viz = spec.lrect("main", "visualizer")
                px = tuple(int(v) for v in images["main"][viz.y + 1, viz.x + 1])
                if px != rows[0]:
                    p.add(f"viscolor.txt: line 0 is {rows[0]} but main.bmp at the visualizer "
                          f"rect {viz} is {px} -- they must match")
        if src.has("pledit.txt"):
            raw = src.read("pledit.txt").decode("latin-1").lower()
            for key in ("normal", "current", "normalbg", "selectedbg"):
                if f"{key}=" not in raw:
                    p.add(f"pledit.txt: missing {key}")
            if "font=" not in raw:
                p.add("pledit.txt: missing font")
        _validate_plfont(src, p, require_plfont)
    finally:
        src.close()
    return p


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    require = False
    targets = []
    for a in argv:
        if a == "--require-plfont":
            require = True
        elif a in ("-h", "--help"):
            print("usage: python3 -m skinkit.validate [--require-plfont] "
                  "<skin-dir-or-wsz> [...]")
            return 0
        else:
            targets.append(a)
    if not targets:
        print("usage: python3 -m skinkit.validate [--require-plfont] "
              "<skin-dir-or-wsz> [...]", file=sys.stderr)
        return 2
    bad = 0
    for target in targets:
        problems = validate(target, require_plfont=require)
        for msg in getattr(problems, "warnings", []):
            print(f"warn {target}: {msg}")
        if problems:
            bad = 1
            print(f"FAIL {target}  ({len(problems)} problem(s))")
            for msg in problems:
                print(f"  - {msg}")
        else:
            print(f"OK   {target}")
    return bad


if __name__ == "__main__":
    raise SystemExit(main())
