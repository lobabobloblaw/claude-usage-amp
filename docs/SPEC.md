# Tokenamp — specification

Tokenamp is a native macOS (26 "Tahoe", Apple silicon) app that shows the user's Claude account
usage in near real time, presented as a faithful Winamp 2.x-style player: a 275×116 bitmap-skinned
main window, an "equalizer" window, a "playlist" window, magnetic docking, window-shade mode, and
hot-swappable skins in the **real classic Winamp skin format** (`.wsz`), so that third-party classic
skins load too.

It really whips the llama's tokens.

> **Amendments** (newer than some of the code — if the implementation disagrees, the spec wins):
> **A1 (2026-09-20, user feedback):** the Sessions/playlist rows must not use a generic system font.
> They are drawn with a per-skin bitmap typeface, `plfont` — see §2.4 and §3.2. This supersedes every
> earlier mention of "vector text" for playlist rows.
> **A3 (2026-09-20, user request):** the visualiser is no longer only a strip in the faceplate.
> It also has a window of its own, **Token Flow** - a vector phosphor field with five configurations
> that the state of the account modulates and can switch between on its own. See §2.9 and §3.3. The
> faceplate well in §2.1 is unchanged; the new window is an addition, off by default.
> **A2 (2026-09-20, user feedback):** a fixed 2× default is far too large on a 1920×1200-point HiDPI
> screen (the docked stack was 550×928 pt). Scale is now expressed in **device pixels per skin pixel**
> so half steps are available on Retina, and the default is chosen from the screen — see §2.8. This
> supersedes "Scale ▸ 1× 2× 3×", "scale (default 2)" and "cycles scale 1×→2×→3×" wherever they appear.

Toolchain on this machine: Swift 6.3 via Command Line Tools only. **No Xcode, no XCTest, no
xcodebuild.** Everything builds with `swift build` and a shell script assembles the `.app`.
Python 3.14 with Pillow 12 and numpy 2 is available for skin tooling.

## 1. Repository layout

```
Package.swift                 5 targets, see the comment at its top (do not restructure)
skinspec/sprites.json         THE sprite map + window layout. Single source of truth.
docs/SPEC.md                  this file
Sources/UsageModel/           contract: UsageSnapshot, UsageProvider, DemoUsageProvider   [done, frozen]
Sources/UsageCore/            real data layer                                              [data worker]
Sources/usage-dump/           CLI over UsageCore                                           [data worker]
Sources/TokenampKit/          skin engine, renderer, windows, app delegate                 [UI worker]
Sources/Tokenamp/main.swift   executable entry; wires a provider into TokenampKit          [UI worker]
scripts/build_app.sh          swift build -c release + assemble build/Tokenamp.app         [UI worker]
scripts/gen_sprites_swift.py  sprites.json -> Sources/TokenampKit/Skin/Sprites.generated.swift [UI worker]
skins/skinkit/                Python skin-painting toolkit                                 [toolkit worker]
skins/base/                   plain reference skin built with skinkit                      [toolkit worker]
skins/<name>/                 one folder per art skin                                      [skin artists]
skins/dist/*.wsz              built skins (what the app bundles)
build/Tokenamp.app            output
```

`Sources/UsageModel` is frozen. If it is genuinely insufficient, do not edit it: say so in your
final report and work around it.

Parallel workers share this checkout. Stay inside the paths assigned to you, and always build with
your own scratch path (`swift build --scratch-path .build-<yourname> --target <yours>`) so builds
do not fight over `.build`.

## 2. Usage → Winamp mapping

The metaphor: **each plan limit is a track.** The account's limits (session 5h, weekly all-models,
weekly per-model) are the tracklist of the main window; `⏮`/`⏭` choose which one is the *hero
track*. The hero track drives the big time display, the seek bar and the marquee. Session and
weekly utilisation are always visible on the volume and balance sliders regardless of hero track.

### 2.1 Main window (275×116)

| Winamp element | Shows | Interaction |
|---|---|---|
| Time digits (4, `MM:SS` shape) | Hero limit: time until reset. ≥ 1 h → `HH:MM`; < 1 h → `MM:SS` (ticks every second). Minus sign shown in "remaining" mode. No limits available → wall clock `HH:MM`. | Click toggles remaining ⇄ elapsed (time since the window opened), like Winamp's time display. |
| Marquee (scrolling 5×6 bitmap font, 154 px wide) | `<n>. <HERO TITLE> - <pct>% USED - RESETS <H:MM AM/PM or DAY H AM> *** SESSION <p>% *** WEEK <p>% *** <PLAN> *** BURN <x>K TOK/MIN *** TODAY <tokens> / $<cost> *** <status>` then loops with ` *** ` separator. Status reports data problems (`LIVE: AUTH EXPIRED - OPEN CLAUDE CODE`, `SCANNING 41/323`, `PAUSED`). | Hovering any gauge temporarily replaces the marquee with that gauge's exact reading (see 2.5). Dragging on the marquee scrubs the text, as in Winamp. |
| kbps field (3 glyphs) | Burn rate: fresh tokens/min in thousands, right-aligned, capped `999`. | — |
| kHz field (2 glyphs) | Active sessions (activity in last 2 min), capped `99`. | — |
| mono / stereo lamps | `mono` lit = local transcripts only. `stereo` lit = live account data OK (both sources). Neither lit = paused/stopped. | — |
| Play-state icon | play = running, pause = paused, stop = stopped. Work indicator LED lights for 600 ms whenever new data (either source) lands. | — |
| Visualizer 76×16 | Token flow for the last 6 min 20 s from `snapshot.fine` (76 × 5 s buckets). **Spectrum mode**: 19 bars × 4 px (3 px bar + 1 px gap); bar *j* = mean cost of fine buckets `4j..<4j+4`, newest at the right; log-ish scaling; bars ease toward targets (fast attack, slow decay) and carry falling peak caps, coloured by `viscolor.txt` 2..17 by height, caps colour 23. While a bar's bucket is "hot" (includes the current 10 s) add a small per-frame shimmer so live work visibly dances. **Oscilloscope mode**: one column per fine bucket, a connected line around the vertical centre whose excursion follows cost, colours 18..22 by distance from centre. Background colour 0 with a dot grid of colour 1 (every 2nd px on every 2nd row… match Winamp: dots at even x on odd y). | Click cycles spectrum → scope → off. |
| Position (seek) bar | Hero limit: elapsed fraction of its window (thumb travels 0..219 px). Hidden thumb when unknown. | Read-only (press feedback only: thumb shows its pressed sprite while held; marquee shows the reading). |
| Volume slider | **Session** limit utilisation 0–100 %: thumb x = 107 + pct·51/100, background frame = round(pct·27/100) (the classic green→red heat ramp). | Read-only; hover/press shows reading. |
| Balance slider | **Weekly all-models** utilisation: thumb x = 177 + pct·24/100, frame = round(pct·27/100). | Read-only; hover/press shows reading. |
| ⏮ / ⏭ | Previous / next hero track (wraps). | |
| ▶ | Resume if paused/stopped, and `refreshNow()`. | |
| ⏸ | Toggle `isPaused`. | |
| ⏹ | Stop: paused + visualizer decays to zero + lamps off. | |
| ⏏ (eject) | "Load Skin…" open panel (`.wsz`, `.zip`, or a folder). | |
| Shuffle | Auto-cycle hero track every 8 s. | toggle, persisted |
| Repeat | Threshold alerts: a user notification when any limit crosses 75 / 90 / 100 % (once per limit per window). | toggle, persisted |
| EQ / PL buttons | Show/hide Equalizer / Playlist windows. | toggle, persisted |
| Clutterbar O A I D V | **O** options menu · **A** always on top · **I** about/info panel (data sources, last fetch, token expiry, paths) · **D** double size (cycles scale 1×→2×→3×) · **V** cycles visualizer mode. | |
| Title bar | Drag to move (whole background also drags). Double-click toggles window-shade. Buttons: options menu, minimise, shade, close (= quit app). | |

### 2.2 Window-shade mode (275×14)

`MAIN_SHADE_BACKGROUND(_SELECTED)`; hero countdown as four text-font glyphs at the `shade.timeGlyphs`
positions; mini position bar (17×7, 3-px thumb whose sprite is LEFT/centre/RIGHT third by position);
mini visualizer 38×5 (19 bars × 2 px from the same data, single colour = viscolor 18... use 2..17 by
height scaled to 5 rows); hit zones for the mini transport buttons; options/minimise/shade/close.
A shaded, always-on-top strip is the app's "glanceable" form, so it must work well.

### 2.3 Equalizer window (275×116) — "Usage Equalizer" (closed by default)

- 10 band sliders = the last 10 time buckets, oldest left, newest right. Range is chosen from the
  PRESETS button popup: **Last 10 hours** (default) / **Last 10 days** / **Last 10 minutes**, and the
  measure: **Cost (API-equivalent)** (default) / **Output tokens** / **All tokens**.
- Slider position = value normalised to the max of the 10 (ON lit = relative scale, default) or to a
  fixed log scale (ON unlit: $0.01…$100 for cost, 1k…100M for tokens). Background frame index = round(v·27).
- AUTO lit = rotate the range every 10 s.
- Preamp slider = the model-scoped weekly limit % if one exists, else weekly-all %.
- Graph (113×19): smooth curve through the 10 band values; pixel colour at row y from
  `EQ_GRAPH_LINE_COLORS` row y; preamp level drawn with `EQ_PREAMP_LINE`.
- Sliders are read-only gauges; hovering shows `T-3H: 1.24M TOK  $4.10` style readings in the main marquee.
- Title bar drag, close button hides the window.
- **Closed on a first run**, and opened from the main window's EQ button or Windows ▸ Equalizer:
  every slider here is a read-only gauge, so unlike the other three windows it earns its place on
  screen only when it is asked for.

### 2.4 Playlist window (275×232 default, vertical resize in 29 px steps) — "Sessions"

- Rows = `snapshot.sessionsToday`: `N. <project> - <MODEL>` left, right-aligned cost (`$12.40`) or
  tokens (`1.2M`) — toggled from the context menu, default cost.
- Text is drawn with the **skin's own bitmap typeface** (`plfont`, §3.2) in skin pixels, crisp and
  nearest-neighbour scaled like every other element — never with a system/vector font (amendment A1:
  a generic Arial list inside hand-made pixel hardware looks pasted-on). Colours from pledit.txt tint
  the glyph mask: `Normal`, `Current` for active sessions, `NormalBG` list background, `SelectedBG`
  for the clicked row. Double-click a row opens its `cwd` in Finder.
- Scroll with the wheel and the skin's scroll handle.
- Bottom-right info text (text-font): `<n> SESS  $<today cost>`; mini time = hero countdown.
- Frame assembled from the pledit.bmp pieces: tile the top/bottom/side tiles, centre the 100 px
  title piece, then corners. Close button hit-zone in the top-right corner hides the window.

### 2.9 Token Flow window (275x232 default, resizable in 25x29 px steps) - the visualiser module (amendment A3)

A fourth window, **open by default** - the third in the stack, under Sessions - and toggled from
the clutterbar **V** button (which lights while it is open) or Windows > Token Flow. A window nobody
knows about is a window nobody opens.
Its frame comes from the `gen` sheet (§3.3) and its interior is one **phosphor field** (§3.3) drawn
in skin pixels through the skin's own `viscolor.txt`.

**The five configurations.** Each is a different geometry for the same field, not a different chart:

| | Draws | Reads |
|---|---|---|
| **SCOPE** | Bipolar trace over the last 6 min 20 s, scrolling continuously past a beam head pinned at the right edge (it slides by the fraction of the newest 5 s bucket elapsed, so the tail is a motion trail rather than a smear of a jump every five seconds): output above the axis, input + cache writes below, cache reads as a mirrored echo behind both. One trace per active session, so parallel work interferes on one axis. Messages punch through as blips; a comet marks `now`. | `fine` |
| **STRATA** | The ledger: one riser per bucket with a tick where each fresh class ends, an outline over the total, cache reads as a ghost behind, and the **pace line** - the rate that lands exactly on the reset without hitting the wall. Span from the context menu or the wheel: last hour / last day / last 10 days. | `minutes`, `hours`, `days` |
| **WEB** | The connectome: a hub, one node per model in play, one per session today. Node radius by tokens, brightness by recency, a pulse ring while live, edge energy by flow. Active sessions are held near the hub, idle ones drift to the rim. Names are set in the skin's `text.bmp` font. | `sessionsToday` + snapshot diffs |
| **ORBIT** | The polar wall: angle is position in the limit window, radius is how hard the work was, and the rings *are* the limits - session inside, weekly outside - with the consumed arc filling each. Past 85 % the ring sheds sparks where the arc presses on it. | `limits`, `hours`, `minutes` |
| **PHASE** | The return map: the flow now against the flow 15 s earlier, trailed. Steady work sits on the diagonal and every burst-and-recover cycle throws a loop off it, so the figure is the *rhythm* of the work. Plotting one token class against another was tried first and collapses onto a line whenever the mix is steady. | `fine` |

**The modulators** ride on whichever configuration is up, and are pure functions of the snapshot:
**pressure** (tightest limit - biases the palette hot and closes a visible wall in past 55 %),
**energy** (burn rate, faded down by idleness), **persistence** (the phosphor time constant: bursty
work keeps a long tail, steady work a short one), **echo** (the cache-read layer), **phase**
(where you are between resets), **beams** (one per active session).

Persistence applies only where something genuinely moves between frames - SCOPE's scroll, WEB's
pulses, ORBIT's arm. STRATA and PHASE are plots: they stand still until the data rolls and then
jump, so a long tail there would smear the jump rather than draw motion, and they get a short fixed
one instead.

**AUTO** (the title-bar lamp, or the context menu) lets the field choose: idle -> ORBIT, or STRATA
when there is history to read; one steady session -> SCOPE; two or more live -> WEB; a critical
limit or a reset within 10 minutes -> ORBIT, overriding. A choice holds for 24 s before another can
take over - a debounce, not a rate limit, so one poll that momentarily sees a second session
cannot flip a steady display. A critical limit still cuts in at once.

**Interaction.** Click the field to step to the next configuration (this also leaves AUTO); the
lamp toggles AUTO; the wheel changes the STRATA span; right-click picks a configuration or span
directly; drag the title bar to move, the bottom-right grip to resize; the close button hides it.
The bottom bar reads `<CONFIGURATION> [SPAN]` on the left and `<BURN>/MIN  <WORST LIMIT>%` on the
right, in the classic 5x6 font. Hovering the field writes its reading into the main marquee (§2.5).

`UsageModel` is frozen and carries only per-session *totals*, so WEB's per-node flow is recovered by
diffing successive snapshots in the controller (`SessionFlowTracker`) rather than by extending the
model.

### 2.5 Hover readings (marquee override, 1.5 s linger)

volume → `SESSION: 42% USED - RESETS IN 2H47M` · balance → `WEEK (ALL): 17% USED - RESETS MON 1PM` ·
posbar → `<HERO>: 2H13M ELAPSED / 2H47M LEFT` · kbps → `BURN: 128K TOK/MIN  $38.20/HR` ·
kHz → `2 ACTIVE SESSIONS` · mono/stereo → source status · visualizer → `TOKEN FLOW - LAST 6 MIN` · Token Flow field → `<CONFIGURATION>: <what it reads>` ·
EQ band / preamp → as in 2.3.

### 2.6 Menus and persistence

Right-click anywhere (and the options button, and clutterbar O) opens the options menu:
Skins ▸ (bundled skins, user skins, separator, Load Skin…, Open Skins Folder, Reload Current) ·
Scale ▸ 1× 2× 3× · Always on Top · Windows ▸ Equalizer / Playlist / Window Shade ·
Windows ▸ Token Flow · Visualizer ▸ Spectrum / Oscilloscope / Off · Data ▸ Live Plan Limits (toggle), Refresh Now,
Poll Every ▸ 30 s / 1 min / 2 min / 5 min, Playlist Shows ▸ Cost / Tokens, Demo Data (toggle) ·
Menu Bar Readout (toggle; an `NSStatusItem` showing `42%·2h47m`) · About Tokenamp · Quit.

The app is a regular Dock app with a minimal main menu (About, Quit ⌘Q, Window). Persist in
`UserDefaults`: skin path, scale (default 2), window origins, which windows are open, shade state,
always-on-top, toggles, visualizer mode, EQ range/measure, poll interval, and the Token Flow
window's origin, size, open state, configuration, AUTO and span. Dropping a `.wsz`/`.zip`/folder
onto any window loads it as the skin and copies it into the user skins folder
`~/Library/Application Support/Tokenamp/Skins/`.

### 2.7 Docking

Borderless, non-resizable (except playlist height) windows. While dragging, a window snaps when any
edge comes within 8 skin-px·scale of another Tokenamp window's edge or of the screen's visible frame.
Windows that are docked to the main window (edge-adjacent, transitively) move with it when the main
window is dragged. **Only the main window carries its group**: a sub-window that dragged its
neighbours along could never be pulled out of a stack, because everything it touched would move with
it and it would never appear to move at all. Default placement: the main window at the top,
**Sessions** under it and **Token Flow** under that, flush. The **Usage Equalizer** takes the foot
of the column but starts closed (§2.3), so the app opens with three windows, not four. A window with
no stored origin is placed at the foot of whatever is on screen when it is opened, rather than
landing on top of another window.

### 2.8 Scale (amendment A2)

- The unit of scale is `ppsp` = whole **device pixels per skin pixel**. Every skin pixel is always
  an exact square of device pixels, so art stays razor sharp at every setting. The on-screen scale in
  points is `ppsp / backingScaleFactor`: on a HiDPI (2×) display the choices are ppsp 2,3,4,5,6 =
  **1×, 1.5×, 2×, 2.5×, 3×**; on a 1× display ppsp 1,2,3 = 1×, 2×, 3×. The Scale menu lists exactly
  the valid choices for the screen the main window is on, labelled in points-scale (`1.5×`), and the
  clutterbar **D** button cycles through them.
- **Default (nothing stored yet):** the largest valid scale `s` (in points) with
  `275·s ≤ 0.22 × visibleFrame.width` and `464·s ≤ 0.62 × visibleFrame.height` (464 = main + EQ +
  default playlist stacked), never below 1×. On 1920×1200 HiDPI that is **1.5×** (main window
  412×174 pt); on a 1440×900 HiDPI laptop 1×; on a 2560×1440 1× display 2×.
- Persist the chosen points-scale. When the main window lands on a screen whose backing factor makes
  the stored scale invalid (e.g. 1.5× on a 1× display), use the nearest valid scale there without
  overwriting the stored preference.
- Window content size is `ceil(skinSize × s)` points (275×1.5 = 412.5 → 413); windows are
  non-opaque with a clear background so the spare half-point column is invisible. Docking/snap maths
  uses the exact scaled skin size, not the rounded window size, so docked windows stay pixel-flush.
- Changing scale keeps the main window's top-left corner fixed and re-lays-out docked windows so
  they stay docked. If the stack would extend past the visible frame, shift it back on screen.
- `--snapshot … --scale N` takes `ppsp` directly (PNG pixels per skin pixel, integer ≥ 1).

## 3. Skin engine

- A skin is a `.wsz`/`.zip` archive or a plain directory. File lookup is **case-insensitive** and
  ignores any directory prefix inside the archive. Images may be `.bmp` or `.png` (a `.png` wins if
  both exist). ZIP reading is in-process: parse the central directory, support methods 0 (stored)
  and 8 (deflate, via the Compression framework, `COMPRESSION_ZLIB` = raw deflate). No temp files.
- Decode with ImageIO into `CGImage`. Sheets smaller than the spec (old skins) must not crash: a
  sprite rect that falls outside its sheet is clipped/omitted.
- Missing optional sheets fall back to the bundled **Base** skin's sheet. A skin missing a required
  sheet still loads with Base fallbacks plus a warning in the info panel. `nums_ex` preferred over `numbers`.
- `viscolor.txt`, `pledit.txt`, `region.txt` parsed leniently (CRLF, comments, stray spaces,
  Latin-1 bytes). `region.txt` is applied as a window shape mask when present (clip drawing and
  hit-testing, clear window background).
- Sprite coordinates come from `skinspec/sprites.json` via the generated Swift table. Never hand-type
  a coordinate in Swift that exists in the JSON.
- **Rendering**: each window is a borderless `NSWindow` with one flipped custom `NSView`. Draw in
  skin pixels through a CGContext scaled by the integer scale factor with
  `interpolationQuality = .none` and antialiasing off for sprites, so every skin pixel is a crisp
  square at 1×/2×/3× on Retina and non-Retina displays. There is **no vector text anywhere in the
  skinned windows** — playlist rows use the skin's bitmap `plfont` (§3.2). Beware the classic trap: `CGContext.draw(image, in:)` in a flipped view draws upside down —
  handle the flip per sprite and verify with a snapshot that text glyphs read correctly.
- Animation: one 30 fps display timer owned by the main window controller invalidates only the rects
  that animate (visualizer, marquee, work LED, seconds digits). Marquee advances 1 glyph-px-step of
  5 px every 220 ms… use the Winamp feel: 1 px per 40 ms step is also acceptable; pick what looks
  right and keep it smooth. Idle CPU must stay low (< 2 % on Apple silicon with all windows open).
- Resource lookup (`ResourceLocator`): `Bundle.main.resourceURL/Skins` when running from the `.app`;
  else `$TOKENAMP_RESOURCES`; else walk up from the executable/CWD to find `skins/dist`.
  Bundled skins are every `*.wsz` in that folder; user skins are in the Application Support folder.

### 3.2 `plfont` — the Sessions-list typeface (Tokenamp extension to the classic format; amendment A1)

Classic Winamp names a Windows system font in `pledit.txt`. Tokenamp instead lets every skin ship a
**bitmap typeface** for the playlist rows so the list belongs to the skin. `pledit.txt`'s `Font` key
is ignored. Nothing in the app is drawn with a system font except the macOS menus and the info panel.

- Files (both optional, same lookup rules as other skin files): `plfont.png` or `plfont.bmp`, and `plfont.txt`.
- **Grid:** 16 columns × 6 rows, row-major. Cell *k* (0…95) holds character code 32+*k*; the cell
  for code 127 holds the ellipsis `…`. `cellW = width/16`, `cellH = height/6`; if either does not
  divide evenly the font is ignored with a skin warning. Recommended cell 8×10 (sheet 128×60): cap
  height 7, x-height 5, descenders 2, real lowercase.
- **Pixels are an ink mask**, not colours: coverage = mean(r,g,b)/255 (× alpha for PNG). Black = no
  ink, white = full ink, greys = partial ink (use them for phosphor halo / LCD ghosting). The app
  composites `tint × coverage` over the row background, where tint = `Normal` or `Current`.
- **Metrics (`plfont.txt`, INI section `[PlaylistFont]`, all optional):** `Monospace=0|1` (default 0),
  `Spacing=1` px between glyphs, `SpaceWidth` (default max(2, cellW/2 − 1)), `RowHeight` = row pitch
  of the list in skin px (default cellH + 1; this replaces `layout.playlist.rowHeight`), `OffsetY`
  = cell top within the row (default 0).
- **Advance.** Proportional (default): an *ink column* is a cell column containing any pixel with
  coverage ≥ 0.5. With `L`/`R` the first/last ink column, advance = `R − L + 1 + Spacing`, and the
  blitted source columns are `[L−1, R+1]` clipped to the cell, placed at `pen − 1` (so a 1-px halo
  survives and simply overlaps the spacing). A cell with no ink column advances `SpaceWidth`.
  Monospace: blit the whole cell at the pen, advance = `cellW`.
- **Text policy.** Fold to ASCII (strip diacritics; curly quotes/dashes → ASCII); anything still
  outside 32…126 → `?`. Too-long left text is truncated with the ellipsis glyph so it never touches
  the right-aligned value column (min gap 4 px).
- **Fallback.** A skin without a usable `plfont` gets the bundled Base skin's `plfont`, tinted with
  that skin's own pledit colours — so third-party classic skins get a pixel list too.
- Toolkit: themes paint it through `pl_font_cell()`, `paint_pl_font_glyph(c, ch)` and
  `pl_font_metrics()`; the Python preview compositor renders rows with the identical algorithm.

### 3.3 `gen` and the phosphor field - the Token Flow window (Tokenamp extension; amendment A3)

**The sheet.** `gen.bmp`/`gen.png`, 152x50, optional, laid out in `skinspec/sprites.json`. It is
*not* the classic Winamp `gen.bmp`: slicing a foreign one at these coordinates would produce
garbage, so a `gen` sheet whose size is not exactly 152x50 is ignored with a warning and the Base
skin's frame is used instead. Every skin therefore gets the window whether or not it ships the
sheet. Pieces: three top pieces plus a 100 px title plate, two side tiles, three bottom pieces, the
close button (normal + pressed) and the AUTO lamp (on + off). The top and bottom tiles repeat
horizontally and must be x-invariant; the side tiles repeat vertically and must be y-invariant.
**No text is baked into the title plate** - the app draws the window title over it in the skin's own
`text.bmp` font, so adding a configuration never means repainting a skin.

**The field.** One accumulation buffer per skin pixel of the well, plus an echo channel, both
decayed every frame and composited through `viscolor.txt`: the bar ramp (2 hot ... 17 dim) for the
beam, the scope ramp (18 ... 22) for the echo, colour 1 for the graticule, and for the saturated
core whichever of colour 23 and colour 2 sits furthest from the background - on a light skin the
core has to be the *darkest* ink, or the trace reads as vanishing into the paper.

- Energy is deposited **per unit of beam path**, so a long sweep and a short one read the same per
  pixel, and it is scaled by `1 - decay`, so persistence changes the length of the tail and not the
  brightness of a settled field.
- Curves are Catmull-Rom sampled at a fixed parametric rate and splatted bilinearly, so the beam is
  bright where it lingers and faint where it flies - the dwell brightness of a real vector display,
  and the reason an oscilloscope, a histogram and a connectome read as one instrument.
- `FieldRenderer.settle` runs the accumulator to convergence over a fixed frame count, with the
  step taken from the persistence (six time constants of the slower channel), so a long tail is as
  bright as a short one and `--snapshot` output is reproducible - exactly as `VisualizerModel.settled`
  is for the faceplate. The live window settles *its own* buffer, so a configuration change, a span
  change or a resize does not show a settled picture that collapses on the next frame.
- The window animates on the app's existing 30 fps clock and only while it is on screen.

### 3.1 Offscreen snapshot mode (required — this is how the work gets verified)

```
Tokenamp --snapshot <outdir> [--skin <path>] [--scale N] [--demo] [--at <unix-seconds>] [--state <name>]
```
Renders, without showing any window or needing Screen Recording permission, PNG files:
`main.png`, `eq.png`, `playlist.png`, `shade.png`, one `field-<configuration>.png` per Token Flow
configuration (§2.9 - one golden cannot show a display whose geometry changes with the state), plus
`all.png` (the three windows docked vertically, main/eq/playlist, as they appear by default). `--demo` uses
`DemoUsageProvider(frozenAt:)` (default `--at` = `DemoUsageProvider.referenceDate`) so output is
reproducible. `--state pressed` renders with play + EQ toggle + volume thumb in their pressed/selected
variants (exercises the alternate sprites). Visualizer bars render at their settled target heights
with peak caps 2 px above. The process exits 0 after writing. Without `--demo` it uses the real
provider, waits up to 8 s for the first live + local data, then renders.

## 4. Data layer (UsageCore)

Implements `UsageProvider` as `LiveUsageProvider` and fills every field of `UsageSnapshot`.

### 4.1 Local transcripts

- Root: `~/.claude/projects/` (honour `$CLAUDE_CONFIG_DIR` if set). Recursively enumerate `*.jsonl`,
  including `<session-uuid>/subagents/**/*.jsonl`. Volume on this machine: ~1,900 files / 5.6 GB
  total, **3.4 GB modified in the last 10 days, 1.5 GB in the last 24 h**. Scanning must therefore:
  only consider files with mtime within the last 10 days; process newest first so today's data shows
  within a second or two; run off the main thread; stream/memory-map rather than load + split whole
  files as Strings; and **pre-filter by bytes** — only lines containing both `"type":"assistant"` and
  `"usage"` are JSON-parsed (the multi-megabyte lines are tool results on `user` lines; never parse those).
- A usage event comes from a line with `type == "assistant"` and a `message.usage` object:
  `timestamp` (ISO-8601 with fractional seconds, UTC), `sessionId`, `cwd`, `message.id`,
  `message.model`, `usage.input_tokens`, `usage.output_tokens`, `usage.cache_creation_input_tokens`,
  `usage.cache_read_input_tokens`, and `usage.cache_creation.ephemeral_5m_input_tokens` /
  `ephemeral_1h_input_tokens` when present. Skip `message.model == "<synthetic>"`.
- **Dedup by `message.id` globally**: one API response is written as several lines (one per content
  block) repeating the same id, and output token counts grow across them. Keep exactly one event per
  id, with the values from the *last* line seen (max of output_tokens). Resumed/forked sessions copy
  old lines into new files — the global id dedup handles that; attribute the event to the first
  session it was seen in.
- Subagent transcripts are attributed to their parent session row (the `<session-uuid>` directory
  name, or the line's `sessionId`, whichever identifies the parent — inspect the real layout).
- Incremental: remember per-file byte offset + size + mtime; on change, parse only appended bytes
  (if the file shrank or its inode changed, re-parse it). Persist per-file parsed events and offsets
  in `~/Library/Application Support/Tokenamp/scan-cache.json` (versioned, written atomically,
  debounced) so relaunch is instant. Evict events older than 11 days.
- Watch the root with an FSEvents stream (file events, ~0.3 s latency) → tail the changed files →
  publish a new snapshot immediately. Also rescan on a 30 s safety timer.
- **Privacy rule for you, the worker:** transcripts contain the user's private conversations and
  sealed project material. The app must extract only the numeric/usage fields above, and while
  developing/debugging you must never print, log or copy message content from transcripts — only
  counts, ids, model names, timestamps and token numbers. Do not open transcript files with the Read
  tool; work with aggregate output from your own code.

### 4.2 Pricing (API-equivalent cost)

Per million tokens, input / output; cache write 5 m = 1.25× input, cache write 1 h = 2× input,
cache read = 0.1× input. Match on lower-cased model id substring, first match wins:

| match | in | out |
|---|---|---|
| `fable`, `mythos` | 10 | 50 |
| `opus-5`, `opus-4-5`, `opus-4-6`, `opus-4-7`, `opus-4-8` | 5 | 25 |
| `opus` (older) | 15 | 75 |
| `sonnet-5` | 2 | 10 |
| `sonnet` | 3 | 15 |
| `haiku-4` | 1 | 5 |
| `haiku-3-5` | 0.8 | 4 |
| `haiku` | 0.25 | 1.25 |
| anything else | 3 | 15 |

User-overridable: if `~/Library/Application Support/Tokenamp/pricing.json` exists it replaces the
table (same shape: ordered list of `{match, input, output}`); write the default file on first run.
When the 5 m / 1 h split is absent, price all cache writes at the 5 m rate.
Display names: `claude-fable-5-1` → `FABLE 5.1`, `claude-opus-5` → `OPUS 5`,
`claude-haiku-4-5-20251001` → `HAIKU 4.5` (strip `claude-`, strip a trailing 8-digit date, family
upper-cased, remaining number parts joined with `.`).

### 4.3 Live plan limits

- Credential: run `/usr/bin/security find-generic-password -s "Claude Code-credentials" -w`, parse the
  JSON, use `claudeAiOauth.accessToken`, `.expiresAt` (ms epoch), `.subscriptionType` (e.g. `max`),
  `.rateLimitTier` (e.g. `default_claude_max_20x` → plan name `MAX 20X`; `default_claude_pro`/`pro` → `PRO`).
  Fallback when the keychain item is absent: `~/.claude/.credentials.json` (same JSON shape).
  **Read-only, always.** Never refresh the token, never write to the keychain, never log or persist
  the token or any part of it, never send it anywhere except `api.anthropic.com` over HTTPS. Re-read
  the credential before each poll (Claude Code rotates it). If it is expired or the API returns 401,
  report `.authExpired` and retry on the normal schedule — Claude Code refreshes it when next used.
- Request: `GET https://api.anthropic.com/api/oauth/usage` with headers
  `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`, `Accept: application/json`,
  `User-Agent: Tokenamp/1.0`. 15 s timeout, ephemeral `URLSession`, no cookies, no cache.
- Response (verified on this account today), abridged:
  ```json
  {"five_hour":{"utilization":0.0,"resets_at":"2026-09-21T01:50:00.324734+00:00"},
   "seven_day":{"utilization":0.0,"resets_at":"2026-09-27T20:00:00.324754+00:00"},
   "seven_day_opus":null,"seven_day_sonnet":null,
   "extra_usage":{"is_enabled":false,"monthly_limit":null,"used_credits":null,"utilization":null},
   "limits":[
     {"kind":"session","group":"session","percent":0,"severity":"normal","resets_at":"2026-09-21T01:50:00.324734+00:00","scope":null,"is_active":true},
     {"kind":"weekly_all","group":"weekly","percent":0,"severity":"normal","resets_at":"2026-09-27T20:00:00.324754+00:00","scope":null,"is_active":false},
     {"kind":"weekly_scoped","group":"weekly","percent":0,"severity":"normal","resets_at":"2026-09-27T20:00:00.324922+00:00",
      "scope":{"model":{"id":null,"display_name":"Fable"},"surface":null},"is_active":false}]}
  ```
  Prefer the `limits` array (kind → `LimitGauge.Kind`; scoped title `WEEK - <DISPLAY_NAME>`). If
  `limits` is absent, build gauges from `five_hour`, `seven_day`, and any non-null `seven_day_<x>`
  objects (`utilization` is already a percentage 0–100). When both exist and `five_hour.utilization`
  has more precision than the integer `percent`, use the more precise value. Note `resets_at` has
  6-digit fractional seconds and may be null. Unknown keys must be ignored; every field optional.
- Poll schedule: immediately on start; every `livePollInterval` (default 60 s) while there was local
  activity in the last 5 min, else every 300 s; immediately on `refreshNow()`, but never more often
  than once per 10 s. HTTP 429 → `.rateLimited`, honour `Retry-After`, else exponential backoff to 15 min.
- Order gauges: session, weekly-all, scoped (alphabetical), other.

### 4.4 usage-dump CLI

`usage-dump [--once] [--no-live] [--json] [--selftest]` — prints the snapshot (human table by default).
`--selftest` runs assertion-style checks on the pure logic (pricing, model display names, dedup,
bucket alignment, ISO-8601 parsing incl. 6-digit fractions, incremental tailing against a temp file
it writes itself, limits JSON parsing incl. the sample above and the fallback shape) and exits non-zero
on failure. This replaces XCTest.

## 5. Skin toolkit and skins (Python)

`skins/skinkit/` is a small package that turns a *theme* (a Python class with painter methods) into
a complete, valid classic skin.

- A theme paints **widgets in window coordinates**; the toolkit cuts them into sheets at the
  coordinates in `skinspec/sprites.json`. The artist never hand-computes a sheet coordinate.
  Every painter receives a canvas whose pixel (0,0) is a known window position, exposed so textures
  (brushed metal, grain, noise) stay continuous across sprite boundaries.
- The toolkit bakes the *normal* state of every widget into `main.bmp`/`eqmain.bmp`, as real skins do.
- Drawing primitives tuned for pixel art at 1×: exact-pixel rect/line/polyline, bevels (raised,
  sunken, double), gradients with optional ordered dithering, seeded value/fbm noise, brushed-metal
  and wood-grain generators, screws/rivets/hex bolts, vents/grilles, LEDs with glow, glass glare
  overlays, drop/inner shadows, alpha compositing helpers, palette quantisation, a complete 5×6 font
  for `text.bmp` (every glyph in `font.rows`), a 3×5 and a 4×5 micro font for engraved labels, and a
  7-segment + dot-matrix digit helper for the 9×13 digits.
- Outputs per skin: all sheets as 24-bit BMP, `viscolor.txt`, `pledit.txt`, a `readme.txt`, zipped to
  `skins/dist/<Name>.wsz`; plus `preview/` PNGs: each window mocked up in a realistic live state
  (marquee text, digits, bars, sliders mid-travel, some buttons pressed) at 1× and 4× nearest-neighbour,
  and a contact sheet of every bitmap.
- `python3 -m skinkit.validate <skin dir or .wsz>` checks sheet sizes, presence, that pressed ≠
  normal for every button, that the 28 slider frames are not all identical, glyph coverage, and
  text-file syntax.

### 5.1 Baked-in labels (Tokenamp's own skins)

Classic skins bake their labels into the bitmaps. Tokenamp's own skins bake labels that match what
the widgets mean *here* (third-party skins will still say "kbps"; that is part of the charm):

| Where (window coords) | Classic label | Tokenamp label |
|---|---|---|
| main title bar, centred | WINAMP | `TOKENAMP` |
| right of the 3-glyph field at (111,43) — free space x≈128..154 | kbps | `K/MIN` |
| right of the 2-glyph field at (156,43) — free space x≈168..210 | kHz | `ACTIVE` |
| mono lamp sprite 27×12 at (212,41) | mono | `LOCAL` |
| stereo lamp sprite 29×12 at (239,41) | stereo | `LIVE` |
| volume gauge 68×13 at (107,57) | (none) | `SESSION` worked into or beside the gauge |
| balance gauge 38×13 at (177,57) | (none) | `WEEK` worked into or beside the gauge |
| shuffle button 47×15 | SHUFFLE | `CYCLE` (+ its lamp) |
| repeat button 28×15 | (repeat glyph) | `ALERT` or a bell glyph (+ its lamp) |
| EQ / PL toggle buttons | EQ / PL | `EQ` / `PL` (kept) |
| clutterbar | O A I D V | `O A I D V` (kept) |
| transport | ⏮ ▶ ⏸ ⏹ ⏭ ⏏ | same iconography |
| EQ title bar | WINAMP EQUALIZER | `USAGE EQUALIZER` |
| EQ buttons | ON / AUTO / PRESETS | `ON` / `AUTO` / `RANGE` |
| EQ preamp caption | PREAMP | `WEEK` |
| EQ band captions (10) | 60 … 16K | `-9 -8 -7 -6 -5 -4 -3 -2 -1 NOW` |
| EQ scale captions | +12 db / 0 / -12 db | `MAX` / `MID` / `0` |
| playlist title piece (100×20) | WINAMP PLAYLIST | `SESSIONS` |

Four art skins ship in addition to Base: **Bulkhead** (amber CRT in worn gunmetal), **Walnut 76**
(teal glass, walnut and champagne aluminium), **Amethyst** (purple-and-gold circuit board) and
**Bookcloth** (an Anthropic-centric, fan-made tribute: clay-orange book cloth, ivory paper, slate
letterpress ink — the one light skin). Their art direction lives in each skin's own `BRIEF.md`.
