#!/usr/bin/env python3
"""Assemble the Token Flow frame from out/gen.bmp exactly the way FieldRenderer
does, so the tiling (and every seam) can be inspected without building the app.

    python3 skins/amethyst/field_mock.py [W H] [--scale 3] [--auto]
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
SPEC = json.loads((ROOT / "skinspec" / "sprites.json").read_text())
GEN = SPEC["sheets"]["gen"]["sprites"]
F = SPEC["layout"]["field"]
FONT = SPEC["font"]

sheet = Image.open(HERE / "out" / "gen.bmp").convert("RGB")
text_sheet = Image.open(HERE / "out" / "text.bmp").convert("RGB")
VIS = [tuple(int(v) for v in ln.split("//")[0].strip().rstrip(",").split(",")[:3])
       for ln in (HERE / "out" / "viscolor.txt").read_text().splitlines() if ln.strip()]


def spr(name):
    x, y, w, h = GEN[name]
    return sheet.crop((x, y, x + w, y + h))


def glyph(ch):
    ch = ch.upper()
    for r, row in enumerate(FONT["rows"]):
        c = row.find(ch)
        if c >= 0:
            break
    else:
        r, c = FONT["space"][0], FONT["space"][1]
    gw, gh = FONT["glyphWidth"], FONT["glyphHeight"]
    return text_sheet.crop((c * gw, r * gh, c * gw + gw, r * gh + gh))


def text(img, s, x, y):
    for ch in s:
        img.paste(glyph(ch), (x, y))
        x += FONT["glyphWidth"]
    return x


def build(w, h, auto=False):
    img = Image.new("RGB", (w, h), (0, 0, 0))
    top, bot = spr("GEN_TOP_TILE"), spr("GEN_BOTTOM_TILE")
    by = h - F["bottomHeight"]
    for x in range(0, w, top.width):
        img.paste(top, (x, 0))
    for x in range(0, w, bot.width):
        img.paste(bot, (x, by))
    img.paste(spr("GEN_TOP_LEFT"), (0, 0))
    img.paste(spr("GEN_TOP_RIGHT"), (w - 12, 0))
    plate = spr("GEN_TITLE_PLATE")
    img.paste(plate, ((w - plate.width) // 2, 0))
    left, right = spr("GEN_LEFT_TILE"), spr("GEN_RIGHT_TILE")
    for y in range(F["titleHeight"], by, left.height):
        img.paste(left.crop((0, 0, left.width, min(left.height, by - y))), (0, y))
        img.paste(right.crop((0, 0, right.width, min(right.height, by - y))), (w - 12, y))
    img.paste(spr("GEN_BOTTOM_LEFT"), (0, by))
    img.paste(spr("GEN_BOTTOM_RIGHT"), (w - 12, by))

    # the well, the way PhosphorField paints an empty field
    wx, wy = F["leftWidth"], F["titleHeight"]
    ww, wh = w - F["leftWidth"] - F["rightWidth"], h - F["titleHeight"] - F["bottomHeight"]
    px = img.load()
    for j in range(wh):
        for i in range(ww):
            px[wx + i, wy + j] = VIS[1] if (i % 4 == 2 and j % 4 == 2) else VIS[0]

    title = "TOKEN FLOW - AUTO" if auto else "TOKEN FLOW"
    text(img, title, (w - len(title) * 5) // 2, F["titleTextY"])
    img.paste(spr("GEN_CLOSE"), (w + F["closeButtonFromTopRight"][0], F["closeButtonFromTopRight"][1]))
    img.paste(spr("GEN_LAMP_ON" if auto else "GEN_LAMP_OFF"),
              (w + F["lampFromTopRight"][0], F["lampFromTopRight"][1]))
    left_s = "STRATA 24H"
    right_s = "19.8K/MIN  78%"
    text(img, left_s, F["readoutFromBottomLeft"][0], h + F["readoutFromBottomLeft"][1])
    text(img, right_s, w + F["valueFromBottomRight"][0] - len(right_s) * 5,
         h + F["valueFromBottomRight"][1])
    return img


def main(argv):
    scale = 3
    auto = "--auto" in argv
    argv = [a for a in argv if not a.startswith("--")]
    if "--scale" in sys.argv:
        scale = int(sys.argv[sys.argv.index("--scale") + 1])
    w, h = (int(argv[0]), int(argv[1])) if len(argv) >= 2 else (275, 232)
    img = build(w, h, auto)
    out = HERE / "work" / f"field_{w}x{h}{'_auto' if auto else ''}_{scale}x.png"
    img.resize((w * scale, h * scale), Image.NEAREST).save(out)
    print(out)


if __name__ == "__main__":
    main(sys.argv[1:])
