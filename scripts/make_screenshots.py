#!/usr/bin/env python3
"""Render the README's screenshots from the real app.

Uses ``Tokenamp --snapshot`` so what ends up in the README is exactly what the
app draws -- offscreen, so it needs no Screen Recording permission.

    python3 scripts/make_screenshots.py

Writes ``docs/images/hero.png`` (one skin's default layout: main, Sessions and
Token Flow stacked),
``docs/images/skins.png`` (every skin's main window, stacked),
``docs/images/flow.png`` (the Token Flow window, one configuration per skin) and
``docs/images/icon.png`` (the app icon, for the README's header).

The demo clock defaults to ``DemoUsageProvider.referenceDate`` rather than to
now, so these images are deterministic: re-running this script over unchanged
art rewrites them byte for byte.
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
#: one Token Flow configuration per skin for the gallery row -- five geometries, five palettes
FLOW = [("Bulkhead", "scope"), ("Amethyst", "web"), ("Walnut76", "orbit"),
        ("Bookcloth", "strata"), ("Base", "phase")]
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


def grid(images: list[Image.Image], per_row: int, gap: int) -> Image.Image:
    rows = [images[i:i + per_row] for i in range(0, len(images), per_row)]
    row_w = [sum(im.width for im in r) + gap * (len(r) - 1) for r in rows]
    w = max(row_w) + PAD * 2
    h = sum(max(im.height for im in r) for r in rows) + gap * (len(rows) - 1) + PAD * 2
    out = Image.new("RGB", (w, h), BG)
    y = PAD
    for r, width in zip(rows, row_w):
        x = (w - width) // 2
        for im in r:
            out.paste(im, (x, y))
            x += im.width + gap
        y += max(im.height for im in r) + gap
    return out


def export_icon(tmp: Path) -> None:
    """Pull the 512 px face out of the tracked .icns for the README header."""
    icns = ROOT / "assets" / "Tokenamp.icns"
    if not icns.is_file():
        print(f"skipping icon: no {icns}")
        return
    iconset = tmp / "icon.iconset"
    subprocess.run(["iconutil", "-c", "iconset", str(icns), "-o", str(iconset)],
                   check=True, capture_output=True)
    src = iconset / "icon_256x256@2x.png"
    Image.open(src).convert("RGBA").save(OUT / "icon.png")
    print(f"wrote {OUT / 'icon.png'}")


def main() -> None:
    if not APP.is_file():
        sys.exit(f"missing {APP} -- run: scripts/build_app.sh")
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        export_icon(tmp)
        shots = {s: snapshot(s, tmp / s) for s in SKINS}

        hero = shots[HERO]
        # The default layout the app opens with: main, Sessions, Token Flow, flush.
        stack([hero["main"], hero["playlist"], hero["field-scope"]], gap=0).save(OUT / "hero.png")
        print(f"wrote {OUT / 'hero.png'}")

        stack([shots[s]["main"] for s in SKINS], gap=PAD).save(OUT / "skins.png")
        print(f"wrote {OUT / 'skins.png'}")

        grid([shots[skin][f"field-{mode}"] for skin, mode in FLOW],
             per_row=3, gap=PAD).save(OUT / "flow.png")
        print(f"wrote {OUT / 'flow.png'}")


if __name__ == "__main__":
    main()
