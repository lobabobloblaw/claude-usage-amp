import Foundation
import UsageModel

/// Slider geometry, straight out of SPEC 2.1 and the travel ranges in sprites.json.
/// Formulas live here (and nowhere else) so `--selftest` can pin the exact pixel positions.
public enum Sliders {

    public static let frameCount = 28

    /// Background heat-ramp frame for a 0...100 percentage: `round(pct * 27 / 100)`.
    public static func frameIndex(percent: Double) -> Int {
        let p = min(100, max(0, percent))
        return min(frameCount - 1, max(0, Int((p * Double(frameCount - 1) / 100).rounded())))
    }

    /// Background frame for a 0...1 fraction: `round(v * 27)` (EQ sliders, SPEC 2.3).
    public static func frameIndex(fraction: Double) -> Int {
        let v = min(1, max(0, fraction))
        return min(frameCount - 1, max(0, Int((v * Double(frameCount - 1)).rounded())))
    }

    /// Thumb x for a percentage over a `[lo, hi]` travel range (volume: 107...158, balance: 177...201).
    public static func thumbX(percent: Double, travel: SkinPair) -> Int {
        let p = min(100, max(0, percent))
        return travel.lo + Int((p * Double(travel.span) / 100).rounded(.down))
    }

    /// Thumb x for a 0...1 fraction over a travel range (position bar: 16...235, i.e. 0...219 px).
    public static func thumbX(fraction: Double, travel: SkinPair) -> Int {
        let f = min(1, max(0, fraction))
        return travel.lo + Int((f * Double(travel.span)).rounded(.down))
    }

    /// EQ slider thumb y inside its well: value 1 is at the top, value 0 at the bottom.
    public static func eqThumbY(value: Double, sliderY: Int, travel: SkinPair) -> Int {
        let v = min(1, max(0, value))
        return sliderY + travel.lo + Int(((1 - v) * Double(travel.span)).rounded())
    }

    /// Inverse of `eqThumbY`, for a future draggable EQ (the gauges are read-only today).
    public static func eqValue(forThumbY y: Int, sliderY: Int, travel: SkinPair) -> Double {
        guard travel.span != 0 else { return 0 }
        let rel = Double(y - sliderY - travel.lo) / Double(travel.span)
        return min(1, max(0, 1 - rel))
    }

    /// Volume gauge = session utilisation (SPEC 2.1).
    public static func volume(_ snapshot: UsageSnapshot) -> (thumbX: Int, frame: Int, percent: Double)? {
        guard let pct = HeroTrack.sessionPercent(snapshot) else { return nil }
        return (thumbX(percent: pct, travel: Layout.Main.volumeThumbTravel), frameIndex(percent: pct), pct)
    }

    /// Balance gauge = weekly-all utilisation.
    public static func balance(_ snapshot: UsageSnapshot) -> (thumbX: Int, frame: Int, percent: Double)? {
        guard let pct = HeroTrack.weeklyPercent(snapshot) else { return nil }
        return (thumbX(percent: pct, travel: Layout.Main.balanceThumbTravel), frameIndex(percent: pct), pct)
    }

    /// Position bar = the hero limit's elapsed fraction. nil hides the thumb (SPEC 2.1).
    public static func position(_ snapshot: UsageSnapshot, heroIndex: Int, now: Date) -> (thumbX: Int, fraction: Double)? {
        guard let hero = HeroTrack.hero(in: snapshot, index: heroIndex),
              let f = hero.elapsedFraction(at: now) else { return nil }
        return (thumbX(fraction: f, travel: Layout.Main.posbarThumbTravel), f)
    }

    /// Shade-strip mini position bar (SPEC 2.2): 17x7 well, 3 px thumb, left/centre/right third.
    public enum ShadeThumbPiece { case left, centre, right }

    public static func shadePosition(fraction: Double) -> (x: Int, piece: ShadeThumbPiece) {
        let travel = Layout.Shade.positionThumbTravel
        let x = thumbX(fraction: fraction, travel: travel)
        let rel = Double(x - travel.lo) / Double(max(1, travel.span))
        let piece: ShadeThumbPiece = rel < 1.0 / 3 ? .left : (rel < 2.0 / 3 ? .centre : .right)
        return (x, piece)
    }
}
