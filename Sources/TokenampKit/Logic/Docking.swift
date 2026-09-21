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
    public static func defaultStack(mainOrigin topLeft: CGPoint, scale: Double,
                                    mainHeight: Int, eqHeight: Int, playlistHeight: Int) -> (main: CGPoint, eq: CGPoint, playlist: CGPoint) {
        // The *exact* scaled height, not the window's ceil()ed one, so the stack stays flush.
        let s = CGFloat(max(ScaleModel.minPoints, scale))
        let mh = CGFloat(mainHeight) * s
        let eh = CGFloat(eqHeight) * s
        let ph = CGFloat(playlistHeight) * s
        let main = CGPoint(x: topLeft.x, y: topLeft.y - mh)
        let eq = CGPoint(x: topLeft.x, y: main.y - eh)
        let playlist = CGPoint(x: topLeft.x, y: eq.y - ph)
        return (main, eq, playlist)
    }
}
