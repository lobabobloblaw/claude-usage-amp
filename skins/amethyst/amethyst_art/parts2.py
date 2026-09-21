"""Bigger parts: ICs, switches, pot caps, connectors, stickers."""

from __future__ import annotations

from . import palette as P
from .parts import silk, M, G, T, E, S
from .type_small import SILK


def ic_body(p, x, y, w, h, chamfer=True):
    """Black epoxy package: matte face, lit top/left arris, dark bottom/right."""
    p.box(x, y, w, h, E[2])
    # a faint moulding sheen: the upper-left third is a step lighter
    for j in range(h):
        for i in range(w):
            if (i + j) < (w + h) * 0.38 and (i * 5 + j * 3) % 4 == 0:
                p.px(x + i, y + j, E[3])
    p.hline(x, x + w - 1, y, E[4]); p.vline(x, y, y + h - 1, E[4])
    p.hline(x, x + w - 1, y + h - 1, E[0]); p.vline(x + w - 1, y, y + h - 1, E[0])
    p.px(x, y, E[5])
    if chamfer:
        p.px(x + w - 1, y + h - 1, E[1])


def pin1(p, x, y):
    """Moulded pin-1 dimple: dark pit, light catching its lower-right wall."""
    p.px(x, y, E[0]); p.px(x + 1, y, E[0]); p.px(x, y + 1, E[0])
    p.px(x + 1, y + 1, E[4])


def qfp(p, x, y, size=17, lines=("TA", "5100"), date="2636"):
    """QFP with gull-wing leads on all four sides (pitch 2).  (x, y) = body."""
    n = (size - 1) // 2
    off = 1
    p.cast(x, y, size, size, depth=2, strength=0.5)
    for k in range(n):
        q = off + 2 * k
        # top / bottom rows of leads: shoulder (dim) then foot (bright, soldered)
        p.px(x + q, y - 1, T[3]); p.px(x + q, y - 2, T[5])
        p.px(x + q, y + size, T[3]); p.px(x + q, y + size + 1, T[4])
        p.px(x - 1, y + q, T[3]); p.px(x - 2, y + q, T[5])
        p.px(x + size, y + q, T[3]); p.px(x + size + 1, y + q, T[4])
        if k % 3 == 0:                       # solder fillets glint here and there
            p.px(x + q, y - 2, T[6]); p.px(x - 2, y + q, T[6])
    ic_body(p, x, y, size, size)
    for cx, cy in ((x, y), (x + size - 1, y), (x, y + size - 1), (x + size - 1, y + size - 1)):
        p.px(cx, cy, M[2])                                   # chamfered corners
    pin1(p, x + 2, y + size - 4)
    ty = y + 2
    for ln in lines:
        tw = sum(SILK.width(ch) for ch in ln) + len(ln) - 1
        silk(p, x + (size - tw) // 2, ty, ln, col=P.ETCH)
        ty += 6
    if date:
        # date code as a row of laser dots -- too small for numerals
        for i, ch in enumerate(date):
            if int(ch) % 2 == 0 or i == 0:
                p.px(x + size - 7 + i * 1, y + size - 3, E[4])


def soic(p, x, y, pins=4, label=None, vertical=False):
    """SOIC: leads on the two long sides, pitch 2.  (x, y) = body corner."""
    ln = pins * 2 + 1
    if not vertical:
        w, h = ln, 5
        p.cast(x, y, w, h, depth=1, strength=0.5)
        for k in range(pins):
            q = x + 1 + 2 * k
            p.px(q, y - 1, T[3]); p.px(q, y - 2, T[5])
            p.px(q, y + h, T[3]); p.px(q, y + h + 1, T[4])
    else:
        w, h = 5, ln
        p.cast(x, y, w, h, depth=1, strength=0.5)
        for k in range(pins):
            q = y + 1 + 2 * k
            p.px(x - 1, q, T[3]); p.px(x - 2, q, T[5])
            p.px(x + w, q, T[3]); p.px(x + w + 1, q, T[4])
    ic_body(p, x, y, w, h, chamfer=False)
    p.px(x + 1, y + h - 2, E[0])                             # pin-1 dot
    if label and not vertical and w >= 9:
        for i in range(2, w - 2, 2):
            p.px(x + i, y + 2, P.ETCH if (i // 2) % 3 else E[4])


def crystal(p, x, y, w=11, h=5, text=None):
    """HC-49 style can: drawn tin, rounded ends, etched frequency."""
    p.cast(x, y, w, h, depth=2, strength=0.45)
    for j in range(h):
        t = j / max(1, h - 1)
        col = P.sample(P.TIN[2:], 1.0 - t * 0.75)
        inset = 1 if j in (0, h - 1) else 0
        p.hline(x + inset, x + w - 1 - inset, y + j, col)
    p.hline(x + 2, x + w - 3, y, T[6])
    p.px(x + 2, y + 1, (255, 255, 255, 255))
    p.vline(x + w - 1, y + 1, y + h - 2, T[2])
    p.hline(x + 1, x + w - 2, y + h - 1, T[1])
    p.px(x - 1, y + h // 2, G[3]); p.px(x + w, y + h // 2, G[2])     # lands peeking out
    if text and h >= 7:
        silk(p, x + 2, y + 1, text, col=T[1])


def electrolytic(p, cx, cy):
    """SMD aluminium can from above: square base with two clipped corners,
    round can, K-shaped vent score, black polarity sector."""
    b = 6
    p.cast(cx - b, cy - b, 2 * b + 1, 2 * b + 1, depth=2, strength=0.5)
    p.box(cx - b, cy - b, 2 * b + 1, 2 * b + 1, E[2])
    p.hline(cx - b, cx + b, cy - b, E[4]); p.vline(cx - b, cy - b, cy + b, E[4])
    p.hline(cx - b, cx + b, cy + b, E[0]); p.vline(cx + b, cy - b, cy + b, E[0])
    for k in range(3):                                       # clipped corners (+ side)
        for i in range(3 - k):
            p.px(cx + b - i, cy - b + k, M[2]); p.px(cx + b - i, cy + b - k, M[2])
    r = 5
    for j in range(-r, r + 1):
        for i in range(-r, r + 1):
            d2 = i * i + j * j
            if d2 <= r * r + 2:
                t = 0.62 - (i + j) * 0.035
                if d2 >= (r - 1) * (r - 1) + 1:
                    t = 0.92 if (i + j) < -2 else 0.22 if (i + j) > 2 else 0.5
                col = P.sample(P.CAN, t)
                if i <= -2 and d2 < (r - 1) * (r - 1) + 1 and abs(j) <= 3 and i <= -3:
                    col = E[1]                               # polarity sector (negative)
                p.px(cx + i, cy + j, col)
    # K vent: a stem and two arms scored into the lid
    p.vline(cx, cy - 2, cy + 2, P.CAN[1])
    p.line(cx, cy, cx + 2, cy - 2, P.CAN[1]); p.line(cx, cy, cx + 2, cy + 2, P.CAN[1])
    p.px(cx - 1, cy - 3, (255, 255, 255, 255))
    p.px(cx - 4, cy, S[2])                                   # the "-" on the black sector


def header(p, x, y, n, vertical=False, pitch=3):
    """Male pin header: black plastic strip, square gold posts."""
    ln = n * pitch + 1
    if vertical:
        p.cast(x, y, 4, ln, depth=2, strength=0.5)
        p.box(x, y, 4, ln, E[1]); p.vline(x, y, y + ln - 1, E[3]); p.vline(x + 3, y, y + ln - 1, E[0])
        for k in range(n):
            q = y + 1 + k * pitch
            p.box(x + 1, q, 2, 2, G[3]); p.px(x + 1, q, G[5]); p.px(x + 2, q + 1, G[1])
            if pitch > 2:
                p.hline(x, x + 3, q + 2, E[0]) if k < n - 1 else None
    else:
        p.cast(x, y, ln, 4, depth=2, strength=0.5)
        p.box(x, y, ln, 4, E[1]); p.hline(x, x + ln - 1, y, E[3]); p.hline(x, x + ln - 1, y + 3, E[0])
        for k in range(n):
            q = x + 1 + k * pitch
            p.box(q, y + 1, 2, 2, G[3]); p.px(q, y + 1, G[5]); p.px(q + 1, y + 2, G[1])
            if pitch > 2 and k < n - 1:
                p.vline(q + 2, y, y + 3, E[0])


def footprint(p, x, y, n, rows=1, pitch=4):
    """Unpopulated through-hole footprint: bare plated holes, square pin 1."""
    from .parts import via
    for r_ in range(rows):
        for k in range(n):
            via(p, x + k * pitch, y + r_ * pitch)
    p.px(x - 1, y - 1, G[4]); p.px(x + 1, y - 1, G[3]); p.px(x - 1, y + 1, G[3]); p.px(x + 1, y + 1, G[1])


def sticker(p, x, y, w=17, h=7, serial=True):
    """Paper serial label: barcode and a row of printed digits (as ticks)."""
    p.cast(x, y, w, h, depth=1, strength=0.3)
    p.box(x, y, w, h, P.STICKER[1])
    p.hline(x, x + w - 1, y, P.STICKER[2]); p.hline(x, x + w - 1, y + h - 1, P.STICKER[0])
    bars = "1101001011001101011010011"
    for i in range(w - 2):
        if bars[i % len(bars)] == "1":
            p.vline(x + 1 + i, y + 1, y + h - 4, E[1])
    if serial:
        for i in range(1, w - 1):
            if (i * 7) % 5 not in (0, 3):
                p.px(x + i, y + h - 2, E[3])
    p.px(x + w - 1, y, P.STICKER[0])                         # a lifted, dog-eared corner


def trimpot(p, x, y):
    """3mm SMD trimmer: blue body, brass cross-slot rotor."""
    rows = ("BbbbbbL", "bbaAabD", "baAAAaD", "bAAsAAD", "baAsAaD", "bbasabD", "LDDDDDD")
    B = P.BLUE_POT
    p.cast(x, y, 7, 7, depth=2, strength=0.5)
    p.rows(x, y, rows, {"B": B[4], "b": B[2], "L": B[1], "D": B[0], "a": G[3], "A": G[4],
                        "s": G[0]})
    p.hline(x + 2, x + 4, y + 3, G[1]); p.px(x + 3, y + 3, G[0])
    p.px(x + 2, y + 2, G[5])


def jst(p, x, y, n=2):
    """Shrouded wire-to-board connector, cream nylon."""
    w = n * 3 + 3
    C = P.STICKER
    p.cast(x, y, w, 6, depth=2, strength=0.5)
    p.box(x, y, w, 6, C[1]); p.hline(x, x + w - 1, y, C[2]); p.vline(x, y, y + 5, C[2])
    p.hline(x, x + w - 1, y + 5, C[0]); p.vline(x + w - 1, y, y + 5, C[0])
    p.box(x + 1, y + 1, w - 2, 3, E[1])
    for k in range(n):
        p.px(x + 2 + 3 * k, y + 2, G[4]); p.px(x + 3 + 3 * k, y + 2, G[2])
    p.px(x + 1, y + 5, P.SILK[0]); p.px(x + w - 2, y + 5, P.SILK[0])
