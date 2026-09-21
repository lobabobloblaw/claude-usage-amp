#!/usr/bin/env python3
"""crop.py -- save an 8x nearest-neighbour crop of any rect of any preview
window or built sheet.

    python3 skins/amethyst/crop.py main 100 14 175 45 [--scale 8] [--name lcd]
    python3 skins/amethyst/crop.py sheet:volume 0 0 68 433
    python3 skins/amethyst/crop.py eq 0 0 275 116 --scale 4

Sources: main / eq / playlist / shade / all (preview/*.png at 1x) or
sheet:<name> (out/<name>.bmp).  Output: work/crop_<name>.png
"""
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent


def main(argv):
    scale, name = 8, None
    args = []
    it = iter(argv)
    for a in it:
        if a == "--scale":
            scale = int(next(it))
        elif a == "--name":
            name = next(it)
        else:
            args.append(a)
    src = args[0]
    if src.startswith("sheet:"):
        path = HERE / "out" / (src[6:] + ".bmp")
    else:
        path = HERE / "preview" / (src + ".png")
    img = Image.open(path).convert("RGB")
    if len(args) >= 5:
        x, y, w, h = (int(v) for v in args[1:5])
    else:
        x, y, w, h = 0, 0, img.width, img.height
    box = (max(0, x), max(0, y), min(img.width, x + w), min(img.height, y + h))
    out = img.crop(box)
    out = out.resize((out.width * scale, out.height * scale), Image.NEAREST)
    (HERE / "work").mkdir(exist_ok=True)
    dst = HERE / "work" / f"crop_{name or src.replace(':', '_')}.png"
    out.save(dst)
    print(dst, out.size)


if __name__ == "__main__":
    main(sys.argv[1:])
