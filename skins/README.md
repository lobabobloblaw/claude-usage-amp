# skins/

Everything that makes a Tokenamp skin. A skin is a real classic Winamp 2.x
`.wsz` — the same format Winamp 2.9 loaded in 1999 — so third-party skins drop
straight into the app, and the skins built here drop straight into Winamp.

```
skinkit/          the Python painting toolkit  (read skinkit/README.md)
base/             the reference skin: Base
<name>/           one folder per skin: theme.py, out/, preview/
dist/*.wsz        the built archives the app bundles
build.py          the build entry point
ART_DIRECTION.md  house style for the art skins
<name>/BRIEF.md   each art skin's own direction
```

## Building

```sh
python3 skins/build.py base          # build one skin
python3 skins/build.py --all         # every folder that has a theme.py
python3 skins/build.py base --no-preview
```

Each build writes three things and then validates them:

| where | what |
|---|---|
| `skins/<name>/out/` | the loose sheets, `viscolor.txt`, `pledit.txt`, `plfont.bmp`, `plfont.txt`, `readme.txt` |
| `skins/dist/<Name>.wsz` | the same files, zipped **flat** with deflate — what the app loads |
| `skins/<name>/preview/` | each window mocked up in a live state at 1x and 4x, plus `sheets.png` |

Validate on its own at any time:

```sh
cd skins && python3 -m skinkit.validate dist/Base.wsz
cd skins && python3 -m skinkit.validate --require-plfont base/out
```

Non-zero exit and a list of problems if a sheet is the wrong size, a pressed
state is identical to its normal state, two digits look the same, a glyph cell
is empty, the visualiser colour disagrees with `viscolor.txt`, or the zip is
not flat.

`validate` checks a *built skin*. To check the *toolkit* — every primitive and
effect still runs, and the baked-widget underlay model still holds pixel for
pixel — run:

```sh
cd skins && python3 -m skinkit.selftest
```

## Making a new skin

1. `mkdir skins/<name>`
2. Write `skins/<name>/theme.py` with a `Theme` subclass and `THEME = MyTheme()`.
3. `python3 skins/build.py <name>`
4. Open `skins/<name>/preview/all_4x.png` and fix what you see.

Overriding nothing but the palette already produces a complete, valid skin —
every painter falls back to `Base`. **`skins/skinkit/README.md` is the artist's
manual**: the build order and underlay model, every painter hook with its
sprite size and window position, the drawing primitives and effects, and the
list of traps that cost a pixel each.

## Ground rules

- `skinspec/sprites.json` is the single source of truth for every sprite rect
  and window layout. Never hand-type a coordinate that lives in it — neither in
  Python nor in Swift.
- `Base` is the app's fallback for any sheet a third-party skin lacks, so it
  must stay complete and legible at 1x.
- The Sessions list is drawn with each skin's own bitmap typeface (`plfont`,
  SPEC 3.2), never a system font.
