import CoreGraphics
import Foundation
import UsageModel

/// Draws the "Token Flow" window (SPEC 2.9): a generic frame assembled from the `gen` sheet, the
/// phosphor field blitted into the well, and the title and readout set in the skin's 5x6 font.
public enum FieldRenderer {

    /// The well the field is drawn in, in window coordinates.
    public static func canvasRect(width w: Int, height h: Int) -> SpriteRect {
        let L = Layout.Field.self
        return SpriteRect(L.leftWidth, L.titleHeight,
                          max(1, w - L.leftWidth - L.rightWidth),
                          max(1, h - L.titleHeight - L.bottomHeight))
    }

    public static func draw(_ c: SkinCanvas, skin: Skin, snapshot: UsageSnapshot, state: ViewState,
                            field: CGImage?, labels: [FieldLabel]) {
        let w = max(Layout.Field.minSize.w, state.fieldWidth)
        let h = max(Layout.Field.minSize.h, state.fieldHeight)
        let well = canvasRect(width: w, height: h)

        drawFrame(c, skin: skin, width: w, height: h, state: state)

        if let field {
            c.draw(field, in: CGRect(x: CGFloat(well.x), y: CGFloat(well.y),
                                     width: CGFloat(well.w), height: CGFloat(well.h)))
        } else {
            c.fill(well, skin.visColors.color(0))
        }

        drawLabels(c, skin: skin, labels: labels, well: well)

        drawChrome(c, skin: skin, snapshot: snapshot, state: state, width: w, height: h)
    }

    /// Labels go over the live field, so they are set in the skin's `plfont` (SPEC 3.2), which is
    /// an *ink mask* and composites; the classic `text.bmp` face carries its own opaque cell
    /// background and would stamp a block of it behind every glyph.
    ///
    /// Here the mask is cut hard (`PlaylistFont.hardInkThreshold`): over a moving field a glyph's
    /// grey halo reads as blur, not glow, so a label is solid ink or nothing. Each one sits on a
    /// patch of the field's background one pixel wider than its ink all round, so no trace runs
    /// through its letters - a pace line through "PACE" reads "PAIE".
    ///
    /// Bright labels take the field's core colour, so a label belongs to the display rather than
    /// sitting on top of it; faint ones take `dimTint`.
    private static func drawLabels(_ c: SkinCanvas, skin: Skin, labels: [FieldLabel], well: SpriteRect) {
        guard !labels.isEmpty else { return }
        let vc = skin.visColors
        c.save()
        c.clip(to: well)
        if let font = skin.playlistFont {
            for set in typeset(labels, font: font, vc: vc, width: well.w, height: well.h) {
                c.fill(SpriteRect(well.x + set.patch.x, well.y + set.patch.y, set.patch.w, set.patch.h),
                       vc.color(0))
                font.drawHardInk(set.text, on: c, x: well.x + set.pen, y: well.y + set.cellTop,
                                 tint: cgColor(set.tint))
            }
        } else {
            // No plfont anywhere, not even Base's: the classic face, whose cells are opaque.
            for label in labels {
                let text = BitmapFont.sanitize(label.text)
                let width = BitmapFont.width(of: text)
                let x = well.x + place(label.x, width: width, centred: label.centred, in: well.w)
                let y = well.y + min(max(0, label.y), max(0, well.h - BitmapFont.glyphHeight))
                c.fill(SpriteRect(x - 1, y - 1, width + 1, BitmapFont.glyphHeight + 2), vc.color(0))
                c.save()
                if label.faint { c.ctx.setAlpha(0.6) }
                c.text(text, font: skin.font, x: x, y: y)
                c.restore()
            }
        }
        c.restore()
    }

    /// Write `labels` straight into a finished field frame, in skin pixels - the same pixels
    /// `draw` would set over it. The live window does this so that a frame reaches the screen as
    /// one image rather than a hundred glyph blits. False when the skin has no `plfont` to cut
    /// (nothing is written; draw the labels instead).
    @discardableResult
    public static func bake(_ labels: [FieldLabel], skin: Skin, into overlay: PhosphorField.Overlay) -> Bool {
        guard let font = skin.playlistFont else { return false }
        let vc = skin.visColors
        let bg = vc.rgb[0]
        for set in typeset(labels, font: font, vc: vc, width: overlay.width, height: overlay.height) {
            overlay.fill(x: set.patch.x, y: set.patch.y, w: set.patch.w, h: set.patch.h, bg)
            font.forEachHardInkPixel(set.text) { x, y in
                overlay.set(set.pen + x, set.cellTop + y, set.tint)
            }
        }
        return true
    }

    /// One label, set: where its pen starts and its cells' top sit, the patch behind it, and its
    /// tint - all in field pixels.
    struct SetLabel {
        let text: String
        let pen: Int
        let cellTop: Int
        let patch: SpriteRect
        let tint: (r: Int, g: Int, b: Int)
    }

    /// Place labels in a field of this size (the well). Shared by `drawLabels` and `bake`, so the
    /// snapshot and the live window set every label on the same pixels.
    static func typeset(_ labels: [FieldLabel], font: PlaylistFont, vc: VisColors,
                        width: Int, height: Int) -> [SetLabel] {
        let bright = PhosphorField.coreRGB(vc)
        let dim = dimTint(vc)
        let cap = font.capRows
        var out: [SetLabel] = []
        out.reserveCapacity(labels.count)
        for label in labels {
            let text = PlaylistFont.sanitize(label.text)
            guard let ink = font.hardInkBox(text) else { continue }
            let left = place(label.x, width: ink.w, centred: label.centred, in: width)
            let top = min(max(0, label.y), max(0, height - cap.height))
            let cellTop = top - cap.top
            let y0 = min(ink.y, cap.top), y1 = max(ink.y + ink.h, cap.top + cap.height)
            out.append(SetLabel(text: text, pen: left - ink.x, cellTop: cellTop,
                                patch: SpriteRect(left - 1, cellTop + y0 - 1, ink.w + 2, y1 - y0 + 2),
                                tint: label.faint ? dim : bright))
        }
        return out
    }

    /// What the geometry needs to know about the face labels will be set in (see `drawLabels`).
    public static func labelMetrics(for skin: Skin) -> FieldLabelMetrics {
        guard let font = skin.playlistFont else { return .classic }
        return FieldLabelMetrics(width: { font.hardInkBox(PlaylistFont.sanitize($0))?.w ?? 0 },
                                 height: font.capRows.height,
                                 ellipsis: font.hasEllipsis ? "\u{2026}" : nil)
    }

    /// Contrast a faint label must keep against the field background: the usual floor for small
    /// text, and these faces are six or seven pixels tall.
    static let faintContrast = 4.5

    /// The tint of faint labels. The bar-ramp colour nearest the middle of the ramp (12) that
    /// still reads against the background, judged by distance from the background the way the
    /// core colour is: on a dark skin that stays a mid-ramp colour, on a light skin like Bookcloth
    /// it walks towards the dark end of the ramp until the text is clearly legible, instead of
    /// fading into the paper.
    static func dimTint(_ vc: VisColors) -> (r: Int, g: Int, b: Int) {
        let bg = vc.rgb[0]
        // 12, 11, 13, 10, 14 ...: outwards from the middle, the hotter side first.
        let order: [Int] = (2...17).sorted { (a: Int, b: Int) -> Bool in
            let da = abs(a - 12), db = abs(b - 12)
            if da != db { return da < db }
            return a < b
        }
        for i in order where contrast(vc.rgb[i], bg) >= faintContrast { return vc.rgb[i] }
        // A palette with nothing legible in its ramp: take whatever stands furthest from the paper.
        var best = PhosphorField.coreRGB(vc)
        for i in 2...17 where contrast(vc.rgb[i], bg) > contrast(best, bg) { best = vc.rgb[i] }
        return best
    }

    /// WCAG contrast ratio of two sRGB colours, 1...21.
    static func contrast(_ a: (r: Int, g: Int, b: Int), _ b: (r: Int, g: Int, b: Int)) -> Double {
        func channel(_ v: Int) -> Double {
            let c = Double(min(255, max(0, v))) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        func luminance(_ c: (r: Int, g: Int, b: Int)) -> Double {
            0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
        }
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private static func cgColor(_ c: (r: Int, g: Int, b: Int)) -> CGColor {
        CGColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1)
    }

    /// Anchor a label and keep it inside a well this wide, whatever the face's metrics turn out
    /// to be. Returns the left edge relative to the well.
    private static func place(_ anchor: Int, width: Int, centred: Bool, in wellWidth: Int) -> Int {
        let left = centred ? anchor - width / 2 : anchor
        return min(max(0, left), max(0, wellWidth - width))
    }

    // MARK: - Frame

    private static func drawFrame(_ c: SkinCanvas, skin: Skin, width w: Int, height h: Int,
                                  state: ViewState) {
        let L = Layout.Field.self
        let topTile = skin.image(Spr.GEN_TOP_TILE)
        c.tileH(topTile, from: 0, to: w, y: 0)
        c.draw(skin.image(Spr.GEN_TOP_LEFT), at: 0, 0)
        if let right = skin.image(Spr.GEN_TOP_RIGHT) { c.draw(right, at: w - right.width, 0) }
        if let plate = skin.image(Spr.GEN_TITLE_PLATE) { c.draw(plate, at: (w - plate.width) / 2, 0) }

        let midTop = L.titleHeight
        let midBottom = h - L.bottomHeight
        c.tileV(skin.image(Spr.GEN_LEFT_TILE), from: midTop, to: midBottom, x: 0)
        if let right = skin.image(Spr.GEN_RIGHT_TILE) {
            c.tileV(right, from: midTop, to: midBottom, x: w - right.width)
        }

        let bottomY = h - L.bottomHeight
        c.tileH(skin.image(Spr.GEN_BOTTOM_TILE), from: 0, to: w, y: bottomY)
        c.draw(skin.image(Spr.GEN_BOTTOM_LEFT), at: 0, bottomY)
        if let br = skin.image(Spr.GEN_BOTTOM_RIGHT) { c.draw(br, at: w - br.width, bottomY) }
    }

    // MARK: - Chrome

    private static func drawChrome(_ c: SkinCanvas, skin: Skin, snapshot: UsageSnapshot,
                                   state: ViewState, width w: Int, height h: Int) {
        let L = Layout.Field.self
        let font = skin.font

        // Title: the window's name, then what it is showing. Nothing is baked into the plate, so
        // a skin never has to reprint its art when a configuration is added.
        let title = state.fieldAuto ? "TOKEN FLOW - AUTO" : "TOKEN FLOW"
        let titleWidth = BitmapFont.width(of: title)
        c.text(title, font: font, x: (w - titleWidth) / 2, y: L.titleTextY)

        let close = state.isPressed(.fieldClose) ? Spr.GEN_CLOSE_PRESSED : Spr.GEN_CLOSE
        c.draw(skin.image(close), at: SpriteRect(w + L.closeButtonFromTopRight.x,
                                                 L.closeButtonFromTopRight.y, 9, 9))
        c.draw(skin.image(state.fieldAuto ? Spr.GEN_LAMP_ON : Spr.GEN_LAMP_OFF),
               at: SpriteRect(w + L.lampFromTopRight.x, L.lampFromTopRight.y, 9, 9))

        // Bottom readout: which configuration, over what span, and the two numbers the field
        // itself cannot state exactly.
        var left = state.fieldMode.label
        if state.fieldMode == .strata { left += " " + state.fieldSpan.label }
        c.text(left, font: font, x: L.readoutFromBottomLeft.a, y: h + L.readoutFromBottomLeft.b)

        let burn = NumberFormatting.abbreviated(snapshot.burnTokensPerMin)
        let pressure = snapshot.limits.map { $0.percent }.max() ?? 0
        let right = "\(burn)/MIN  \(NumberFormatting.percent(pressure))"
        let rightWidth = BitmapFont.width(of: BitmapFont.sanitize(right))
        // Right-aligned clear of the bottom-right corner piece, which carries the resize grip:
        // a text.bmp cell is opaque, and stamped over the corner it cuts the grip in two.
        let corner = skin.image(Spr.GEN_BOTTOM_RIGHT)?.width ?? L.rightWidth
        let rightEdge = min(w + L.valueFromBottomRight.a, w - corner)
        c.text(right, font: font, x: rightEdge - rightWidth, y: h + L.valueFromBottomRight.b)
    }

    // MARK: - Hit regions

    public static func regions(width w: Int, height h: Int) -> [HitRegion] {
        let L = Layout.Field.self
        return [
            HitRegion(.fieldTitleBar, SpriteRect(0, 0, w, L.titleHeight),
                      showsPressed: false, dragsWindow: true),
            HitRegion(.fieldCanvas, canvasRect(width: w, height: h),
                      showsPressed: false, hasHoverReading: true),
            HitRegion(.fieldResize, SpriteRect(w + L.resizeGripFromBottomRight.x,
                                               h + L.resizeGripFromBottomRight.y, 20, 20),
                      showsPressed: false),
            HitRegion(.fieldLamp, SpriteRect(w + L.lampFromTopRight.x, L.lampFromTopRight.y, 9, 9)),
            HitRegion(.fieldClose, SpriteRect(w + L.closeButtonFromTopRight.x,
                                              L.closeButtonFromTopRight.y, 9, 9)),
        ]
    }

    // MARK: - Snapshot rendering

    /// Run `field` from wherever it is to a settled state for this instant.
    ///
    /// The step is chosen from the persistence rather than fixed at a frame: a long phosphor tail
    /// needs a longer simulated run to converge, and at 1/30 s a 2.25 s tail would still be at
    /// half brightness after 48 frames - which would make bursty work render systematically dimmer
    /// than steady work at the same token volume, exactly the thing the decay gain exists to
    /// prevent (SPEC 3.3). Deterministic: the step is a pure function of the snapshot.
    ///
    /// A configuration whose picture does not move within an instant (`FieldGeometry.moves`) takes
    /// the whole run in one step - one decay over all of it and one draw is the closed form of the
    /// frame-by-frame sum, to rounding - so a click, a span change or a resize step costs one
    /// frame rather than forty-eight.
    @discardableResult
    public static func settle(into field: PhosphorField, snapshot: UsageSnapshot, mode: FieldMode,
                              span: FieldSpan, now: Date,
                              metrics: FieldLabelMetrics = .classic) -> [FieldLabel] {
        let mods = FieldModulators(snapshot: snapshot, now: now)
        // Six time constants of the slower (ghost) channel, spread over a fixed frame count.
        let frames = 48
        let tail = mods.tail(for: mode)
        let dt = max(1.0 / 30, tail * 2.2 * 6 / Double(frames))
        var labels: [FieldLabel] = []
        if FieldGeometry.moves(mode) {
            for i in 0..<frames {
                field.decay(dt: dt, persistence: tail)
                labels = FieldGeometry.draw(mode, into: field, snapshot: snapshot, mods: mods,
                                            span: span, flows: [:], t: Double(i) * dt, now: now,
                                            metrics: metrics)
            }
        } else {
            field.decay(dt: dt * Double(frames), persistence: tail)
            labels = FieldGeometry.draw(mode, into: field, snapshot: snapshot, mods: mods,
                                        span: span, flows: [:], t: Double(frames - 1) * dt, now: now,
                                        metrics: metrics)
        }
        FieldGeometry.drawGraticule(field, mode, mods)
        return labels
    }

    /// The settled field for one instant, rendered into a fresh buffer (SPEC 3.1).
    public static func settled(snapshot: UsageSnapshot, skin: Skin, mode: FieldMode,
                               span: FieldSpan, width: Int, height: Int, now: Date)
        -> (image: CGImage?, labels: [FieldLabel]) {
        let well = canvasRect(width: width, height: height)
        let field = PhosphorField(width: well.w, height: well.h)
        let labels = settle(into: field, snapshot: snapshot, mode: mode, span: span, now: now,
                            metrics: labelMetrics(for: skin))
        let pressure = FieldModulators(snapshot: snapshot, now: now).pressure
        return (field.makeImage(skin: skin, pressure: pressure), labels)
    }

    /// The largest the window grows: 1000 x 725, on the resize grid. SPEC 2.9 gives the grid
    /// no ceiling, but the field pays for its area on every frame, and past this a window is more
    /// field than a screen shows at any useful scale - thirteen times the default's pixels
    /// already.
    public static let maxSize = SkinPair(Layout.Field.minSize.w + 31 * Layout.Field.resizeStep.w,
                                          Layout.Field.minSize.h + 20 * Layout.Field.resizeStep.h)

    /// Snap a proposed size onto the resize grid, never below the minimum or above `maxSize`
    /// (SPEC 2.9).
    public static func snapWidth(_ proposed: Int) -> Int {
        snap(proposed, min: Layout.Field.minSize.w, max: maxSize.w, step: Layout.Field.resizeStep.w)
    }

    public static func snapHeight(_ proposed: Int) -> Int {
        snap(proposed, min: Layout.Field.minSize.h, max: maxSize.h, step: Layout.Field.resizeStep.h)
    }

    private static func snap(_ proposed: Int, min minimum: Int, max maximum: Int, step: Int) -> Int {
        let steps = max(0, Int((Double(proposed - minimum) / Double(step)).rounded()))
        return min(maximum, minimum + steps * step)
    }
}
