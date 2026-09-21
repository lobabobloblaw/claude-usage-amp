#!/usr/bin/env python3
"""Render the README's screenshots from the real app.

Uses ``Tokenamp --snapshot`` so what ends up in the README is exactly what the
app draws -- offscreen, so it needs no Screen Recording permission.

    python3 scripts/make_screenshots.py

Writes ``docs/images/hero.png`` (one skin's full window stack) and
``docs/images/skins.png`` (every skin's main window, stacked).

The demo provider's clock moves, so the countdown differs between runs; that
is cosmetic, and the images are only regenerated on purpose.
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "images"
APP = ROOT / "build" / "Tokenamp.app" / "Contents" / "MacOS" / "Tokenamp"

#: order the skins appear in the gallery
SKINS = ["Bulkhead", "Walnut76", "Amethyst", "Bookcloth", "Base"]
HERO = "Bulkhead"
SCALE = 2
PAD = 16
BG = (22, 22, 24)


def snapshot(skin: str, into: Path) -> dict[str, Image.Image]:
    into.mkdir(parents=True, exist_ok=True)
    wsz = ROOT / "skins" / "dist" / f"{skin}.wsz"
    if not wsz.is_file():
        sys.exit(f"missing {wsz} -- run: python3 skins/build.py --all")
    subprocess.run([str(APP), "--snapshot", str(into), "--demo",
                    "--skin", str(wsz), "--scale", str(SCALE)],
                   check=True, capture_output=True)
    return {p.stem: Image.open(p).convert("RGB") for p in into.glob("*.png")}


def stack(images: list[Image.Image], gap: int) -> Image.Image:
    w = max(im.width for im in images) + PAD * 2
    h = sum(im.height for im in images) + gap * (len(images) - 1) + PAD * 2
    out = Image.new("RGB", (w, h), BG)
    y = PAD
    for im in images:
        out.paste(im, ((w - im.width) // 2, y))
        y += im.height + gap
    return out


def main() -> None:
    if not APP.is_file():
        sys.exit(f"missing {APP} -- run: scripts/build_app.sh")
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        shots = {s: snapshot(s, tmp / s) for s in SKINS}

        hero = shots[HERO]
        stack([hero["main"], hero["eq"], hero["playlist"]], gap=0).save(OUT / "hero.png")
        print(f"wrote {OUT / 'hero.png'}")

        stack([shots[s]["main"] for s in SKINS], gap=PAD).save(OUT / "skins.png")
        print(f"wrote {OUT / 'skins.png'}")


if __name__ == "__main__":
    main()
