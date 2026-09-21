#!/usr/bin/env python3
"""swatches.py -- palette ramps, board materials and the parts bin at 8x.
Step 2 of the mandatory process: look at materials before painting windows.
Writes work/swatch_ramps.png and work/swatch_parts.png."""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent)); sys.path.insert(0, str(HERE))

import numpy as np
from PIL import Image
from skinkit.canvas import Canvas
from amethyst_art import palette as P, pen, parts as K, parts2 as K2, controls as C


def save(c, name, scale=8):
    img = c.to_pil().convert("RGB")
    img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
    (HERE / "work").mkdir(exist_ok=True)
    img.save(HERE / "work" / name)


def ramps():
    names = ["MASK", "POUR", "FR4", "GOLD", "SILK", "TIN", "EPOXY", "SEG", "BEZEL", "LED_G",
             "LED_A", "LED_R", "LED_B", "CERAMIC", "TANT", "CAN", "CAP", "RED_CAP", "STICKER"]
    c = Canvas(8 * 6 + 2, len(names) * 5 + 1, fill="#000000")
    for j, n in enumerate(names):
        for i, col in enumerate(getattr(P, n)):
            c.box(1 + i * 6, 1 + j * 5, 6, 4, col)
    save(c, "swatch_ramps.png")


def board():
    c = Canvas(150, 96, origin=(0, 0), window="main")
    t = pen.mask_value(c, seed=41)
    pen.paint_mask(c, t)
    reg = np.zeros((c.h, c.w), bool)
    reg[60:92, 4:60] = True
    for k in range(6):
        reg[60 + k, 4:4 + 6 - k] = False
    pen.pour(c, t, reg)
    p = pen.Pen(c)
    K.bus(p, [(6, 6), (36, 6), (46, 16), (46, 36)], 4, side=1)
    K.via(p, 50, 10); K.via_tented(p, 56, 10); K.test_point(p, 62, 10, "TP1")
    K.fiducial(p, 84, 8); K.mount_hole(p, 100, 10)
    K.chip_r(p, 6, 24); K.chip_c(p, 14, 24); K.chip_r(p, 22, 22, horizontal=False)
    K.chip_c(p, 28, 22, horizontal=False); K.tantalum(p, 34, 24); K.diode(p, 46, 24)
    K.res_array(p, 56, 23); K.sot23(p, 68, 23); K.inductor(p, 76, 21)
    for i, (kind, lv) in enumerate((("g", 0), ("g", 0.5), ("g", 1), ("a", 0), ("a", 1),
                                    ("r", 0), ("r", 1), ("b", 0), ("b", 1))):
        K.led_smd(p, 6 + i * 9, 34, kind, lv)
    K.silk(p, 6, 42, "R12 C4 U1 D3 SW2 TOKENAMP REV C")
    K.silk(p, 6, 49, "MADE ON EARTH 0123456789 +-/.:%", worn=0.3)
    K2.qfp(p, 112, 30, 17); K2.soic(p, 90, 24, 4, label=True); K2.crystal(p, 90, 36)
    K2.electrolytic(p, 138, 12); K2.header(p, 64, 58, 8); K2.footprint(p, 64, 68, 5, rows=2)
    K2.sticker(p, 100, 60); K2.trimpot(p, 124, 58); K2.jst(p, 134, 58)
    C.tact_switch(p, 66, 78); C.tact_legs(p, 66, 78)
    C.tact_switch(p, 84, 78, pressed=True); C.tact_switch(p, 102, 78, red=True)
    C.slide_switch(p, 6, 64, 17, 9); C.slide_switch(p, 26, 64, 17, 9, on=True)
    C.slide_switch(p, 6, 78, 13, 7, pressed=True)
    for i, g in enumerate(("options", "minimize", "shade", "unshade", "close")):
        C.gold_button(p, 120 + (i % 3) * 10, 70 + (i // 3) * 10, g, pressed=(i == 4))
    C.cap(p, 6, 86, 14, 9); C.cap(p, 24, 86, 14, 9, pressed=True)
    C.cap(p, 44, 84, 11, 11, index="h")
    save(c, "swatch_parts.png")


if __name__ == "__main__":
    ramps(); board()
    print("ok")
