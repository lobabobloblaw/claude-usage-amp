import Foundation

/// Scroll position and selection of the Sessions list (SPEC 2.4), kept valid while the data moves
/// underneath them. Pure, so `--selftest` covers it without a window.
///
/// The list is re-sorted by activity on every publish, so the selection is held by **session id**:
/// held as a row index it pointed at a different session after the next update, and "Reveal
/// Selected in Finder" opened the wrong folder. A session that drops out of the list takes the
/// selection with it. The scroll position is re-clamped on every update too, or a shrinking list
/// left the window scrolled past its last row.
public struct SessionListState: Equatable {

    public private(set) var scroll = 0
    public private(set) var selectedID: String?

    public init() {}

    public static func maxScroll(count: Int, visibleRows: Int) -> Int {
        max(0, count - max(0, visibleRows))
    }

    public mutating func setScroll(_ value: Int, count: Int, visibleRows: Int) {
        scroll = min(max(0, value), SessionListState.maxScroll(count: count, visibleRows: visibleRows))
    }

    /// Select the row at `index` of `ids` (nil, or an index past the end, clears the selection).
    public mutating func select(index: Int?, in ids: [String]) {
        guard let index, ids.indices.contains(index) else {
            selectedID = nil
            return
        }
        selectedID = ids[index]
    }

    /// The selected session's row in the list as it is now.
    public func selectedIndex(in ids: [String]) -> Int? {
        guard let selectedID else { return nil }
        return ids.firstIndex(of: selectedID)
    }

    /// New data: re-clamp the scroll position and forget a selection whose session is gone.
    /// Returns true when anything changed.
    @discardableResult
    public mutating func reconcile(ids: [String], visibleRows: Int) -> Bool {
        let before = self
        if let selectedID, !ids.contains(selectedID) { self.selectedID = nil }
        setScroll(scroll, count: ids.count, visibleRows: visibleRows)
        return self != before
    }
}
