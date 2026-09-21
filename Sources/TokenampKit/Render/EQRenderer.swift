import CoreGraphics
import Foundation
import UsageModel

/// Draws the 275x116 "Usage Equalizer" window (SPEC 2.3).
public enum EQRenderer {

    public static func draw(_ c: SkinCanvas, skin: Skin, snapshot: UsageSnapshot, state: ViewState) {
        let L = Layout.EQ.self
        c.draw(skin.image(Spr.EQ_WINDOW_BACKGROUND), at: SpriteRect(0, 0, L.size.w, L.size.h))
        c.draw(skin.image(state.eqIsKey ? Spr.EQ_TITLE_BAR_SELECTED : Spr.EQ_TITLE_BAR), at: L.titleBar)
        if state.isPressed(.eqClose) { c.draw(skin.image(Spr.EQ_CLOSE_BUTTON_ACTIVE), at: L.closeButton) }

        // ON = relative scaling, AUTO = rotate the range every 10 s, PRESETS = range/measure popup.
        c.draw(skin.image(buttonRef(on: state.eqRelative, pressed: state.isPressed(.eqOn),
                                    normal: Spr.EQ_ON_BUTTON, normalDown: Spr.EQ_ON_BUTTON_DEPRESSED,
                                    selected: Spr.EQ_ON_BUTTON_SELECTED, selectedDown: Spr.EQ_ON_BUTTON_SELECTED_DEPRESSED)),
               at: L.onButton)
        c.draw(skin.image(buttonRef(on: state.eqAuto, pressed: state.isPressed(.eqAuto),
                                    normal: Spr.EQ_AUTO_BUTTON, normalDown: Spr.EQ_AUTO_BUTTON_DEPRESSED,
                                    selected: Spr.EQ_AUTO_BUTTON_SELECTED, selectedDown: Spr.EQ_AUTO_BUTTON_SELECTED_DEPRESSED)),
               at: L.autoButton)
        c.draw(skin.image(state.isPressed(.eqPresets) ? Spr.EQ_PRESETS_BUTTON_SELECTED : Spr.EQ_PRESETS_BUTTON),
               at: L.presetsButton)

        let bands = EQModel.bands(snapshot, range: state.eqRange, measure: state.eqMeasure,
                                  relative: state.eqRelative)
        let levels = bands.map { $0.level }
        let preamp = EQModel.preampLevel(snapshot)

        drawGraph(c, skin: skin, levels: levels, preamp: preamp)
        drawSlider(c, skin: skin, rect: L.preampSlider, level: preamp, pressed: state.isPressed(.eqPreamp))
        let B = L.BandSliders.self
        for i in 0..<B.count {
            let rect = SpriteRect(B.x0 + i * B.strideX, B.y, B.w, B.h)
            let level = i < levels.count ? levels[i] : 0
            drawSlider(c, skin: skin, rect: rect, level: level, pressed: state.isPressed(.eqBand(i)))
        }
    }

    private static func buttonRef(on: Bool, pressed: Bool, normal: SpriteRef, normalDown: SpriteRef,
                                  selected: SpriteRef, selectedDown: SpriteRef) -> SpriteRef {
        switch (on, pressed) {
        case (true, true): return selectedDown
        case (true, false): return selected
        case (false, true): return normalDown
        case (false, false): return normal
        }
    }

    private static func drawSlider(_ c: SkinCanvas, skin: Skin, rect: SpriteRect, level: Double, pressed: Bool) {
        c.draw(skin.frame(.eqmain, Sliders.frameIndex(fraction: level)), at: rect)
        let y = Sliders.eqThumbY(value: level, sliderY: rect.y, travel: Layout.EQ.sliderThumbTravelY)
        let ref = pressed ? Spr.EQ_SLIDER_THUMB_SELECTED : Spr.EQ_SLIDER_THUMB
        c.draw(skin.image(ref), at: SpriteRect(rect.x + Layout.EQ.sliderThumbOffsetX, y, 11, 11))
    }

    /// 113x19 graph: a smooth curve through the 10 band levels, coloured per row from
    /// EQ_GRAPH_LINE_COLORS, plus the preamp level as a horizontal EQ_PREAMP_LINE.
    private static func drawGraph(_ c: SkinCanvas, skin: Skin, levels: [Double], preamp: Double) {
        let rect = Layout.EQ.graph
        c.draw(skin.image(Spr.EQ_GRAPH_BACKGROUND), at: rect)
        guard !levels.isEmpty else { return }

        c.save()
        c.clip(to: rect)

        // The preamp line spans the whole graph at the preamp's height.
        if let line = skin.image(Spr.EQ_PREAMP_LINE) {
            let py = rect.y + rowFor(level: preamp, height: rect.h)
            c.draw(line, in: CGRect(x: CGFloat(rect.x), y: CGFloat(py),
                                    width: CGFloat(min(rect.w, line.width)), height: 1))
        }

        // One colour per graph row, read out of the skin's 1x19 strip once.
        let colours = skin.renderCache.eqGraphRowColors(height: rect.h)
        let curve = EQModel.graphCurve(levels: levels, width: rect.w)
        var previous: Int? = nil
        for x in 0..<rect.w {
            let row = rowFor(level: curve[x], height: rect.h)
            let from = previous ?? row
            let lo = min(from, row), hi = max(from, row)
            for r in lo...hi {
                c.pixel(rect.x + x, rect.y + r, colours[min(r, colours.count - 1)])
            }
            previous = row
        }
        c.restore()
    }

    private static func rowFor(level: Double, height: Int) -> Int {
        let v = min(1, max(0, level))
        return min(height - 1, max(0, Int(((1 - v) * Double(height - 1)).rounded())))
    }

    // MARK: - Hit regions

    public static func regions() -> [HitRegion] {
        let L = Layout.EQ.self
        var out: [HitRegion] = [
            HitRegion(.eqClose, L.closeButton),
            HitRegion(.eqOn, L.onButton),
            HitRegion(.eqAuto, L.autoButton),
            HitRegion(.eqPresets, L.presetsButton),
            HitRegion(.eqGraph, L.graph, showsPressed: false),
            HitRegion(.eqPreamp, L.preampSlider, hasHoverReading: true),
        ]
        let B = L.BandSliders.self
        for i in 0..<B.count {
            out.append(HitRegion(.eqBand(i), SpriteRect(B.x0 + i * B.strideX, B.y, B.w, B.h), hasHoverReading: true))
        }
        out.append(HitRegion(.eqTitleBar, L.titleBar, showsPressed: false, dragsWindow: true))
        out.append(HitRegion(.background, SpriteRect(0, 0, L.size.w, L.size.h), showsPressed: false,
                             dragsWindow: true))
        return out
    }
}
