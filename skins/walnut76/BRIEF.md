# Skin brief — "Walnut 76"

Folder `skins/walnut76/`, theme name `Walnut 76`, output `skins/dist/Walnut76.wsz`.
Read `skins/ART_DIRECTION.md` first; it sets the quality bar, the hard rules and the process.

## Concept

A top-of-the-line 1976 stereo receiver, lovingly kept. Oiled walnut cabinet cheeks, a brushed
champagne-aluminium fascia, and across the top a long **black glass dial window** whose legends glow
teal from behind, swept by a red tuning needle. Warm incandescent pilot lamps. Everything engraved,
knurled, machined. It should look expensive and make people nostalgic for something they never owned.
No real brand names, logos or model numbers — this is its own marque (`TOKENAMP · MODEL TA-76`).

## Palette ramps (starting point — tune by eye)

- Walnut: `#1e0f07 #35190b #4f2810 #6b3a18 #8a5226 #a96d38 #c58a52`
- Champagne aluminium: `#5d5546 #7d745f #9c927a #b9af95 #d4cbb2 #ece5d0 #fbf7ea`
- Black glass: `#050708 #0b1012 #121a1d` (+ glare streak `#2a3a3e` at low alpha)
- Backlit teal: ghost `#062a2c`, dim `#0f5e60`, mid `#1fa6a0`, bright `#55e0d2`, core `#c8fff6`
- Needle red: `#5a0c08 #c21e12 #ff4a30` (+ glow)
- Incandescent pilot: `#3a1c04 #a35a0c #ffb642 #fff0c0`
- Chrome trim: `#2b2f33 #6e777f #c9d1d6 #ffffff`
- Black control plastic: `#0a0a0b #17181a #26282b #3a3d41`

## Direction, element by element

- **Cabinet and fascia.** Walnut end-cheeks at the far left and right (roughly 7–9 px each) with real
  grain: long flowing figure, a small knot, darker end-grain at the top edge, a satin sheen line.
  Between them, horizontally brushed champagne aluminium (fine 1-px streaks of varying length, a
  broad soft vertical sheen band), a thin chrome trim line separating glass from aluminium,
  countersunk slotted screws in the aluminium. Engraved, black-filled micro labels, serif flavoured
  where size allows.
- **Glass dial window.** One continuous black glass pane across the upper area housing the time
  digits, play-state, visualizer, marquee and numeric fields, set in a chrome bezel with an inner
  shadow. Static backlit legends on the glass (`K/MIN`, `ACTIVE`, tiny scale marks, a faint dial
  scale) in dim teal. A diagonal glare streak across the static glass only.
- **Time digits.** Vacuum-fluorescent teal: slightly slanted seven-segment, bright core with a soft
  halo, ghost segments just visible. Cell background flat-to-vertically-graded glass black.
- **Text font.** Teal VFD dot-matrix feel on flat glass black; crisp and legible.
- **Visualizer palette.** Teal at the base → aqua → near-white at the top, **needle-red peak caps**;
  grid dots very dim teal; scope trace bright aqua core.
- **Seek bar = the tuning dial.** A long strip of black glass with backlit tick marks and tiny
  numerals (a unitless 0–10 logging scale), and the thumb is the **red tuning needle** in a slim
  chrome carriage, glowing onto the glass. Pressed thumb: needle brighter. This is the skin's
  signature element; spend pixels here.
- **Volume / balance gauges.** Slide pots in black slots with a backlit level scale beside the slot:
  the lit run grows with the frame index, teal for most of its travel, turning amber then red over
  the last quarter. Thumbs are knurled aluminium slider caps with a black index line and a bright
  top edge. `SESSION` / `WEEK` engraved in the aluminium.
- **Transport.** Machined aluminium piano keys with chamfered edges, engraved black-filled icons,
  a hairline dark gap between keys, brushed faces with a highlight along the top chamfer. Pressed:
  key tilts away — face darkens, top highlight vanishes, bottom shadow closes, icon shifts 1 px.
- **CYCLE / ALERT, EQ / PL.** Small rectangular push switches in black plastic with an amber jewel
  pilot lamp each — dark glassy bead when off, glowing with a warm halo when selected.
- **LOCAL / LIVE.** Beacon legends behind the glass: `LOCAL` teal when lit, `LIVE` **red** when lit
  (the classic red stereo beacon), ghost-dim when off.
- **Title bar.** The cabinet's top rail: walnut ends, an inlaid aluminium strip engraved
  `TOKENAMP`; active = a tiny lit pilot at the left, inactive = pilot dead and the strip duller.
  Title buttons are tiny black plastic push caps with engraved pictograms.
- **Clutterbar.** A column of five tiny aluminium push caps engraved O A I D V.
- **Equalizer ("USAGE EQUALIZER").** The matching graphic-equalizer component: ten slide pots with
  aluminium caps in black slots, each frame lighting a teal→amber→red level ladder beside the slot
  from the bottom up; the curve window is black glass with a faint graticule; band captions
  engraved; walnut cheeks and the same screws. Line colours teal with a warm top.
- **Playlist ("SESSIONS").** A walnut-framed black glass panel — like the receiver's matching tape
  deck window. Footer in brushed aluminium with engraved labels and a small badge; the scrollbar is
  a slot with an aluminium slider cap. pledit colours: background glass black, normal text mid
  teal, current warm amber, selection deep teal block.

- **Sessions typeface (`plfont`).** The receiver's own lettering seen through glass: a refined
  humanist face with 1970s hi-fi manners — gently rounded terminals, a two-storey `a`, elegant
  `g`/`y` descenders, old-style rhythm, slightly wide; proportional, `Spacing=1`. A faint 1-px teal
  halo (low grey coverage) so the text glows from behind the glass without losing crispness. It
  should feel like the silk-screened dial lettering of a fine tuner, not a computer font.

## Pitfalls specific to this skin

Brushed aluminium turns to TV static if streaks are too contrasty — keep streak contrast within one
ramp step and let the broad sheen do the work. Wood grain must flow (long correlated figure), not
speckle. Keep the glass genuinely dark so the teal glows.
