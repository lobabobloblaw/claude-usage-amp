# Skin brief — "Amethyst"

Folder `skins/amethyst/`, theme name `Amethyst`, output `skins/dist/Amethyst.wsz`.
Read `skins/ART_DIRECTION.md` first; it sets the quality bar, the hard rules and the process.

## Concept

The player with its case off: a bare development board in **deep purple solder mask with gold ENIG
copper**, white silkscreen, and a city of surface-mount parts. Time is shown on **red seven-segment
LED modules**, text on a **yellow-green STN character LCD** (dark pixels on a glowing green-yellow
field), token flow on an **LED bargraph**. Transport keys are tact switches, toggles are DIP/slide
switches with indicator LEDs, gauges are slide pots with LED ladders. Every trace is routed with
intent: 45° bends, buses running in parallel, vias where a trace dives to the other layer. An
electronics person should be able to "read" the board.

## Palette ramps (starting point — tune by eye)

- Purple mask over bare FR4: `#160a24 #231038 #32174f #432066 #57307f`
- Mask over copper (traces, pours read lighter): `#4b2a78 #5a3a8c #6f4aa6`
- ENIG gold: `#5c4408 #8f6b10 #c4981e #e8c440 #fff0a0`
- Silkscreen: `#e9e6f2`, worn `#b9b3cc`
- Solder / tin: `#4a5058 #6a7078 #a9b0b8 #e6eaee`
- IC epoxy: `#0c0c0e #1a1b1f #2a2c32`, laser-etch text `#7c808a`
- Red LED segments: face `#160606`, ghost `#3a0a08`, lit `#ff2a1a`, core `#ffb0a0`
- STN LCD: field `#a4bf1a`, field shade `#8aa510`, pixel `#1c2808`, bezel black `#101114`, metal frame tin ramp
- SMD LEDs: green `#0a3a12→#38ff6a`, amber `#3a2604→#ffb020`, red `#3a0606→#ff3324`, blue `#06123a→#4a8cff`
- Passives: ceramic cap tan `#8f7750 #b89868 #d8bc8c`; tantalum `#a06a0c #d89a1e #f4c04a`; resistor body `#0e0e10` with white numerals

## Direction, element by element

- **The board.** fbm-mottled purple mask with a faint fibreglass weave; copper pours visible as
  lighter purple regions with hatch/thermal reliefs; gold-ringed mounting holes in the corners;
  hand-routed traces linking the controls to a central QFP microcontroller (gull-wing pins, pin-1
  dot, laser-etched `TA-5100` and a date code); a crystal can, decoupling caps hugging the chip,
  SOT-23 transistors, a tantalum with polarity bar, an electrolytic can seen from above (circle,
  K-vent, stripe), resistor arrays, an unpopulated JTAG footprint, test points `TP1…`, fiducials,
  reference designators (`R12 C4 U1 D3 SW2`), a tiny barcode/serial sticker, polarity marks,
  `TOKENAMP REV C` and `MADE ON EARTH` in silk. Solder fillets glint (single bright pixels).
- **Time digits.** Red seven-segment LED modules: dark red-black face, clearly visible ghost
  segments, lit segments saturated red with a hot pale core and 1-px bloom; cell background varies
  only vertically. The module bodies, decimal-point dots and pin rows are painted in `main.bmp`
  around the (clean) digit cells. The colon is two lit round LEDs.
- **Text font / LCD.** Dark `#1c2808` glyphs on the flat LCD field colour. The marquee, kbps and kHz
  wells are windows of **one LCD module**: black bezel, tin frame with bent tabs, a row of header
  pins, a backlight glow gradient painted on the *static* bezel edge only. Glyphs: 5×6 character-LCD
  letterforms, very legible.
- **Visualizer palette = LED bargraph.** Colour 0 near-black module face; grid dots = unlit segment
  ghosts; bars green at the base → yellow → red at the top; peak caps bright white-blue; scope trace
  green core. Paint the bargraph module's body and pin rows around the well.
- **Transport.** Six tact switches: tin can with four crimp dimples, round black plunger with a
  specular dot, and the function icon in white silk beside or beneath each within its sprite.
  Pressed: plunger sinks (smaller highlight, darker, +1,+1) and a tiny adjacent SMD LED lights.
  Eject is the odd one out — a right-angle or a red-capped switch.
- **Seek bar.** A long linear slide potentiometer: metal channel, slot, silk tick ruler along it; the
  thumb is the pot's cap (black with a white index), pressed = index lit.
- **Volume / balance gauges.** Rows of tiny SMD LEDs (or a segmented LED light-bar) lighting
  left→right with the frame index, green → amber → red, each lit LED blooming onto the mask; silk
  labels `SESSION` / `WEEK`. Thumbs: small slide-pot caps.
- **CYCLE / ALERT, EQ / PL.** DIP/slide switches whose slider visibly changes side when selected,
  each with its own indicator LED (off = dull lens, on = lit with bloom); pressed = slider mid-travel
  or can darkened. Silk labels.
- **LOCAL / LIVE.** Two labelled SMD LEDs with silk legends: `LOCAL` amber, `LIVE` green; lit lenses
  bloom across neighbouring mask and silk.
- **Title bar.** The board's top edge: FR4 edge tan line, gold edge-plating or castellations, silk
  `TOKENAMP` in the centre, gold test pads as the title buttons (pictograms in silk; pressed = pad
  darkened with a solder-blob highlight). Active = a blue power LED lit; inactive = LED off, silk dimmer.
- **Clutterbar.** Five tiny gold pads / micro switches labelled in silk O A I D V.
- **Equalizer ("USAGE EQUALIZER").** A graphic-EQ board: ten long slide pots (metal body, slot, cap),
  each frame lighting an LED ladder along the slot bottom→top green→amber→red; the curve window is a
  small monochrome LCD/OLED module; traces fan from each pot to a header; more silk designators.
  Line colours suited to the little display.
- **Playlist ("SESSIONS").** A large STN LCD module mounted on the same purple board: tin frame,
  black bezel, mounting screws, header along the bottom, the board visible around it with parts and
  traces; the scrollbar is a slide pot. pledit colours: background `#a4bf1a`, normal `#34440f`,
  current `#0b1203` (bolder/darker), selection `#86a012`.

- **Sessions typeface (`plfont`).** A true **character-LCD face**: 5×8 dot-matrix letterforms in
  the HD44780 tradition (its distinctive lowercase `g j p q y` squeezed above the cursor line),
  `Monospace=1` with a 6-px cell pitch so rows fall on a visible character grid. Add very low grey
  coverage in each character cell's unlit dots so the LCD's ghost pixel grid is faintly visible
  behind the text, exactly like a real STN module at an angle.

## Pitfalls specific to this skin

A PCB done lazily is just purple noise with yellow lines. Routing must be orderly — traces the same
width, consistent 45° corners, parallel buses with even spacing, vias drawn as gold ring + dark
hole. Keep the mask dark and the gold sparing so the displays stay the brightest things. The LCD
field is very bright: make sure dark glyphs have full contrast and the field colour is identical
everywhere glyphs are drawn.
