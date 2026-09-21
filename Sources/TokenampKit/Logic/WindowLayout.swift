import CoreGraphics
import Foundation

/// Where the windows are kept between launches, and how a layout whose display went away is
/// brought back (SPEC 2.6, 2.7). Pure geometry in **screen coordinates** (origin bottom-left,
/// y up), so `--selftest` covers it without creating a window.
///
/// Positions are persisted as **top-left corners**. Every size change the app makes - window
/// shade, the Sessions height, a Token Flow resize, a scale change - keeps a window's top-left
/// fixed (`resized(_:to:)`, the way a Winamp window grows downwards), so a stored corner means the
/// same place whatever size the window happens to have when a launch puts it back. A bottom-left
/// origin does not: the shaded strip's origin, applied to the full-height window a launch creates,
/// put the strip (116 - 14) x scale points higher on every relaunch.
public enum WindowLayout {

    // MARK: - Corners

    public static func topLeft(of frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX, y: frame.maxY)
    }

    /// The bottom-left origin (what AppKit takes) of a window of this height whose top-left
    /// corner is `topLeft`.
    public static func origin(topLeft: CGPoint, height: CGFloat) -> CGPoint {
        CGPoint(x: topLeft.x, y: topLeft.y - height)
    }

    /// `frame` resized to `size` around its top-left corner: what `SkinWindow.setSkinSize` does.
    public static func resized(_ frame: CGRect, to size: CGSize) -> CGRect {
        CGRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height)
    }

    /// Window height in points for a skin height: the `ceil(skin x scale)` of SPEC 2.8, the same
    /// number `ScaleModel.contentSize` gives.
    public static func windowHeight(skinHeight: Int, scale: Double) -> CGFloat {
        ScaleModel.contentSize(skin: SkinPair(1, skinHeight), points: scale).height
    }

    // MARK: - The art's own rectangle (SPEC 2.8)

    /// The rectangle a window's art really covers: `skinSize x scale` exactly, hung from the
    /// window's top-left corner. The window itself is `ceil()`ed (412.5 pt of art in a 413 pt
    /// window), and the spare fraction is a transparent sliver along the right and bottom edges, so
    /// docking against the window frame left a one-device-pixel seam. Every docking decision is
    /// made on this rectangle instead.
    public static func skinRect(frame: CGRect, skinSize: SkinPair, scale: Double) -> CGRect {
        let size = ScaleModel.exactSize(skin: skinSize, points: scale)
        return CGRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height)
    }

    /// The window origin (bottom-left, what AppKit takes) that puts the art rectangle's origin at
    /// `skinOrigin`: the two share their top-left corner.
    public static func frameOrigin(skinOrigin: CGPoint, skinHeight: CGFloat, frameHeight: CGFloat) -> CGPoint {
        CGPoint(x: skinOrigin.x, y: skinOrigin.y + skinHeight - frameHeight)
    }

    /// The whole-point window origin for an art rectangle that wants to be at `art`.
    ///
    /// AppKit keeps window frames on whole points - a half-point origin is floored, even on a 2x
    /// display - so an art edge on a half point (261 px of Sessions is 391.5 pt of art at 1.5x)
    /// cannot be met exactly by the window docked to it. Each axis is therefore rounded *towards*
    /// the neighbour the art is docked to: a window hanging under another is rounded up into it, one
    /// to the left of another is rounded right into it. The two arts then overlap by half a point
    /// (one device pixel on Retina) where they would otherwise leave a see-through seam. With no
    /// neighbour on that side the origin is floored, as AppKit would.
    public static func wholePointOrigin(art: CGRect, frameHeight: CGFloat, neighbours: [CGRect],
                                        tolerance: CGFloat = 1) -> CGPoint {
        let exact = CGPoint(x: art.minX, y: art.maxY - frameHeight)
        let spansX = { (n: CGRect) in art.minX < n.maxX && n.minX < art.maxX }
        let spansY = { (n: CGRect) in art.minY < n.maxY && n.minY < art.maxY }
        let hangsUnder = neighbours.contains { spansX($0) && abs(art.maxY - $0.minY) <= tolerance }
        let leftOf = neighbours.contains { spansY($0) && abs(art.maxX - $0.minX) <= tolerance }
        let rightOf = neighbours.contains { spansY($0) && abs(art.minX - $0.maxX) <= tolerance }
        return CGPoint(x: leftOf && !rightOf ? exact.x.rounded(.up) : exact.x.rounded(.down),
                       y: hangsUnder ? exact.y.rounded(.up) : exact.y.rounded(.down))
    }

    /// Skin height of the main window in its normal or window-shade form (SPEC 2.1, 2.2).
    public static func mainSkinHeight(shaded: Bool) -> Int {
        shaded ? Layout.Shade.size.h : Layout.Main.size.h
    }

    /// A point just inside a stored corner, for asking which screen the window is on. The corner
    /// itself lies on the window's top edge, and `CGRect.contains` leaves out a rectangle's top
    /// edge, so a window flush with the top of a screen would otherwise be on no screen at all.
    public static func probePoint(topLeft: CGPoint) -> CGPoint {
        CGPoint(x: topLeft.x + 1, y: topLeft.y - 1)
    }

    // MARK: - Migration from bottom-left origins

    /// Builds before top-left corners stored each window's bottom-left origin, taken at the size
    /// the window had when it was saved. Its corner is that origin raised by that height.
    public static func migratedTopLeft(legacyOrigin: CGPoint, skinHeight: Int, scale: Double) -> CGPoint {
        CGPoint(x: legacyOrigin.x, y: legacyOrigin.y + windowHeight(skinHeight: skinHeight, scale: scale))
    }

    // MARK: - Bringing a layout back on screen

    /// One window as the rescue sees it.
    public struct Slot: Equatable {
        public var frame: CGRect
        /// On screen, or about to be: the main window always, the others per their open preference.
        public var isOpen: Bool
        /// Its position is one the user gave it (a stored corner, or it is on screen now), as
        /// opposed to the default slot the app just picked for it on a screen that exists.
        public var isPlaced: Bool

        public init(frame: CGRect, isOpen: Bool, isPlaced: Bool) {
            self.frame = frame
            self.isOpen = isOpen
            self.isPlaced = isPlaced
        }
    }

    /// Move the windows at `moves` (indices into the slots) by `offset`.
    public struct Rescue: Equatable {
        public var offset: CGVector
        public var moves: [Int]
    }

    /// How far inside the home screen's top-left corner a rescued main window lands - the same
    /// corner the default column starts from.
    public static let rescueInset: CGFloat = 40

    /// A window counts as reachable when it touches *any* screen's visible frame, not just the
    /// main screen's, so a good layout on a second display is never yanked across.
    public static func isReachable(_ frame: CGRect, screens: [CGRect]) -> Bool {
        screens.contains { $0.intersects(frame.insetBy(dx: -1, dy: -1)) }
    }

    /// Decide whether the layout has to be brought back on screen, e.g. after the display it was
    /// on was unplugged. Slot 0 is the main window.
    ///
    /// - Only open windows with a user-given place vote. A closed window is not on screen, so it
    ///   cannot make the layout reachable; a window with no stored corner sits in the default
    ///   column the app just laid out on a live screen, so it proves nothing about the others.
    /// - The app steps in only when *no* voter is reachable; a partly off-screen stack is the
    ///   user's choice.
    /// - Every voter moves by one shared offset, so windows docked together stay docked. The main
    ///   window's top-left lands `rescueInset` inside `home`'s top-left.
    /// - A closed window with a stored place travels with the group when it is off screen too, so
    ///   it reopens where it belongs relative to the stack; one parked on a live screen stays put.
    public static func rescue(_ slots: [Slot], screens: [CGRect], home: CGRect) -> Rescue? {
        let voters = slots.indices.filter { slots[$0].isOpen && slots[$0].isPlaced }
        guard let firstVoter = voters.first else { return nil }
        guard !voters.contains(where: { isReachable(slots[$0].frame, screens: screens) }) else { return nil }

        let anchor = voters.contains(0) ? 0 : firstVoter
        let from = topLeft(of: slots[anchor].frame)
        let to = CGPoint(x: home.minX + rescueInset, y: home.maxY - rescueInset)
        let moves = slots.indices.filter { i in
            let s = slots[i]
            guard s.isPlaced else { return false }
            return s.isOpen || !isReachable(s.frame, screens: screens)
        }
        return Rescue(offset: CGVector(dx: to.x - from.x, dy: to.y - from.y), moves: moves)
    }

    /// Where a window goes when the user opens it: at the foot of the column (SPEC 2.7) when it
    /// was never placed, and also when the place it has is on no screen any more.
    public static func needsPlacementOnOpen(isPlaced: Bool, frame: CGRect, screens: [CGRect]) -> Bool {
        !isPlaced || !isReachable(frame, screens: screens)
    }
}
