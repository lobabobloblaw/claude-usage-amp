#!/usr/bin/env python3
"""Type specimen for the Bookcloth faces, straight from the glyph data.

    python3 skins/bookcloth/specimen.py     -> crops/specimen_list_6x.png etc.
"""
from __future__ import annotations
import sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE)); sys.path.insert(0, str(HERE.parent))
import numpy as np
from PIL import Image
from bookcloth_art import type_list as TL, palette as P

LINES = [
    "1. code/tokenamp - FABLE 5.1      $12.40",
    "2. tokenamp-ui/Sources/TokenampKit/SkinRenderer.swift",
    "6. scratch: quagga glyph jumping - SONNET 5  $1.08",
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ &?!",
    "abcdefghijklmnopqrstuvwxyz",
    "0123456789 $39.63 1.2M 42% (#7) [x] {y} <z> a_b",
    "The quick brown fox jumps over the lazy dog; \"Why?\"",
    "Illegal 1lI| O0o S5 Z2 B8 ce ao uv gq rn m ~^`'*+=@\\ …",
]

def set_line(text, spacing=1, space=3):
    w = 400
    cov = np.zeros((TL.CELL_H, w), dtype=np.float32)
    pen = 2
    for ch in text:
        c = TL.cell(ch)
        cols = np.nonzero((c >= 0.5).any(axis=0))[0]
        if cols.size == 0:
            pen += space; continue
        lo, hi = int(cols[0]), int(cols[-1])
        s0, s1 = max(0, lo - 1), min(TL.CELL_W - 1, hi + 1)
        dx = (pen - 1) + (s0 - (lo - 1))
        seg = c[:, s0:s1 + 1]
        cov[:, dx:dx + seg.shape[1]] = 1 - (1 - cov[:, dx:dx + seg.shape[1]]) * (1 - seg)
        pen += hi - lo + 1 + spacing
    return cov[:, :pen + 2]

def main():
    rows = [set_line(t) for t in LINES]
    W = max(r.shape[1] for r in rows); rh = 13
    cov = np.zeros((rh * len(rows) + 2, W), dtype=np.float32)
    for i, r in enumerate(rows):
        cov[1 + i * rh:1 + i * rh + TL.CELL_H, :r.shape[1]] = r
    bg, ink = P.rgb(P.PAPER_FLAT), P.rgb(P.INK_BODY)
    img = bg[None, None, :] + (ink - bg)[None, None, :] * cov[..., None]
    im = Image.fromarray(np.clip(np.rint(img), 0, 255).astype(np.uint8))
    out = HERE / "crops"; out.mkdir(exist_ok=True)
    k = int(sys.argv[1]) if len(sys.argv) > 1 else 5
    im.resize((im.width * k, im.height * k), Image.Resampling.NEAREST).save(out / "specimen_list.png")
    im.resize((im.width * 2, im.height * 2), Image.Resampling.NEAREST).save(out / "specimen_list_2x.png")
    print(im.size)

if __name__ == "__main__":
    main()
