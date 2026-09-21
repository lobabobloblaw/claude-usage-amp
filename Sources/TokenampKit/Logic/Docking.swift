import CoreGraphics
import Foundation

/// Magnetic docking geometry (SPEC 2.7). Pure functions over rectangles in **screen coordinates**
/// (macOS: origin bottom-left, y up), so `--selftest` can check the snapping arithmetic without
/// ever creating a window.
public enum Docking {

    /// Snap distance in skin pixels; multiplied by the current scale at the call site.
    public static let thresholdSkinPixels: CGFloat = 8

    public static func threshold(scale: Double) -> CGFloat {
        thresholdSkinPixels * CGFloat(max(ScaleModel.minPoints, scale))
    }

    /// Snap `frame`'s origin to any sibling frame or to the screen's visible frame.
    ///
    /// Horizontal and vertical are decided independently; the nearest candidate inside the
    /// threshold wins on each axis.
    public static func snap(frame: CGRect, to others: [CGRect], screen: CGRect?, threshold t: CGFloat) -> CGPoint {
        var best = frame.origin
        var bestDX = t
        var bestDY = t

        func considerX(_ candidateX: CGFloat) {
            let d = abs(candidateX - frame.minX)
            if d < bestDX { bestDX = d; best.x = candidateX }
        }
        func considerY(_ candidateY: CGFloat) {
            let d = abs(candidateY - frame.minY)
            if d < bestDY { bestDY = d; best.y = candidateY }
        }

        for other in others {
            // Vertical adjacency: only snap when the windows overlap horizontally (or nearly).
            if overlaps(frame.minX, frame.maxX, other.minX, other.maxX, slack: t) {
                considerY(other.maxY)                    // our bottom edge on their top edge
                considerY(other.minY - frame.height)     // our top edge on their bottom edge
                considerY(other.minY)                    // flush bottoms
                considerY(other.maxY - frame.height)     // flush tops
            }
            if overlaps(frame.minY, frame.maxY, other.minY, other.maxY, slack: t) {
                considerX(other.maxX)                    // our left edge on their right edge
                considerX(other.minX - frame.width)      // our right edge on their left edge
                considerX(other.minX)                    // flush lefts
                considerX(other.maxX - frame.width)      // flush rights
            }
        }

        if let screen {
            considerX(screen.minX)
            considerX(screen.maxX - frame.width)
            considerY(screen.minY)
            considerY(screen.maxY - frame.height)
        }
        return best
    }

    private static func overlaps(_ a0: CGFloat, _ a1: CGFloat, _ b0: CGFloat, _ b1: CGFloat, slack: CGFloat) -> Bool {
        a0 - slack < b1 && b0 - slack < a1
    }

    /// Are two windows edge-adjacent (touching, with a 1 px tolerance) and overlapping on the
    /// shared axis? That is what "docked" means for group dragging.
    public static func isAdjacent(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 1.0) -> Bool {
        let verticallyTouching = abs(a.maxY - b.minY) <= tolerance || abs(b.maxY - a.minY) <= tolerance
        if verticallyTouching, overlaps(a.minX, a.maxX, b.minX, b.maxX, slack: 0) { return true }
        let horizontallyTouching = abs(a.maxX - b.minX) <= tolerance || abs(b.maxX - a.minX) <= tolerance
        if horizontallyTouching, overlaps(a.minY, a.maxY, b.minY, b.maxY, slack: 0) { return true }
        return false
    }

    /// Transitive closure of "docked to the anchor", by index into `frames`.
    /// The anchor itself is not included.
    public static func dockedGroup(anchor: CGRect, frames: [CGRect], tolerance: CGFloat = 1.0) -> Set<Int> {
        var group: Set<Int> = []
        var wave: [CGRect] = [anchor]
        var changed = true
        while changed {
            changed = false
            for (i, f) in frames.enumerated() where !group.contains(i) {
                if wave.contains(where: { isAdjacent($0, f, tolerance: tolerance) }) {
                    group.insert(i)
                    wave.append(f)
                    changed = true
                }
            }
        }
        return group
    }

    /// Default stacked layout: main at `mainOrigin` (top-left in screen coords), EQ directly
    /// under it, playlist under the EQ (SPEC 2.7). Returns bottom-left origins for AppKit.
    /// Stack windows into a flush column from a top-left corner, given their skin-pixel heights
    /// in top-to-bottom order. Returns one origin per height.
    ///
    /// Heights are scaled *exactly*, not through the window's ceil()ed size, so the column stays
    /// flush at a fractional scale (SPEC 2.8).
    public static func defaultColumn(topLeft: CGPoint, scale: Double, heights: [Int]) -> [CGPoint] {
        let s = CGFloat(max(ScaleModel.minPoints, scale))
        var out: [CGPoint] = []
        var top = topLeft.y
        for h in heights {
            let scaled = CGFloat(h) * s
            out.append(CGPoint(x: topLeft.x, y: top - scaled))
            top -= scaled
        }
        return out
    }

    /// The default column as whole-point top-left corners (what the windows are placed by): each
    /// window hangs under the previous one's *art* (skin size x scale exactly, SPEC 2.8), rounded
    /// up where that edge falls on a half point (`WindowLayout.wholePointOrigin`) - so at 1.5x the
    /// window under an odd-height Sessions overlaps it by half a point instead of leaving a gap.
    public static func column(topLeft: CGPoint, scale: Double, skinSizes: [SkinPair]) -> [CGPoint] {
        var out: [CGPoint] = []
        var above: CGRect?
        for skin in skinSizes {
            let size = ScaleModel.exactSize(skin: skin, points: scale)
            let frameHeight = ScaleModel.contentSize(skin: skin, points: scale).height
            let wantedTop = above?.minY ?? topLeft.y
            let art = CGRect(x: topLeft.x, y: wantedTop - size.height, width: size.width, height: size.height)
            let origin = WindowLayout.wholePointOrigin(art: art, frameHeight: frameHeight,
                                                       neighbours: above.map { [$0] } ?? [])
            let top = CGPoint(x: origin.x, y: origin.y + frameHeight)
            out.append(top)
            above = CGRect(x: top.x, y: top.y - size.height, width: size.width, height: size.height)
        }
        return out
    }

    // MARK: - Keeping a docked group together across a size or scale change (SPEC 2.8)

    /// One window around the main one, as `relayout` sees it.
    public struct GroupMember {
        /// Its art rectangle (`WindowLayout.skinRect`) before the change.
        public var rect: CGRect
        /// Its size in skin pixels, which a scale change does not alter.
        public var skinSize: SkinPair
        /// Docked to the main window (transitively) before the change.
        public var isDocked: Bool

        public init(rect: CGRect, skinSize: SkinPair, isDocked: Bool) {
            self.rect = rect
            self.skinSize = skinSize
            self.isDocked = isDocked
        }
    }

    /// Where the docked windows go after the main window changed size or scale: new whole-point
    /// top-left corners by index into `members`. Undocked windows are absent - they stay where the
    /// user parked them.
    ///
    /// A window that hung directly under the previous one in the column goes directly under its new
    /// art rectangle, so main -> Sessions -> Token Flow stays docked; anything else docked keeps its
    /// offset from the main window's top-left, in whole skin pixels so it survives a scale change
    /// and a round trip. All of it on art rectangles, never on the `ceil()`ed window frames, and
    /// each corner rounded towards the window it docks to (`WindowLayout.wholePointOrigin`).
    public static func relayout(main old: CGRect, to now: CGRect, scale oldScale: Double, to newScale: Double,
                                members: [GroupMember]) -> [Int: CGPoint] {
        let oldS = CGFloat(max(ScaleModel.minPoints, oldScale))
        let newS = CGFloat(max(ScaleModel.minPoints, newScale))
        var placed: [Int: CGPoint] = [:]
        var settled: [CGRect] = [now]      // art rectangles already in their new place

        /// Put member `i`'s art at `wanted` (its exact top-left), on whole points; its art rectangle.
        func place(_ i: Int, _ wanted: CGPoint) -> CGRect {
            let skin = members[i].skinSize
            let size = ScaleModel.exactSize(skin: skin, points: Double(newS))
            let frameHeight = ScaleModel.contentSize(skin: skin, points: Double(newS)).height
            let art = CGRect(x: wanted.x, y: wanted.y - size.height, width: size.width, height: size.height)
            let origin = WindowLayout.wholePointOrigin(art: art, frameHeight: frameHeight, neighbours: settled)
            let top = CGPoint(x: origin.x, y: origin.y + frameHeight)
            placed[i] = top
            let result = CGRect(x: top.x, y: top.y - size.height, width: size.width, height: size.height)
            settled.append(result)
            return result
        }

        var anchorOld = old
        var anchorNew = now
        var progress = true
        while progress {
            progress = false
            for (i, m) in members.enumerated() where m.isDocked && placed[i] == nil {
                guard abs(m.rect.maxY - anchorOld.minY) <= 1,
                      m.rect.minX < anchorOld.maxX, anchorOld.minX < m.rect.maxX else { continue }
                let dxSkin = ((m.rect.minX - anchorOld.minX) / oldS).rounded()
                anchorOld = m.rect
                anchorNew = place(i, CGPoint(x: anchorNew.minX + dxSkin * newS, y: anchorNew.minY))
                progress = true
                break
            }
        }

        for (i, m) in members.enumerated() where m.isDocked && placed[i] == nil {
            let dxSkin = ((m.rect.minX - old.minX) / oldS).rounded()
            let dySkin = ((old.maxY - m.rect.maxY) / oldS).rounded()
            _ = place(i, CGPoint(x: now.minX + dxSkin * newS, y: now.maxY - dySkin * newS))
        }
        return placed
    }
}
