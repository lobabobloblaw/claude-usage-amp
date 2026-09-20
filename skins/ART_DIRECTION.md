# Tokenamp skins — shared art direction

You are a pixel artist painting a complete classic-format Winamp skin **in code**. The canvas is tiny
(main window 275×116) and shown at 2× nearest-neighbour, so *every single pixel is visible and must be
deliberate*. The bar is the best of the classic skin scene: the skins people kept for a decade because
they looked like physical objects you could touch.

## What "hyperdetailed" means here

1. **Material realism at pixel scale.** Every surface has a material: grain, brushing, weave, speckle,
   wear. No flat fills larger than ~6×6 px anywhere except display wells. Textures are sampled in
   window coordinates so they run continuously under and across widgets.
2. **One light source, top-left, always.** 1-px highlights on top/left edges, 1-px core shadows on
   bottom/right, a softer 1–2 px contact shadow under anything raised, inner shadow at the top/left
   of anything recessed. Specular glints are single hand-placed pixels. Never mix light directions.
3. **Depth in layers.** At least four distinct depth levels: recessed wells (displays, grooves),
   the faceplate, raised controls, and things standing proud of controls (caps, jewels, needles).
   Pressed states physically move: art shifts +1,+1, bevel inverts, contact shadow disappears, the
   face darkens slightly. Selected/lit states glow: lamp core near-white, body saturated, 1–2 px of
   bloom spilling onto the surrounding surface.
4. **Micro-detail that rewards looking.** Fasteners (with varied slot rotation), seams between
   panels, vents, engraved/silk-screened micro labels (3×5 / 4×5 fonts), serial numbers, tick scales,
   tiny warning marks, edge wear, scratches, fingerprints of use near controls, a maker's plate.
   Aim for **25+ distinct kinds** of detail across the three windows; list them in your report.
5. **Ramped, limited palette.** Build each material from a 5–8 step ramp (shadow → midtone →
   highlight, hue-shifted: shadows cooler/more saturated, highlights warmer/lighter). Use ordered
   dithering only where a ramp step would band visibly. Total distinct colours will be large because
   of noise, but every colour must belong to a ramp.
6. **One object, three windows.** Main, equalizer and playlist are one family of hardware — stacked
   components of the same system, sharing materials, fasteners, typography and lamp colours.
   The equalizer and playlist get the same care as the main window.
7. **Function first.** This is a usage monitor. Time digits, marquee text, the kbps/kHz fields, the
   volume/balance gauges and the visualizer must be *instantly* legible at 2×. Highest contrast in the
   skin belongs to the displays. Labels from SPEC §5.1 must be readable.

8. **Your own typefaces.** Type is half of a skin's character. The 5×6 marquee font, the time
   digits and above all the **Sessions-list typeface (`plfont`, SPEC §3.2)** must be designed for
   this skin — never the toolkit defaults left as they are. The user has already rejected a
   generic-looking list font once. The `plfont` is a full mixed-case ASCII face (8×10 cell
   recommended) drawn as an ink mask: design letterforms that belong to the hardware you are
   depicting, use grey halo pixels where the display technology would bloom or ghost, set the
   metrics (`Monospace`, `Spacing`, `RowHeight`) to suit, and check long mixed-case rows like
   `fable5dot1/claude-usage-amp - FABLE 5.1   $12.40` at 4× for rhythm, legibility and descenders.

## Hard technical rules (break these and the skin glitches)

- Read `skins/skinkit/README.md` first; it documents the hooks, the underlay build order and traps.
- Work only inside your own `skins/<name>/` folder. Do not edit `skins/skinkit/` or `skins/base/` — if
  the toolkit has a bug or lacks something, work around it inside your folder (subclass, helper
  module) and describe it in your report. Do not look at the other art skins' folders; your skin must
  be your own design.
- **Wells stay clean.** Nothing dynamic is baked. The areas under the time digits, marquee
  (111,27,154×6), kbps (111,43,15×6), kHz (156,43,10×6) and visualizer (24,43,76×16) are flat wells.
- **Glyph cell background = a single flat colour**, identical to the marquee/kbps/kHz well colour
  (the marquee scrolls by 1 px, so any pattern in the cell would crawl). The same glyphs are also
  drawn in shade mode and the playlist footer, so paint those wells in the same flat colour.
- **Digit cell background** may vary vertically (scanlines, a gradient) but not horizontally, since
  one digit sprite is used at four x positions. The time well in `main.bmp` must match it exactly.
- **`viscolors()[0]` is the visualizer well colour**: the app fills the well with it, draws the dot
  grid in colour 1, bars in 2..17 (top→bottom), scope in 18..22, peak caps in 23. Make this palette a
  showpiece of the theme.
- Volume/balance/EQ slider **frames 0..27 are a gauge**: frame 0 = empty/cool, 27 = full/hot. They
  must read as a level at a glance — they are the app's main utilisation read-out. Thumbs are
  opaque sprites riding on top.
- Every pressed sprite must differ clearly from normal; every selected/on sprite must be obviously lit.
- The validator must pass: `cd skins && python3 -m skinkit.validate dist/<Name>.wsz`.

## Process (mandatory)

1. Read the toolkit README and `skins/base/theme.py` to see how a complete theme is put together.
2. Write your palette ramps and material generators first; render swatches; look at them at 8×.
3. Block in all three windows, build (`python3 skins/build.py <name>`), open
   `skins/<name>/preview/all_4x.png` with the Read tool. Get the big shapes and depth right.
4. Then detail zone by zone. After each pass rebuild and **look**: `main_4x.png`, `eq_4x.png`,
   `playlist_4x.png`, `shade_4x.png`, `sheets.png`. Also write yourself a crop helper that saves 8×
   crops of any rect, and inspect the zones you touched — 4× hides 1-px errors.
5. Do at least **six** full critique→refine rounds. In each, write down (for yourself) the five
   weakest things in the current render, fix them, re-render. Typical weaknesses: flat/empty areas,
   muddy contrast, labels that are illegible smudges, bevels with inconsistent light, thumbs that do
   not sit in their grooves, pressed states that barely change, lamps that do not glow, texture that
   reads as noise rather than material, seams where widget underlays do not match, EQ/playlist
   plainer than the main window.
6. Finish: validator passes, previews rendered, `skins/dist/<Name>.wsz` built. Final report: concept
   in two sentences, palette ramps, the detail inventory, toolkit workarounds/bugs, and an honest
   list of what is still weakest.
