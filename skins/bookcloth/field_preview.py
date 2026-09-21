#!/usr/bin/env python3
"""Mock the Token Flow window from out/gen.bmp, exactly the way FieldRenderer
assembles it, so the frame can be judged (and its tiling checked) without
building the app.

    python3 skins/bookcloth/field_preview.py [scale] [w h] ...
"""
from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import numpy as np                                            # noqa: E402
from PIL import Image                                         # noqa: E402

from skinkit import spec                                      # noqa: E402

OUT = HERE / "out"
CROPS = HERE / "crops"


def sheet(name: str) -> np.ndarray:
    return np.array(Image.open(OUT / spec.sheet_file(name)).convert("RGB"))


def spr(sh: np.ndarray, sheet_name: str, sprite: str) -> np.ndarray:
    r = spec.sprite(sheet_name, sprite)
    return sh[r.y:r.y + r.h, r.x:r.x + r.w]


def blit(dst: np.ndarray, src: np.ndarray, x: int, y: int) -> None:
    h, w = src.shape[:2]
    x0, y0 = max(0, x), max(0, y)
    x1, y1 = min(dst.shape[1], x + w), min(dst.shape[0], y + h)
    if x1 <= x0 or y1 <= y0:
        return
    dst[y0:y1, x0:x1] = src[y0 - y:y1 - y, x0 - x:x1 - x]


def text(dst: np.ndarray, tx: np.ndarray, s: str, x: int, y: int) -> None:
    for ch in s.upper():
        try:
            r = spec.glyph_rect(ch)
        except Exception:
            r = spec.glyph_rect(" ")
        blit(dst, tx[r.y:r.y + r.h, r.x:r.x + r.w], x, y)
        x += 5


def text_w(s: str) -> int:
    return 5 * len(s)


def window(w: int, h: int, auto: bool, left: str, right: str) -> np.ndarray:
    g, tx = sheet("gen"), sheet("text")
    F = spec.layout("field")
    top_h, bot_h = int(F["titleHeight"]), int(F["bottomHeight"])
    dst = np.zeros((h, w, 3), dtype=np.uint8)

    # the field well: viscolor 0 with the dot grid, so the frame is judged
    # against what the app actually puts there
    vis = [ln.split("//")[0].strip() for ln in (OUT / "viscolor.txt").read_text().splitlines()]
    vis = [tuple(int(v) for v in ln.split(",")[:3]) for ln in vis if ln]
    dst[:, :] = vis[0]
    well_x, well_y = int(F["leftWidth"]), top_h
    ww = w - well_x - int(F["rightWidth"])
    wh = h - top_h - bot_h
    for yy in range(2, wh, 4):
        for xx in range(2, ww, 4):
            dst[well_y + yy, well_x + xx] = vis[1]

    top = spr(g, "gen", "GEN_TOP_TILE")
    for x in range(0, w, top.shape[1]):
        blit(dst, top, x, 0)
    blit(dst, spr(g, "gen", "GEN_TOP_LEFT"), 0, 0)
    blit(dst, spr(g, "gen", "GEN_TOP_RIGHT"), w - 12, 0)
    plate = spr(g, "gen", "GEN_TITLE_PLATE")
    blit(dst, plate, (w - plate.shape[1]) // 2, 0)

    lt, rt = spr(g, "gen", "GEN_LEFT_TILE"), spr(g, "gen", "GEN_RIGHT_TILE")
    for y in range(top_h, h - bot_h, lt.shape[0]):
        blit(dst, lt, 0, y)
        blit(dst, rt, w - 12, y)

    bot = spr(g, "gen", "GEN_BOTTOM_TILE")
    for x in range(0, w, bot.shape[1]):
        blit(dst, bot, x, h - bot_h)
    blit(dst, spr(g, "gen", "GEN_BOTTOM_LEFT"), 0, h - bot_h)
    blit(dst, spr(g, "gen", "GEN_BOTTOM_RIGHT"), w - 12, h - bot_h)

    close = [int(v) for v in F["closeButtonFromTopRight"]]
    lamp = [int(v) for v in F["lampFromTopRight"]]
    blit(dst, spr(g, "gen", "GEN_CLOSE"), w + close[0], close[1])
    blit(dst, spr(g, "gen", "GEN_LAMP_ON" if auto else "GEN_LAMP_OFF"),
         w + lamp[0], lamp[1])

    title = "TOKEN FLOW - AUTO" if auto else "TOKEN FLOW"
    text(dst, tx, title, (w - text_w(title)) // 2, int(F["titleTextY"]))
    ro = [int(v) for v in F["readoutFromBottomLeft"]]
    va = [int(v) for v in F["valueFromBottomRight"]]
    text(dst, tx, left, ro[0], h + ro[1])
    text(dst, tx, right, w + va[0] - text_w(right), h + va[1])
    return dst


def main() -> None:
    k = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    CROPS.mkdir(exist_ok=True)
    shots = [("field", 275, 232, True, "STRATA 24H", "19.8K/MIN  78%"),
             ("field_wide", 375, 290, False, "SCOPE", "1.2K/MIN  9%"),
             ("field_min", 225, 145, True, "WEAVE 7D", "402/MIN  100%")]
    for name, w, h, auto, left, right in shots:
        im = Image.fromarray(window(w, h, auto, left, right))
        im.resize((im.width * k, im.height * k), Image.Resampling.NEAREST).save(
            CROPS / f"{name}_{k}x.png")
        print(f"{name}: {w}x{h} -> {CROPS / f'{name}_{k}x.png'}")


if __name__ == "__main__":
    main()
