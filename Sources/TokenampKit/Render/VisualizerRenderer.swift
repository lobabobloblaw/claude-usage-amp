import CoreGraphics
import Foundation
import UsageModel

/// Draws the 76x16 token-flow well and the 38x5 shade strip. Pure: same input, same pixels.
///
/// This is the only thing that redraws 30 times a second, so the background dot grid and the
/// 16-colour bar ramp come pre-baked out of `SkinRenderCache` instead of being filled pixel by
/// pixel every frame.
public enum VisualizerRenderer {

    /// Main window well (SPEC 2.1).
    public static func draw(_ c: SkinCanvas, skin: Skin, state: ViewState, rect: SpriteRect = Layout.Main.visualizer) {
        let vc = skin.visColors
        if state.visualizerMode == .off {
            c.fill(rect, vc.color(0))
            return
        }
        if let bg = skin.renderCache.visualizerBackground(width: rect.w, height: rect.h) {
            c.draw(bg, at: rect.x, rect.y)
        } else {
            c.fill(rect, vc.color(0))
        }

        switch state.visualizerMode {
        case .spectrum: drawSpectrum(c, skin: skin, state: state, rect: rect)
        case .oscilloscope: drawScope(c, vc: vc, state: state, rect: rect)
        case .off: break
        }
    }

    static func rows(_ v: Double, of total: Int) -> Int {
        min(total, max(0, Int((min(1, max(0, v)) * Double(total)).rounded())))
    }

    private static func drawSpectrum(_ c: SkinCanvas, skin: Skin, state: ViewState, rect: SpriteRect) {
        let total = rect.h
        let capColor = skin.visColors.color(23)
        for j in 0..<VisualizerModel.barCount {
            let x = rect.x + j * VisualizerModel.barPitch
            guard x + VisualizerModel.barWidth <= rect.x + rect.w else { break }
            let h = rows(state.visBars.indices.contains(j) ? state.visBars[j] : 0, of: total)
            if h > 0, let seg = skin.renderCache.barSegment(height: h, rows: total,
                                                            width: VisualizerModel.barWidth) {
                c.draw(seg, at: x, rect.y + total - h)
            }
            let p = rows(state.visPeaks.indices.contains(j) ? state.visPeaks[j] : 0, of: total)
            if p > 0 {
                let row = total - p
                if row >= 0, row < total {
                    c.fill(CGRect(x: CGFloat(x), y: CGFloat(rect.y + row),
                                  width: CGFloat(VisualizerModel.barWidth), height: 1), capColor)
                }
            }
        }
    }

    private static func drawScope(_ c: SkinCanvas, vc: VisColors, state: ViewState, rect: SpriteRect) {
        let centre = rect.h / 2
        let amplitude = Double(rect.h / 2 - 1)
        var previous: Int? = nil
        for i in 0..<rect.w {
            let v = state.visScope.indices.contains(i) ? state.visScope[i] : 0
            var y = centre - Int((v * amplitude).rounded())
            y = min(rect.h - 1, max(0, y))
            let from = previous ?? y
            let lo = min(from, y), hi = max(from, y)
            for row in lo...hi {
                let d = abs(row - centre)
                let idx = 18 + min(4, Int(Double(d) / max(1, amplitude) * 5))
                c.pixel(rect.x + i, rect.y + row, vc.color(idx))
            }
            previous = y
        }
    }

    /// Window-shade mini visualizer: 19 bars x 2 px in a 38x5 strip (SPEC 2.2).
    public static func drawMini(_ c: SkinCanvas, skin: Skin, state: ViewState,
                                rect: SpriteRect = Layout.Shade.miniVisualizer) {
        guard state.visualizerMode != .off else { return }
        c.fill(rect, skin.visColors.color(0))
        let total = rect.h
        for j in 0..<VisualizerModel.barCount {
            let x = rect.x + j * 2
            guard x + 2 <= rect.x + rect.w else { break }
            let h = rows(state.visBars.indices.contains(j) ? state.visBars[j] : 0, of: total)
            guard h > 0, let seg = skin.renderCache.miniSegment(height: h, rows: total, width: 2) else { continue }
            c.draw(seg, at: x, rect.y + total - h)
        }
    }
}
