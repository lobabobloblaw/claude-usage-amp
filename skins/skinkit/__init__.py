"""skinkit -- a pixel-art toolkit for building real classic Winamp 2.x skins (.wsz).

A *theme* is a Python class with one painter method per widget state.  The
toolkit hands every painter a :class:`~skinkit.canvas.Canvas` that is already
the exact size of the sprite and already pre-filled with whatever lies
underneath it, then cuts the results into the sheets at the coordinates in
``skinspec/sprites.json``.  An artist never hand-computes a sheet coordinate.

Typical use::

    from skinkit.theme import Theme

    class MySkin(Theme):
        name = "MySkin"
        def paint_main_background(self, c): ...

    THEME = MySkin()

then ``python3 skins/build.py myskin``.

See ``skins/skinkit/README.md`` for the artist's manual.
"""

from __future__ import annotations

__all__ = [
    "spec",
    "canvas",
    "fx",
    "fonts",
    "theme",
    "builder",
    "preview",
    "validate",
]

__version__ = "1.0.0"
