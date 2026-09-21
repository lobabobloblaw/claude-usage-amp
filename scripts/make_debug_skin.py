#!/usr/bin/env python3
"""Build a throwaway DEBUG skin straight from skinspec/sprites.json.

Every sprite gets its own flat colour, a 1 px contrasting border and - where it fits - a tiny
label, so a misplaced, mis-cropped or upside-down sprite is obvious the instant you look at a
render. The 28 slider frames ramp visibly, the digits and the 5x6 font are drawn with a real
pixel font so text can be *read* in a snapshot.

    python3 scripts/make_debug_skin.py [outdir]

Default outdir is .build-ui/debugskin, zipped to .build-ui/DebugSkin.wsz.
"""

from __future__ import annotations

import colorsys
import json
import os
import sys
import zipfile

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SPEC_PATH = os.path.join(ROOT, "skinspec", "sprites.json")

# ---------------------------------------------------------------------------
# A 4x5 pixel font, drawn into the 5x6 classic cells with a 1 px gutter.
# ---------------------------------------------------------------------------

GLYPHS = {
    "A": ".##.|#..#|####|#..#|#..#",
    "B": "###.|#..#|###.|#..#|###.",
    "C": ".###|#...|#...|#...|.###",
    "D": "###.|#..#|#..#|#..#|###.",
    "E": "####|#...|###.|#...|####",
    "F": "####|#...|###.|#...|#...",
    "G": ".###|#...|#.##|#..#|.###",
    "H": "#..#|#..#|####|#..#|#..#",
    "I": "####|.##.|.##.|.##.|####",
    "J": "..##|...#|...#|#..#|.##.",
    "K": "#..#|#.#.|##..|#.#.|#..#",
    "L": "#...|#...|#...|#...|####",
    "M": "#..#|####|####|#..#|#..#",
    "N": "#..#|##.#|#.##|#..#|#..#",
    "O": ".##.|#..#|#..#|#..#|.##.",
    "P": "###.|#..#|###.|#...|#...",
    "Q": ".##.|#..#|#..#|#.#.|.#.#",
    "R": "###.|#..#|###.|#.#.|#..#",
    "S": ".###|#...|.##.|...#|###.",
    "T": "####|.##.|.##.|.##.|.##.",
    "U": "#..#|#..#|#..#|#..#|.##.",
    "V": "#..#|#..#|#..#|.##.|.##.",
    "W": "#..#|#..#|####|####|#..#",
    "X": "#..#|.##.|.##.|.##.|#..#",
    "Y": "#..#|#..#|.##.|.##.|.##.",
    "Z": "####|...#|.##.|#...|####",
    "0": ".##.|#.##|##.#|#..#|.##.",
    "1": ".#..|##..|.#..|.#..|###.",
    "2": ".##.|#..#|..#.|.#..|####",
    "3": "###.|...#|.##.|...#|###.",
    "4": "#..#|#..#|####|...#|...#",
    "5": "####|#...|###.|...#|###.",
    "6": ".##.|#...|###.|#..#|.##.",
    "7": "####|...#|..#.|.#..|.#..",
    "8": ".##.|#..#|.##.|#..#|.##.",
    "9": ".##.|#..#|.###|...#|.##.",
    '"': "#.#.|#.#.|....|....|....",
    "@": ".##.|#..#|#.##|#...|.##.",
    "…": "....|....|....|....|#.#.",
    ".": "....|....|....|....|.#..",
    ":": "....|.#..|....|.#..|....",
    "(": "..#.|.#..|.#..|.#..|..#.",
    ")": ".#..|..#.|..#.|..#.|.#..",
    "-": "....|....|###.|....|....",
    "'": ".#..|.#..|....|....|....",
    "!": ".#..|.#..|.#..|....|.#..",
    "_": "....|....|....|....|####",
    "+": "....|.#..|###.|.#..|....",
    "\\": "#...|#...|.#..|..#.|..#.",
    "/": "..#.|..#.|.#..|#...|#...",
    "[": ".##.|.#..|.#..|.#..|.##.",
    "]": ".##.|..#.|..#.|..#.|.##.",
    "^": ".#..|#.#.|....|....|....",
    "&": ".#..|#.#.|.#..|#.#.|.###",
    "%": "#..#|...#|..#.|.#..|#..#",
    ",": "....|....|....|.#..|#...",
    "=": "....|###.|....|###.|....",
    "$": ".###|##..|.##.|..##|###.",
    "#": "#.#.|####|#.#.|####|#.#.",
    "?": "###.|...#|.##.|....|.#..",
    "*": "#.#.|.#..|#.#.|....|....",
    "Å": ".##.|#..#|####|#..#|#..#",
    "Ö": ".##.|#..#|#..#|#..#|.##.",
    "Ä": ".##.|#..#|####|#..#|#..#",
    " ": "....|....|....|....|....",
}

GLYPH_W, GLYPH_H = 4, 5


def draw_glyph(img, ch, x, y, colour, scale=1):
    pattern = GLYPHS.get(ch.upper())
    if pattern is None:
        return
    px = img.load()
    for row, line in enumerate(pattern.split("|")):
        for col, cell in enumerate(line):
            if cell != "#":
                continue
            for dy in range(scale):
                for dx in range(scale):
                    xx, yy = x + col * scale + dx, y + row * scale + dy
                    if 0 <= xx < img.width and 0 <= yy < img.height:
                        px[xx, yy] = colour


def draw_text(img, s, x, y, colour, scale=1, limit=None):
    cx = x
    for i, ch in enumerate(s):
        if limit is not None and i >= limit:
            break
        draw_glyph(img, ch, cx, y, colour, scale)
        cx += (GLYPH_W + 1) * scale
    return cx


# ---------------------------------------------------------------------------

def sprite_colour(name, i):
    h = (hash(name) % 997) / 997.0
    h = (h + i * 0.137) % 1.0
    s = 0.55 + 0.35 * ((i * 7) % 5) / 4.0
    v = 0.45 + 0.45 * ((i * 3) % 4) / 3.0
    r, g, b = colorsys.hsv_to_rgb(h, s, v)
    return (int(r * 255), int(g * 255), int(b * 255))


def contrast(c):
    lum = 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]
    return (0, 0, 0) if lum > 140 else (255, 255, 255)


def short_label(name):
    t = name
    for p in ("MAIN_", "EQ_", "PLAYLIST_", "DIGIT_"):
        if t.startswith(p):
            t = t[len(p):]
    parts = [w for w in t.split("_") if w]
    if not parts:
        return ""
    if len(parts) == 1:
        return parts[0][:6]
    return "".join(w[0] for w in parts)[:6]


def fill_sprite(img, rect, name, index, label=True):
    x, y, w, h = rect
    col = sprite_colour(name, index)
    edge = contrast(col)
    d = ImageDraw.Draw(img)
    d.rectangle([x, y, x + w - 1, y + h - 1], fill=col, outline=edge)
    if label and w >= 7 and h >= 7:
        text = short_label(name)
        maxchars = max(0, (w - 2) // (GLYPH_W + 1))
        draw_text(img, text, x + 1, y + 1, edge, 1, limit=maxchars)
    return col, edge


# ---------------------------------------------------------------------------
# Per-sheet painters
# ---------------------------------------------------------------------------

def paint_main_window(img, layout):
    """main.bmp is the whole chassis: every baked-in element lives here."""
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, img.width - 1, img.height - 1], fill=(46, 52, 64), outline=(120, 132, 150))
    L = layout["main"]

    # Dark wells where dynamic content is drawn, so overdraw is obvious.
    for key in ("visualizer", "marquee", "posbar", "volume", "balance", "kbps", "khz"):
        x, y, w, h = L[key]
        d.rectangle([x, y, x + w - 1, y + h - 1], fill=(14, 16, 20), outline=(90, 200, 255))
    for r in L["digits"]:
        x, y, w, h = r
        d.rectangle([x, y, x + w - 1, y + h - 1], fill=(10, 12, 16), outline=(70, 90, 110))

    # Clutter bar: the normal state is baked into main.bmp on real skins too.
    x, y, w, h = L["clutterBar"]
    d.rectangle([x, y, x + w - 1, y + h - 1], fill=(30, 34, 42), outline=(150, 160, 180))
    for letter, r in L["clutterButtons"].items():
        draw_glyph(img, letter, r[0] + 2, r[1] + 1, (170, 200, 230))

    # Captions in the free space, per SPEC 5.1.
    draw_text(img, "K/MIN", 129, 43, (120, 230, 200))
    draw_text(img, "ACTIVE", 169, 43, (120, 230, 200))
    draw_text(img, "SESSION", 108, 51, (90, 160, 200))
    draw_text(img, "WEEK", 178, 51, (90, 160, 200))
    draw_text(img, "TOKENAMP DEBUG", 150, 108, (200, 200, 90))

    # Outline the remaining widget slots so placement errors jump out.
    slots = ["mono", "stereo", "eqButton", "plButton", "previous", "play", "pause", "stop",
             "next", "eject", "shuffle", "repeat", "aboutLogo", "playPauseIndicator", "workIndicator"]
    for i, key in enumerate(slots):
        x, y, w, h = L[key]
        d.rectangle([x, y, x + w - 1, y + h - 1], outline=sprite_colour(key, i))


def paint_titlebar(img, sheets, layout):
    sprites = sheets["titlebar"]["sprites"]
    for i, (name, rect) in enumerate(sprites.items()):
        if name.startswith("MAIN_CLUTTER_BAR"):
            continue
        col, edge = fill_sprite(img, rect, name, i, label=False)
        x, y, w, h = rect
        if w >= 200:
            label = "TOKENAMP " + ("SEL" if "SELECTED" in name else "")
            if "SHADE" in name:
                label = "SHADE " + ("SEL" if "SELECTED" in name else "")
            if "EASTER" in name:
                label = "EGG"
            draw_text(img, label, x + 100, y + 4, edge)
            # left/right markers prove the sprite is not mirrored
            draw_text(img, "L", x + 2, y + 4, edge)
            draw_text(img, "R", x + w - 7, y + 4, edge)
        else:
            draw_text(img, short_label(name), x + 1, y + 1, edge, limit=max(0, (w - 2) // 5))

    # Clutter bar columns: 304 = normal, 312 = disabled, 316.. = one pressed letter per column.
    d = ImageDraw.Draw(img)
    letters = ["O", "A", "I", "D", "V"]
    for col in range(7):
        x = 304 + col * 8
        y = 0 if col < 2 else 44
        base = (30, 34, 42) if col != 1 else (60, 60, 60)
        d.rectangle([x, y, x + 7, y + 42], fill=base, outline=(150, 160, 180))
        for i, letter in enumerate(letters):
            pressed = col >= 2 and (col - 2) == i
            ly = y + 3 + i * 8
            if pressed:
                d.rectangle([x + 1, ly, x + 6, ly + 6], fill=(255, 190, 60))
            draw_glyph(img, letter, x + 2, ly + 1, (20, 20, 20) if pressed else (170, 200, 230))


def paint_frames(img, sheet, sheet_name):
    frames = sheet["frames"]
    count = frames["count"]
    x0 = frames.get("x0", frames.get("x", 0))
    y0 = frames.get("y0", frames.get("y", 0))
    sx = frames.get("strideX", 0)
    sy = frames.get("strideY", 0)
    per_row = frames.get("perRow", 1)
    w, h = frames["w"], frames["h"]
    d = ImageDraw.Draw(img)
    for i in range(count):
        col = i % per_row
        row = i // per_row
        x = x0 + sx * col
        y = y0 + sy * row
        t = i / float(count - 1)
        # green -> red heat ramp, plus a bar whose length/height encodes the frame index
        base = (int(40 + 200 * t), int(220 - 170 * t), 60)
        d.rectangle([x, y, x + w - 1, y + h - 1], fill=(12, 14, 18), outline=(90, 90, 110))
        if h > w:                      # EQ slider well: fill from the bottom
            fh = max(1, int((h - 4) * t))
            d.rectangle([x + 4, y + h - 2 - fh, x + w - 5, y + h - 3], fill=base)
        else:                          # volume/balance: fill from the left
            fw = max(1, int((w - 4) * t))
            d.rectangle([x + 2, y + 4, x + 2 + fw, y + h - 5], fill=base)
        draw_text(img, "%d" % i, x + 1, y + 1, (255, 255, 255), limit=2)


def paint_digits(img, sheet, sheet_name):
    d = ImageDraw.Draw(img)
    for i, (name, rect) in enumerate(sheet["sprites"].items()):
        x, y, w, h = rect
        if w < 5 or h < 5:
            # the legacy 5x1 minus strips
            d.rectangle([x, y, x + w - 1, y + h - 1],
                        fill=(255, 80, 80) if name == "MINUS_SIGN" else (20, 20, 20))
            continue
        d.rectangle([x, y, x + w - 1, y + h - 1], fill=(8, 10, 14), outline=(60, 70, 90))
        ch = None
        if name.startswith("DIGIT_") and name[6:].isdigit():
            ch = name[6:]
        elif name.endswith("MINUS"):
            ch = "-"
        if ch:
            draw_glyph(img, ch, x + 1, y + 2, (120, 255, 180), scale=2)


def paint_font(img, spec):
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, img.width - 1, img.height - 1], fill=(6, 8, 10))
    font = spec["font"]
    gw, gh = font["glyphWidth"], font["glyphHeight"]
    for r, row in enumerate(font["rows"]):
        for c, ch in enumerate(row):
            if c >= font["columns"]:
                break
            draw_glyph(img, ch, c * gw, r * gh, (150, 255, 210))


def paint_eq(img, sheets, layout):
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, 274, 115], fill=(40, 46, 60), outline=(120, 140, 170))
    L = layout["eq"]
    for key in ("graph", "preampSlider"):
        x, y, w, h = L[key]
        d.rectangle([x, y, x + w - 1, y + h - 1], fill=(10, 12, 16), outline=(90, 200, 255))
    B = L["bandSliders"]
    for i in range(B["count"]):
        x = B["x0"] + i * B["strideX"]
        d.rectangle([x, B["y"], x + B["w"] - 1, B["y"] + B["h"] - 1], fill=(10, 12, 16), outline=(70, 90, 110))
        draw_text(img, "NOW" if i == 9 else "-%d" % (9 - i), x, 104, (140, 200, 240))
    draw_text(img, "WEEK", 16, 104, (140, 200, 240))
    draw_text(img, "EQ DEBUG", 100, 104, (200, 200, 90))

    for i, (name, rect) in enumerate(sheets["eqmain"]["sprites"].items()):
        if name == "EQ_WINDOW_BACKGROUND":
            continue
        if name == "EQ_GRAPH_LINE_COLORS":
            x, y, w, h = rect
            for row in range(h):
                t = row / float(max(1, h - 1))
                d.rectangle([x, y + row, x + w - 1, y + row],
                            fill=(int(60 + 195 * t), int(255 - 120 * t), int(200 - 150 * t)))
            continue
        if name == "EQ_PREAMP_LINE":
            x, y, w, h = rect
            d.rectangle([x, y, x + w - 1, y + h - 1], fill=(255, 210, 60))
            continue
        col, edge = fill_sprite(img, rect, name, i, label=False)
        x, y, w, h = rect
        text = {"EQ_ON_BUTTON": "ON", "EQ_AUTO_BUTTON": "AUTO", "EQ_PRESETS_BUTTON": "RANGE"}.get(
            name.replace("_SELECTED", "").replace("_DEPRESSED", ""), short_label(name))
        draw_text(img, text, x + 2, y + 2, edge, limit=max(0, (w - 3) // 5))
        if w >= 200:
            draw_text(img, "USAGE EQUALIZER", x + 90, y + 4, edge)

    paint_frames(img, sheets["eqmain"], "eqmain")


def paint_pledit(img, sheets):
    for i, (name, rect) in enumerate(sheets["pledit"]["sprites"].items()):
        col, edge = fill_sprite(img, rect, name, i, label=False)
        x, y, w, h = rect
        if "TITLE_BAR" in name:
            draw_text(img, "SESSIONS", x + 25, y + 6, edge)
        elif w >= 30:
            draw_text(img, short_label(name), x + 2, y + 2, edge, limit=max(0, (w - 3) // 5))
        else:
            draw_text(img, short_label(name)[:2], x + 1, y + 1, edge, limit=max(0, (w - 2) // 5))
        # Corner/tile pieces get an L-marker so tiling seams and mirroring are visible.
        if "TILE" in name or "CORNER" in name:
            d = ImageDraw.Draw(img)
            d.line([x, y, x, y + h - 1], fill=edge)
            d.line([x, y, x + w - 1, y], fill=edge)


def paint_generic(img, sheet, sheet_name):
    sprites = sheet.get("sprites") or {}
    for i, (name, rect) in enumerate(sprites.items()):
        fill_sprite(img, rect, name, i)


# ---------------------------------------------------------------------------

VISCOLOR = """\
0,0,0            // 0 viz background
24,33,41         // 1 background dots
255,255,255      // 2 bars, top
255,214,120
255,176,60
255,140,40
250,110,40
235,86,40
215,70,55
190,60,70
160,55,95
130,55,125
100,60,155
70,70,185
45,90,205
30,120,220
20,150,235
10,180,245      // 17 bars, bottom
120,255,180     // 18 scope centre
90,225,160
60,195,140
40,160,120
25,130,100      // 22 scope edge
255,60,60       // 23 peak caps
"""

PLEDIT = """\
[Text]
Normal=#7FE8C8
Current=#FFE066
NormalBG=#0A0D12
SelectedBG=#1C4A6E
Font=Helvetica
"""

README = """Tokenamp DEBUG skin - generated by scripts/make_debug_skin.py.
Every sprite is a distinct flat colour with a 1 px contrasting border and a tiny label,
so anything misplaced, mis-cropped or drawn upside down is immediately visible.
"""


def build(outdir):
    with open(SPEC_PATH, "r", encoding="utf-8") as fh:
        spec = json.load(fh)
    sheets = spec["sheets"]
    layout = spec["layout"]
    os.makedirs(outdir, exist_ok=True)

    written = []
    for name, sheet in sheets.items():
        img = Image.new("RGB", (sheet["width"], sheet["height"]), (24, 26, 32))
        if name == "main":
            paint_main_window(img, layout)
        elif name == "titlebar":
            paint_titlebar(img, sheets, layout)
        elif name in ("volume", "balance"):
            paint_generic(img, sheet, name)
            paint_frames(img, sheet, name)
            # thumbs sit below the frame strip; redraw them on top
            for i, (sname, rect) in enumerate((sheet.get("sprites") or {}).items()):
                fill_sprite(img, rect, sname, i)
        elif name in ("numbers", "nums_ex"):
            paint_digits(img, sheet, name)
        elif name == "text":
            paint_font(img, spec)
        elif name == "eqmain":
            paint_eq(img, sheets, layout)
        elif name == "pledit":
            paint_pledit(img, sheets)
        else:
            paint_generic(img, sheet, name)
        path = os.path.join(outdir, sheet["file"])
        img.save(path, "BMP")
        written.append(sheet["file"])

    for fname, body in (("viscolor.txt", VISCOLOR), ("pledit.txt", PLEDIT), ("readme.txt", README)):
        with open(os.path.join(outdir, fname), "w", encoding="utf-8") as fh:
            fh.write(body)
        written.append(fname)
    return written


def zip_skin(outdir, zip_path):
    if os.path.exists(zip_path):
        os.remove(zip_path)
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        for name in sorted(os.listdir(outdir)):
            z.write(os.path.join(outdir, name), name)
    return zip_path


def main(argv):
    outdir = argv[1] if len(argv) > 1 else os.path.join(ROOT, ".build-ui", "debugskin")
    written = build(outdir)
    zip_path = os.path.join(os.path.dirname(outdir), "DebugSkin.wsz")
    zip_skin(outdir, zip_path)
    print("wrote %d files to %s" % (len(written), outdir))
    print("zipped -> %s" % zip_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
