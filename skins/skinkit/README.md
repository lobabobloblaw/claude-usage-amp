# skinkit — the artist's manual

`skinkit` turns a Python `Theme` subclass into a real classic Winamp 2.x skin: a
set of 24-bit BMP sheets, `viscolor.txt`, `pledit.txt`, `readme.txt`, zipped
into a flat `.wsz`. You paint **widgets in window coordinates** — the faceplate,
a button, a display well — and the toolkit cuts each painted widget into the
sheet rect that `skinspec/sprites.json` says it lives at. You never hand-compute
a sheet coordinate, and a texture that samples in window space (everything in
`skinkit.fx` does) stays continuous across the seam between the background and
the button cut out of it.

```python
from skinkit.theme import Theme

class MySkin(Theme):
    name = "MySkin"
    def paint_main_background(self, c):
        self.faceplate(c)   # or your own material

THEME = MySkin()
```

Run it with:

```
python3 skins/build.py <folder>
```

A skin folder needs only a `theme.py` that defines `THEME = MySkin()`. Every
painter you don't override falls back to `Theme`'s own art (the shipped `Base`
skin), so a skin is valid the moment `THEME` exists — even before you've
touched a single painter.

## 1. The build order and the underlay model

This is the whole seamlessness story, from `builder.py`:

1. **`paint_main_background`** fills a pristine 275×116 `main_bg` — everything
   static in the main window: faceplate, bezel, display wells, engraved
   labels, screws, the digit frame. Nothing dynamic goes here.
2. **Every main-window widget gets a canvas that is a copy of `main_bg` at
   that widget's layout rect**, with `origin` set to the rect's top-left. Its
   *normal* state is painted, kept as a sprite, and baked back into `main.bmp`
   at the same rect — so `main.bmp` on disk shows the window idle, exactly as
   a hand-made skin would.
3. **Every other state** (pressed, selected, active/inactive) starts again
   from a **fresh copy** of `main_bg` at the same rect, so pressed/selected art
   composites over the identical underlay and can never disagree with the
   baked normal state by a pixel.
4. **Thumbs** (position, volume, balance, EQ slider, playlist scroll handle,
   shade position) float over their frame rather than sit in the background —
   they start from their own neutral fill (`self.free(...)`) and must end up
   **fully opaque**, because a translucent thumb would show the frame pixels
   that were never drawn under it.
5. **The EQ window** repeats steps 1–4 with `eq_bg` / `paint_eq_background`.
   **The playlist is tiled**: its pieces start from a flat `pl_face` fill
   (there is no single "playlist background" canvas to cut from), and a tile
   must be **invariant along the axis it repeats on** — `paint_pl_top_tile`
   tiles horizontally, so its art may vary in `y` but not in a way that breaks
   at any `x`; `paint_pl_left_tile` / `paint_pl_right_tile` tile vertically.

**What you get for free:** seamlessness. A gradient, brushed-metal grain, or
noise field painted into the 275×116 background and the same generator called
again inside a 23×18 button cut out of it produce identical pixels at the
overlap, because both canvases report the same window coordinates for the same
physical location (see §2). You do not need to "line things up" — the origin
does it.

**What you must not do:**

- Draw outside the widget's own canvas. A painter's canvas is exactly the
  sprite's size (`w`, `h`); the builder raises `ValueError` if you resize it.
- Assume a transparent canvas. Every main/EQ-window painter's canvas already
  has the background painted into it (or, for thumbs and digits/glyphs, a flat
  neutral fill); there is no "clear to transparent, draw on top" step. Draw
  the whole widget, including corners the background already coloured, if your
  material differs from the background's.
- Bake anything dynamic (marquee text, digit values, slider position) into a
  background or a well. Wells hold only their frame and flat interior colour;
  the app fills them at runtime.

## 2. Origin-aware textures

Every `Canvas` knows where it lives:

- `canvas.origin` — the window coordinate of the canvas's own pixel (0, 0).
- `canvas.window` — `"main"`, `"eq"`, `"playlist"`, `"shade"`, or `None` for
  free-floating sprites.
- `c.wx(x)` / `c.wy(y)` — local → window coordinate.
- `c.lx(wx)` / `c.ly(wy)` — window → local coordinate.

Every noise and gradient generator in `skinkit.fx` samples in **window space**
by default (`window_space=True`), reading `canvas.origin` through
`fx.window_grid(c)`. That is the entire trick: paint a gradient into the
275×116 background, then cut a 23×18 button out of it — the button's canvas
has `origin = (btn.x, btn.y)`, so the same gradient call reproduces exactly the
background's slice at that rect.

```python
# in paint_main_background(self, c):           # c.origin == (0, 0)
fx.linear_gradient(c, self.face_hi, self.face_lo, direction="v")
# in paint_transport(self, c, which, pressed):  # c.origin == (16, 88), say
fx.linear_gradient(c, self.face_hi, self.face_lo, direction="v")  # same slice
```

**Sprites with no meaningful window position** — the builder still gives them
an `origin`, but it is a convention, not a real placement, so do not rely on it
lining up with anything visible:

- **Digits** (`paint_digit`) — every digit sprite (`0`..`9`, blank, minus) is
  painted with the *same* origin, the first digit cell's rect
  (`layout.main.digits[0]`), regardless of which of the four digit slots it
  will actually occupy in the sheet.
- **Glyphs** (`paint_glyph`) — every character cell is painted with the
  marquee well's origin (`layout.main.marquee`), not its real column in
  `text.bmp`.
- **Thumbs** — position/volume/balance/EQ/scroll-handle/shade thumbs are
  built with `self.free(...)`, a plain flat-filled canvas with an origin that
  is nominal (typically the frame's origin), because a thumb floats and has no
  single fixed window position.
- **EQ slider frames** (`paint_eq_slider_frame`) — this one sprite is baked at
  **eleven** different x positions (the preamp trough plus ten band troughs),
  all painted from one canvas whose origin is fixed at the first band slider's
  rect. Its art must be **x-invariant** — do not let a window-space gradient
  or noise field key off `c.ox`, or the ten baked copies will visibly disagree.
- **Playlist tiles** — a tile's origin is where the builder happens to place
  that *one* instance (e.g. `paint_pl_left_tile` gets `origin=(0, title_h)`),
  but the same art is repeated at every other multiple of the tile size, so it
  must tile cleanly regardless of where any one copy's origin says it is.

## 3. Every painter hook

`c` is always a `Canvas` already sized to the sprite and pre-filled per §1.
Coordinates below are window coordinates from `skinspec/sprites.json`
`layout`; sprite sizes are `w×h`.

### Main window (`window="main"`)

| Method | Sprite size | Window position | Draws |
|---|---|---|---|
| `paint_main_background(self, c)` | 275×116 | `(0,0)` | Everything static: faceplate, outer bevel, both display wells, the visualiser well, the time-digit frame, the marquee/kbps/khz field outlines, the SPEC 5.1 baked labels, the clutter-bar surround, the four faceplate screws, and the about-logo. |
| `paint_time_frame(self, c)` | *(drawn into main_bg, no sprite of its own)* | around `digits`/`minusSignEx` | A 1px outline around the four 9×13 time digits plus the colon; deliberately an outline only — the digit cells must stay the flat colour `digit_background()` returns. |
| `paint_about_logo(self, c)` | 13×15 | `aboutLogo` (253,91) | Decorative mark at the bottom-right of the main window. |
| `paint_title_bar(self, c, active: bool, variant: str)` | 275×14 | `titleBar` (0,0) | The title strip. `variant` is `"main"`, `"shade"`, or `"easter"`; keep the far-left/right ~20px identical between `active` states (see §11). |
| `paint_title_button(self, c, which: str, pressed: bool)` | 9×9 | `optionsButton` (6,3) / `minimizeButton` (244,3) / `shadeButton` (254,3) / `closeButton` (264,3) | `which` is `"options"`, `"minimize"`, `"shade"`, `"close"`, or `"unshade"` (the shade button's selected state, shown while already shaded — same rect as `"shade"`). |
| `paint_clutter_bar(self, c, pressed: str \| None = None, disabled: bool = False)` | 8×43 | `clutterBar` (10,22) | The O A I D V strip. `pressed` is `None` or one of `"O" "A" "I" "D" "V"`; the whole column is repainted with that one letter pushed in. |
| `paint_transport(self, c, which: str, pressed: bool)` | 23×18 (`previous`/`play`/`pause`/`stop`), 22×18 (`next`), 22×16 (`eject`) | `previous` (16,88) `play` (39,88) `pause` (62,88) `stop` (85,88) `next` (108,88) `eject` (136,89) | `which` selects the icon; `pressed` moves it via `press_offset`. |
| `paint_shuffle(self, c, pressed: bool, selected: bool)` | 47×15 | `shuffle` (164,89) | SPEC 5.1 relabels SHUFFLE as `CYCLE`. |
| `paint_repeat(self, c, pressed: bool, selected: bool)` | 28×15 | `repeat` (210,89) | SPEC 5.1 relabels REPEAT as `ALERT`. Note: `repeat`'s rect starts at the same x where `shuffle`'s rect ends — see §11. |
| `paint_eq_toggle(self, c, pressed: bool, selected: bool)` | 23×12 | `eqButton` (219,58) | Shows/hides the equaliser window. |
| `paint_pl_toggle(self, c, pressed: bool, selected: bool)` | 23×12 | `plButton` (242,58) | Shows/hides the playlist window. |
| `paint_posbar_background(self, c)` | 248×10 | `posbar` (16,72) | The groove only — never the thumb. |
| `paint_posbar_thumb(self, c, pressed: bool)` | 29×10 | floats over `posbarThumbTravel` (16..235) | Fully opaque; rides over the groove, not through it. |
| `paint_volume_frame(self, c, i: int)` | 68×13 | `volume` (107,57) | `i` is 0..27; 0 = empty/cool, 27 = full/hot. Drawn 28 times, once per frame. |
| `paint_volume_thumb(self, c, pressed: bool)` | 14×11 | floats near `volume` | Fully opaque. |
| `paint_balance_frame(self, c, i: int)` | 38×13 | `balance` (177,57) | Same `i` convention as the volume frame. |
| `paint_balance_thumb(self, c, pressed: bool)` | 14×11 | floats near `balance` | Fully opaque. |
| `paint_mono(self, c, on: bool)` | 27×12 | `mono` (212,41) | SPEC 5.1 relabels `mono` as `LOCAL`. |
| `paint_stereo(self, c, on: bool)` | 29×12 | `stereo` (239,41) | SPEC 5.1 relabels `stereo` as `LIVE`. |
| `paint_play_state(self, c, state: str)` | 9×9 | `playPauseIndicator` (26,28) | `state` is `"playing"`, `"paused"`, or `"stopped"`. |
| `paint_work_indicator(self, c, working: bool)` | 3×9 | `workIndicator` (24,28) | Only its left 2 columns are ever visible — the 9×9 play-state icon at (26,28) overlaps its third column (see §11). |
| `paint_digit(self, c, d)` | 9×13 | nominal: `digits[0]` (48,26) for every digit | `d` is `0`..`9`, `"blank"`, or `"minus"`. Background **must** equal `digit_background()`. |
| `paint_glyph(self, c, ch: str)` | 5×6 | nominal: `marquee` origin (111,27) for every glyph | One `text.bmp` character cell. Background **must** equal `text_background()`. |
| `paint_shade_position_background(self, c)` | 17×7 | shade `position` (226,4) | Mini position-bar groove for the window-shade strip. |
| `paint_shade_position_thumb(self, c, which: str)` | 3×7 | floats over shade `positionThumbTravel` | `which` is `"left"`, `"center"`, or `"right"` — the third of the handle showing at that end of travel. |

### Equaliser window (`window="eq"`, 275×116)

| Method | Sprite size | Window position | Draws |
|---|---|---|---|
| `paint_eq_background(self, c)` | 275×116 | `(0,0)` | Everything static: faceplate, bezel, graph well, preamp/band troughs, the SPEC 5.1 captions, four corner screws. |
| `paint_eq_title_bar(self, c, active: bool)` | 275×14 | `titleBar` (0,0) | SPEC 5.1: `USAGE EQUALIZER`. |
| `paint_eq_close(self, c, pressed: bool)` | 9×9 | `closeButton` (264,3) | Delegates to `paint_title_button(c, "close", pressed)`. |
| `paint_eq_on(self, c, pressed: bool, selected: bool)` | 26×12 | `onButton` (14,18) | SPEC 5.1 keeps the caption `ON`. |
| `paint_eq_auto(self, c, pressed: bool, selected: bool)` | 32×12 | `autoButton` (40,18) | SPEC 5.1 keeps the caption `AUTO`. |
| `paint_eq_presets(self, c, pressed: bool)` | 44×12 | `presetsButton` (217,18) | SPEC 5.1 relabels PRESETS as `RANGE`. |
| `paint_eq_slider_frame(self, c, i: int)` | 14×63 | nominal: first band slider rect (78,38) — baked at **11** x positions | `i` is 0..27; 0 = thumb at the bottom (min), 27 = thumb at the top (max). Must be x-invariant (§2). |
| `paint_eq_thumb(self, c, pressed: bool)` | 11×11 | floats at `(bandSliders.x0 + sliderThumbOffsetX, bandSliders.y)` = (79,38) | Fully opaque; rides over the frame. |
| `paint_eq_graph_background(self, c)` | 113×19 | `graph` (86,17) | The curve well, no curve drawn. |
| `paint_eq_preamp_line(self, c)` | 113×1 | `(graph.x, graph.y + graph.h // 2)` = (86,26) | The colour strip used to draw the preamp level line. |

### Playlist window (`window="playlist"`, tiled)

Positions below assume the default 275×232 playlist size (`W=275`, `H=232`);
`title_h=20`, `bottom_h=38`, `left_w=12`, `right_w=20`.

| Method | Sprite size | Window position (default size) | Draws |
|---|---|---|---|
| `paint_pl_top_left(self, c, active: bool)` | 25×20 | `(0,0)` | Top-left corner of the playlist frame. |
| `paint_pl_title(self, c, active: bool)` | 100×20 | centred, `((W-100)//2, 0)` = (87,0) | SPEC 5.1: `SESSIONS`. |
| `paint_pl_top_tile(self, c, active: bool)` | 25×20 | `(corner_w, 0)` = (25,0), repeated | Repeated horizontally along the top edge. |
| `paint_pl_top_right(self, c, active: bool)` | 25×20 | `(W-25, 0)` = (250,0) | Top-right corner; the playlist close button's *normal* state is baked in at local (14,3) by the builder. |
| `paint_pl_left_tile(self, c)` | 12×29 | `(0, title_h)` = (0,20), repeated | Repeated down the left edge. |
| `paint_pl_right_tile(self, c)` | 20×29 | `(W-20, title_h)` = (255,20), repeated | Repeated down the right edge; carries the scrollbar groove (local x 4..13). |
| `paint_pl_bottom_tile(self, c)` | 25×38 | `(left_w, H-bottom_h)` = (12,194), repeated | Repeated along the bottom edge on wide windows. |
| `paint_pl_bottom_left(self, c)` | 125×38 | `(0, H-bottom_h)` = (0,194) | Bottom-left corner (buttons area in classic skins). |
| `paint_pl_bottom_right(self, c)` | 150×38 | `(W-150, H-bottom_h)` = (125,194) | Bottom-right corner; carries the running-info and mini-time wells (positions from `layout.playlist.runningInfoFromBottomRight` / `miniTimeFromBottomRight`, converted to local coordinates of this piece). |
| `paint_pl_visualizer_background(self, c)` | 75×38 | same origin as `paint_pl_bottom_right`, (125,194) | Optional mini-visualiser well; Tokenamp does not place this piece in its own layout, kept for third-party-compatible sheets. |
| `paint_pl_scroll_handle(self, c, pressed: bool)` | 8×18 | `(W-15, title_h)` = (260,20) | Opaque scrollbar handle. |
| `paint_pl_close(self, c, pressed: bool)` | 9×9 | `(W-11, 3)` = (264,3) | Delegates to `paint_title_button(c, "close", pressed)`. |
| `paint_pl_collapse(self, c, pressed: bool)` | 9×9 | `(W-21, 3)` = (254,3) | Delegates to `paint_title_button(c, "shade", pressed)`. |
| `paint_pl_font_glyph(self, c, ch: str)` | `pl_font_cell()` (Base default 8×10) | none — a free-floating grid cell, not window-anchored | One cell of the Sessions-list bitmap typeface `plfont.bmp` (SPEC §3.2, not a `sprites.json` sheet). The canvas is pre-filled black; paint **white for full ink, greys for partial coverage** — it's an ink-coverage mask, not colour, so a grey pixel reads as a soft phosphor halo once the app tints it. `ch` is the character, with the ellipsis cell passed as `"…"`. Full detail in §9. |

### Data hooks

| Method | Returns | Meaning |
|---|---|---|
| `name` | `str` (class attribute) | Skin name; also the `.wsz` filename. |
| `author` | `str` (class attribute) | Credited in `readme.txt`. |
| `description` | `str` (class attribute) | One line, used in `readme.txt`. |
| `viscolors(self)` | `list[tuple[int,int,int]]`, 24 entries | `viscolor.txt`. 0 = visualiser background (**must** equal the colour painted at `layout.main.visualizer`), 1 = background dots, 2..17 = spectrum bars top→bottom, 18..22 = oscilloscope (18 brightest), 23 = peak caps. |
| `pledit_colours(self)` | `dict[str,str]` | `pledit.txt` values: `Normal`, `Current`, `NormalBG`, `SelectedBG`, `Font`. |
| `eq_graph_line_colours(self)` | `list[tuple[int,int,int]]`, 19 entries | Row 0 = top of the EQ graph, row 18 = bottom. |
| `digit_background(self)` | `Colour` | Background of the 9×13 digit cells; must equal the interior of the time well. |
| `text_background(self)` | `Colour` | Background of the 5×6 glyph cells; must equal the marquee/kbps/khz well interiors. |
| `readme(self)` | `str` | Contents of `readme.txt` inside the `.wsz`. |
| `pl_font_cell(self)` | `tuple[int,int]` | `(cellW, cellH)` of one `plfont.bmp` cell. The sheet is always 16×6 cells, so the Base default `(8, 10)` produces a 128×60 sheet. Keep `cw >= 3` and `ch >= 5` — the builder rejects anything smaller as illegible. Full detail in §9. |
| `pl_font_metrics(self)` | `dict` | `plfont.txt` `[PlaylistFont]` values: `Monospace` (0/1), `Spacing`, `SpaceWidth`, `RowHeight` (replaces `layout.playlist.rowHeight`), `OffsetY`. A key whose value is `None` is omitted so the app's own default applies. Full detail in §9. |

## 4. The palette

Override these class attributes and most of the skin follows — a subclass
that overrides only the palette (plus `name`) already produces a complete,
valid skin, because every painter above is implemented in terms of these
tokens. `Theme` *is* the Base skin (its own docstring says so), so the values
below are Base's values: they are `skinkit.theme.Theme`'s own defaults. The
shipped `skins/base/theme.py::BaseTheme` overrides every one of them with its
own, very slightly different palette (a few points lighter/darker here and
there) — that subclass is itself the worked example of what overriding just
the palette buys you.

| Attribute | Meaning | Base's value |
|---|---|---|
| `sheet_filler` | Colour used for the unreachable parts of each sheet | `"#0d1013"` |

**Faceplate**

| Attribute | Meaning | Base's value |
|---|---|---|
| `face_hi` | Top of the faceplate gradient | `"#454c55"` |
| `face` | Faceplate mid tone | `"#343b43"` |
| `face_lo` | Bottom of the faceplate gradient | `"#232930"` |
| `edge_light` | Outer bevel highlight | `"#6f7b89"` |
| `edge_mid` | | `"#525c68"` |
| `edge_shadow` | Outer bevel shadow | `"#171b20"` |
| `edge_black` | | `"#0b0d10"` |

**Displays**

| Attribute | Meaning | Base's value |
|---|---|---|
| `well_bg` | LCD background (glyph + digit background) | `"#0a1310"` |
| `well_rim` | | `"#080a0c"` |
| `viz_bg` | Visualiser well — **must equal** `viscolors()[0]` | `"#060d0a"` |
| `viz_dots` | Visualiser dot grid — `viscolors()[1]` | `"#12241c"` |
| `text_fg` | Phosphor text | `"#7ff0a4"` |
| `text_dim` | | `"#39795a"` |
| `digit_on` | Lit segment | `"#84ffb0"` |
| `digit_off` | Unlit segment ghost (`None` = clean LCD) | `None` |

**Buttons**

| Attribute | Meaning | Base's value |
|---|---|---|
| `btn_face` | | `"#3b424b"` |
| `btn_hi` | | `"#79838f"` |
| `btn_lo` | | `"#171b20"` |
| `btn_inner_hi` | | `"#4d5661"` |
| `btn_inner_lo` | | `"#252b32"` |
| `btn_pressed_face` | Declared for a pressed-face fill; no stock painter reads it yet — free for a subclass to use | `"#2b3138"` |
| `icon` | Transport glyph colour | `"#d3dbe4"` |
| `icon_dim` | | `"#8a939d"` |

**Lamps and labels**

| Attribute | Meaning | Base's value |
|---|---|---|
| `lamp_on` | | `"#6cff9a"` |
| `lamp_off` | | `"#1e3a2b"` |
| `lamp_alt_on` | | `"#ffcf5a"` |
| `label` | Micro-label ink | `"#aab5c3"` |
| `label_relief` | 1px shadow drawn under a micro label | `"#090b0e"` |
| `accent` | | `"#5fe08a"` |

**Sliders**

| Attribute | Meaning | Base's value |
|---|---|---|
| `groove_bg` | | `"#14181d"` |
| `groove_rim_hi` | | `"#5a636e"` |
| `groove_rim_lo` | | `"#0c0e11"` |
| `heat_cool` | Green end of the volume/balance/EQ heat ramp | `"#2fd257"` |
| `heat_warm` | | `"#e6d044"` |
| `heat_hot` | Red end of the heat ramp | `"#e34530"` |

**Title bar**

| Attribute | Meaning | Base's value |
|---|---|---|
| `title_active_hi` | | `"#4d5661"` |
| `title_active_lo` | | `"#2a3038"` |
| `title_inactive_hi` | | `"#3a4048"` |
| `title_inactive_lo` | | `"#252a31"` |
| `title_text_on` | | `"#cfe8d8"` |
| `title_text_off` | | `"#6d7d75"` |
| `title_grip_hi` | | `"#5d6873"` |
| `title_grip_lo` | | `"#1b1f25"` |

**Playlist**

| Attribute | Meaning | Base's value |
|---|---|---|
| `pl_face` | | `"#2e343b"` |
| `pl_face_hi` | | `"#3c434c"` |
| `pl_list_bg` | | `"#0a1310"` |

**Identity and determinism**

| Attribute | Meaning | Base's value |
|---|---|---|
| `name` | Skin name and `.wsz` filename | `"Base"` |
| `author` | | `"Tokenamp"` |
| `description` | One line for `readme.txt` | `"Dark graphite hi-fi faceplate with a green phosphor display."` |
| `seed` | Passed to every deterministic noise call so the same theme always renders the same pixels | `11` |

One more overridable, not a colour: `pl_font_halo` (default `0.28`) is the
strength `paint_pl_font_glyph`'s stock implementation passes to `fonts.halo`
for the Sessions-list typeface's phosphor glow (§9); set it to `0` for crisp,
halo-free ink.

**Geometry constants** (override to move a well; the widgets that reach into
it, such as `paint_glyph`'s underlay, move with it)

| Attribute | Meaning | Value |
|---|---|---|
| `WELL_LEFT` | The left display well: work/play icons, four time digits, visualiser. `(x, y, w, h)` | `(20, 18, 85, 43)` |
| `WELL_RIGHT` | The right display well: marquee, kbps/khz fields, mono/stereo lamps, SESSION/WEEK captions. | `(107, 18, 161, 36)` |
| `MAIN_SCREWS` | Screw positions on the main faceplate, all in clear space | `((6, 78), (6, 108), (268, 78), (268, 108))` |
| `EQ_TROUGH_PREAMP` | The preamp slider's recessed trough rect | `(19, 36, 18, 66)` |
| `EQ_TROUGH_BANDS` | The ten band sliders' shared trough rect | `(76, 36, 180, 66)` |
| `EQ_BAND_CAPTIONS` | SPEC 5.1 band captions, oldest bucket first | `("-9","-8","-7","-6","-5","-4","-3","-2","-1","NOW")` |

## 5. Theme helpers

`Theme` itself provides a handful of small, overridable helpers that most
painters above are built from; artists call these constantly. `digit_background()`
and `text_background()` are already covered in §3's data-hooks table, but
`well()` is what actually gets filled with the colour they return.

| Method | Signature | Example |
|---|---|---|
| `faceplate` | `faceplate(self, c)` | Fills a canvas with the skin's faceplate material (gradient + two noise passes), continuous in window space. The one-liner every custom `paint_main_background` starts from: `self.faceplate(c)`. |
| `micro` | `micro(self, c, x, y, text, colour=None, font=None, spacing=None, relief=...)` | A tiny panel label: `label` ink over a 1px `label_relief` shadow one pixel down-right. The parameter is `relief`, not `lip`; `relief=None` draws flat text (what you want on an LCD). At 3×5 this reads far better than a true engrave, which turns to mush — use `fx.engrave_text` instead on light plates. `self.micro(c, 2, c.h - 6, "SESSION")`. |
| `lcd_text` | `lcd_text(self, c, x, y, text, colour=None, font=None, spacing=None)` | Flat phosphor text for the inside of a display well; defaults to `text_dim`. This is what the baked `K/MIN`, `ACTIVE`, `SESSION`, and `WEEK` captions in `paint_main_background` use. |
| `lamp` | `lamp(self, c, x, y, w, h, on, colour=None, bloom=1)` | An indicator lamp whose off state still reads as a lamp (a dimmed body, not a blank one). `self.lamp(c, 2, 4, 4, 3, on=True)`. |
| `button_face` | `button_face(self, c, pressed=False, rect=None, double=True)` | A raised (or, if `pressed`, pressed) button plate filling the canvas — the basis of every button painter. `self.button_face(c, pressed)`. |
| `press_offset` | `press_offset(self, pressed) -> (dx, dy)` | How far a button's art moves when pressed; `(1, 1)` in Base, `(0, 0)` otherwise. Use it rather than hardcoding the offset, so a skin can change the convention (or disable the shift) in one place. |
| `well` | `well(self, c, rect, colour=None, rim_hi=None, rim_lo=None, shadow_depth=2) -> Canvas` | Cuts a recessed display well and **returns a view of its interior**. The 1px rim is drawn *around* `rect`, so the interior is exactly `rect` — which is what lets glyph and digit cells sit on the known flat colour `text_background()`/`digit_background()` returns. `interior = self.well(c, self.WELL_LEFT)`. |
| `_tri` | `_tri(self, c, x, y, w, h, direction, colour)` | Internal but stable — the solid-pixel-triangle primitive behind every transport/mini-icon painter. `direction` is `"left"`, `"right"`, `"up"`, or `"down"`. `self._tri(c, cx - 3, cy - 4, 7, 9, "right", self.icon)` draws a play glyph. |

## 6. Canvas primitives

`Canvas(w=0, h=0, origin=(0,0), window=None, fill=None, array=None)`. Every
method below returns `self` unless noted, so calls chain.

**Colour parsing** — `parse_colour(c)` accepts `(r,g,b)`, `(r,g,b,a)`,
`"#rrggbb"`, `"#rrggbbaa"`, `"#rgb"`, or `"#rgba"`, and returns `(r,g,b,a)`
ints. Every colour parameter on every `Canvas`/`fx` method goes through it.

| Function | Signature | Example |
|---|---|---|
| `parse_colour` | `parse_colour(c: Colour) -> (r,g,b,a)` | `parse_colour("#7cf0a6")` → `(124,240,166,255)` |
| `rgb` | `rgb(c: Colour) -> (r,g,b)` | `rgb("#ff0000ff")` → `(255,0,0)` |
| `rgba_tuple` | `rgba_tuple(c: Colour) -> (r,g,b,a)` | alias of `parse_colour` |
| `mix` | `mix(a: Colour, b: Colour, t: float) -> (r,g,b,a)` | `mix("#000", "#fff", 0.5)` → mid grey |
| `lighten` | `lighten(c: Colour, amount: float) -> (r,g,b,a)` | `lighten(self.face, 0.16)` |
| `darken` | `darken(c: Colour, amount: float) -> (r,g,b,a)` | `darken(self.btn_face, 0.22)` |
| `with_alpha` | `with_alpha(c: Colour, a: int) -> (r,g,b,a)` | `with_alpha("#7cf0a6", 128)` — half-transparent |
| `hsv_shift` | `hsv_shift(c: Colour, dh=0.0, ds=1.0, dv=1.0)` | `hsv_shift(self.accent, dh=0.5)` — complementary hue |

**Construction and views**

| Method | Signature | Example |
|---|---|---|
| `Canvas.from_rect` | `Canvas.from_rect(rect, window=None, fill=None) -> Canvas` | `Canvas.from_rect(spec.lrect("main","posbar"), window="main")` |
| `Canvas.from_pil` | `Canvas.from_pil(img, origin=(0,0), window=None) -> Canvas` | loading a reference PNG into a canvas |
| `sub` | `sub(x, y=None, w=None, h=None) -> Canvas` (shares memory) | `c.sub(2, 3, c.w-4, 4)` — a view of the groove |
| `crop` | `crop(x, y=None, w=None, h=None) -> Canvas` (independent copy) | `main_bg.crop(r.x, r.y, r.w, r.h)` |
| `copy` | `copy() -> Canvas` | `main_bg.copy()` |
| `resized_view` | `resized_view(window=None, origin=None) -> Canvas` | reinterpreting the same pixels under a new origin |

**Geometry**

| Method | Signature | Example |
|---|---|---|
| `w`, `h`, `size` | properties | `c.w, c.h` |
| `ox`, `oy` | properties, window x/y of local (0,0) | `c.ox` |
| `wx` / `wy` | `wx(x) -> x`, `wy(y) -> y` (local → window) | `c.wx(0) == c.ox` |
| `lx` / `ly` | `lx(wx) -> x`, `ly(wy) -> y` (window → local) | `c.lx(c.ox) == 0` |
| `in_bounds` | `in_bounds(x, y) -> bool` | `c.in_bounds(-1, 0)` → `False` |

**Pixel access**

| Method | Signature | Example |
|---|---|---|
| `poke` | `poke(x, y, colour)` — no blending, replaces alpha too | `c.poke(0, 0, "#ff00ff")` |
| `px` | `px(x, y, colour)` — opaque replaces, translucent composites | `c.px(4, 4, "#ffffff80")` |
| `get` | `get(x, y) -> (r,g,b,a)` | `c.get(0, 0)` |
| `get_rgb` | `get_rgb(x, y) -> (r,g,b)` | `c.get_rgb(0, 0)` |

**Fills and rectangles** — `box` takes a **width/height**; `hline`/`vline`
take **inclusive** end coordinates. This is the easiest mistake to make:
`c.box(0, 0, 5, 1, col)` and `c.hline(0, 4, 0, col)` draw the same five
pixels, *not* `c.hline(0, 5, 0, col)`, which draws six.

| Method | Signature | Example |
|---|---|---|
| `fill` | `fill(colour, rect=None) -> Canvas` | `c.fill(self.well_bg)` |
| `clear` | `clear() -> Canvas` | zero every channel |
| `box` | `box(x, y, w, h, colour) -> Canvas` | `c.box(2, 4, fill_w, 5, col)` |
| `rect` | `rect(x, y, w, h, colour) -> Canvas` — 1px outline | `c.rect(x-1, y-1, w+2, h+2, lo)` |
| `frame` | `frame(colour, n=1, rect=None) -> Canvas` — `n` nested outlines | `c.frame(self.edge_black, n=2)` |
| `hline` | `hline(x0, x1, y, colour) -> Canvas` — **inclusive**, order-free | `c.hline(0, c.w-1, 0, col)` |
| `vline` | `vline(x, y0, y1, colour) -> Canvas` — **inclusive**, order-free | `c.vline(0, 0, c.h-1, col)` |
| `line` | `line(x0, y0, x1, y1, colour) -> Canvas` — Bresenham | `c.line(0, 0, 8, 8, col)` |
| `polyline` | `polyline(points, colour, closed=False) -> Canvas` | `c.polyline([(0,0),(4,4)], col)` |
| `polygon` | `polygon(points, colour, outline=None) -> Canvas` — scanline fill | `c.polygon(hex_pts, body, outline=darken(body,0.25))` |

**Circles (pixel-perfect midpoint)**

| Method | Signature | Example |
|---|---|---|
| `circle` | `circle(cx, cy, r, colour) -> Canvas` — outline | `c.circle(6, 6, 3, col)` |
| `disc` | `disc(cx, cy, r, colour) -> Canvas` — filled | `c.disc(6, 6, 3, col)` |
| `ellipse` | `ellipse(x, y, w, h, colour, fill=False) -> Canvas` | `c.ellipse(0, 0, 9, 5, col, fill=True)` |

**Compositing**

| Method | Signature | Example |
|---|---|---|
| `blit` | `blit(other, x=0, y=0, alpha=True) -> Canvas` — `alpha=False` copies raw RGBA rows | `dst.blit(sprite, r.x, r.y, alpha=False)` |
| `over` | `over(other, x=0, y=0) -> Canvas` — alias of `blit(..., alpha=True)` | `c.over(logo, 4, 4)` |
| `paste_array` | `paste_array(arr, x=0, y=0, alpha=False) -> Canvas` — accepts `(h,w)`, `(h,w,3)` or `(h,w,4)` | `c.paste_array(mask_array)` |

**Whole-surface adjustments**

| Method | Signature | Example |
|---|---|---|
| `tint` | `tint(colour, amount=0.5, rect=None) -> Canvas` | `c.tint(self.accent, 0.15)` |
| `adjust` | `adjust(brightness=0.0, contrast=1.0, saturation=1.0, rect=None) -> Canvas` | `c.adjust(brightness=10, saturation=0.8)` |
| `multiply` | `multiply(factor, rect=None) -> Canvas` | `c.multiply(0.85)` |
| `set_alpha` | `set_alpha(a, rect=None) -> Canvas` | `c.set_alpha(255)` |
| `opaque` | `opaque(background=(0,0,0)) -> Canvas` — composites onto a solid colour, new canvas | `c.opaque(self.filler)` |

**Masks**

| Method | Signature | Example |
|---|---|---|
| `alpha_mask` | `alpha_mask(threshold=128) -> np.ndarray` | `c.alpha_mask()` |
| `colour_mask` | `colour_mask(colour, tolerance=0) -> np.ndarray` | `c.colour_mask(self.lamp_on, tolerance=8)` |
| `luma` | `luma() -> np.ndarray` — float32, 0..255 | `c.luma()` |
| `apply_mask` | `apply_mask(mask, colour, rect=None) -> Canvas` | `c.apply_mask(m, self.accent)` |
| `mask_keep` | `mask_keep(mask) -> Canvas` — zero alpha outside `mask` | `c.mask_keep(disc_mask)` |
| `masked_copy` | `masked_copy(mask) -> Canvas` — copy with `mask_keep` applied | `c.masked_copy(m)` |

**Interchange**

| Method | Signature | Example |
|---|---|---|
| `to_pil` | `to_pil() -> PIL.Image` | `c.to_pil().save("debug.png")` |
| `save_png` | `save_png(path) -> None` | `c.save_png("/tmp/frame.png")` |

## 7. fx

Every generator in `skinkit.fx` is **deterministic** — pass a `seed` and get
the same pixels every time — and samples in **window** coordinates by default,
which is what keeps a texture continuous across a sprite cut (§2).

**Noise**

| Function | Signature | Example |
|---|---|---|
| `window_grid` | `window_grid(c) -> (X, Y)` float arrays of window coords | used internally by every generator below |
| `bayer_field` | `bayer_field(c) -> np.ndarray` — 4×4 ordered-dither matrix tiled in window space | `t + (fx.bayer_field(c) - 0.5) * 0.06` |
| `value_noise` | `value_noise(c, scale=8.0, seed=0, sx=None, sy=None) -> np.ndarray` (0..1) | `sx=40, sy=1` gives horizontal streaks |
| `fbm` | `fbm(c, scale=16.0, octaves=4, gain=0.5, lacunarity=2.0, seed=0, sx=None, sy=None) -> np.ndarray` | `fx.fbm(c, octaves=3, seed=self.seed)` |
| `apply_noise` | `apply_noise(c, amount=8.0, scale=3.0, seed=0, octaves=1, rect=None, sx=None, sy=None, tint_colour=None) -> Canvas` | `fx.apply_noise(c, amount=6, scale=2.5, seed=7)` — fine film grain |
| `speckle` | `speckle(c, density=0.04, seed=0, rect=None, light=None, dark=None, strength=0.5) -> Canvas` | single-pixel highlights/pits, e.g. wood pores |

**Gradients**

| Function | Signature | Example |
|---|---|---|
| `linear_gradient` | `linear_gradient(c, top=None, bottom=None, *, direction="v", stops=None, rect=None, dither=0.0, steps=None, window_space=True, alpha=1.0) -> Canvas` | `fx.linear_gradient(c, "#3a3f46", "#20242a", dither=0.05)` |
| `radial_gradient` | `radial_gradient(c, cx, cy, radius, inner=None, outer=None, *, stops=None, rect=None, dither=0.0, steps=None, window_space=False, alpha=1.0, aspect=1.0) -> Canvas` | `fx.radial_gradient(c, c.w/2, c.h/2, 8, "#fff", "#000")` |
| `gradient_fill` | `gradient_fill(c, stops, **kw) -> Canvas` — multi-stop wrapper over `linear_gradient` | `fx.gradient_fill(c, [(0,"#000"),(0.5,"#888"),(1,"#fff")])` |

Two-line worked example — a gradient that lines up across a sprite cut:

```python
fx.linear_gradient(main_bg, self.face_hi, self.face_lo, direction="v")   # c.origin == (0,0)
fx.linear_gradient(button_c, self.face_hi, self.face_lo, direction="v") # button_c.origin == (16,88): identical slice
```

**Bevels**

| Function | Signature | Example |
|---|---|---|
| `bevel` | `bevel(c, rect=None, *, light="#ffffff66", shadow="#00000080", raised=True, n=1, corner="mix", inset=0) -> Canvas` | `fx.bevel(c, raised=False)` |
| `bevel_raised` | `bevel_raised(c, rect=None, *, light=..., shadow=..., n=1, corner="mix", inset=0) -> Canvas` | `fx.bevel_raised(c, light="#8e98a6", shadow="#14171b")` |
| `bevel_sunken` | `bevel_sunken(c, rect=None, *, light=..., shadow=..., n=1, corner="mix", inset=0) -> Canvas` | a well or a groove |
| `bevel_double` | `bevel_double(c, rect=None, *, outer_light=..., outer_shadow=..., inner_light=..., inner_shadow=..., raised=True, corner="mix", inset=0) -> Canvas` | `fx.bevel_double(c, raised=False)` for a pressed button |

**Shadows and glow**

| Function | Signature | Example |
|---|---|---|
| `inner_shadow` | `inner_shadow(c, rect=None, colour="#000000", depth=3, strength=0.55, sides="tlbr") -> Canvas` | `fx.inner_shadow(groove, depth=2, sides="tl")` |
| `drop_shadow` | `drop_shadow(c, mask=None, colour="#00000099", dx=1, dy=1, blur=0, rect=None) -> Canvas` | shadow under a floating icon |
| `glow` | `glow(c, mask_or_points, colour="#7cff9a", radius=2, strength=0.8, rect=None) -> Canvas` | `fx.glow(c, [(4,4)], "#6bff8f", radius=3)` |

**Material generators**

| Function | Signature | Example |
|---|---|---|
| `brushed_metal` | `brushed_metal(c, base="#8d949c", direction="h", strength=0.16, seed=0, rect=None, streak=48.0, grain=1.0, sheen=0.10) -> Canvas` | `fx.brushed_metal(c, "#9aa2ab", "h", strength=0.2, seed=3)` |
| `wood_grain` | `wood_grain(c, palette=None, seed=0, rect=None, direction="h", rings=5.0, warp=6.0, pore_density=0.05, contrast=1.0) -> Canvas` | `fx.wood_grain(c, ["#c49a68","#8a5a30","#4a2d16"], seed=5, rings=7)` |
| `scanlines` | `scanlines(c, rect=None, every=2, amount=0.18, colour=None, phase=0, window_space=True) -> Canvas` | `fx.scanlines(well, every=3, amount=0.09)` |
| `glass_glare` | `glass_glare(c, rect=None, colour="#ffffff", strength=0.18, angle=-0.6, width=0.32, offset=-0.15, window_space=True, second=True) -> Canvas` | `fx.glass_glare(c, strength=0.05, angle=-0.55)` |

**Hardware details**

| Function | Signature | Example |
|---|---|---|
| `screw` | `screw(c, cx, cy, r=2, style="slot", body=..., light=..., shadow=..., slot_colour=None, angle=0) -> Canvas` | `fx.screw(c, 6, 6, r=2, style="phillips")` |
| `rivet` | `rivet(c, cx, cy, r=2, body=..., light=..., shadow=...) -> Canvas` | a domed rivet at a panel corner |
| `vent` | `vent(c, rect=None, slots=4, direction="h", gap=2, slot_thickness=2, margin=1, dark=..., light=..., face=None) -> Canvas` | `fx.vent(c, (4,3,20,12), slots=3)` |
| `grille` | `grille(c, rect=None, pitch=2, direction="h", dark=..., light=None, window_space=True) -> Canvas` | a fine line grille over a speaker area |
| `perforation` | `perforation(c, rect=None, pitch=3, r=0, dark=..., light=..., stagger=True, window_space=True) -> Canvas` | punched-hole speaker grille |
| `led` | `led(c, x, y, w, h, colour="#5fe07a", on=True, bloom=1, off_colour=None, bezel="#0d0f12", strength=0.7) -> Canvas` | `fx.led(c, 3, 4, 4, 3, "#ff5533", on=True)` |
| `hazard_stripes` | `hazard_stripes(c, rect=None, a="#e8c62a", b="#1a1c20", width=4, slope=1, window_space=True) -> Canvas` | diagonal warning stripes |

**Text relief**

| Function | Signature | Example |
|---|---|---|
| `emboss_text` | `emboss_text(c, x, y, text, font=None, colour="#c9d2dc", light="#ffffff55", shadow="#00000099", spacing=1) -> Canvas` | text standing proud of the plate |
| `engrave_text` | `engrave_text(c, x, y, text, font=None, colour="#161a1f", light="#ffffff40", spacing=1) -> Canvas` | `fx.engrave_text(c, 2, 2, "SESSION", fonts.MICRO_3x5, "#0e1114")` |

**Palette control**

| Function | Signature | Example |
|---|---|---|
| `quantize` | `quantize(c, n_colours=32, rect=None, dither=False) -> Canvas` | reduce a generated texture to N colours |
| `palette_lock` | `palette_lock(c, palette, rect=None) -> Canvas` | snap every pixel to the nearest declared colour, no dithering — use last |
| `ramp` | `ramp(stops, t) -> (r,g,b,a)` | `fx.ramp([(0,"#000"),(1,"#fff")], 0.5)` |
| `heat_colour` | `heat_colour(t, cool="#28d24a", warm="#e8d43a", hot="#e0392b", knee=0.62) -> (r,g,b,a)` | the green→yellow→red gauge ramp used by every heat bar |

## 8. fonts

Three bitmap faces. `FONT_5x6` is a **rigid** grid (`fixed_width=True`):
every glyph is exactly 5px wide because `text.bmp` is a fixed cell sheet. The
two micro faces are **variable-width**: `w` is each font's *nominal* cell
width, but a glyph may render wider than that — `M` and `W` are 5 columns
wide in both `MICRO_4x5` and `MICRO_3x5`, because 3 or 4 columns cannot draw
either letter legibly. Use `font.width(ch)` (not `font.w`) when you need one
glyph's real width; `text_width()` already sums per-glyph widths for you.

| Font | Nominal cell size | `default_spacing` | Use |
|---|---|---|---|
| `FONT_5x6` | 5×6, fixed | `0` | Fills `text.bmp`'s glyph grid. Column 4 of the cell is the inter-glyph gap, so its natural spacing is 0 — adding spacing on top would double the gap. |
| `MICRO_4x5` | 4×5, variable | `1` | Engraved panel labels with a little more room. |
| `MICRO_3x5` | 3×5, variable | `1` | Labels that have to fit in almost nothing. |

| Method / Function | Signature | Notes |
|---|---|---|
| `BitmapFont.width` | `font.width(ch) -> int` | A glyph's actual width in pixels; may exceed `font.w` on a variable-width face. |
| `advance` | `advance(font=FONT_5x6, spacing=None, ch=None) -> int` | Pixels from one glyph's left edge to the next. With `ch`, that glyph's own advance; without it, the font's nominal one (the two differ only for wide glyphs like `M`/`W` on a variable-width face). |
| `draw_text` | `draw_text(c, x, y, text, font=FONT_5x6, colour="#ffffff", spacing=None, shadow=None, shadow_offset=(1,1), align="left", width=None) -> int` | Returns the x just past the last glyph. `spacing=None` uses the font's `default_spacing`. `align` needs `width`. |
| `text_width` | `text_width(text, font=FONT_5x6, spacing=None) -> int` | Width in pixels, no trailing gap; sums each character's own `font.width(ch)`. |
| `text_mask` | `text_mask(text, font=FONT_5x6, spacing=None) -> np.ndarray` | Boolean `(font.h, text_width)` ink mask of a whole string. |
| `draw_glyph` | `draw_glyph(c, x, y, ch, font=FONT_5x6, colour="#ffffff") -> int` | One character; returns that glyph's own width. |
| `glyph_mask` | `glyph_mask(ch, font=FONT_5x6) -> np.ndarray` | One character's boolean mask. |

**Digits.** The four 9×13 time cells are filled by one of two helpers:

| Function | Signature | Notes |
|---|---|---|
| `seven_segment` | `seven_segment(c, digit, on="#6cf08a", off=None, slant=0.0, thickness=2, pivot_row=None, glow_colour=None) -> Canvas` | `digit` is `0..9`, `"blank"`/`None`, or `"minus"`/`"-"`. `off` draws unlit segments faintly; leave `None` for a clean LCD. |
| `dot_matrix` | `dot_matrix(c, digit, on="#6cf08a", off=None, pitch=2, dot=1) -> Canvas` | 5×7 dot pattern on a 2px pitch, exactly 9×13 at the defaults. |

The legacy `numbers.bmp` sheet encodes the minus sign as a 5×1 strip cut out
of the `"2"` digit cell (`MINUS_SIGN`, `[20,6,5,1]`) and its absence as the
same strip cut out of the `"1"` cell (`NO_MINUS_SIGN`, `[9,6,5,1]`).
`seven_segment` satisfies this **by construction**: its middle segment (`g`)
always lands on `x=2..6, y=6` and is never lit for digit `"1"`, so the strip
the legacy sheet reads out of each cell is correct without any special case.
`dot_matrix` cannot supply this — the builder patches the two legacy strips
itself after painting digits, so a theme using `dot_matrix` still produces a
usable `numbers.bmp`, but do not rely on its `"2"`/`"1"` cells looking right
if you inspect them directly at that 5×1 strip.

## 9. plfont — the Sessions-list typeface

Playlist rows are never drawn with a system or TrueType font (`pledit.txt`'s
`Font` key is ignored): every skin ships its own bitmap typeface, built from
your theme and baked to `plfont.bmp` + `plfont.txt` (SPEC §3.2, added by
amendment A1). Both files are not part of `skinspec/sprites.json` — they are
written straight into `<skin>/out/` and the `.wsz` alongside the spec'd
sheets.

**The grid.** 16 columns × 6 rows, row-major. Cell *k* (0..95) holds
character code 32+*k*; the last cell (95) holds the ellipsis `…`.
`cellW = width/16`, `cellH = height/6` — both must divide evenly, or the
skin's `plfont` is ignored with a warning. `pl_font_cell()`'s Base default is
`(8, 10)`, i.e. a 128×60 sheet: cap height 7, x-height 5, descenders 2,
baseline on row 7.

**Pixels are an ink-coverage mask, not colour.** `coverage = mean(r,g,b)/255`
(scaled by alpha for a PNG face): black = no ink, white = full ink, grey =
partial ink. The app composites `tint × coverage` over the row background,
where `tint` is `pledit.txt`'s `Normal` or `Current` colour — so a grey pixel
becomes a soft phosphor halo in whatever colour the skin declares, and
painting your skin's actual green into a cell does nothing useful: paint
white for ink and let the app do the tinting.

**The three theme hooks** (the last methods on `Theme`, under its own
"plfont" heading):

| Method | Returns | Notes |
|---|---|---|
| `pl_font_cell(self)` | `(cellW, cellH)` | Base default `(8, 10)` → 128×60 sheet. Keep ink out of column 0 and the last column so the halo has room; the builder rejects a cell smaller than 3×5 as illegible. |
| `paint_pl_font_glyph(self, c, ch)` | — | `c` is one `pl_font_cell()`-sized canvas, pre-filled black. Paint white for full ink, greys for partial coverage. `ch` is the character; the ellipsis cell is passed as `"…"`. |
| `pl_font_metrics(self)` | `dict` | `plfont.txt` `[PlaylistFont]` keys: `Monospace` (0/1), `Spacing`, `SpaceWidth`, `RowHeight`, `OffsetY`. A key whose value is `None` is omitted so the app's own default applies. **`RowHeight` replaces `layout.playlist.rowHeight`** — it is the actual row pitch once a skin ships a `plfont`. |

The palette attribute `pl_font_halo` (default `0.28`, see §4) is what the
stock `paint_pl_font_glyph` passes to `fonts.halo` for its glow; `0` disables
it for crisp, halo-free ink.

**The advance rule (SPEC §3.2)**, shared byte-for-byte by the builder, the
validator, and the preview compositor, so all three agree to the pixel: an
*ink column* is a cell column containing a pixel whose coverage is `>= 0.5`.
With `L`/`R` the first/last ink column, `advance = R - L + 1 + Spacing`, and
the blitted source columns are `[L-1, R+1]` clipped to the cell, placed at
`pen - 1` — so a 1px halo survives the blit and simply overlaps the spacing.
A cell with no ink column advances `SpaceWidth`. `Monospace` blits the whole
cell at the pen and advances `cellW`. The implementation, in `fonts.py`:

| Function | Signature | Notes |
|---|---|---|
| `plfont_cell_chars` | `plfont_cell_chars() -> list[str]` | The 96 characters of the grid in cell order: codes 32..126, then `…`. |
| `plfont_cell_index` | `plfont_cell_index(ch) -> int` | Grid cell number for a character; falls back to the `?` cell. |
| `plfont_cell_rect` | `plfont_cell_rect(ch, cell_w, cell_h) -> (x,y,w,h)` | A character's cell inside the sheet. |
| `plfont_rows` | `plfont_rows(ch, glyphs=None) -> tuple[str,...]` | The `'#'`/`'.'` rows of a character in the default (`PLFONT_8x10`) face. |
| `draw_plfont_glyph` | `draw_plfont_glyph(c, ch, glyphs=None, ink="#ffffff", x=0, y=0) -> Canvas` | Paints one glyph as full-coverage ink; this is what `paint_pl_font_glyph`'s default implementation calls. |
| `plfont_ink_columns` | `plfont_ink_columns(cell, threshold=0.5) -> (L,R) \| None` | The `(L, R)` of the advance rule above, or `None` for a blank cell. |
| `plfont_advance` | `plfont_advance(cell, spacing=1, space_width=None, monospace=False) -> int` | The pen-advance half of the same rule. |
| `fold_to_ascii` | `fold_to_ascii(text, keep=PLFONT_ELLIPSIS) -> str` | SPEC §3.2 text policy: strip diacritics, map smart punctuation, turn anything still outside 32..126 into `?`. |
| constants | `PLFONT_COLUMNS=16`, `PLFONT_ROWS=6`, `PLFONT_CELLS=96`, `PLFONT_ELLIPSIS="…"` | |

**Derivation helpers.** You are expected to *derive* your face from the
default rather than hand-draw 96 glyphs:

| Function | Signature | Example |
|---|---|---|
| `embolden` | `embolden(rows, dx=1, dy=0) -> tuple[str,...]` | `fonts.embolden(fonts.plfont_rows("a"))` — a one-line bold cut. |
| `slant_rows` | `slant_rows(rows, amount=0.25, pivot=None) -> tuple[str,...]` | `fonts.slant_rows(fonts.plfont_rows("M"), 0.3)` — italicise. |
| `dot_matrixise` | `dot_matrixise(rows, pitch=2, dot=1, cell=None) -> tuple[str,...]` | `fonts.dot_matrixise(fonts.plfont_rows("5"), pitch=2)` — an LED-panel face. |
| `halo` | `halo(c, radius=1, strength=0.35, threshold=128, colour="#ffffff") -> Canvas` | `fonts.halo(c, radius=1, strength=0.3)` — grey partial-ink coverage around solid ink; never dims ink that is already there. |

```python
def paint_pl_font_glyph(self, c, ch):
    rows = fonts.plfont_rows(ch)          # the default 8x10 face's rows
    rows = fonts.slant_rows(rows, 0.2)    # italicise
    rows = fonts.embolden(rows, dx=1)     # then bold it
    fonts.draw_plfont_glyph(c, ch, glyphs={ch: rows}, ink="#ffffff")
    fonts.halo(c, radius=1, strength=self.pl_font_halo)
```

## 10. Previewing and validating

```
python3 skins/build.py <name>              # build one skin folder under skins/
python3 skins/build.py base walnut76       # build several
python3 skins/build.py --all               # build every folder with a theme.py
python3 skins/build.py base --no-preview   # skip preview rendering
python3 skins/build.py base --no-validate  # skip the validator
```

Each run writes:

- **`<skin>/out/`** — the loose 24-bit BMP sheets, `plfont.bmp` (the
  Sessions-list typeface, SPEC §3.2 — always built, even though it isn't a
  `sprites.json` sheet), and `viscolor.txt` / `pledit.txt` / `plfont.txt` /
  `readme.txt`.
- **`skins/dist/<Name>.wsz`** — the flat, deflated zip the app actually loads
  (entries have no directory prefix).
- **`<skin>/preview/`** — `main.png` / `shade.png` / `eq.png` / `playlist.png`
  / `all.png` at 1×, the same set again as `*_4x.png` at 4× nearest-neighbour,
  and a labelled `sheets.png` contact sheet. The previewer never imports
  `skinkit.theme` or `skinkit.builder` — it only reads the built sheets back
  through `skinspec/sprites.json`, so a correct preview is independent proof
  that every sprite really is where the spec says it is.

Then validate directly:

```
cd skins && python3 -m skinkit.validate dist/Base.wsz
cd skins && python3 -m skinkit.validate base/out
cd skins && python3 -m skinkit.validate --require-plfont base/out
```

`build.py` always validates with `require_plfont=True` — a missing Sessions-
list typeface fails the build for Tokenamp's own skins (a third-party skin
without one just falls back to Base's `plfont`, so `--require-plfont` is
opt-in when calling the validator directly).

`skinkit.validate` (also run automatically by `build.py` unless
`--no-validate`) checks, from a built `.wsz` or loose `out/` folder:

- every required sheet is present and **exactly** the size `sprites.json`
  declares;
- a `.wsz` is a **flat** zip (no directory prefixes in its entries);
- `viscolor.txt`, `pledit.txt`, `readme.txt` are present;
- every pressed/selected sprite differs from its normal counterpart (an
  explicit list of ~35 sprite pairs across every sheet — buttons, toggles,
  thumbs, lamps, the play/pause/stop icons, the work LED, title bars);
- every clutter-bar pressed column differs from the unpressed bar and from
  every other letter's column, and the disabled bar differs from the normal
  one;
- the shade position thumb's left/center/right pieces are pairwise distinct;
- the volume, balance, and EQ slider frame strips have frame 0 different from
  the last frame, are not all identical, and have at least half their frames
  mutually distinct;
- no two digit sprites in `numbers.bmp`/`nums_ex.bmp` are identical (including
  the blank), and `MINUS_SIGN` differs from `NO_MINUS_SIGN`;
- no `text.bmp` glyph renders as blank (matches the space cell) and no two
  glyphs are identical;
- `viscolor.txt` parses to exactly 24 valid colour lines, and line 0 equals
  the pixel one inset into `main.bmp`'s `visualizer` rect;
- `pledit.txt` has `Normal`, `Current`, `NormalBG`, `SelectedBG`, and `Font`;
- **`plfont.bmp`/`plfont.txt`** (SPEC §3.2): if a `plfont.bmp`/`.png` is
  present its checks are unconditional failures — `--require-plfont` only
  decides whether the *absence* of one is itself a failure (Tokenamp's own
  skins) or silently accepted (third-party skins, which fall back to Base's
  face). When present: width divides evenly by 16 and height by 6; every
  printable glyph 33..126 plus the ellipsis has at least one ink column;
  every letter/digit glyph (and the ellipsis) is visually distinct from every
  other; look-alike pairs (`I`/`l`, `O`/`0`, `S`/`5`, …) that differ by 2
  pixels or fewer are reported as **warnings**, never failures; if
  `plfont.txt` is present, it has a `[PlaylistFont]` section, `RowHeight` is
  not smaller than the cell height, and `Monospace` is `0` or `1` — a missing
  `plfont.txt` is itself only a warning, and only under `--require-plfont`.

## 11. Traps

- **Pressed art must move.** `press_offset(pressed)` returns `(1, 1)` when
  pressed — shift the icon by that amount — **and** the bevel must invert
  (`fx.bevel_double(..., raised=False)` via `button_face(c, pressed=True)`).
  Moving the icon without inverting the bevel (or vice versa) reads as broken,
  not pressed.
- **Thumbs are fully opaque.** Position/volume/balance/EQ/scroll-handle/shade
  thumbs float over a frame in classic skins; end a thumb painter with
  `c.a[:, :, 3] = 255` (most base-class thumb painters already do this, but a
  material that touches alpha, e.g. a mask, can undo it).
- **Glyph cells are exactly 5×6 with no bleed.** Column 4 is the inter-glyph
  gap (`FONT_5x6.default_spacing == 0`); ink in column 4 leaks into the next
  character on-screen.
- **`plfont` cells are ink-coverage masks, not colour art.** `paint_pl_font_glyph`
  must paint on the greyscale scale from black (no ink) to white (full ink);
  painting a hue in there does not mean what it would in `paint_glyph` — the
  app reads luminance and tints the whole glyph with one flat colour, so any
  chroma you paint is simply discarded.
- **`text_background()` must be identical everywhere it is used**: inside
  `paint_glyph`, inside the marquee well, and inside the kbps/khz wells in
  `paint_main_background`. If they disagree, glyphs show a visible seam
  against the well they sit in.
- **`digit_background()` must match the time well's interior colour** that
  `paint_main_background` painted. Same failure mode as above, for digits.
- **`viscolors()[0]` must equal the colour painted at
  `layout.main.visualizer`** — the validator fails the build otherwise (it
  checks the actual built pixel against line 0 of `viscolor.txt`).
- **Nothing dynamic may be baked into a well.** Marquee text, digit values,
  slider fill, and the EQ curve are drawn by the app at runtime; a well's
  painter (`paint_main_background`, `paint_eq_background`, etc.) provides only
  the frame and the flat interior colour.
- **Keep the far-left and far-right ~20px of every main title-bar variant
  identical.** `MAIN_TITLE_BAR(_SELECTED)`, `MAIN_SHADE_BACKGROUND(_SELECTED)`,
  and `MAIN_EASTER_EGG_TITLE_BAR(_SELECTED)` all share **one** baked title-
  button sprite pair (options/minimize/shade or unshade/close), taken from the
  active main title bar. If those edges differ between variants, the shared
  buttons will show a seam against whichever variant they were not painted
  from.
- **`MAIN_SHADE_BACKGROUND_SELECTED` and `MAIN_SHADE_BACKGROUND` overlap by
  one row inside `titlebar.bmp`**: rows 29..42 and 42..55 respectively (row 42
  is shared). Give both variants the same top and bottom border row so the
  shared row is consistent either way it gets read.
- **The shuffle and repeat layout rects overlap by 1px at x=210** (`shuffle`
  is `[164,89,47,15]`, right edge at x=210; `repeat` is `[210,89,28,15]`,
  starting at x=210). Painting either widget's edge column inconsistently will
  show as a seam between the two buttons.
- **The 3px work indicator at (24,28) is covered by the 9×9 play-state icon at
  (26,28)**: only the work indicator's left 2 columns (x=24,25) are ever
  visible on screen; its third column (x=26) is always painted over.
- **Every sheet must come out at its exact spec size.** The builder raises
  `ValueError` if a painter's canvas doesn't match its sprite rect, and the
  validator separately checks every sheet's final BMP dimensions — get either
  one wrong and the build fails loudly rather than shipping a misaligned skin.
- **Playlist tiles must be invariant along the axis they repeat on.**
  `paint_pl_left_tile`/`paint_pl_right_tile` are tiled *vertically*, so their
  material must be y-invariant — no vertical gradient, and any noise sampled
  with a huge `sy` (`_pl_plate(c, repeat="v")` does exactly this).
  `paint_pl_top_tile`/`paint_pl_bottom_tile` are tiled *horizontally*, so they
  must be x-invariant (`_pl_plate(c, repeat="h")`), and any repeating detail
  inside them needs a pitch that divides the tile width — the top tile is
  25px wide, so a grip pitch of 5 works and a pitch of 4 shows a phase jump
  at every seam. A bevel with edges perpendicular to the repeat axis prints a
  seam line at every tile boundary — that is why `paint_pl_right_tile` draws
  its scrollbar groove with vertical rim lines only, never a sunken bevel.
- **plfont ink belongs in columns 1..(cellW-2), never column 0 or the last
  column.** The advance rule's blit reads `[L-1, R+1]`; ink flush against
  either edge gets clipped instead of gaining the 1px halo margin it needs.
- **`plfont.txt`'s `RowHeight` must be `>= cellH`**, or playlist rows clip
  each other — the validator fails this outright, not as a warning.
- **Give your plfont face descenders.** A face with none (every glyph sitting
  on the baseline) reads as a spreadsheet, not a designed list; `q g j p y`
  dropping below the baseline is what sells it.

## 12. A worked example

```python
from skinkit.theme import Theme
from skinkit.canvas import darken, lighten
from skinkit import fx


class BrushedSteel(Theme):
    name = "BrushedSteel"
    author = "artist"

    # -- override the palette; every painter below reads these tokens ----
    face_hi = "#c9ccd1"
    face = "#9aa0a8"
    face_lo = "#6b7178"
    edge_light = "#eef1f4"
    edge_mid = "#7d838a"
    edge_black = "#101214"
    btn_face = "#8b9299"

    def paint_main_background(self, c):
        # brushed_metal samples in *window* space (c.origin == (0,0) here),
        # so the grain runs straight across every widget cut out of it.
        fx.brushed_metal(c, self.face, direction="h", strength=0.22, seed=self.seed)
        fx.bevel_double(c, outer_light=self.edge_light, outer_shadow=self.edge_black,
                         inner_light=lighten(self.face, 0.1),
                         inner_shadow=darken(self.face, 0.3))
        # MAIN_SCREWS is geometry, not palette -- keep it, just re-skin it
        for sx, sy in self.MAIN_SCREWS:
            fx.screw(c, sx, sy, r=2, style="phillips", body=self.edge_mid,
                     light=self.edge_light, shadow=self.edge_black)
        # call super() to keep the wells, labels, and clutter bar from Theme
        super().paint_main_background(c)

    def paint_transport(self, c, which, pressed):
        self.button_face(c, pressed)          # raised, or pressed + inverted bevel
        dx, dy = self.press_offset(pressed)   # (1,1) when pressed, (0,0) otherwise
        if which == "play":
            self._tri(c, c.w // 2 - 3 + dx, c.h // 2 - 4 + dy, 7, 9, "right", self.icon)
        else:
            super().paint_transport(c, which, pressed)


THEME = BrushedSteel()
```
