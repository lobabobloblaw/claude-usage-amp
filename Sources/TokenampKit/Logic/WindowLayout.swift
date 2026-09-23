import CoreGraphics
import Foundation

/// Where the windows are kept between launches, how a layout whose display went away is brought
/// back (SPEC 2.6, 2.7), and how the main window's docked group is kept on screen (SPEC 2.8).
/// Pure geometry in **screen coordinates** (origin bottom-left, y up), so `--selftest` covers it
/// without creating a window.
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
        /// Its art rectangle (`skinRect`); the window frame would do as well, as the checks allow a
        /// point of slack.
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

    /// What the rescue does: move the windows at `moves` (indices into the slots) by `offset`,
    /// then put each of `strays`, in that order, at the foot of the column (SPEC 2.7).
    public struct Rescue: Equatable {
        /// Whole points. Zero when the main window is on a screen.
        public var offset: CGVector
        /// The main window and its docked group, when the main window is on no screen; else empty.
        public var moves: [Int]
        /// Open windows, other than the main one and not in `moves`, that have no place of their
        /// own or whose place is on no screen.
        public var strays: [Int]

        public init(offset: CGVector, moves: [Int], strays: [Int] = []) {
            self.offset = offset
            self.moves = moves
            self.strays = strays
        }
    }

    /// How far inside the home screen's top-left corner a rescued main window lands - the same
    /// corner the default column starts from.
    public static let rescueInset: CGFloat = 40

    /// A window counts as reachable when it touches *any* screen's visible frame, not just the
    /// main screen's, so a good layout on a second display is never yanked across.
    public static func isReachable(_ frame: CGRect, screens: [CGRect]) -> Bool {
        screens.contains { $0.intersects(frame.insetBy(dx: -1, dy: -1)) }
    }

    /// Decide what has to be brought back on screen, e.g. after the display a window was on was
    /// unplugged. Slot 0 is the main window; nil when nothing has to move.
    ///
    /// - Without a place of its own for the main window, every window is in the default column the
    ///   app just laid out on a live screen: nothing to do.
    /// - When the main window is on no screen it is rescued together with its docked group - the
    ///   placed windows docked to it, transitively, in the stored layout - by one whole-point
    ///   offset, so they stay docked; its top-left lands `rescueInset` inside `home`'s top-left.
    ///   Whatever else is still on a screen stays where the user put it.
    /// - A closed member of the group travels only when it is off screen too, so it reopens where
    ///   it belongs relative to the stack; one parked on a live screen stays put.
    /// - Every other open window with no place of its own, or with a place on no screen, is a
    ///   stray: it goes to the foot of the column (`needsPlacementOnOpen`), in slot order. A closed
    ///   one is dealt with when it is opened.
    public static func rescue(_ slots: [Slot], screens: [CGRect], home: CGRect) -> Rescue? {
        guard let main = slots.first, main.isPlaced else { return nil }

        var offset = CGVector.zero
        var moves: [Int] = []
        if !isReachable(main.frame, screens: screens) {
            let placed = slots.indices.dropFirst().filter { slots[$0].isPlaced }
            let docked = Docking.dockedGroup(anchor: main.frame, frames: placed.map { slots[$0].frame })
            moves = [0] + docked.map { placed[$0] }.sorted().filter { i in
                slots[i].isOpen || !isReachable(slots[i].frame, screens: screens)
            }
            let from = topLeft(of: main.frame)
            let to = CGPoint(x: home.minX + rescueInset, y: home.maxY - rescueInset)
            offset = CGVector(dx: (to.x - from.x).rounded(), dy: (to.y - from.y).rounded())
        }
        let strays = slots.indices.dropFirst().filter { i in
            slots[i].isOpen && !moves.contains(i)
                && needsPlacementOnOpen(isPlaced: slots[i].isPlaced, frame: slots[i].frame, screens: screens)
        }
        guard !moves.isEmpty || !strays.isEmpty else { return nil }
        return Rescue(offset: offset, moves: moves, strays: strays)
    }

    // MARK: - Keeping the main window's group on screen (SPEC 2.8)

    /// Is `rect` wholly inside the visible frames, give or take `tolerance` points at its edges?
    /// It may span two displays: visible frames never overlap (displays tile the desktop), so the
    /// areas they cover add up. The slack lets an art edge that whole-point rounding left half a
    /// point past a screen edge (A6) count as on screen.
    public static func isWhollyOnScreen(_ rect: CGRect, screens: [CGRect], tolerance: CGFloat = 1) -> Bool {
        let inner = rect.insetBy(dx: tolerance, dy: tolerance)
        guard !inner.isNull, inner.width > 0, inner.height > 0 else { return isReachable(rect, screens: screens) }
        let covered = screens.reduce(CGFloat(0)) { sum, screen in
            let part = screen.intersection(inner)
            return part.isNull ? sum : sum + part.width * part.height
        }
        return covered >= inner.width * inner.height - 1e-6
    }

    /// The offset that brings the main window's docked group (`group`, its art rectangles) back
    /// inside `home` - the visible frame of the main window's screen - as one unit, or nil when it
    /// need not move (SPEC 2.8).
    ///
    /// - Nothing moves while every window of the group lies wholly on some screen, so a stack the
    ///   user spread over two displays stays put.
    /// - Otherwise the union of the group moves by the shortest distance that puts it inside
    ///   `home`: up or left when it hangs off the bottom or the right, down or right when it hangs
    ///   off the top or the left.
    /// - A group taller than `home` keeps its top on screen, at the top of `home`; one wider than
    ///   `home` keeps its left edge at the left of `home`. That is where the title bars are.
    /// - The offset is in whole points, the same for every window, so docked windows keep their
    ///   places relative to one another exactly and no seam can open between them (A6).
    public static func onScreenShift(_ group: [CGRect], screens: [CGRect], home: CGRect,
                                     tolerance: CGFloat = 1) -> CGVector? {
        guard let first = group.first else { return nil }
        guard !group.allSatisfy({ isWhollyOnScreen($0, screens: screens, tolerance: tolerance) }) else { return nil }
        let union = group.dropFirst().reduce(first) { $0.union($1) }
        let dx = axisShift(low: union.minX, high: union.maxX, screenLow: home.minX, screenHigh: home.maxX,
                           keepHigh: false)
        let dy = axisShift(low: union.minY, high: union.maxY, screenLow: home.minY, screenHigh: home.maxY,
                           keepHigh: true)
        return dx == 0 && dy == 0 ? nil : CGVector(dx: dx, dy: dy)
    }

    /// One axis of `onScreenShift`: the whole-point shift that puts `low...high` inside
    /// `screenLow...screenHigh` by the shortest move. When it cannot fit, the edge that stays on
    /// screen is `high` (`keepHigh`: the top) or `low` (the left).
    static func axisShift(low: CGFloat, high: CGFloat, screenLow: CGFloat, screenHigh: CGFloat,
                          keepHigh: Bool) -> CGFloat {
        let least = screenLow - low      // any shift at least this keeps `low` on screen
        let most = screenHigh - high     // any shift at most this keeps `high` on screen
        let keep = keepHigh ? most.rounded(.down) : least.rounded(.up)
        guard least <= most else { return keep }
        if least <= 0, 0 <= most { return 0 }
        let whole = least > 0 ? least.rounded(.up) : most.rounded(.down)
        // Less than a point of room: no whole shift fits both edges, so keep the one that matters.
        return whole >= least && whole <= most ? whole : keep
    }

    /// Where a window goes when it is opened, at launch or later: at the foot of the column
    /// (SPEC 2.7) when it was never placed, and also when the place it has is on no screen any more.
    public static func needsPlacementOnOpen(isPlaced: Bool, frame: CGRect, screens: [CGRect]) -> Bool {
        !isPlaced || !isReachable(frame, screens: screens)
    }
}
