import CoreGraphics
import Foundation

/// Window scale (SPEC 2.8, amendment A2).
///
/// The unit of scale is **ppsp** - whole *device* pixels per skin pixel - so every skin pixel is
/// always an exact square of device pixels and the art stays razor sharp at every setting. What
/// the user picks, and what is persisted, is the on-screen scale *in points*: `ppsp / backing`.
/// On a Retina (2x) display that makes half steps available - ppsp 2,3,4,5,6 = 1x, 1.5x, 2x,
/// 2.5x, 3x - while a 1x display keeps the classic 1x, 2x, 3x.
///
/// Pure arithmetic, so `--selftest` can pin every case down without a screen.
public enum ScaleModel {

    /// Points-scale never goes below 1x or above 3x.
    public static let minPoints: Double = 1
    public static let maxPoints: Double = 3

    /// Backing factor of a screen, sanitised to a whole number >= 1.
    public static func backingSteps(_ backing: CGFloat) -> Int {
        max(1, Int(backing.rounded()))
    }

    /// Exactly the scales that are valid on a screen with this backing factor, ascending,
    /// expressed in points (`1`, `1.5`, `2`, ...).
    public static func validPointScales(backing: CGFloat) -> [Double] {
        let b = backingSteps(backing)
        return (b...(b * Int(maxPoints))).map { Double($0) / Double(b) }
    }

    /// Device pixels per skin pixel for a points-scale on this screen. Always a whole number
    /// when `points` is one of `validPointScales`.
    public static func ppsp(points: Double, backing: CGFloat) -> Int {
        max(1, Int((points * Double(backingSteps(backing))).rounded()))
    }

    /// The nearest valid scale on this screen. Used when a stored preference cannot be honoured
    /// there (1.5x on a 1x display), *without* overwriting the preference.
    /// A tie (1.5x on a 1x display is exactly between 1x and 2x) goes to the larger scale, the
    /// same way `round()` breaks a tie - the window stays readable rather than shrinking.
    public static func nearest(_ points: Double, backing: CGFloat) -> Double {
        let options = validPointScales(backing: backing)
        guard let first = options.first else { return minPoints }
        return options.dropFirst().reduce(first) { best, s in
            abs(s - points) <= abs(best - points) + 1e-9 ? s : best
        }
    }

    /// The next scale up, wrapping back to the smallest - what the clutterbar's **D** button does.
    public static func next(after points: Double, backing: CGFloat) -> Double {
        let options = validPointScales(backing: backing)
        guard !options.isEmpty else { return minPoints }
        let current = nearest(points, backing: backing)
        let i = options.firstIndex(where: { abs($0 - current) < 1e-9 }) ?? 0
        return options[(i + 1) % options.count]
    }

    /// Skin size of the default docked stack: main + EQ + default playlist.
    public static let stackedSkinHeight = Layout.Main.size.h + Layout.EQ.size.h + Layout.Playlist.defaultSize.h
    public static let skinWidth = Layout.Main.size.w

    /// Default when nothing is stored: the largest valid scale whose main window takes at most
    /// 22 % of the visible width and whose docked stack takes at most 62 % of the visible height.
    /// Never below 1x (SPEC 2.8).
    public static func defaultPointScale(visibleFrame: CGRect, backing: CGFloat) -> Double {
        let options = validPointScales(backing: backing)
        var best = minPoints
        for s in options {
            let fitsWide = Double(skinWidth) * s <= 0.22 * Double(visibleFrame.width)
            let fitsTall = Double(stackedSkinHeight) * s <= 0.62 * Double(visibleFrame.height)
            if fitsWide && fitsTall { best = max(best, s) }
        }
        return best
    }

    /// The scale to use on a screen (SPEC 2.8): the stored preference when there is one, else the
    /// default *for this screen*, snapped to what the screen can render.
    ///
    /// The default is derived from the screen every time, never from the scale currently in use.
    /// Taking the current scale as the "wanted" one made a first-run 1.5x window that visited a 1x
    /// display come back to Retina at 2x (1.5 snaps to 2 there, and 2 was then wanted everywhere).
    public static func resolved(stored: Double?, visibleFrame: CGRect, backing: CGFloat) -> Double {
        nearest(stored ?? defaultPointScale(visibleFrame: visibleFrame, backing: backing), backing: backing)
    }

    /// `1x`, `1.5x`, `2x` - the menu label for a points-scale.
    public static func label(_ points: Double) -> String {
        let rounded = (points * 100).rounded() / 100
        if abs(rounded - rounded.rounded()) < 1e-9 { return "\(Int(rounded.rounded()))x" }
        return String(format: "%.1fx", rounded)
    }

    /// Window content size in points for a skin size: `ceil(skin x scale)`, so the spare fraction
    /// of a point is a transparent sliver rather than a clipped column of art (SPEC 2.8).
    public static func contentSize(skin: SkinPair, points: Double) -> CGSize {
        CGSize(width: (Double(skin.w) * points).rounded(.up), height: (Double(skin.h) * points).rounded(.up))
    }

    /// The exact (unrounded) scaled size, which is what docking arithmetic uses so docked windows
    /// stay pixel-flush.
    public static func exactSize(skin: SkinPair, points: Double) -> CGSize {
        CGSize(width: Double(skin.w) * points, height: Double(skin.h) * points)
    }

    public static func isValid(_ points: Double, backing: CGFloat) -> Bool {
        validPointScales(backing: backing).contains { abs($0 - points) < 1e-9 }
    }
}
