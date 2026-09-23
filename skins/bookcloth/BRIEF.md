# Skin brief — "Bookcloth"

Folder `skins/bookcloth/`, theme name `Bookcloth`, output `skins/dist/Bookcloth.wsz`.
Read `skins/ART_DIRECTION.md` first; it sets the quality bar, the hard rules and the process.

## Concept

The user asked for an **Anthropic-centric** skin. Anthropic's visual identity is warm, humane and
hand-made: ivory paper, clay orange, slate ink, literary serif type, wobbly hand-drawn line
illustrations, cut-paper shapes. That language is minimal — so the hyperdetail here comes from
**craft materials, not machinery**: the player is a hand-bound stationery object. A cover wrapped in
clay-orange **book cloth** (you can see the weave), pages of ivory laid paper with fibres and a
deckled edge, labels **letterpressed** into the stock so they cast tiny deboss shadows, linen
thread stitching, layered **cut paper** with soft warm shadows, slate ink that has bled a hair into
the fibres, pencil guide-lines someone forgot to erase. It should feel like something made slowly,
by a person, for a person. It is the only *light* skin in the set — dark ink on paper — and must be
the calmest and the most elegant.

**Brand handling (important).** This is a fan-made tribute for the user's personal tool, not an
official product. Evoke the identity through palette, materials, typography and illustration
style. The maker's mark is the skin's **own** letterpress monogram (see *The maker's mark*
below) and the doodles are your own node-and-line drawings; do **not** trace or attempt to
reproduce Anthropic's or Claude's official logo geometry or wordmark, and do not label anything
as official. Plain descriptive text such as `CLAUDE USAGE` is fine. Your `readme()` must end
with: `Fan-made tribute skin. Not affiliated with or endorsed by Anthropic.`

## Palette ramps (starting point — tune by eye)

- Ivory paper: `#c9c3ae #ddd8c4 #e8e6dc #f0eee6 #faf9f5` (+ `#ffffff` only as rare fibre glints)
- Slate ink: `#141413 #262624 #3d3d3a #5e5d59 #87867f #b0aea5`
- Book cloth / clay orange: `#7a3b26 #9c4a2f #c15f3c #d97757 #e8957a #f3bfa8`
- Kraft / manilla: `#a67c52 #c4966c #d4a27f #ebdbbc`
- Accent blue (graph rules, cool states): `#4f7fae #6a9bcc #a9c4e0`
- Accent green (cool/low gauge states): `#5a6b44 #788c5d #a7b68e`
- Linen thread: `#9c8f6e #cfc4a2 #e8e0c8`
- Shadows are **warm** (`#5e5d59` / `#7a3b26` at low alpha), never neutral black.

## Direction, element by element

- **The object.** Main window = the closed book's front: a book-cloth cover (woven texture with
  warp/weft highlights, slightly darker toward the spine, a worn lighter edge at corners) with
  inset **paper panels** let into the cloth — each panel a cut opening showing ivory laid paper
  beneath, with a bevelled cut edge (you see the board's core) and an inner shadow. A stitched
  spine down the left behind the clutterbar (linen thread, individual stitches with shadows).
  Hand-drawn slate-ink doodles printed on the paper where space allows: a node-and-line
  constellation, a wobbly underline. A pencil registration mark. A blind-debossed maker's line
  along the foot of the cover, and the maker's mark in its roundel at the lower right.
- **The maker's mark.** A letterpress monogram, drawn for this skin: a bold serif capital `T`
  (for Tokenamp) printed in clay ink on a disc of ivory stock let into the cloth, inside a
  blind-struck ring. Three-pixel stem, two-row bar ending in bracketed beak serifs, a bracketed
  slab foot, a hair of ink squash at the edges. It must read unmistakably as a serif T at the
  app's usual 1.5× on a Retina display (3 device pixels per skin pixel). Where the mark is small
  (5–7 px) nothing figurative survives, so it becomes a **solid clay lozenge** set at the cap
  height of the small capitals beside it: after the running head and the figure caption, on the
  EQ page, rubber-stamped ahead of `LIVE`, as the work indicator, in a miniature roundel on the
  shade strip, and foil-stamped either side of the title on the easter-egg spine. The Sessions
  colophon has room for a small `T`. (A radiating starburst was tried first and rejected: at that
  scale its rays read as specks.)
- **Displays are print, not screens.** The time/marquee/numeric wells are flat ivory paper
  (`#f0eee6`-ish, one flat colour per the hard rules). Digits, text and visualizer are **ink**.
- **Time digits.** Letterpress numerals: a sturdy old-style/Clarendon-flavoured serif figure in
  slate ink, 9×13, with subtle ink-spread (a slightly softer outer pixel in `#3d3d3a`/`#5e5d59`)
  and a whisper of deboss shadow (one lighter pixel row beneath strokes). Hand-set, confident,
  extremely legible. The colon is two inked dots.
- **Text font (5×6).** Slate ink on the flat paper colour; small-caps serif feeling where 5×6
  allows (tiny slab serifs on I, T, L…), never at the cost of legibility.
- **Visualizer palette.** Colour 0 = the paper; grid dots = faint pencil (`#ddd8c4`); bars rise
  kraft → clay orange → deep book-cloth at the top, like strokes of gouache; peak caps slate ink;
  scope trace slate core with softer greys.
- **Transport.** Six ivory card-stock keys, each a separate piece of cut paper lifted off the
  cloth by a soft warm shadow, with letterpressed slate pictograms (play in clay orange). Subtle
  paper fibre, a bright top-left cut edge. Pressed: the shadow collapses, the card darkens a step,
  the pictogram shifts 1 px and turns clay orange as if freshly inked.
- **Seek bar.** A hand-ruled ink scale on a long paper strip (ticks slightly uneven like a ruled
  pen line, tiny serif numerals), and the thumb is a **clay-orange ribbon bookmark tab** or a small
  terracotta tile with a glazed highlight. Pressed thumb: deeper orange.
- **Volume / balance gauges.** Paper strips with ruled tick marks where a band of ink/gouache
  wash grows left→right with the frame index: accent green when low → kraft → clay orange → deep
  red-clay when nearly full, with a slightly irregular hand-painted leading edge. `SESSION` /
  `WEEK` letterpressed beside them. Thumbs: small terracotta tiles.
- **LOCAL / LIVE.** Rubber stamps, not lamps: off = a blind deboss barely visible in the paper;
  on = stamped — `LOCAL` in slate ink, `LIVE` in clay orange with a tiny lozenge — slightly rotated
  or unevenly inked the way real stamps are (within the sprite's pixel budget).
- **CYCLE / ALERT, EQ / PL.** Paper tabs with a hand-drawn checkbox: empty ink square when off,
  filled with clay orange (and a little overshoot outside the lines) when selected.
- **Play state / work indicator.** Inked pictograms; the work indicator is a tiny clay lozenge.
- **Title bar.** The book's spine/top edge: book cloth with **ivory foil-stamped** serif
  `TOKENAMP`, a line of stitches, head-band threads at the ends. Inactive: the cloth sun-faded
  toward kraft, foil duller. Title buttons: foil pictograms on cloth; pressed = darker cloth.
- **Clutterbar.** A column of five index tabs cut into the page edge, lettered O A I D V.
- **Equalizer ("USAGE EQUALIZER") = a lab-notebook page.** Ivory graph paper with faint accent-blue
  rules, ten hand-ruled vertical scales whose frames fill bottom→top with ink wash (green → kraft
  → clay → deep clay), terracotta tile thumbs, the curve window a pasted-in slip of graph paper
  with the curve drawn in clay orange ink (line colours: clay with a darker top), captions in
  letterpress serif small caps, a paper-clip or a strip of washi tape holding the slip, a coffee
  ring ghost if you can make it subtle enough to be charming rather than dirty.
- **Playlist ("SESSIONS") = a ledger card.** Book-cloth frame with the ivory page inside; the
  right side shows the **fore-edge of the page block** (fine stacked page lines) and the scroll
  handle is a **ribbon bookmark**; the footer is a colophon: serif small caps, the small
  monogram `T`, a ruled line. pledit colours: background `#f0eee6`, normal text `#3d3d3a`,
  current `#c15f3c`, selection `#ebdbbc`.
- **Sessions typeface (`plfont`).** A literary old-style serif pixel face — bracketed serifs,
  two-storey `a`, a graceful `g`, slightly condensed so long project paths fit; proportional,
  `Spacing=1`; ink-spread via a few low-coverage grey pixels at stroke joins. It should feel
  typeset, like a well-made book index.

## Pitfalls specific to this skin

Light skins show every mistake. Paper and cloth texture must stay within one ramp step or the
skin looks dirty rather than tactile. Keep generous calm areas — elegance here is restraint plus
exquisite edges (cut bevels, deboss shadows, stitches). Do not let it drift into a flat web UI:
every element must read as a physical material at 8×. Warm greys only; pure black nowhere.
