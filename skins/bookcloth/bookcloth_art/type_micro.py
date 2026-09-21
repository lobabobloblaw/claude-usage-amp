"""type_micro -- "Bookcloth Petite", five-row small capitals for baked captions.

Variable width (3 px for most letters, 4-5 for M N W), set with generous
letter-spacing the way small caps are in a running head.  The I carries slabs,
everything else is as plain as five rows demand; the character comes from how
it is printed (letterpress deboss, foil, blind stamp -- see typeset.py).

Legend:  ``#`` ink   ``+`` soft ink   ``.`` paper.
"""

from __future__ import annotations

GLYPHS: dict[str, tuple[str, ...]] = {}


def _g(ch: str, rows: str) -> None:
    r = tuple(rows.split())
    w = max(len(x) for x in r)
    r = tuple(x.ljust(w, ".") for x in r)
    assert len(r) == 5, ch
    GLYPHS[ch] = r


_g("A", ".#. #.# #.# ### #.#")
_g("B", "##. #.# ##. #.# ##.")
_g("C", ".## #.. #.. #.. .##")
_g("D", "##. #.# #.# #.# ##.")
_g("E", "### #.. ##. #.. ###")
_g("F", "### #.. ##. #.. #..")
_g("G", ".## #.. #.# #.# .##")
_g("H", "#.# #.# ### #.# #.#")
_g("I", "### .#. .#. .#. ###")
_g("J", ".## ..# ..# #.# .#.")
_g("K", "#.# #.# ##. #.# #.#")
_g("L", "#.. #.. #.. #.. ###")
_g("M", "#...# ##.## #.#.# #...# #...#")
_g("N", "#..# ##.# #.## #..# #..#")
_g("O", ".#. #.# #.# #.# .#.")
_g("P", "##. #.# ##. #.. #..")
_g("Q", ".#. #.# #.# #.# .##")
_g("R", "##. #.# ##. #.# #.#")
_g("S", ".## #.. .#. ..# ##.")
_g("T", "### .#. .#. .#. .#.")
_g("U", "#.# #.# #.# #.# ###")
_g("V", "#.# #.# #.# #.# .#.")
_g("W", "#...# #...# #.#.# ##.## #...#")
_g("X", "#.# #.# .#. #.# #.#")
_g("Y", "#.# #.# .#. .#. .#.")
_g("Z", "### ..# .#. #.. ###")
_g("0", "### #.# #.# #.# ###")
_g("1", ".#. ##. .#. .#. ###")
_g("2", "##. ..# .#. #.. ###")
_g("3", "##. ..# .#. ..# ##.")
_g("4", "#.# #.# ### ..# ..#")
_g("5", "### #.. ##. ..# ##.")
_g("6", ".## #.. ### #.# ###")
_g("7", "### ..# .#. .#. .#.")
_g("8", "### #.# ### #.# ###")
_g("9", "### #.# ### ..# ##.")
_g("/", "..# ..# .#. #.. #..")
_g("-", ".. .. ## .. ..")
_g(".", ". . . . #")
_g(",", ". . . # #")
_g(":", ". # . # .")
_g("+", "... .#. ### .#. ...")
_g("%", "#.# ..# .#. #.. #.#")
_g("'", "# # . . .")
_g("&", ".#. #.# .#. #.# .##")
_g("!", "# # # . #")
_g("(", ".# #. #. #. .#")
_g(")", "#. .# .# .# #.")
_g("·", ". . # . .")          # interpunct
_g("–", "... ... ### ... ...")  # en rule
_g(" ", ".. .. .. .. ..")
