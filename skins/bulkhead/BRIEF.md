# Skin brief — "Bulkhead"

Folder `skins/bulkhead/`, theme name `Bulkhead`, output `skins/dist/Bulkhead.wsz`.
Read `skins/ART_DIRECTION.md` first; it sets the quality bar, the hard rules and the process.

## Concept

A control module unbolted from the engineering deck of a long-haul freighter and put to work
monitoring token flow. Heavy gunmetal plate, decades of service: paint chipped back to bare steel
on every exposed edge, oil-dark seams, hazard striping around anything dangerous, stencilled
inventory codes, and at the centre an **amber phosphor CRT** glowing through thick curved glass.
Alien's Nostromo, not Star Trek: analogue, heavy, used, believable.

## Palette ramps (starting point — tune by eye)

- Gunmetal plate: `#0d1013 #181d22 #252c33 #343d46 #47525c #5e6b76 #7d8b96 #a7b3bb`
- Bare worn steel (chips, edges): `#59626a #808b93 #aab4ba #d7dee2`
- Safety orange paint: `#4a1f08 #7a330c #b04e10 #e06a14 #ff8c2a #ffb060`
- Hazard yellow / black: `#b88a0c #e8b618 #ffd84a` / `#1a1a18 #2a2925`
- Amber phosphor: well `#0a0602`, ghost `#1c0f02`, dim `#5a2f04`, mid `#c46a08`, bright `#ffa91f`, core `#ffe2a0`
- Lamps: red `#3a0606 → #ff3b24 → #ffc0b0`; green `#07280e → #3dff6e → #d0ffe0`
- Rubber / gasket: `#08090a #121416 #1e2124`

## Direction, element by element

- **Faceplate.** Two overlapping gunmetal plates with a visible lap seam and a row of rivets; hex
  bolts at the corners (each rotated differently); fine horizontal machining marks plus blotchy
  fbm wear; chipped orange paint band down the left behind the clutterbar; a louvred vent; a short
  run of armoured conduit or a cable gland; stencil text (`ENG-04`, `TOKEN FLOW MON`, `MK IV`) in the
  micro fonts, slightly broken up as worn stencil paint; a tiny riveted maker's plate with a serial
  number; a `CAUTION` label with hazard chevrons. Oil streaks running *down* from bolts.
- **CRT display well.** One deep bezel housing time digits, play-state, visualizer, marquee and the
  two numeric fields, with a rubber gasket, an inner shadow, and a curved-glass glare streak painted
  on the *bezel and non-dynamic glass* (never over the dynamic wells). Subtle green-black → amber-black
  vignette in the static parts of the glass.
- **Time digits.** Chunky amber CRT numerals — seven-segment with slightly rounded, blooming strokes
  (bright core, mid halo, dim outer pixel), ghost segments faintly visible, horizontal scanlines in the
  cell. Must be the most legible thing on the skin.
- **Text font.** Amber on the flat well colour; squared, technical letterforms; if you restyle the
  glyphs keep them razor-legible.
- **Visualizer palette.** Deep amber at the base rising through bright amber to orange and a red
  tip; peak caps near-white amber; grid dots barely-visible dim amber; scope trace bright core with
  dimmer falloff colours.
- **Transport.** Six heavy keycaps: dark rubberised faces in steel surrounds, icons engraved and
  paint-filled (orange for play, yellowed white for the rest), wear-polished at the centres. Pressed:
  sunk 1 px, surround shadow deepens, icon paint brightens as if backlit. Eject is the guarded one:
  hazard-striped surround.
- **Seek bar.** A milled slot with engraved tick scale; thumb is a machined steel slider with knurling
  and a red index line; pressed thumb shows the index lit.
- **Volume / balance gauges.** Segmented LED ladders behind smoked glass: segments light left→right
  with the frame index, green → amber → red, lit segments bloom, unlit are visible ghosts. `SESSION`
  and `WEEK` stencilled beside/inside. Thumb: small knurled steel knob.
- **LOCAL / LIVE.** Aircraft-style annunciator tiles: legend dark when off, tile back-lit when on —
  `LOCAL` amber, `LIVE` green — with light spilling onto the surround.
- **CYCLE / ALERT, EQ / PL.** Rectangular steel toggles, each with a caged pilot lamp that is
  obviously lit when selected.
- **Title bar.** A steel grab-rail strip: knurled grip sections, `TOKENAMP` stencilled in the centre,
  pilot lamps at both ends (amber lit when active, dead when inactive), tiny square keys for the
  options/minimise/shade/close buttons with paint-filled pictograms (close = red).
- **Clutterbar.** A column of five tiny engraved keys on an orange-painted strip.
- **Equalizer ("USAGE EQUALIZER").** A rack unit of ten vertical "fuel-rod" gauges: each frame is a
  glass tube/LED ladder filling bottom→top and heating green → amber → red; thumbs are knurled steel
  collars. The graph window is a small amber CRT with graticule; line colours amber with a hot top.
  Same plate, bolts, stencils and hazard language as the main window.
- **Playlist ("SESSIONS").** A steel-framed amber terminal: bezel, gasket, corner bolts, a status
  strip at the bottom with riveted label plates; scrollbar is a slotted rail with a steel slider.
  pledit colours: background deep amber-black, normal text mid amber, current bright amber-white,
  selection a dim amber block.

- **Sessions typeface (`plfont`).** A shipboard terminal face: squared, slightly condensed,
  OCR-A / DIN-stencil flavoured letterforms with open counters, slashed zero, flat-topped `A`,
  single-storey `a`, sturdy descenders; proportional, `Spacing=1`. Grey halo pixels on the
  right/below strokes for phosphor bloom and a hint of horizontal smear, so rows look *emitted* by
  the CRT rather than printed on it.

## Pitfalls specific to this skin

Dark skins go muddy: keep the plate midtones light enough (around `#343d46`–`#5e6b76`) that bevels
and wear read, and reserve pure black for seams and the CRT. Amber on black is easy to over-bloom —
halo pixels must not reduce digit legibility.
