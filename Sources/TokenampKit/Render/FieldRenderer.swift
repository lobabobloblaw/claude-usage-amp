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
    /// background and would stamp a block of it behind every glyph. The tint is the field's own
    /// core colour, so a label belongs to the display rather than sitting on top of it.
    private static func drawLabels(_ c: SkinCanvas, skin: Skin, labels: [FieldLabel], well: SpriteRect) {
        guard !labels.isEmpty else { return }
        let core = PhosphorField.coreRGB(skin.visColors)
        let bright = CGColor(srgbRed: CGFloat(core.r) / 255, green: CGFloat(core.g) / 255,
                             blue: CGFloat(core.b) / 255, alpha: 1)
        let dim = skin.visColors.color(12)
        c.save()
        c.clip(to: well)
        for label in labels {
            let tint = label.faint ? dim : bright
            if let font = skin.playlistFont {
                let text = PlaylistFont.sanitize(label.text)
                let width = font.measure(text)
                let x = place(label.x, width: width, centred: label.centred, in: well)
                _ = font.draw(text, on: c, x: x, y: well.y + label.y, tint: tint)
            } else {
                let text = BitmapFont.sanitize(label.text)
                let x = place(label.x, width: BitmapFont.width(of: text), centred: label.centred, in: well)
                c.save()
                if label.faint { c.ctx.setAlpha(0.6) }
                c.text(text, font: skin.font, x: x, y: well.y + label.y)
                c.restore()
            }
        }
        c.restore()
    }

    /// Anchor a label and keep it inside the well, whatever the face's metrics turn out to be.
    private static func place(_ anchor: Int, width: Int, centred: Bool, in well: SpriteRect) -> Int {
        let left = centred ? anchor - width / 2 : anchor
        return well.x + min(max(0, left), max(0, well.w - width))
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
        c.text(right, font: font, x: w + L.valueFromBottomRight.a - rightWidth,
               y: h + L.valueFromBottomRight.b)
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
    @discardableResult
    public static func settle(into field: PhosphorField, snapshot: UsageSnapshot, mode: FieldMode,
                              span: FieldSpan, now: Date) -> [FieldLabel] {
        let mods = FieldModulators(snapshot: snapshot, now: now)
        // Six time constants of the slower (ghost) channel, spread over a fixed frame count.
        let frames = 48
        let dt = max(1.0 / 30, mods.persistence * 2.2 * 6 / Double(frames))
        var labels: [FieldLabel] = []
        for i in 0..<frames {
            field.decay(dt: dt, persistence: mods.persistence)
            labels = FieldGeometry.draw(mode, into: field, snapshot: snapshot, mods: mods,
                                        span: span, flows: [:], t: Double(i) * dt, now: now)
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
        let labels = settle(into: field, snapshot: snapshot, mode: mode, span: span, now: now)
        let pressure = FieldModulators(snapshot: snapshot, now: now).pressure
        return (field.makeImage(skin: skin, pressure: pressure), labels)
    }

    /// Snap a proposed size onto the resize grid, never below the minimum (SPEC 2.9).
    public static func snapWidth(_ proposed: Int) -> Int {
        snap(proposed, min: Layout.Field.minSize.w, step: Layout.Field.resizeStep.w)
    }

    public static func snapHeight(_ proposed: Int) -> Int {
        snap(proposed, min: Layout.Field.minSize.h, step: Layout.Field.resizeStep.h)
    }

    private static func snap(_ proposed: Int, min minimum: Int, step: Int) -> Int {
        let steps = max(0, Int((Double(proposed - minimum) / Double(step)).rounded()))
        return minimum + steps * step
    }
}
