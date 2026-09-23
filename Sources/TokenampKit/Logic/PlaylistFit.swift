import CoreGraphics
import Foundation

/// Auto-fit for the Sessions window (SPEC 2.4, amendment A7): the height that shows every session
/// and no more, capped so the window and the column hanging under it stay on screen. Pure, so
/// `--selftest` covers it without a window.
///
/// Every height here is one the grip could produce (`PlaylistRenderer.snapHeight`): the minimum,
/// then whole resize steps. The row arithmetic is `PlaylistRenderer.visibleRows` turned around:
/// a height shows `n` rows when its list area (the height less the title and bottom bars) holds
/// `n` whole rows at the skin's pitch.
public enum PlaylistFit {

    /// The smallest valid height whose list shows `count` rows at `rowHeight` (the skin's `plfont`
    /// pitch, SPEC 3.2), but never taller than the largest valid height within `maxHeight`, and
    /// never below the minimum - a cap below the minimum still gets the minimum. No sessions is the
    /// minimum height. Past the cap the list scrolls.
    public static func height(count: Int, rowHeight: Int, maxHeight: Int = .max) -> Int {
        let L = Layout.Playlist.self
        let minH = L.minSize.h
        let step = L.resizeStep.h
        let needed = L.titleHeight + L.bottomHeight + max(0, count) * max(1, rowHeight)
        let steps = max(0, (needed - minH + step - 1) / step)
        return min(minH + steps * step, largestHeight(atMost: maxHeight))
    }

    /// The largest valid height that is at most `limit`, never below the minimum.
    public static func largestHeight(atMost limit: Int) -> Int {
        let L = Layout.Playlist.self
        guard limit > L.minSize.h else { return L.minSize.h }
        return L.minSize.h + (limit - L.minSize.h) / L.resizeStep.h * L.resizeStep.h
    }

    /// The tallest Sessions height, in skin pixels, that keeps the window and everything docked
    /// below it inside `screen` (a visible frame), given its art rectangle now (`art`), the art
    /// rectangles of the windows docked below it (`Docking.dockedBelow`) and the scale in points.
    /// The window keeps its top-left, so the room is what lies between its top edge and the
    /// screen's bottom once the windows below it are set aside.
    ///
    /// Those windows hang from the bottom edge rounded up to a whole point and move with it
    /// (`Docking.followingShift`), so they are measured from that rounded edge, and the answer is
    /// exact at a half-point scale too. It may be below the minimum when even the shortest window
    /// cannot fit; `height` then still gives the minimum.
    public static func maxHeight(art: CGRect, below: [CGRect], screen: CGRect, scale: Double) -> Int {
        let s = CGFloat(max(ScaleModel.minPoints, scale))
        guard let lowest = below.map({ $0.minY }).min() else {
            // Nothing below: only the window's own art has to stay on screen.
            return Int(((art.maxY - screen.minY) / s).rounded(.down))
        }
        let extent = max(0, art.minY.rounded(.up) - lowest)
        func fits(_ h: Int) -> Bool {
            (art.maxY - CGFloat(h) * s).rounded(.up) - extent >= screen.minY
        }
        // This fits with up to a point to spare, which the rounding up can give to one more pixel.
        var h = Int(((art.maxY - extent - screen.minY) / s).rounded(.down))
        while fits(h + 1) { h += 1 }
        return h
    }
}
