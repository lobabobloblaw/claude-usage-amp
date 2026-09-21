import AppKit
import Foundation

/// Magnetic window docking (SPEC 2.7). Owns no windows; it is handed the current set on every
/// drag so windows can come and go. All geometry lives in `Logic/Docking.swift`.
///
/// Every decision is made on the windows' art rectangles (`SkinWindow.skinFrame`: skin size x
/// scale exactly), not on their frames, which are `ceil()`ed to whole points (SPEC 2.8). At 1.5x an
/// odd-height Sessions window is 391.5 pt of art in a 392 pt frame, and docking to the frame left a
/// see-through one-device-pixel seam under it. AppKit keeps window origins on whole points, so a
/// half-point art edge is met by rounding towards it (`WindowLayout.wholePointOrigin`): docked
/// arts touch or overlap by one device pixel, and never gap.
public final class DockingManager {

    public weak var main: SkinWindow?
    public weak var equalizer: SkinWindow?
    public weak var playlist: SkinWindow?
    public weak var field: SkinWindow?
    /// Points per skin pixel (SPEC 2.8).
    public var scale: Double = 2

    /// Offsets of the windows that were docked to the anchor when the drag began.
    private var followers: [(window: SkinWindow, offset: CGPoint)] = []

    /// Between `beginDrag` and `endDrag`.
    private var dragActive = false

    /// A window drag is in progress. Also checks the button, so a drag whose mouse-up never
    /// arrived cannot hold anything back for good.
    public var isDragging: Bool { dragActive && (NSEvent.pressedMouseButtons & 1) != 0 }

    /// Called when a window drag ends - where work that must not happen mid-drag (a rescale when
    /// the main window changed screens) catches up.
    public var onDragEnd: (() -> Void)?

    public init() {}

    private var allWindows: [SkinWindow] {
        [main, equalizer, playlist, field].compactMap { $0 }.filter { $0.isVisible }
    }

    private func screenFrame(for window: SkinWindow) -> CGRect? {
        (window.screen ?? NSScreen.main)?.visibleFrame
    }

    /// Remember which windows are docked to `anchor` so they can travel with it.
    ///
    /// Only the main window carries its group (SPEC 2.7). A sub-window that picked up followers
    /// would be impossible to pull out of a docked stack: dragging it would move everything it
    /// touches, so it would never appear to move at all.
    public func beginDrag(anchor: SkinWindow) {
        dragActive = true
        guard anchor === main else {
            followers = []
            return
        }
        let others = allWindows.filter { $0 !== anchor }
        let group = Docking.dockedGroup(anchor: anchor.skinFrame, frames: others.map { $0.skinFrame })
        followers = group.sorted().map { i in
            (others[i], CGPoint(x: others[i].frame.minX - anchor.frame.minX,
                                y: others[i].frame.minY - anchor.frame.minY))
        }
    }

    public func endDrag() {
        followers.removeAll()
        dragActive = false
        onDragEnd?()
    }

    /// Snap `proposed` (a window origin) and move the anchor plus everything docked to it.
    @discardableResult
    public func drag(anchor: SkinWindow, to proposed: CGPoint) -> CGPoint {
        let followerSet = Set(followers.map { ObjectIdentifier($0.window) })
        let others = allWindows.filter { $0 !== anchor && !followerSet.contains(ObjectIdentifier($0)) }
        let snapped = snappedOrigin(of: anchor, at: proposed, to: others)
        anchor.setFrameOrigin(snapped)
        for f in followers {
            f.window.setFrameOrigin(CGPoint(x: snapped.x + f.offset.x, y: snapped.y + f.offset.y))
        }
        return snapped
    }

    /// Snap a window that is being placed (not dragged), e.g. after a scale change.
    public func settle(_ window: SkinWindow) {
        let others = allWindows.filter { $0 !== window }
        window.setFrameOrigin(snappedOrigin(of: window, at: window.frame.origin, to: others))
    }

    /// The window origin that snaps `window`'s art rectangle, were the window at `origin`, to the
    /// art rectangles of `others` and to the screen edges.
    private func snappedOrigin(of window: SkinWindow, at origin: CGPoint, to others: [SkinWindow]) -> CGPoint {
        let art = window.skinFrame
        let frameHeight = window.frame.height
        let candidate = CGRect(x: origin.x, y: origin.y + frameHeight - art.height,
                               width: art.width, height: art.height)
        let neighbours = others.map { $0.skinFrame }
        let snapped = Docking.snap(frame: candidate, to: neighbours, screen: screenFrame(for: window),
                                   threshold: Docking.threshold(scale: scale))
        return WindowLayout.wholePointOrigin(art: CGRect(origin: snapped, size: art.size),
                                             frameHeight: frameHeight, neighbours: neighbours)
    }

    /// Default placement (SPEC 2.7): the main window at the top, Sessions under it, Token Flow
    /// under that. The Usage Equalizer is placed at the foot of the column but starts closed - its
    /// sliders are read-only gauges, so it is the one window that does not earn a place on screen
    /// until it is asked for.
    public func applyDefaultLayout() {
        guard let main else { return }
        let screen = screenFrame(for: main) ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let topLeft = CGPoint(x: screen.minX + 40, y: screen.maxY - 40)
        let column = Docking.column(topLeft: topLeft, scale: scale,
                                    skinSizes: [Layout.Main.size,
                                                playlist?.skinSize ?? Layout.Playlist.defaultSize,
                                                field?.skinSize ?? Layout.Field.defaultSize,
                                                Layout.EQ.size])
        main.setTopLeft(column[0])
        playlist?.setTopLeft(column[1])
        field?.setTopLeft(column[2])
        equalizer?.setTopLeft(column[3])
    }

    /// Where a window with no stored origin goes when it is opened: at the foot of whatever of the
    /// column is on screen, so it never lands on top of another window.
    public func placeBelowColumn(_ window: SkinWindow) {
        let others = allWindows.filter { $0 !== window }.map { $0.skinFrame }
        guard let lowest = others.min(by: { $0.minY < $1.minY }) else { return }
        let size = window.skinFrame.size
        let art = CGRect(x: lowest.minX, y: lowest.minY - size.height, width: size.width, height: size.height)
        window.setFrameOrigin(WindowLayout.wholePointOrigin(art: art, frameHeight: window.frame.height,
                                                            neighbours: others))
    }

    // MARK: - Keeping a docked group together across a size or scale change

    /// A snapshot of where everything was before the main window changed size or scale, as art
    /// rectangles.
    public struct GroupLayout {
        let main: CGRect
        let scale: Double
        let frames: [(window: SkinWindow, frame: CGRect)]
        /// Which of `frames` were docked to the main window (transitively) at capture time.
        let docked: Set<ObjectIdentifier>
    }

    /// Record the current geometry, so `relayoutDocked` can put the docked windows back where they
    /// belong afterwards. Windows the user deliberately parked elsewhere are *not* in `docked`,
    /// and are therefore left exactly where they are (SPEC 2.8: only docked windows re-lay out).
    public func captureLayout() -> GroupLayout? {
        guard let main else { return nil }
        let others = allWindows.filter { $0 !== main }
        let group = Docking.dockedGroup(anchor: main.skinFrame, frames: others.map { $0.skinFrame })
        var docked: Set<ObjectIdentifier> = []
        for i in group where i < others.count { docked.insert(ObjectIdentifier(others[i])) }
        return GroupLayout(main: main.skinFrame, scale: scale,
                           frames: others.map { ($0, $0.skinFrame) }, docked: docked)
    }

    /// Re-place the windows that were docked to the main window, at the new scale or size
    /// (`Docking.relayout`). A window that hung below the main window stays below it; anything else
    /// keeps its offset from the main window's top-left, measured in skin pixels so it survives a
    /// scale change.
    public func relayoutDocked(from before: GroupLayout?) {
        guard let before, let main else { return }
        let members = before.frames.map { window, rect in
            Docking.GroupMember(rect: rect, skinSize: window.skinSize,
                                isDocked: before.docked.contains(ObjectIdentifier(window)))
        }
        let placed = Docking.relayout(main: before.main, to: main.skinFrame, scale: before.scale, to: scale,
                                      members: members)
        for (i, topLeft) in placed.sorted(by: { $0.key < $1.key }) {
            before.frames[i].window.setTopLeft(topLeft)
        }
    }
}
