#!/usr/bin/env python3
"""Crop the assembled Token Flow mock: field_crop.py x y w h [--scale 8] [--auto] [--size W H]"""
import sys
from pathlib import Path
from PIL import Image
sys.path.insert(0, str(Path(__file__).resolve().parent))
import field_mock

def main(a):
    scale, auto, size = 8, False, (275, 232)
    args = []
    it = iter(a)
    for t in it:
        if t == "--scale": scale = int(next(it))
        elif t == "--auto": auto = True
        elif t == "--size": size = (int(next(it)), int(next(it)))
        else: args.append(t)
    x, y, w, h = (int(v) for v in args[:4])
    img = field_mock.build(*size, auto=auto)
    c = img.crop((x, y, x + w, y + h)).resize((w * scale, h * scale), Image.NEAREST)
    dst = Path(__file__).resolve().parent / "work" / f"fc_{x}_{y}.png"
    c.save(dst); print(dst, c.size)

main(sys.argv[1:])
